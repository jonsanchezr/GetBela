# GetBela

Grupo de contenedores para **GetBela**, un proyecto independiente del stack
`docker-windows`.

No comparte nada con `docker-windows`: ni imágenes, ni redes, ni MySQL, ni
puertos. Se levanta y se baja por separado.

## Estructura

```
GetBela/
├── compose.getbela.yaml            # Desarrollo (Docker Desktop, hot-reload)
├── compose.getbela.prod.yaml       # Producción (VPS, detrás de Traefik)
├── bootstrap.sh                    # Prepara el servidor la primera vez
├── .env                            # Secretos (git-ignored)
├── .env.example                    # Plantilla para otras máquinas
├── docker/
│   ├── backend/                    # Imagen PHP 8.3 + nginx + php-fpm
│   │   ├── Dockerfile
│   │   ├── entrypoint.sh
│   │   ├── nginx/app-nginx.conf
│   │   ├── php-fpm.conf
│   │   └── supervisor/supervisord.conf
│   ├── frontend/                   # Imagen Node 22 + Vite
│   │   ├── Dockerfile              #   versión desarrollo (dev-server)
│   │   ├── Dockerfile.prod         #   versión producción (build + nginx)
│   │   ├── entrypoint.sh
│   │   └── nginx/default.conf      #   configuración del nginx de producción
│   └── mysql/
│       └── init/                   # .sql que corren en el primer arranque
├── app/                            # Código clonado en producción (git-ignored)
│   ├── backend/                    #   Laravel 13
│   └── frontend/                   #   React 19 + Vite 8
└── GetBela/                        # Código en Docker Desktop (git-ignored)
    └── sitio-web/
        └── GetBela-App/            #   El repo clonado (GetBela-App)
```

## Servicios

| Servicio  | Stack                       | Puerto interno | Rol                                  |
| --------- | --------------------------- | -------------- | ------------------------------------ |
| `mysql`   | MySQL 8.0 LTS (Debian)       | 3306           | Base de datos propia del grupo       |
| `backend` | Laravel 13, PHP 8.3, nginx  | 80              | API REST en `/api/*`                 |
| `frontend`| React 19 + Vite 8 (build)    | 80              | SPA servida con nginx                |

### Nota sobre la imagen de MySQL

Se usa **`mysql:8.0-debian`**, no `mysql:8.4` ni `mysql:8.0` (glibc).

MySQL 8.4 y 8.0 compilados contra glibc exigen una CPU **x86-64-v2** (SSE4.2 y
POPCNT) y abortan al arrancar con:

```
Fatal glibc error: CPU does not support x86-64-v2
```

La build Debian de 8.0 está compilada con un baseline más bajo y funciona en
servidores con CPU emulada básica. El flag de autenticación también difiere
entre versiones: 8.0 usa `--default-authentication-plugin`, mientras que
8.4 lo reemplazó por `--mysql-native-password=ON`.


## Desarrollo (Docker Desktop)

```bash
cp .env.example .env    # completar los secretos
docker compose -f compose.getbela.yaml up -d
docker compose -f compose.getbela.yaml ps
docker compose -f compose.getbela.yaml logs -f
docker compose -f compose.getbela.yaml down
```

El frontend corre en <http://127.0.0.1:5173> y la API en
<http://127.0.0.1:8000>. No hay proxy inverso en desarrollo: el navegador
entra por 5173 y llama a la API por 8000.

El código se monta por *bind mount* desde `./GetBela/sitio-web/GetBela-App`,
así que los cambios en PHP y React se ven de inmediato.

### URL de la API en el frontend

La URL base de la API se resuelve con la variable de entorno `VITE_API_URL`:

- En desarrollo: `VITE_API_URL=http://localhost:8000` (URL absoluta, el
  frontend y la API están en puertos distintos → CORS).
- En producción: `VITE_API_URL=/api` (ruta relativa, mismo dominio → sin
  CORS).

Si no está definida, la base queda vacía y las URLs son relativas al
dominio actual.

