# AmneziaWG module for FriendlyWrt NanoPi R3S

Device:
- NanoPi R3S / R3S LTS
- FriendlyWrt / OpenWrt 25.12.2
- Target: rockchip/armv8
- Architecture: aarch64
- Kernel: 6.1.141

Files:
- amneziawg.ko
- install-amneziawg.sh
- device-kernel-info.txt
- kernel-6.1.141-r3s.config
- build-info.txt

Install on router:

cd /tmp
wget https://raw.githubusercontent.com/Fawero/friendlywrt-r3s-amneziawg-6.1.141/main/amneziawg.ko
wget https://raw.githubusercontent.com/Fawero/friendlywrt-r3s-amneziawg-6.1.141/main/install-amneziawg.sh
chmod +x install-amneziawg.sh
./install-amneziawg.sh

Check:

lsmod | grep amneziawg
dmesg | grep amneziawg

Kernel binding:

This module is built only for kernel 6.1.141.

Expected vermagic:

6.1.141 SMP mod_unload modversions aarch64

If FriendlyWrt kernel changes, the module must be rebuilt.
