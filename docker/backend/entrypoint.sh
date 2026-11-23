#!/usr/bin/env bash
# =============================================================================
# Entrypoint del contenedor backend de GetBela (getbela-backend).
#
# Responsabilidades:
#   1. Espera a MySQL (vive en el grupo getbela; depends_on no puede
#      referenciarlo porque MySQL esta en un proyecto de Compose distinto
#      solo si se separara, aqui se resuelve en runtime igual)
#   2. Instala las dependencias de PHP (composer install) si faltan
#   3. Prepara el .env a partir del .env.example, con los valores del
#      contenedor (que ganan sobre cualquier .env stale del host)
#   4. Genera la APP_KEY si falta
#   5. Ajusta permisos de storage/ y bootstrap/cache/
#   6. Corre las migraciones
#   7. Arranca nginx + php-fpm (via supervisor)
#
# NO hay `php artisan serve`: el nginx de la app resuelve la ruta y php-fpm
# ejecuta el PHP.
# =============================================================================
set -euo pipefail

DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"

WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
APP_DIR="${APP_DIR:-/var/www/html}"
APP_NAME="${APP_NAME:-getbela-backend}"

log()  { printf "\033[0;36m[%s]\033[0;36m %s\033[0m\n" "${APP_NAME}" "$*"; }
warn() { printf "\033[0;33m[%s]\033[0;33m %s\033[0m\n" "${APP_NAME}" "$*" >&2; }
err()  { printf "\033[0;31m[%s]\033[0;31m %s\033[0m\n" "${APP_NAME}" "$*" >&2; }

cd "${APP_DIR}"

# -----------------------------------------------------------------------------
# 1. Esperar a MySQL
# -----------------------------------------------------------------------------
wait_for() {
  local host="$1" port="$2" label="$3"
  log "Esperando ${label} en ${host}:${port} (timeout ${WAIT_TIMEOUT}s)"
  local elapsed=0
  while ! php -r "
    \$s = @fsockopen('${host}', ${port}, \$e, \$m, 2);
    if (\$s) { fclose(\$s); exit(0); }
    exit(1);
  " 2>/dev/null; do
    if [ "${elapsed}" -ge "${WAIT_TIMEOUT}" ]; then
      warn "Timeout esperando ${label} en ${host}:${port}"
      return 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  log "${label} responde en ${host}:${port}"
}

wait_for "${DB_HOST}" "${DB_PORT}" "MySQL" || err "MySQL no responde en ${DB_HOST}:${DB_PORT}"

# -----------------------------------------------------------------------------
# 2. .env
#
# El repo trae .env.example. El .env del host (si existe) se conserva como
# base, pero las variables de infraestructura se sobreescriben con las del
# contenedor: asi la base de datos y la URL siempre apuntan al stack correcto.
# -----------------------------------------------------------------------------
if [ ! -f .env ]; then
  log "No hay .env: se crea desde .env.example"
  cp .env.example .env
else
  log ".env encontrado: se conserva"
fi

# set_env <KEY> <VALUE>
# Reemplaza la linea KEY=... si existe; si no, la agrega al final.
set_env() {
  local key="$1" value="$2"
  if grep -q "^${key}=" .env 2>/dev/null; then
    # El separador de `sed` es `|`, y el valor puede traer `|` raro: se
    # escapan los caracteres especiales del patron.
    local escaped
    escaped=$(printf '%s' "$value" | sed -e 's/[&|]/\\&/g')
    sed -i "s|^${key}=.*|${key}=${escaped}|" .env
  else
    printf '%s=%s\n' "${key}" "${value}" >> .env
  fi
}

set_env APP_NAME       "${APP_NAME}"
set_env APP_ENV        "${APP_ENV:-local}"
set_env APP_DEBUG      "${APP_DEBUG:-true}"
set_env APP_URL        "${APP_URL:-http://localhost:8000}"
set_env LOG_CHANNEL    "${LOG_CHANNEL:-stack}"
set_env LOG_LEVEL      "${LOG_LEVEL:-debug}"
set_env CACHE_STORE    "${CACHE_STORE:-file}"
set_env SESSION_DRIVER "${SESSION_DRIVER:-file}"
set_env QUEUE_CONNECTION "${QUEUE_CONNECTION:-sync}"
set_env DB_CONNECTION  mysql
set_env DB_HOST        "${DB_HOST}"
set_env DB_PORT        "${DB_PORT}"
set_env DB_DATABASE    "${DB_DATABASE}"
set_env DB_USERNAME    "${DB_USERNAME}"
set_env DB_PASSWORD    "${DB_PASSWORD}"

if [ -n "${CORS_ALLOWED_ORIGINS:-}" ]; then
  set_env CORS_ALLOWED_ORIGINS "${CORS_ALLOWED_ORIGINS}"
