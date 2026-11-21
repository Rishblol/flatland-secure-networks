#!/bin/sh
set -eu

tls_dir=/etc/nginx/lab-tls
install -d -m 0700 "$tls_dir"
if [ ! -s "$tls_dir/web.crt" ] || [ ! -s "$tls_dir/web.key" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
        -subj /CN=web -addext subjectAltName=DNS:web \
        -keyout "$tls_dir/web.key" -out "$tls_dir/web.crt"
fi

exec nginx -c /etc/nginx/flatland.conf -g 'daemon off;'
