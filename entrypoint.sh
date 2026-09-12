#!/bin/sh
# Entrypoint for CanaanCope.Land on Railway.
#
# The app writes to config/, public/ and extensions/ (relative to its own
# directory) at runtime. The container filesystem is ephemeral, so those three
# directories live on a persistent volume (DATA_DIR, default /data) and are
# symlinked back into the app directory.
#
# Seeding rules, applied every boot against the pristine copy in /app/.seed:
#   * file missing on the volume            -> copied in (first boot seeds everything)
#   * file identical to the shipped copy    -> nothing to do
#   * config/defaults.json                  -> always replaced (engine defaults)
#   * file unchanged since it was last      -> replaced with the new shipped
#     seeded (hash matches .seed-manifest)     version (i.e. an upstream update)
#   * file modified by the user/admin panel -> left alone, logged
# Files that only exist on the volume (blog posts, media, master.json, ...)
# are never touched.
set -eu

APP_DIR="${APP_DIR:-/app}"
DATA_DIR="${DATA_DIR:-/data}"
SEED_DIR="$APP_DIR/.seed"
MANIFEST="$DATA_DIR/.seed-manifest"
NEW_MANIFEST="$MANIFEST.new"

log() { echo "[entrypoint] $*"; }

hash_of() { sha256sum "$1" | cut -d' ' -f1; }

# Previous seeded hash of a path (empty if never seeded). Manifest lines are
# "<sha256><TAB><relative path>".
prev_hash() {
    [ -f "$MANIFEST" ] || return 0
    awk -F'\t' -v p="$1" '$2 == p { print $1; exit }' "$MANIFEST"
}

seed_tree() {
    name="$1"
    src="$SEED_DIR/$name"
    dst="$DATA_DIR/$name"
    mkdir -p "$dst"

    if [ -d "$src" ]; then
        (cd "$src" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) | while IFS= read -r rel; do
            new="$src/$rel"
            cur="$dst/$rel"
            key="$name/$rel"
            # version.txt is written from UPSTREAM_TAG below, never synced.
            if [ "$key" = "config/version.txt" ]; then continue; fi
            newh=$(hash_of "$new")
            printf '%s\t%s\n' "$newh" "$key" >> "$NEW_MANIFEST"

            if [ ! -e "$cur" ]; then
                mkdir -p "$(dirname "$cur")"
                cp -p "$new" "$cur"
                if [ "$FIRST_RUN" = 0 ]; then log "added $key"; fi
                continue
            fi

            curh=$(hash_of "$cur")
            if [ "$curh" = "$newh" ]; then
                continue
            fi

            if [ "$key" = "config/defaults.json" ]; then
                cp -p "$new" "$cur"
                log "refreshed $key (always replaced)"
                continue
            fi

            prevh=$(prev_hash "$key")
            if [ -n "$prevh" ] && [ "$curh" = "$prevh" ]; then
                cp -p "$new" "$cur"
                log "updated $key"
            elif [ -n "$prevh" ] && [ "$newh" = "$prevh" ]; then
                : # user-modified, upstream unchanged: nothing to report
            else
                log "kept user-modified $key (new upstream copy at $SEED_DIR/$key)"
            fi
        done
    fi

    rm -rf "$APP_DIR/$name"
    ln -s "$dst" "$APP_DIR/$name"
}

mkdir -p "$DATA_DIR"
if [ -f "$MANIFEST" ]; then
    FIRST_RUN=0
    log "volume at $DATA_DIR already seeded; syncing shipped files for upstream ${UPSTREAM_TAG:-unknown}"
else
    FIRST_RUN=1
    log "first boot: seeding $DATA_DIR from shipped files (upstream ${UPSTREAM_TAG:-unknown})"
fi
: > "$NEW_MANIFEST"

for tree in config public extensions; do
    seed_tree "$tree"
done

mv "$NEW_MANIFEST" "$MANIFEST"

# Tell the app's update checker which upstream version is running.
if [ -n "${UPSTREAM_TAG:-}" ]; then
    printf '%s\n' "$UPSTREAM_TAG" > "$DATA_DIR/config/version.txt"
fi

log "config/ public/ extensions/ -> $DATA_DIR"
log "starting: $*"
exec "$@"
