include $(TOPDIR)/rules.mk

PKG_NAME:=amneziawg-tools
PKG_VERSION:=3.1.20260812
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/amneziawg-tools
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AmneziaWG userspace tools
  URL:=https://github.com/amnezia-vpn/amneziawg-tools
  DEPENDS:=+libc +libmnl
endef

define Package/amneziawg-tools/description
 AmneziaWG userspace control utility for the Korobka FriendlyWrt image.
 This package intentionally installs only /usr/bin/awg. awg-quick is not
 included because netifd/Podkop own interface lifecycle and policy routing.
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		WITH_WGQUICK=no \
		WITH_BASHCOMPLETION=no \
		WITH_SYSTEMDUNITS=no \
		V=1
endef

define Package/amneziawg-tools/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/wg $(1)/usr/bin/awg
	$(INSTALL_DIR) $(1)/usr/share/korobka
	$(INSTALL_DATA) ./files/amneziawg-tools-build-info.txt $(1)/usr/share/korobka/amneziawg-tools-build-info.txt
endef

$(eval $(call BuildPackage,amneziawg-tools))
