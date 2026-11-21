#!/bin/sh
set -eu

install -d -m 0755 /run/sshd
ssh-keygen -A
/usr/sbin/sshd -f /etc/ssh/flatland_sshd_config
exec "$@"
