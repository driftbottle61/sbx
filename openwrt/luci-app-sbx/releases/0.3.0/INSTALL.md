# luci-app-sbx 0.3.0 安装说明

## APK（ImmortalWrt 25.12）

```sh
apk add --allow-untrusted ./luci-app-sbx-0.3.0-r1.apk
/etc/init.d/rpcd restart
/usr/bin/sbx-luci-health
```

## IPK（传统 OpenWrt/OPKG）

```sh
opkg install ./luci-app-sbx_0.3.0-1_x86_64.ipk
/etc/init.d/rpcd restart
/usr/bin/sbx-luci-health
```

升级时 `/etc/config/sbx` 是 conffile，不会用包内默认配置覆盖用户配置。
安装后迁移记录位于 `/etc/sbx/migration.version`。

安装完成后进入 LuCI 的“服务 → SBX”，确认运行状态为正常，再执行模式切换。
