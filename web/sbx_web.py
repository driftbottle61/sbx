#!/usr/bin/env python3
"""SBX local monitoring panel. Uses only the Python standard library."""
import base64
import json
import os
import shutil
import socket
import time
import urllib.request
import urllib.parse
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG = "/etc/sbx-web/config.json"
DEFAULT = {
    "listen": "127.0.0.1",
    "port": 9096,
    "token": "",
    "network_interface": "",
    "adguard_url": "",
    "adguard_user": "",
    "adguard_password": "",
    "poll_seconds": 2,
}
events = deque(maxlen=200)
last_query_ids = set()
last_net = None
last_net_time = None

def load_config():
    config = DEFAULT.copy()
    try:
        with open(CONFIG, "r", encoding="utf-8") as source:
            config.update(json.load(source))
    except FileNotFoundError:
        pass
    return config

def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as source:
            return source.read().strip()
    except OSError:
        return ""

def cpu_percent():
    first = [int(item) for item in read_text("/proc/stat").splitlines()[0].split()[1:]]
    time.sleep(0.08)
    second = [int(item) for item in read_text("/proc/stat").splitlines()[0].split()[1:]]
    total = sum(second) - sum(first)
    idle = second[3] - first[3]
    return round(100 * (total - idle) / total, 1) if total else 0

def memory():
    values = {}
    for line in read_text("/proc/meminfo").splitlines():
        key, value = line.split(":", 1)
        values[key] = int(value.split()[0]) * 1024
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    return {"total": total, "used": total - available, "percent": round(100 * (total - available) / total, 1) if total else 0}

def choose_interface(config):
    requested = config.get("network_interface")
    if requested and os.path.exists("/sys/class/net/" + requested):
        return requested
    for name in os.listdir("/sys/class/net"):
        if name != "lo" and os.path.exists("/sys/class/net/%s/statistics/rx_bytes" % name):
            return name
    return "lo"

def network(config):
    global last_net, last_net_time
    name = choose_interface(config)
    base = "/sys/class/net/%s/statistics/" % name
    current = {"rx": int(read_text(base + "rx_bytes") or 0), "tx": int(read_text(base + "tx_bytes") or 0)}
    now = time.time()
    rates = {"rx": 0, "tx": 0}
    if last_net and last_net["name"] == name:
        elapsed = now - last_net_time
        if elapsed > 0:
            rates = {key: round((current[key] - last_net[key]) / elapsed, 1) for key in current}
    last_net, last_net_time = {"name": name, **current}, now
    return {"interface": name, **current, "rx_rate": max(0, rates["rx"]), "tx_rate": max(0, rates["tx"])}

def system_metrics(config):
    disk = shutil.disk_usage("/")
    return {"time": int(time.time()), "hostname": socket.gethostname(), "cpu": cpu_percent(), "memory": memory(), "disk": {"total": disk.total, "used": disk.used, "percent": round(100 * disk.used / disk.total, 1)}, "network": network(config)}

def poll_adguard(config):
    url = config.get("adguard_url", "").rstrip("/")
    if not url:
        return
    request = urllib.request.Request(url + "/control/querylog?limit=80")
    user = config.get("adguard_user", "")
    if user:
        credential = (user + ":" + config.get("adguard_password", "")).encode()
        request.add_header("Authorization", "Basic " + base64.b64encode(credential).decode())
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            data = json.load(response).get("data", [])
    except Exception:
        return
    incoming = []
    for item in reversed(data):
        question = item.get("question") or {}
        answers = item.get("answer") or []
        client_info = item.get("client_info") or {}
        key = "%s|%s|%s" % (item.get("time", ""), item.get("client", ""), question.get("name", ""))
        if key in last_query_ids:
            continue
        result = ", ".join(str(answer.get("value", "")) for answer in answers if isinstance(answer, dict) and answer.get("value"))
        incoming.append({"id": key, "time": item.get("time", ""), "client": item.get("client", ""), "client_name": client_info.get("name", ""), "domain": question.get("name", ""), "type": question.get("type", ""), "result": result or item.get("reason", "")})
    for item in incoming:
        events.appendleft(item)
        last_query_ids.add(item["id"])
    if len(last_query_ids) > 1000:
        last_query_ids.clear()
        last_query_ids.update(item["id"] for item in events)

HTML = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>SBX 面板</title><style>body{margin:0;background:#101417;color:#e6edf3;font:14px system-ui;padding:20px}h1{font-size:20px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}.card{background:#182027;border:1px solid #2d3942;padding:14px;border-radius:6px}.v{font-size:24px;margin-top:9px}.muted{color:#93a4b2}table{width:100%;border-collapse:collapse;margin-top:18px;background:#182027}th,td{text-align:left;padding:10px;border-bottom:1px solid #29343d;word-break:break-all}th{color:#9fb2c3}.ok{color:#54d18b}</style><h1>SBX 运行面板 <span class="muted" id="host"></span></h1><div class="grid"><div class="card">CPU<div class="v" id="cpu">-</div></div><div class="card">内存<div class="v" id="mem">-</div></div><div class="card">磁盘<div class="v" id="disk">-</div></div><div class="card">下载<div class="v" id="rx">-</div></div><div class="card">上传<div class="v" id="tx">-</div></div></div><h2>DNS 动态</h2><div class="muted">来自 AdGuard Home 查询日志；显示终端、域名和解析结果。</div><table><thead><tr><th>时间</th><th>客户端</th><th>域名</th><th>类型</th><th>结果</th></tr></thead><tbody id="dns"></tbody></table><script>const f=n=>n>1048576?(n/1048576).toFixed(1)+' MB/s':n>1024?(n/1024).toFixed(1)+' KB/s':n+' B/s';const b=n=>(n/1073741824).toFixed(1)+' GB';async function refresh(){let d=await fetch('/api/status').then(x=>x.json());host.textContent=d.hostname;cpu.textContent=d.cpu+'%';mem.textContent=d.memory.percent+'% / '+b(d.memory.used);disk.textContent=d.disk.percent+'% / '+b(d.disk.used);rx.textContent=f(d.network.rx_rate);tx.textContent=f(d.network.tx_rate);dns.innerHTML=d.events.map(x=>`<tr><td>${x.time}</td><td>${x.client_name||x.client||'-'}</td><td>${x.domain}</td><td>${x.type}</td><td class="ok">${x.result||'-'}</td></tr>`).join('')}refresh();setInterval(refresh,2000)</script></html>'''

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def authorized(self, config):
        token = config.get("token", "")
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        return not token or self.headers.get("Authorization") == "Bearer " + token or query.get("token", [""])[0] == token
    def do_GET(self):
        config = load_config()
        if not self.authorized(config): self.send_response(401); self.end_headers(); return
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/status":
            poll_adguard(config)
            payload = json.dumps({**system_metrics(config), "events": list(events)}, ensure_ascii=False).encode()
            self.send_response(200); self.send_header("Content-Type", "application/json; charset=utf-8"); self.end_headers(); self.wfile.write(payload); return
        page = HTML.replace("fetch('/api/status')", "fetch('/api/status?token='+encodeURIComponent(new URLSearchParams(location.search).get('token')||''))")
        self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.end_headers(); self.wfile.write(page.encode())

if __name__ == "__main__":
    config = load_config()
    ThreadingHTTPServer((config["listen"], int(config["port"])), Handler).serve_forever()
