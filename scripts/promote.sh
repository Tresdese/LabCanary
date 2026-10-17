#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="${1:-}"
case "$stage" in blue|canary10|canary50|green) ;; *) echo 'Uso: ./scripts/promote.sh blue|canary10|canary50|green' >&2; exit 2;; esac
cp "nginx/active.conf" "nginx/previous.conf"
cp "nginx/stages/${stage}.conf" nginx/active.conf
if ! docker compose exec -T proxy nginx -t; then
  cp nginx/previous.conf nginx/active.conf
  echo 'Configuracion invalida: restaurada; no se recargo Nginx' >&2
  exit 1
fi
docker compose exec -T proxy nginx -s reload
echo "Etapa activada: ${stage}"
