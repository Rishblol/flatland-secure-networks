#!/bin/sh
set -eu

# Private macvlan links on dummy parents cannot exchange packets with workloads.
# Join the zones at layer 2 only after the forwarding policy has loaded.
nft -f /etc/flatland/firewall/flatland.nft
for interface in zone-user zone-dmz zone-server zone-mgmt; do
    ip link set dev "$interface" type macvlan mode bridge
done

printf '%s\n' 'Flatland firewall loaded. Starting the NFLOG group 10 listener.'
exec ulogd -c /etc/flatland/ulogd.conf
