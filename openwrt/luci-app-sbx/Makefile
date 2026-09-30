include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-sbx
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-sbx
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for SBX/sing-box
  DEPENDS:=+luci-base +curl +unzip +ca-bundle +nftables +kmod-nft-tproxy +kmod-nf-tproxy +kmod-tun
endef

define Package/luci-app-sbx/description
  A small LuCI control surface for the SBX sing-box side-router plugin.
endef

define Build/Compile
endef

define Package/luci-app-sbx/install
  $(CP) ./root/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-sbx))
