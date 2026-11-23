# =============================================================================
# Imagen del frontend de GetBela: React 19 + Vite 8 sobre Node 22.
#
# Es una imagen PROPIA del grupo getbela (el stack docker-windows no tiene
# una capa de Node para SPAs).
#
# El codigo viene por bind mount desde el host
# (GetBela/sitio-web/GetBela-App/frontend), asi que el node_modules del
# contenedor se monta como volumen anonimo: se usa la instalacion de linux,
# no la del host (windows), que tiene binarios incompatibles.
#
# El `npm install` NO corre en el build: el package.json del host puede
# cambiar en cualquier momento y la instalacion tiene que reflejar eso. Corre
# en el entrypoint, en el arranque del contenedor.
# =============================================================================
FROM node:22-alpine

# ---------------------------------------------------------------------------
# Paquetes de sistema
#
# `libc6-compat` es lo que necesitan los binarios nativos de Vite/Rollup en
# Alpine, y `bash` para el entrypoint.
# ---------------------------------------------------------------------------
RUN apk add --no-cache \
        bash \
        libc6-compat \
        tzdata \
    && rm -rf /var/cache/apk/*

ENV TZ=${TZ:-America/Santiago}

WORKDIR /app

# ---------------------------------------------------------------------------
# El entrypoint espera a que el codigo este montado (bind mount) antes de
# decidir si hay que instalar dependencias.
# ---------------------------------------------------------------------------
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5173

CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
