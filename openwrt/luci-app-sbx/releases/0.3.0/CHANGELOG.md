# SBX 0.3.0

发布日期：2026-10-05

当前打包修订：`0.3.0-r3`

## 本版本

当前打包修订：`0.3.0-r4`

- `0.3.0-r4` 修复 SBX 版本检查对 OpenWrt release tag 的识别。

- 标准化 ImmortalWrt/OpenWrt LuCI 插件目录与 Makefile。
- 支持 TUN、TProxy 和 proxy-only 模式的事务式切换。
- 配置下载前执行 sing-box 校验和模式类型校验。
- 切换失败自动恢复旧配置、UCI 选择器和路由策略。
- 增加运行状态、路由策略和 DNS 风险检查。
- 增加配置备份和保留数量控制。
- 增加 Zashboard 安装/更新入口。
- 增加升级迁移脚本，保护用户现有 URL、模式和配置文件。
- 增加源码发布自检脚本。
- `0.3.0-r2` 增加 LuCI 配置备份列表和安全回滚功能。
- `0.3.0-r2` 增加 `sbx-luci-backup` 命令及对应 RPCD ACL。
- `0.3.0-r3` 修复 BusyBox 环境下备份列表和备份数量清理兼容性。

## 已知事项

- 本插件定位为旁路由，不修改上游主路由器配置。
- DNS 明文上游风险由健康检查提示，但不会自动修改用户的 mosdns、AdGuard Home 或 RouterOS 配置。
- ImmortalWrt 25.12 系列优先使用 APK；传统 OpenWrt/ImmortalWrt 环境可使用 IPK。
