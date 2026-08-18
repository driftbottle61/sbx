#!/bin/bash

readonly SBX_WEB_SERVICE="sbx-web.service"
readonly SBX_WEB_CONFIG="/etc/sbx-web/config.json"
readonly SBX_WEB_DEFAULT_CONFIG="/opt/sbx/data/sbx-web.json.example"

ensure_web_token() {
    local token
    [ -f "$SBX_WEB_CONFIG" ] || return 1
    token=$(jq -r '.token // ""' "$SBX_WEB_CONFIG" 2>/dev/null)
    case "$token" in
        ""|null|"请生成一个随机访问令牌"|"生成随机令牌")
            token=$(openssl rand -hex 24 2>/dev/null || tr -dc A-Za-z0-9 </dev/urandom | head -c 48)
            jq --arg token "$token" '.token=$token' "$SBX_WEB_CONFIG" > "$SBX_WEB_CONFIG.tmp" && \
                mv "$SBX_WEB_CONFIG.tmp" "$SBX_WEB_CONFIG"
            chmod 600 "$SBX_WEB_CONFIG"
            ok "已自动生成 Web 面板访问令牌"
            ;;
    esac
}

web_install() {
    mkdir -p /etc/sbx-web
    if [ ! -f "$SBX_WEB_CONFIG" ]; then
        cp "$SBX_WEB_DEFAULT_CONFIG" "$SBX_WEB_CONFIG"
        chmod 600 "$SBX_WEB_CONFIG"
    fi
    ensure_web_token
    cat > /etc/systemd/system/$SBX_WEB_SERVICE <<'EOF'
[Unit]
Description=SBX Web Monitor
After=network-online.target sing-box.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/sbx/web/sbx_web.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    ok "Web 面板服务已安装"
}

web_configure() {
    web_install
    local listen port iface adguard_url adguard_user adguard_password token current_password
    listen=$(jq -r '.listen // "127.0.0.1"' "$SBX_WEB_CONFIG")
    port=$(jq -r '.port // 9096' "$SBX_WEB_CONFIG")
    iface=$(jq -r '.network_interface // ""' "$SBX_WEB_CONFIG")
    adguard_url=$(jq -r '.adguard_url // ""' "$SBX_WEB_CONFIG")
    adguard_user=$(jq -r '.adguard_user // ""' "$SBX_WEB_CONFIG")
    token=$(jq -r '.token // ""' "$SBX_WEB_CONFIG")
    current_password=$(jq -r '.adguard_password // ""' "$SBX_WEB_CONFIG")
    read -r -p "监听地址 [$listen]：" input; listen=${input:-$listen}
    read -r -p "端口 [$port]：" input; port=${input:-$port}
    read -r -p "网卡（留空自动识别）[$iface]：" input; iface=${input:-$iface}
    read -r -p "AdGuard 地址（留空不显示 DNS）[$adguard_url]：" input; adguard_url=${input:-$adguard_url}
    read -r -p "AdGuard 只读用户名 [$adguard_user]：" input; adguard_user=${input:-$adguard_user}
    read -r -s -p "AdGuard 密码（留空保持不变）：" adguard_password; echo
    if [ -z "$token" ] || [ "$token" = "请生成一个随机访问令牌" ]; then
        token=$(openssl rand -hex 24 2>/dev/null || tr -dc A-Za-z0-9 </dev/urandom | head -c 48)
    fi
    read -r -p "访问令牌 [$token]：" input; token=${input:-$token}
    [ -z "$adguard_password" ] || current_password=$adguard_password
    jq --arg listen "$listen" --argjson port "$port" --arg iface "$iface" --arg url "$adguard_url" --arg user "$adguard_user" --arg password "$current_password" --arg token "$token" \
       '.adguard_password=$password | .listen=$listen | .port=$port | .network_interface=$iface | .adguard_url=$url | .adguard_user=$user | .token=$token' \
       "$SBX_WEB_CONFIG" > "$SBX_WEB_CONFIG.tmp" && mv "$SBX_WEB_CONFIG.tmp" "$SBX_WEB_CONFIG"
    chmod 600 "$SBX_WEB_CONFIG"
    systemctl restart "$SBX_WEB_SERVICE"
    ok "配置已保存"
    web_show_url
}

web_show_url() {
    [ -f "$SBX_WEB_CONFIG" ] || { warn "请先安装 Web 面板"; return; }
    local listen port token host
    listen=$(jq -r '.listen // "127.0.0.1"' "$SBX_WEB_CONFIG")
    port=$(jq -r '.port // 9096' "$SBX_WEB_CONFIG")
    token=$(jq -r '.token // ""' "$SBX_WEB_CONFIG")
    host=$listen
    [ "$host" = "0.0.0.0" ] && host=$(hostname -I | awk '{print $1}')
    echo "访问地址：http://$host:$port/?token=$token"
}

web_menu() {
    while true; do
        clear
        cat <<EOF
================================
          SBX Web 面板
================================
1. 安装/更新服务
2. 配置面板与 AdGuard
3. 启动
4. 停止
5. 重启
6. 查看状态
7. 显示访问地址
0. 返回
================================
EOF
        read -r -p "请选择：" NUM
        case "$NUM" in
            1) web_install; pause ;;
            2) web_configure; pause ;;
            3) web_install; systemctl start "$SBX_WEB_SERVICE"; pause ;;
            4) systemctl stop "$SBX_WEB_SERVICE"; pause ;;
            5) web_install; systemctl restart "$SBX_WEB_SERVICE"; pause ;;
            6) systemctl status "$SBX_WEB_SERVICE" --no-pager; pause ;;
            7) web_show_url; pause ;;
            0) return ;;
            *) warn "输入错误"; pause ;;
        esac
    done
}
