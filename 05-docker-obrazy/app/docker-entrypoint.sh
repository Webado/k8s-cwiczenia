#!/bin/sh
set -e

echo "Start kontenera, tryb: $1"

if [ "$1" = "worker" ]; then
    exec php bin/worker.php
else
    exec apache2-foreground
fi
