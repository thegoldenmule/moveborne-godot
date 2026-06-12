# Generic static-site host BYOSnap: stock nginx serving whatever is dropped into ./site.
# Reusable across games/snaps — nothing in here is Moveborne-specific. The web build for a
# given game is copied into ./site before `docker build` (or baked in by a CI step).
#
# nginx 1.27 is well past 1.21.1, so `application/wasm` is already in the stock mime.types
# (required for browsers to stream-compile the Godot/emscripten .wasm). .pck stays
# application/octet-stream, which is correct.
FROM nginx:1.27-alpine

# The gateway forwards the FULL base path unstripped (e.g. /v1/byosnap-site-host/...), so the
# server block matches on it. BASE_PATH is the only thing that changes per snap/game; override
# it (and LISTEN_PORT) via the BYOSnap profile env_params. Defaults here keep `docker run`
# working locally with no args.
ENV BASE_PATH=/v1/byosnap-site-host \
    LISTEN_PORT=8080 \
    NGINX_ENVSUBST_FILTER='BASE_PATH|LISTEN_PORT'

# The official image runs envsubst over /etc/nginx/templates/*.template at container start,
# writing the result to /etc/nginx/conf.d/ (overwriting the stock default.conf). The FILTER
# above restricts substitution to our two vars so nginx runtime vars ($uri, $host, …) survive.
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# The site payload. Empty in git (just .gitkeep); a real game build is synced into ./site
# (see sync-build.sh) before building.
COPY site/ /usr/share/nginx/html/

EXPOSE 8080
