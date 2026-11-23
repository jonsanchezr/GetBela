# =============================================================================
# Imagen del backend de GetBela: Laravel 13 sobre PHP 8.3.
#
# Es una imagen PROPIA del grupo getbela. El stack docker-windows usa PHP 8.2
# con Laravel 9, y este repo declara "php": "^8.3" con Laravel 13, asi que no
# puede compartir la imagen `docker-windows/app:dev`.
#
# Modelo de procesos (dentro del contenedor):
#   nginx    -> :80             (HTTP, document root /var/www/html/public)
#   php-fpm  -> 127.0.0.1:9000  (FastCGI, solo loopback)
#
# El codigo de la aplicacion viene por bind mount desde el host
# (GetBela/sitio-web/GetBela-App/backend), asi que los cambios en PHP se ven
# en el contenedor de inmediato.
#
# NO hay `php artisan serve` en el camino de la peticion: el nginx de la app
# resuelve la ruta y php-fpm ejecuta el PHP.
# =============================================================================
FROM php:8.3-fpm-alpine

# ---------------------------------------------------------------------------
# Paquetes de sistema
#
# nginx + supervisor: los dos procesos de la app, orquestados por supervisor.
# ---------------------------------------------------------------------------
RUN apk add --no-cache \
        bash \
        curl \
        git \
        unzip \
        tzdata \
        nginx \
        icu-dev \
        libxml2-dev \
        libzip-dev \
        oniguruma-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        supervisor \
    && rm -rf /var/cache/apk/*

# ---------------------------------------------------------------------------
# Extensiones PHP
#
# Solo las que NO vienen en la imagen oficial. Reconstruir las que ya estan
# (tokenizer, dom, xml, ...) falla porque la imagen no trae las fuentes del
# parser de PHP.
#
# pdo_mysql es obligatoria: es la conexion a la base de datos de GetBela.
# ---------------------------------------------------------------------------
RUN docker-php-ext-install -j"$(nproc)" \
        pdo_mysql \
        bcmath \
        intl \
        mbstring \
        xml \
        zip \
        opcache \
        gd \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    # NO se eliminan libpng/libzip/freetype/libjpeg: las extensiones
    # compiladas (gd, zip) las necesitan en runtime, no solo en build.
    #
    # IMPORTANTE: se borran SOLO los paquetes -dev, NO sus librerias de
    # runtime. `apk del icu-dev` arrastra tambien `icu-libs` (y `icu-data-en`,
    # `libstdc++`), y la extension intl deja de cargar con:
    #   "Unable to load dynamic library 'intl' ... libicuio.so.78: No such
    #    file or directory"
    && apk del icu-dev libxml2-dev oniguruma-dev \
    && apk add --no-cache icu-libs icu-data-en libstdc++ \
    && rm -rf /var/cache/apk/*

# ---------------------------------------------------------------------------
# Extension redis
#
# El .env.example del repo declara REDIS_CLIENT=phpredis. Este grupo no
# levanta un Redis propio (el cache y las sesiones van a file/database), asi
# que la extension se deja compilada para que el repo pueda activarla por su
# cuenta sin tener que reconstruir la imagen.
#
# Se compila desde el tarball de GitHub y no con `pecl install redis`: el
# canal PECL (pecl.php.net) se alcanza por TLS y desde los contenedores corta
# la conexion de forma intermitente ("No releases available for package
# pecl.php.net/redis"), lo que rompe el build de la imagen por un motivo ajeno
# a la aplicacion.
# ---------------------------------------------------------------------------
ARG PHPREDIS_VERSION=6.3.0
RUN apk add --no-cache linux-headers \
    && curl -fsSL -o /tmp/phpredis.tar.gz \
        "https://github.com/phpredis/phpredis/archive/refs/tags/${PHPREDIS_VERSION}.tar.gz" \
    && mkdir -p /usr/src/php/ext/redis \
    && tar -xzf /tmp/phpredis.tar.gz -C /usr/src/php/ext/redis --strip-components=1 \
    && rm /tmp/phpredis.tar.gz \
    && docker-php-ext-configure redis \
    && docker-php-ext-install redis \
    && apk del linux-headers \
    && rm -rf /var/cache/apk/* /tmp/pear

# ---------------------------------------------------------------------------
# Composer
#
# El `composer install` NO corre en el build: el codigo llega por bind mount
# en tiempo de ejecucion, y las dependencias se instalan en el contenedor
# (ver entrypoint.sh). Instalar en el build seria tirar la basura: el
# vendor/ del host no existe todavia y el volumen montado lo taparia.
# ---------------------------------------------------------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# ---------------------------------------------------------------------------
# Configuracion PHP
#
# OPcache en modo desarrollo: los cambios hechos en el host se toman en la
# siguiente peticion, sin esperar a que expire la ventana de cache.
# ---------------------------------------------------------------------------
RUN { \
      echo 'opcache.enable=1'; \
      echo 'opcache.enable_cli=0'; \
      echo 'opcache.validate_timestamps=1'; \
      echo 'opcache.revalidate_freq=0'; \
      echo 'memory_limit=512M'; \
      echo 'upload_max_filesize=32M'; \
      echo 'post_max_size=32M'; \
      echo 'max_execution_time=120'; \
    } > /usr/local/etc/php/conf.d/zz-dev.ini

# ---------------------------------------------------------------------------
# nginx (servidor web de la app) + supervisor (php-fpm + nginx)
# ---------------------------------------------------------------------------
COPY nginx/app-nginx.conf /etc/nginx/nginx.conf
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

# php-fpm: sobreescribe el www.conf por defecto, que escucha en 0.0.0.0:9000
# (alcanzable desde la red Docker). Este lo limita a loopback: solo el nginx
# de este contenedor puede hablarle.
COPY php-fpm.conf /usr/local/etc/php-fpm.d/zz-app.conf

# ---------------------------------------------------------------------------
# Usuario con UID/GID 1000
#
# Laravel escribe en storage/ y bootstrap/cache/ sobre el bind mount. En
# Windows los permisos de un bind mount no se mapean a Linux, asi que el
# entrypoint aplica los bits de escritura con chmod. El UID 1000 coincide con
# el de Windows y con el que usan las imagenes de code/docker.
# ---------------------------------------------------------------------------
RUN addgroup -g 1000 -S hostgroup \
    && adduser -u 1000 -G hostgroup -S -D hostuser

# Directorios que necesita nginx. El chown va DESPUES de crear el usuario.
RUN mkdir -p /var/log/nginx /var/lib/nginx/tmp /etc/nginx/conf.d /var/www/html \
    && chown -R hostuser:hostgroup /var/log/nginx /var/lib/nginx /etc/nginx/conf.d /var/www/html

# ---------------------------------------------------------------------------
# storage/
#
# Cuando Docker inicializa un volumen nombrado, copia el contenido y la
# PROPIEDAD del directorio que existe en la imagen en esa ruta. Si la ruta NO
# existe en la imagen, el volumen se crea como root:root 755 y el usuario del
# contenedor (hostuser, uid 1000) no puede escribir en el.
#
# En Windows eso es lo que rompia la app: el chmod sobre un bind mount
# falla ("Operation not permitted"), y Laravel no podia escribir el log ni
# las sesiones -> HTTP 500 en cada peticion. Con los directorios precreados
# y con ownership de hostuser, el volumen nace con el ownership correcto y
# el chmod 777 del entrypoint es un extra, no la unica via.
# ---------------------------------------------------------------------------
RUN mkdir -p /var/www/html/storage/logs \
             /var/www/html/storage/framework/cache/data \
             /var/www/html/storage/framework/sessions \
             /var/www/html/storage/framework/testing \
             /var/www/html/storage/framework/views \
             /var/www/html/storage/app/public \
    && chown -R hostuser:hostgroup /var/www/html/storage \
    && chmod -R 777 /var/www/html/storage

USER hostuser

WORKDIR /var/www/html

# nginx escucha en 80 (dentro del contenedor), php-fpm en 9000
EXPOSE 80

# nginx + php-fpm, orquestados por supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
