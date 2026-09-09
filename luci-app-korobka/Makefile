# See /LICENSE for more information.
# This is free software, licensed under the GNU General Public License v2.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Korobka management panel
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +ucode-mod-fs +jq +qrencode
LUCI_PKGARCH:=all

PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=Fawero

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
