include $(TOPDIR)/rules.mk

PKG_NAME:=friendlywrt-amneziawg-tools
PKG_VERSION:=1.0.20260812
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=COPYING

include $(INCLUDE_DIR)/package.mk

define Package/friendlywrt-amneziawg-tools
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=VPN
  TITLE:=AmneziaWG 3.1 userspace control tool for Korobka
  URL:=https://github.com/amnezia-vpn/amneziawg-tools
endef

define Package/friendlywrt-amneziawg-tools/description
 Reproducible aarch64/musl build of the AmneziaWG userspace control program
 from the pinned upstream commit that adds AWG 3.1 parameters. The package
 intentionally contains only /usr/bin/awg and Korobka build metadata; netifd
 and LuCI integration are packaged separately so their AWG 3.1 parameter
 handling can be audited independently.
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src-tree/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR)/src \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		PLATFORM=linux \
		RUNSTATEDIR=/var/run \
		WITH_BASHCOMPLETION=no \
		WITH_WGQUICK=no \
		WITH_SYSTEMDUNITS=no \
		V=1 \
		wg
endef

define Package/friendlywrt-amneziawg-tools/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/wg $(1)/usr/bin/awg
	$(INSTALL_DIR) $(1)/usr/share/korobka
	$(INSTALL_DATA) ./files/amneziawg-tools-build-info.txt $(1)/usr/share/korobka/amneziawg-tools-build-info.txt
endef

$(eval $(call BuildPackage,friendlywrt-amneziawg-tools))
