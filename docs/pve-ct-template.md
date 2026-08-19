# SBX PVE CT 创建模板

在 PVE 主机上执行。下面模板创建一个与当前 SBX CT 114 相同规格的 Debian CT。

## 默认模板

```bash
pct create 122 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --arch amd64 \
  --cores 1 \
  --memory 512 \
  --swap 512 \
  --hostname debian.sbx.singbox \
  --rootfs local-lvm:8 \
  --unprivileged 1 \
  --features nesting=1 \
  --dev0 /dev/net/tun \
  --onboot 1 \
  --nameserver "223.5.5.5 119.29.29.29" \
  --net0 name=eth0,bridge=vmbr0,firewall=1,gw=192.168.100.1,ip=192.168.100.18/24,type=veth
```

## 使用前修改

`122` 是示例 CT ID，必须替换为未占用的 ID。`192.168.100.18` 是当前主 SBX 地址，也必须替换为未占用的地址。主机名、磁盘大小、CPU 和内存可以按实际用途调整。

检查模板和地址：

```bash
pveam list local
pct list
ping -c 2 192.168.100.18
```

## 启动和初始化

```bash
pct start 122
pct enter 122
passwd
```

进入 CT 后安装 SSH 公钥，随后从 Windows 或其他客户端通过新 IP 登录。确认网络后再安装 SBX：

```bash
ip -br addr
ip route
curl -fsSL https://github.com/driftbottle61/sbx/releases/download/v1.2.24/install-oneclick.sh | bash
```

## 检查配置

```bash
pct config 122
pct status 122
pct exec 122 -- ip -br addr
pct exec 122 -- ip route
```

`/dev/net/tun` 和 `nesting=1` 是 SBX 使用 TUN/TProxy 路由功能所需的配置。不要让两个运行中的 CT 同时使用同一个 IP。
