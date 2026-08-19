# SBX

SBX is an interactive Sing-box manager for Debian and Ubuntu. It installs and
upgrades Sing-box, manages its configuration and systemd service, and provides
TUN/TProxy routing tools.

## Install

Run as `root`, or pipe the script to `sudo bash`:

```bash
curl -fsSL https://github.com/driftbottle61/sbx/raw/refs/heads/main/install.sh | sudo bash
```

With `wget`:

```bash
wget -qO- https://github.com/driftbottle61/sbx/raw/refs/heads/main/install.sh | sudo bash
```

Install the fixed `v1.2.1` release as `root`:

```bash
curl -fsSL https://github.com/driftbottle61/sbx/releases/download/v1.2.1/install-oneclick.sh | bash
```

Then start the manager:

```bash
sudo sbx
```

The same install command upgrades SBX. Existing `/opt/sbx/data/sbx.conf` is
preserved during an upgrade.

## Download proxy

SBX automatically checks `http://127.0.0.1:8080` when it starts. If the local
proxy is available, dependency, GitHub API, configuration, and Sing-box release
downloads use it automatically. If it is unavailable, SBX uses the direct
connection with bounded timeouts and retries.

Set a different proxy for one run:

```bash
SBX_DOWNLOAD_PROXY=http://192.168.100.18:8080 sbx
```

Force direct downloads:

```bash
SBX_DOWNLOAD_PROXY=off sbx
```

## Web 面板

在 `sbx` 主菜单选择 `6. Web 面板`，先执行“安装/更新服务”，再选择“配置面板与 AdGuard”。面板默认监听 `127.0.0.1:9096`；如需从局域网访问，将监听地址改为 `0.0.0.0`，随后菜单会显示带访问令牌的 URL。

面板显示服务器 CPU、内存、磁盘及网卡实时流量。DNS 动态从 AdGuard Home 的 Query Log API 获取，因此能显示真实请求客户端、域名、记录类型和解析结果，而不是只显示 mosdns。请在 AdGuard Home 中创建专门的低权限只读账号并填入其地址、用户名和密码；未配置 AdGuard 时，系统指标仍可使用，DNS 列表为空。

面板配置在 `/etc/sbx-web/config.json`，权限为 `600`，升级不会覆盖。该文件含 AdGuard 密码及访问令牌，严禁提交到 Git。局域网访问时应保留随机令牌，并在 RouterOS 或反向代理侧限制可访问的设备。

## Install a release or fork

```bash
curl -fsSL https://github.com/driftbottle61/sbx/raw/refs/heads/main/install.sh \
  | sudo bash -s -- --ref v1.2.1
```

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh \
  | sudo SBX_REPO=OWNER/REPO bash
```

Use `--skip-deps` if all required system packages are already installed.

## Uninstall

Remove SBX while leaving the Sing-box binary and `/etc/sing-box` in place:

```bash
sudo /opt/sbx/uninstall.sh
```

Add `--keep-data` to copy the SBX and Sing-box configuration into a timestamped
directory under `/var/lib` before removal.

## Files

- `/opt/sbx`: SBX application files
- `/usr/local/bin/sbx`: command entry point
- `/etc/sing-box/config.json`: Sing-box configuration
- `/etc/systemd/system/sing-box.service`: generated systemd service
- `/etc/sbx-web/config.json`: Web 面板私有配置

## PVE CT 模板

当前 SBX CT 的 PVE 创建命令和初始化检查见 [`docs/pve-ct-template.md`](docs/pve-ct-template.md)。

## Supported systems

- Debian and Ubuntu
- `amd64`, `arm64`, and `armv7` for Sing-box downloads

## License

MIT
