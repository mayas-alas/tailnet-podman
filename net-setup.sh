#!/usr/bin/env bash
echo "Applying Proxmox network for (IPv4 + IPv6)..."

cat << 'EOF' > /etc/network/interfaces
auto lo
iface lo inet loopback

iface nic0 inet manual
iface nic1 inet manual
iface nic2 inet manual

# The MAIN network (passt + Tailscale + Internet)
auto vmbr0
iface vmbr0 inet dhcp
    bridge-ports nic0
    bridge-stp off
    bridge-fd 0
iface vmbr0 inet6 auto

# Zone 1 (Slirp IPv4 + IPv6)
auto vmbr1
iface vmbr1 inet static
    address 172.18.0.15/24
    bridge-ports nic1
    bridge-stp off
    bridge-fd 0
iface vmbr1 inet6 static
    address fd00:18::15/64

# Zone 2 (Slirp IPv4 + IPv6)
auto vmbr2
iface vmbr2 inet static
    address 124.10.0.15/24
    bridge-ports nic2
    bridge-stp off
    bridge-fd 0
iface vmbr2 inet6 static
    address fd00:10::15/64
EOF

systemctl restart networking
echo "Network setup finnish! Ping, Internet, and Tailscale (port 8006) should now work perfectly."
