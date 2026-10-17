#!/usr/bin/env bash
set -euo pipefail
port="${HOST_PORT:-8080}"
n="${1:-30}"
for ((i=0;i<n;i++)); do
  curl --no-keepalive -sS -o /dev/null -w '%{http_code}\n' "http://127.0.0.1:${port}/api/checkout"
done | sort | uniq -c
