# 0.3.0 升级脚本

自动升级脚本位于发布目录的 `../install-sbx.sh`。

在目标 ImmortalWrt 上执行：

```sh
chmod 755 install-sbx.sh
./install-sbx.sh luci-app-sbx-0.3.0-r1.apk SHA256值
```

传统 OPKG 系统使用对应的 IPK：

```sh
./install-sbx.sh luci-app-sbx_0.3.0-1_x86_64.ipk SHA256值
```

脚本会自动：

1. 校验 SHA256（提供校验值时）。
2. 备份 `/etc/config/sbx` 和当前 sing-box 配置。
3. 根据文件格式选择 `apk` 或 `opkg`。
4. 重启 RPCD 并执行 SBX 健康检查。
5. 健康检查失败时恢复备份配置并重新启动 sing-box。
