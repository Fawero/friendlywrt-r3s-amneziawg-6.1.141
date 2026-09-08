include $(TOPDIR)/rules.mk

PKG_NAME:=friendlywrt-amneziawg-kmod
PKG_VERSION:=3.1.20260906
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/friendlywrt-amneziawg-kmod
  SECTION:=net
  CATEGORY:=Network
  TITLE:=AmneziaWG 3.1 kernel module for FriendlyWrt NanoPi R3S/LTS
  URL:=https://github.com/amnezia-vpn/amneziawg-linux-kernel-module
endef

define Package/friendlywrt-amneziawg-kmod/description
 AmneziaWG 3.1 kernel module built specifically for the FriendlyWrt
 NanoPi R3S/R3S LTS runtime kernel 6.1.141 ABI. This package intentionally
 does not use OpenWrt KernelPackage dependencies because FriendlyWrt 25.12.2
 on this device runs kernel 6.1.141 while its APK metadata references 6.12.74.
endef

# The module is cross-built separately against the exact FriendlyARM 6.1.141
# kernel tree. The APK SDK is used only for reproducible package generation.
define Build/Compile
endef

define Package/friendlywrt-amneziawg-kmod/install
	$(INSTALL_DIR) $(1)/lib/modules/6.1.141
	$(INSTALL_DATA) ./files/amneziawg.ko $(1)/lib/modules/6.1.141/amneziawg.ko
	$(INSTALL_DIR) $(1)/etc/modules.d
	echo 'amneziawg' > $(1)/etc/modules.d/30-amneziawg
	$(INSTALL_DIR) $(1)/usr/share/korobka
	$(INSTALL_DATA) ./files/amneziawg-build-info.txt $(1)/usr/share/korobka/amneziawg-build-info.txt
endef

define Package/friendlywrt-amneziawg-kmod/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

expected='6.1.141'
actual="$$(uname -r)"
if [ "$$actual" != "$$expected" ]; then
	echo "Refusing installation: FriendlyWrt runtime kernel is $$actual, expected $$expected." >&2
	exit 1
fi
exit 0
endef

define Package/friendlywrt-amneziawg-kmod/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

DEP='/lib/modules/6.1.141/modules.dep'
LINE='amneziawg.ko: libchacha20poly1305.ko poly1305-neon.ko libcurve25519-generic.ko ip6_udp_tunnel.ko udp_tunnel.ko'

if [ ! -f "$$DEP" ]; then
	echo "Missing $$DEP; refusing to register AmneziaWG module." >&2
	exit 1
fi

if ! grep -q '^amneziawg\.ko:' "$$DEP"; then
	printf '%s\n' "$$LINE" >> "$$DEP"
fi

# Do not force-load the module during installation. The first load is an
# explicit validation step; /etc/modules.d/30-amneziawg handles future boots.
exit 0
endef

define Package/friendlywrt-amneziawg-kmod/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

if grep -q '^amneziawg ' /proc/modules 2>/dev/null; then
	if ! rmmod amneziawg 2>/dev/null; then
		echo 'AmneziaWG is still in use. Remove AWG interfaces before uninstalling.' >&2
		exit 1
	fi
fi

DEP='/lib/modules/6.1.141/modules.dep'
[ -f "$$DEP" ] && sed -i '/^amneziawg\.ko:/d' "$$DEP"
exit 0
endef

$(eval $(call BuildPackage,friendlywrt-amneziawg-kmod))
