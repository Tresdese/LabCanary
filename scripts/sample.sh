#!/usr/bin/env bash
set -euo pipefail
port="${HOST_PORT:-8080}"
count="${1:-100}"
case "$count" in ''|*[!0-9]*) echo 'Cantidad invalida' >&2; exit 2;; esac
for ((i=0;i<count;i++)); do
  curl --no-keepalive -fsS "http://127.0.0.1:${port}/api/info" || exit 1
  printf '\n'
done | grep -o '"version":"v[12]"' | sort | uniq -c