## Producción (VPS)

El sitio se sirve en <https://getbela.syrexsoftware.com>, con Traefik
terminando TLS y enrutando:

| Ruta                          | Servicio  |
| ----------------------------- | --------- |
| `/`                           | `frontend`|
| `/api/*`, `/sanctum/*`        | `backend` |

### Preparación (una vez)

```bash
git clone <este-repo> /opt/getbela
cd /opt/getbela
./bootstrap.sh
docker compose -f compose.getbela.prod.yaml up -d --build
```

`bootstrap.sh` genera el `.env` con secretos aleatorios, clona el código de
la aplicación en `./app` y prepara los permisos de `storage/`.

### Ciclo de actualización

```bash
cd app && git pull && cd ..
docker compose -f compose.getbela.prod.yaml up -d --build
```

### Diferencias con desarrollo

1. El frontend es un **build estático** servido por nginx, no el dev-server
   de Vite. El build corre dentro de la imagen (`Dockerfile.prod`).
2. El backend toma el código del repo clonado en `./app/backend`, no de un
   bind mount de una máquina de desarrollo.
3. **Ningún puerto se publica en el host.** Traefik enruta por la red del
   grupo. Publicarlos abriría el backend y el MySQL a internet.
4. `APP_ENV=production` y `APP_DEBUG=false`: los errores no filtran el stack
   trace al navegador.
5. `CORS_ALLOWED_ORIGINS` y `SANCTUM_STATEFUL_DOMAINS` apuntan al dominio
   real, no a `localhost:5173`.
6. El frontend se compila con `VITE_API_URL` **vacío**: el código llama a la
   API con el prefijo ya incluido (`api.get("/api/public/services")`), así
   que una base `/api` produciría `/api/api/public/services`.

### Enrutamiento en Traefik

El frontend y el backend comparten el dominio y se reparten por prefijo:

| Prefijo               | Servicio  |
| --------------------- | --------- |
| `/api/*`              | `backend` |
| `/sanctum/*`          | `backend` |
| `/storage/*`          | `backend` |
| todo lo demás         | `frontend`|

La regla del frontend excluye explícitamente esos prefijos. Sin la
exclusión, su regla (`Host(...)`) se quedaría también con las peticiones de
la API y respondería con el `index.html` de la SPA en vez del JSON.

### Seeds

El backend corre las migraciones en cada arranque. Los seeds (categorías,
super admin, negocios de prueba con sus dueños, empleados y servicios) se
ejecutan solo si la tabla `businesses` está vacía, y se pueden desactivar
con `GETBELA_RUN_SEEDS=false` en el `.env`.

Credenciales del admin que crea el seed: `admin@getbela.com` / `password123`.

### Actualizar el código

```bash
cd /opt/getbela/app && git pull
cd /opt/getbela
chown -R 1000:1000 app/backend
docker compose -f compose.getbela.prod.yaml up -d --build
```

El `chown` es necesario: el contenedor backend corre como uid 1000 y el
`git pull` deja el código con el owner del repositorio, lo que impide crear
el `.env` y el `vendor/` de composer dentro del contenedor.

### Arranque tras un reinicio

Los tres servicios declaran `restart: unless-stopped`, así que Docker los
levanta solo. No hace falta ningún servicio adicional.


## Comandos utiles

```bash
# Estado
docker compose -f compose.getbela.prod.yaml ps

# Logs
docker compose -f compose.getbela.prod.yaml logs -f backend
docker compose -f compose.getbela.prod.yaml logs -f frontend

# Entrar a un contenedor
docker compose -f compose.getbela.prod.yaml exec backend sh
docker compose -f compose.getbela.prod.yaml exec mysql mysql -u getbela -p

# Artisan
docker compose -f compose.getbela.prod.yaml exec backend php artisan migrate --force
docker compose -f compose.getbela.prod.yaml exec backend php artisan db:seed --force

# Bajar todo (conserva los volumenes)
docker compose -f compose.getbela.prod.yaml down
```
