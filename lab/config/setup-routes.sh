#!/bin/sh
set -eu

if [ -n "${FLATLAND_ROUTER:-}" ]; then
    # The directly connected zone has a more specific route than this aggregate.
    ip -4 route replace "${FLATLAND_LAB_SUBNET:?missing lab subnet}" via "$FLATLAND_ROUTER" dev eth0
    ip link set dev eth0 type macvlan mode bridge
    exec setpriv --bounding-set=-net_admin -- "$@"
fi

exec "$@"
