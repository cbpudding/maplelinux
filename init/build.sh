#!/bin/sh
cd root
tar --group=0 --numeric-owner --owner=0 \
    -cJf ../maple-none-init-$(date +%Y%m%d%H%M).txz .
