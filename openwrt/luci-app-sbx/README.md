# luci-app-sbx

SBX is a LuCI control package for the ImmortalWrt side-router deployment of sing-box.

The package provides:

- TUN, TProxy, and proxy-only mode orchestration;
- remote configuration download with sing-box validation;
- configuration backup and rollback on failed transitions;
- mode-specific policy routing and nftables setup;
- runtime, route, and DNS health checks;
- LuCI status, logs, configuration, and Zashboard integration.

The package is intentionally designed for a side-router. It does not modify the upstream main router configuration.

`/etc/config/sbx` is a preserved conffile. Package upgrades must not overwrite the configured URLs, mode, or routing parameters.

During an upgrade, the post-install migration only adds missing selector
fields (`mode`, `config_profile`, and `active_config_url`). It records the
result in `/etc/sbx/migration.version` and does not replace configured URLs or
the downloaded sing-box configuration.
