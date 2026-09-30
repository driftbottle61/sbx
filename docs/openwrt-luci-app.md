# OpenWrt LuCI 插件

`luci-app-sbx` 为 SBX 提供 ImmortalWrt/OpenWrt LuCI 管理界面。它适合旁路由场景，不会自动修改上游主路由器。

## 功能

LuCI 页面包含五个标签页：

- 运行状态：sing-box/SBX 版本、运行状态、CPU/内存、TUN/TProxy/代理模式选择和服务控制。
- 配置文件：分别保存 TUN 与 TProxy 配置文件 URL。
- 面板：显示已安装 Zashboard 版本和打开面板的链接。
- 当前配置：只读显示当前实际使用的 `/etc/sing-box/config.json`。
- 日志：实时滚动显示 sing-box 日志。

## 构建

将本目录放入 OpenWrt SDK 或完整构建树的 package feed，然后执行：

```sh
make package/luci-app-sbx/compile V=s
```

包依赖包括 LuCI、curl、unzip、ca-bundle、nftables、TUN 和 nftables TProxy 内核模块。

## 发布与升级

OpenWrt/ImmortalWrt 插件使用独立发布通道，不复用 Linux 版 SBX 的 `v1.x` Release。

- 发布标签格式为 `openwrt-v版本号`，例如 `openwrt-v0.2.4`。
- GitHub Release 资产固定包含 `luci-app-sbx-x86_64.apk`。
- 兼容旧版 opkg 的安装包命名为 `luci-app-sbx_版本-1_x86_64.ipk`。
- LuCI 页面里的 SBX/OpenWrt 版本检测只读取 `openwrt-v*` Release，不读取 Linux 版 `v1.x` Release。
- 当远程 OpenWrt 插件版本高于本地 `luci-app-sbx` 包版本时，最新版后方的“更新”按钮会启用；没有更新时按钮保持禁用，避免重复安装。
- 点击“更新”会下载对应 `openwrt-v*` Release 下的 APK，并执行 `apk add --allow-untrusted` 升级。

sing-box 使用独立版本检测与更新逻辑：页面只读取 `SagerNet/sing-box` 官方 Release，并根据设备架构下载 Linux musl 包。更新前会先用当前配置执行 `sing-box check`，校验通过后才替换二进制并重启服务；没有更新时按钮保持禁用。

在测试机上已验证从 `v0.2.2` 通过 LuCI 更新按钮升级到 `v0.2.4`，升级后本地版本与最新版一致，更新按钮自动隐藏。

## 模式切换

运行状态页的模式下拉框只在点击“应用并重启”后生效：

1. 根据选择读取对应的 TUN/TProxy URL。
2. 下载到临时文件并执行 `sing-box check`。
3. 校验配置确实包含对应的 `tun` 或 `tproxy` 入站。
4. 写入 `/etc/sing-box/config.json`。
5. 清理旧模式路由策略。
6. 重启 sing-box。
7. 应用新模式路由策略。

TUN 模式会等待新的 TUN 接口创建后，再添加旁路由入口接口的策略路由。TProxy 模式使用独立 nftables 表 `inet sbx`、mark `1` 和路由表 `100`。

## 安全注意事项

- 远程配置 URL 必须使用 HTTP 或 HTTPS，并且下载内容必须通过 sing-box 配置检查。
- 默认不修改上游主路由器，也不自动接管未明确指向本旁路由的流量。
- TProxy 透明代理需要 `kmod-nft-tproxy` 和 `kmod-nf-tproxy`。
- TUN/TProxy 配置可能包含节点密码、UUID、密钥或订阅信息，不要提交真实配置到 Git。
- 页面显示 Zashboard 版本和访问链接；Zashboard 是否兼容当前 sing-box API，取决于面板版本和 sing-box 配置。

## 手工验证

```sh
/usr/bin/sbx-luci-status
/usr/bin/sbx-luci-route status
/usr/bin/sing-box check -c /etc/sing-box/config.json
```

模式切换后的预期状态：

- TUN：存在 `utun` 和 `from all iif br-lan lookup 101`。
- TProxy：存在 `fwmark 0x1 lookup 100` 和 `table inet sbx`。
- proxy-only：不存在上述透明代理策略。