fi
if [ -n "${SANCTUM_STATEFUL_DOMAINS:-}" ]; then
  set_env SANCTUM_STATEFUL_DOMAINS "${SANCTUM_STATEFUL_DOMAINS}"
fi

# -----------------------------------------------------------------------------
# 3. Dependencias de PHP
#
# `composer install` corre DENTRO del contenedor: el vendor/ del host no
# existe todavia (el repo recien clonado) y las dependencias deben coincidir
# con la plataforma del contenedor (linux), no con la del host (windows).
# -----------------------------------------------------------------------------
if [ -f vendor/autoload.php ]; then
  log "Dependencias de PHP presentes (vendor/autoload.php)"
else
  log "Instalando dependencias de PHP (composer install)"
  if [ -f composer.lock ]; then
    composer install --no-interaction --prefer-dist --no-progress
  else
    composer install --no-interaction --prefer-dist --no-progress
  fi
fi

# -----------------------------------------------------------------------------
# 4. APP_KEY
# -----------------------------------------------------------------------------
if [ -z "$(grep '^APP_KEY=' .env | cut -d= -f2-)" ]; then
  log "Generando APP_KEY"
  php artisan key:generate --force --no-interaction
else
  log "APP_KEY ya esta definida"
fi

# -----------------------------------------------------------------------------
# 5. Permisos
#
# El contenedor corre como hostuser (uid 1000): hay que garantizar que
# pueda escribir en storage/logs y storage/framework.
# En un bind mount de Windows el chmod sobre subdirectorios NO es efectivo.
# -----------------------------------------------------------------------------
log "Ajustando permisos de storage y bootstrap/cache"
mkdir -p storage/framework/cache/data storage/framework/sessions \
         storage/framework/views storage/logs storage/app/public bootstrap/cache

# Laravel espera el symlink public/storage -> storage/app/public (lo usa el
# `php artisan storage:link`). En Windows el symlink no sobrevive al bind
# mount, asi que hay que recrearlo en cada arranque.
if [ ! -e public/storage ]; then
  ln -sfn /var/www/html/storage/app/public public/storage 2>/dev/null \
    || warn "No se pudo crear el symlink public/storage"
fi

# Los permisos de un bind mount en Windows: el chmod sobre subdirectorios
# falla con "Operation not permitted" (son inodos respaldados por Windows).
# La raiz del bind mount ya es 777, asi que alcanza con crear lo que falte.
chmod -R 777 storage bootstrap/cache 2>/dev/null \
  || warn "No se pudieron ajustar permisos (revisar ownership en el host)"

# -----------------------------------------------------------------------------
# 6. Migraciones
#
# Se corren en cada arranque: son idempotentes y asi el esquema siempre
# corresponde al codigo montado. Si fallan, el contenedor lo dice y sigue:
# un fallo de migracion no deberia impedir levantar la API.
# -----------------------------------------------------------------------------
log "Corriendo migraciones"
php artisan migrate --force --no-interaction || err "Las migraciones fallaron (el contenedor sigue arriba)"

# -----------------------------------------------------------------------------
# 6b. Seeds (datos de prueba)
#
# GETBELA_RUN_SEEDS=true corre el DatabaseSeeder, que delega en
# DemoDataSeeder (categorias, super admin, negocios de prueba con duenos,
# empleados y servicios).
#
# Los seeds se saltan si la base YA tiene negocios: son idempotentes a
# nivel de esquema pero no deben duplicar datos en cada reinicio del
# contenedor. El chequeo es por la tabla `businesses`, que el seeder crea.
#
# Con GETBELA_RUN_SEEDS=false (o ausente) los seeds no se corren.
# -----------------------------------------------------------------------------
if [ "${GETBELA_RUN_SEEDS:-false}" = "true" ]; then
  log "Verificando si ya hay datos de prueba"
  SEEDED=$(php artisan tinker --execute='
    try {
        echo \Illuminate\Support\Facades\DB::table("businesses")->count();
    } catch (\Throwable $e) {
        echo "0";
    }
' 2>/dev/null | tr -dc '0-9' || echo "0")

  if [ "${SEEDED:-0}" -gt 0 ]; then
    log "La base ya tiene ${SEEDED} negocio(s): no se corren los seeds"
  else
    log "Corriendo seeds (datos de prueba)"
    php artisan db:seed --force --no-interaction || warn "Los seeds fallaron (el contenedor sigue arriba)"
  fi
else
  log "GETBELA_RUN_SEEDS no es true: no se corren seeds"
fi

# -----------------------------------------------------------------------------
# 7. Arranque
# -----------------------------------------------------------------------------
if [ "${1:-}" = "supervisord" ] || [ "${1:-}" = "/usr/bin/supervisord" ]; then
  log "Arrancando nginx + php-fpm"
  exec "$@"
fi

log "Arrancando: $*"
exec "$@"
