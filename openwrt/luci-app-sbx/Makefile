include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-sbx
PKG_VERSION:=0.3.0
PKG_RELEASE:=11

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-sbx
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for SBX/sing-box
  DEPENDS:=+luci-base +curl +jsonfilter +unzip +ca-bundle +nftables +kmod-nft-tproxy +kmod-nf-tproxy +kmod-tun
endef

define Package/luci-app-sbx/description
  A small LuCI control surface for the SBX sing-box side-router plugin.
endef

define Package/luci-app-sbx/conffiles
/etc/config/sbx
endef

define Package/luci-app-sbx/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
  chmod 755 /usr/bin/sbx-luci-* /usr/bin/sbx-zashboard 2>/dev/null || true
  /usr/bin/sbx-luci-migrate 2>/dev/null || true
  /etc/init.d/rpcd restart 2>/dev/null || true
}
exit 0
endef

define Package/luci-app-sbx/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
  /etc/init.d/sbx stop 2>/dev/null || true
  /usr/bin/sbx-luci-route clear 2>/dev/null || true
}
exit 0
endef

define Build/Compile
endef

define Package/luci-app-sbx/install
  $(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-sbx))
