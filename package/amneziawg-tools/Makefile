include $(TOPDIR)/rules.mk

PKG_NAME:=amneziawg-tools
PKG_VERSION:=3.1.20260812
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=COPYING
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk

define Package/amneziawg-tools
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=AmneziaWG 3.1 userspace tools
  URL:=https://github.com/amnezia-vpn/amneziawg-tools
endef

define Package/amneziawg-tools/description
 AmneziaWG userspace control utility for the Korobka FriendlyWrt image.
 This package intentionally installs only /usr/bin/awg. awg-quick and the
 upstream netifd helper are not included here: interface lifecycle belongs to
 netifd/Korobka, and the current upstream OpenWrt helper does not expose the
 full AWG 3.1 parameter set yet.
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src-tree/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
	CFLAGS="$(TARGET_CFLAGS)" \
	LDFLAGS="$(TARGET_LDFLAGS)" \
	$(MAKE) -C $(PKG_BUILD_DIR)/src \
		CC="$(TARGET_CC)" \
		PLATFORM=linux \
		RUNSTATEDIR=/var/run \
		WITH_WGQUICK=no \
		WITH_BASHCOMPLETION=no \
		WITH_SYSTEMDUNITS=no \
		V=1 \
		wg
endef

define Package/amneziawg-tools/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/wg $(1)/usr/bin/awg
	$(INSTALL_DIR) $(1)/usr/share/korobka
	$(INSTALL_DATA) ./files/amneziawg-tools-build-info.txt $(1)/usr/share/korobka/amneziawg-tools-build-info.txt
endef

$(eval $(call BuildPackage,amneziawg-tools))
