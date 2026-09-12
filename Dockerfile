# syntax=docker/dockerfile:1
#
# Railway wrapper for CanaanCope.Land (https://github.com/CanaanJC/CanaanCope.Land).
# The upstream app is cloned at a pinned tag; nothing here modifies it.
# To update: bump UPSTREAM_TAG below and redeploy.

ARG UPSTREAM_TAG=26.9.2
ARG UPSTREAM_REPO=https://github.com/CanaanJC/CanaanCope.Land

# ---- stage 1: fetch the pinned upstream tag -------------------------------
FROM node:22-slim AS source
ARG UPSTREAM_TAG
ARG UPSTREAM_REPO
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${UPSTREAM_TAG}" "${UPSTREAM_REPO}" /src \
 && rm -rf /src/.git

# ---- stage 2: runtime -------------------------------------------------------
FROM node:22-slim
ARG UPSTREAM_TAG
ENV UPSTREAM_TAG=${UPSTREAM_TAG} \
    DATA_DIR=/data \
    NODE_ENV=production

# ffmpeg: media compression + favicon generation (the app skips both if missing).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=source /src /app

# Keep a pristine copy of the shipped config/ and public/ trees. entrypoint.sh
# seeds the persistent volume from these on first boot and refreshes
# unmodified engine files on later boots (after a tag bump).
RUN mkdir -p /app/.seed/extensions \
 && cp -a /app/config /app/.seed/config \
 && cp -a /app/public /app/.seed/public

# Extra pages shipped with this wrapper (served from public/ on the volume).
COPY site/ /app/.seed/public/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Public site (Railway injects PORT). The admin panel listens on ADMIN_PORT
# (default 9832) and is intentionally NOT exposed.
EXPOSE 9138

ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "node.js"]
