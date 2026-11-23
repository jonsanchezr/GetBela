#!/usr/bin/env bash
# =============================================================================
# Entrypoint del contenedor frontend de GetBela (getbela-frontend).
#
# Responsabilidades:
#   1. Instala las dependencias de node si faltan (o si el package-lock.json
#      cambio desde la ultima instalacion)
#   2. Arranca el dev server de Vite escuchando en 0.0.0.0
#
# El codigo llega por bind mount, asi que la instalacion se hace en cada
# arranque y refleja el package.json actual.
# =============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/app}"
APP_NAME="${APP_NAME:-getbela-frontend}"

log()  { printf "\033[0;36m[%s]\033[0;36m %s\033[0m\n" "${APP_NAME}" "$*"; }
warn() { printf "\033[0;33m[%s]\033[0;33m %s\033[0m\n" "${APP_NAME}" "$*" >&2; }
err()  { printf "\033[0;31m[%s]\033[0;31m %s\033[0m\n" "${APP_NAME}" "$*" >&2; }

cd "${APP_DIR}"

# -----------------------------------------------------------------------------
# 1. Dependencias de node
#
# El node_modules es un volumen anonimo: la instalacion se hace dentro del
# contenedor (linux), nunca se usa la del host (windows).
#
# La comparacion es por el hash del package-lock.json: si el lock cambio, la
# instalacion se rehace. Sin esto, cambiar una dependencia del repo no
# tendria efecto hasta borrar el volumen a mano.
# -----------------------------------------------------------------------------
LOCK_HASH_FILE="/app/node_modules/.getbela-lock-hash"

current_hash=""
if [ -f package-lock.json ]; then
  current_hash=$(sha256sum package-lock.json | cut -d' ' -f1)
fi

installed_hash=""
if [ -f "${LOCK_HASH_FILE}" ]; then
  installed_hash=$(cat "${LOCK_HASH_FILE}")
fi

if [ ! -d node_modules ] || [ ! -f node_modules/.package-lock.json ]; then
  log "Instalando dependencias de node (npm ci)"
  if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi
  [ -n "${current_hash}" ] && printf '%s' "${current_hash}" > "${LOCK_HASH_FILE}"
elif [ -n "${current_hash}" ] && [ "${current_hash}" != "${installed_hash}" ]; then
  log "package-lock.json cambio: reinstalando dependencias"
  npm install --no-audit --no-fund
  printf '%s' "${current_hash}" > "${LOCK_HASH_FILE}"
else
  log "Dependencias de node presentes"
fi

# -----------------------------------------------------------------------------
# 2. Vite dev server
#
# `--host 0.0.0.0` es obligatorio: Vite por defecto escucha solo en 127.0.0.1
# DENTRO del contenedor, y el puerto publicado al host no llegaria.
# -----------------------------------------------------------------------------
log "Arrancando el dev server de Vite en 0.0.0.0:5173"
exec "$@"
