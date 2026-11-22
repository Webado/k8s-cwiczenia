#!/bin/sh
set -e

echo "Start kontenera, tryb: $1"

# exec = ZASTĄP proces shella procesem PHP/Apache.
# Bez exec: PID 1 = sh, który NIE przekazuje SIGTERM dziecku -> docker stop / K8s czeka i zabija (SIGKILL).
# Z exec:   PID 1 = php/apache, dostaje SIGTERM bezpośrednio -> czyste zamknięcie.
if [ "$1" = "worker" ]; then
    exec php bin/worker.php
else
    exec apache2-foreground
fi
