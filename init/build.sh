#!/bin/sh
cd root
chmod 640 etc/shadow
tar --group=0 --numeric-owner --owner=0 \
    -cJf ../maple-none-init-$(date +%Y%m%d).txz .
