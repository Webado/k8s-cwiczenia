#!/bin/sh
set -e

echo "Start kontenera, tryb: $1"

if [ "$1" = "worker" ]; then
    php bin/worker.php
else
    apache2-foreground
fi
