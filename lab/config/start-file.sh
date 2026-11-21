#!/bin/sh
set -eu

printf '%s\n' flatland-smb-demo flatland-smb-demo | smbpasswd -s -a lab
exec smbd --foreground --no-process-group
