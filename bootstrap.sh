#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh - prepara el entorno de GetBela en el servidor
#
# Se ejecuta UNA vez, la primera vez, en un servidor nuevo. Despu��s, el ciclo
# de trabajo es:
#
#   ./bootstrap.sh          # solo si cambia la configuracion de infra
#   git pull && docker compose -f compose.getbela.prod.yaml up -d --build
#
# -----------------------------------------------------------------------------
# QUE HACE
#
#   1. Verifica que las herramientas necesarias esten (docker, compose, git).
#   2. Crea el .env con secretos generados, a partir de .env.example.
#   3. Clona el codigo de la aplicacion en ./app (el repo GetBela-App), si
#      no esta ya.
#   4. Deja el arbol con la forma que espera el compose:
#
#        ./app/backend     <- codigo Laravel (clonado de GetBela-App)
#        ./app/frontend    <- codigo React (clonado de GetBela-App)
#
# -----------------------------------------------------------------------------
# NOTA SOBRE LOS SECRETOS
#
# El .env NO se versiona. Si este script se ejecuta de nuevo sobre un .env
# existente, NO lo sobreescribe: los secretos ya generados se conservan.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APP_REPO_URL="${GETBELA_APP_REPO_URL:-https://github.com/jonsanchezr/GetBela-App.git}"
APP_REPO_BRANCH="${GETBELA_APP_REPO_BRANCH:-main}"
APP_DIR="${SCRIPT_DIR}/app"

log()  { printf "\033[0;36m[bootstrap]\033[0m %s\n" "$*"; }
warn() { printf "\033[0;33m[bootstrap]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[0;31m[bootstrap]\033[0m %s\n" "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# 1. Requisitos
# -----------------------------------------------------------------------------
log "Verificando requisitos"

command -v docker >/dev/null 2>&1 || die "docker no esta instalado"
docker compose version >/dev/null 2>&1 || die "docker compose v2 no esta disponible"
command -v git >/dev/null 2>&1 || die "git no esta instalado"

log "docker:      $(docker --version)"
log "compose:     $(docker compose version --short)"
log "git:         $(git --version)"

# -----------------------------------------------------------------------------
# 2. Secretos (.env)
# -----------------------------------------------------------------------------
if [ -f .env ]; then
  log ".env ya existe: se conserva (los secretos no se regeneran)"
else
  log "Generando .env con secretos nuevos"

  # Contraseñas aleatorias: 32 caracteres alfanumericos.
  random_secret() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-32}"
  }

  MYSQL_ROOT_PW="$(random_secret 32)"
  DB_PW="$(random_secret 24)"

  cat > .env <<EOF
# =============================================================================
# GetBela - secretos del grupo (produccion)
#
# Generado por bootstrap.sh el $(date -u +%Y-%m-%dT%H:%M:%SZ)
# NO versionar este archivo.
# =============================================================================

# MySQL
GETBELA_MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PW}
GETBELA_DB_DATABASE=getbela
GETBELA_DB_USERNAME=getbela
GETBELA_DB_PASSWORD=${DB_PW}

# Zona horaria de los contenedores
TZ=America/Santiago

# Correr los seeds (datos de prueba) en el arranque del backend.
# Poner en false cuando la base ya tenga datos y no se quiera re-sembrar.
GETBELA_RUN_SEEDS=true
EOF

  chmod 600 .env
  log ".env creado con permisos 600"
fi

# -----------------------------------------------------------------------------
# 3. Codigo de la aplicacion
# -----------------------------------------------------------------------------
if [ -d "${APP_DIR}/.git" ]; then
  log "El codigo ya esta clonado en ${APP_DIR}: se actualiza"
  git -C "${APP_DIR}" fetch --all --tags
  git -C "${APP_DIR}" checkout "${APP_REPO_BRANCH}"
  git -C "${APP_DIR}" pull --ff-only origin "${APP_REPO_BRANCH}"
else
  log "Clonando ${APP_REPO_URL} (rama ${APP_REPO_BRANCH}) en ${APP_DIR}"
  mkdir -p "${APP_DIR}"
  git -C "${APP_DIR}" init -q
  git -C "${APP_DIR}" remote add origin "${APP_REPO_URL}"
  git -C "${APP_DIR}" fetch --depth 1 origin "${APP_REPO_BRANCH}"
  git -C "${APP_DIR}" checkout -q -B "${APP_REPO_BRANCH}" FETCH_HEAD
fi

[ -f "${APP_DIR}/backend/artisan" ] || die "No se encontro backend/artisan en ${APP_DIR}"
[ -f "${APP_DIR}/frontend/package.json" ] || die "No se encontro frontend/package.json en ${APP_DIR}"

log "Codigo listo:"
log "  backend:  $(git -C "${APP_DIR}" rev-parse --short HEAD)"
log "  frontend: $(git -C "${APP_DIR}" rev-parse --short HEAD)"

# -----------------------------------------------------------------------------
# 4. Permisos de los volumenes
#
# El backend corre como hostuser (uid 1000). Los volumenes nombrados los crea
# Docker con root:root, y el usuario del contenedor necesita escribir en
# storage/ y bootstrap/cache/. Los directorios se pre-crean en la imagen
# (con el ownership correcto) y aqui se deja el arbol listo.
# -----------------------------------------------------------------------------
log "Preparando permisos"
mkdir -p "${APP_DIR}/backend/storage/framework/cache/data" \
         "${APP_DIR}/backend/storage/framework/sessions" \
         "${APP_DIR}/backend/storage/framework/views" \
         "${APP_DIR}/backend/storage/logs" \
         "${APP_DIR}/backend/storage/app/public" \
         "${APP_DIR}/backend/bootstrap/cache"
chmod -R 777 "${APP_DIR}/backend/storage" "${APP_DIR}/backend/bootstrap/cache" 2>/dev/null \
  || warn "No se pudieron ajustar los permisos (revisar ownership)"

log ""
log "Bootstrap completado."
log ""
log "Siguiente paso:"
log "  docker compose -f compose.getbela.prod.yaml up -d --build"
