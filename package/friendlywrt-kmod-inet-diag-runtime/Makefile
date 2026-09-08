include $(TOPDIR)/rules.mk

PKG_NAME:=friendlywrt-kmod-inet-diag-runtime
PKG_VERSION:=6.1.141
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/friendlywrt-kmod-inet-diag-runtime
  SECTION:=net
  CATEGORY:=Network
  TITLE:=FriendlyWrt 6.1.141 inet-diag runtime provider
  PKGARCH:=all
  PROVIDES:=kmod-inet-diag
endef

define Package/friendlywrt-kmod-inet-diag-runtime/description
 Runtime compatibility shim for the FriendlyWrt NanoPi R3S/LTS image.
 The real inet_diag, tcp_diag, udp_diag and raw_diag kernel modules are already
 shipped for the running FriendlyWrt 6.1.141 kernel. This package contains no
 kernel modules; it validates and registers those runtime modules and provides
 the virtual kmod-inet-diag dependency required by OpenWrt userspace packages
 such as sing-box without installing incompatible OpenWrt 6.12.74 kmods.
endef

define Build/Compile
endef

define Package/friendlywrt-kmod-inet-diag-runtime/install
	$(INSTALL_DIR) $(1)/etc/modules.d
	printf '%s\n' inet_diag tcp_diag udp_diag raw_diag > $(1)/etc/modules.d/31-inet-diag
	$(INSTALL_DIR) $(1)/usr/share/korobka
	printf '%s\n' \
		'product=korobka' \
		'package=friendlywrt-kmod-inet-diag-runtime' \
		'package_version=6.1.141-r1' \
		'runtime_kernel=6.1.141' \
		'provides=kmod-inet-diag' \
		'modules=inet_diag,tcp_diag,udp_diag,raw_diag' \
		'contains_kernel_modules=no' \
		> $(1)/usr/share/korobka/inet-diag-runtime-info.txt
endef

define Package/friendlywrt-kmod-inet-diag-runtime/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

expected='6.1.141'
actual="$$(uname -r)"
if [ "$$actual" != "$$expected" ]; then
	echo "Refusing installation: FriendlyWrt runtime kernel is $$actual, expected $$expected." >&2
	exit 1
fi

for module in inet_diag tcp_diag udp_diag raw_diag; do
	path="/lib/modules/6.1.141/$$module.ko"
	if [ ! -f "$$path" ]; then
		echo "Refusing installation: required runtime module is missing: $$path" >&2
		exit 1
	fi
done

exit 0
endef

define Package/friendlywrt-kmod-inet-diag-runtime/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

for module in inet_diag tcp_diag udp_diag raw_diag; do
	if ! modprobe "$$module"; then
		echo "Failed to load FriendlyWrt runtime module: $$module" >&2
		exit 1
	fi
done

exit 0
endef

$(eval $(call BuildPackage,friendlywrt-kmod-inet-diag-runtime))
