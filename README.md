# CanaanCope.Land on Railway

Deployment wrapper for [CanaanJC/CanaanCope.Land](https://github.com/CanaanJC/CanaanCope.Land),
a dependency-free Node site engine originally built for a Debian home server.
This repo contains no application code: the Dockerfile clones the upstream
repo at a pinned tag and adds the two things a container platform needs,
`ffmpeg` and persistent storage.

## Layout

| File | Purpose |
|---|---|
| `Dockerfile` | `node:22-slim` + `ffmpeg`, clones upstream at `UPSTREAM_TAG`, keeps a pristine copy of `config/` and `public/` in `/app/.seed` |
| `entrypoint.sh` | Seeds/symlinks `config/`, `public/`, `extensions/` onto the volume, then runs `node node.js` |
| `railway.json` | Dockerfile builder, `/` healthcheck, restart on failure |

## How persistence works

The app writes next to its own files at runtime: `config/master.json`,
`config/theme.json`, `config/backup/`, blog posts and media under `public/`,
and `extensions/`. The container filesystem is thrown away on every deploy,
so those three directories live on a Railway volume mounted at `/data`
(`DATA_DIR`) and are symlinked back into `/app`.

On every boot the entrypoint compares the shipped files in `/app/.seed` with
the volume:

- **First boot**: everything shipped in `config/` and `public/` is copied to the volume.
- **File missing on the volume**: copied in.
- **`config/defaults.json`**: always replaced (engine defaults, same as upstream's `update.sh`).
- **Shipped file you never touched**: replaced when upstream changes it.
- **Shipped file the admin panel or you modified**: left alone and logged
  (`kept user-modified ...`). The new upstream copy is at `/app/.seed/<path>`.
- **Files that only exist on the volume** (posts, media, `master.json`, backups): never touched.

A hash manifest at `/data/.seed-manifest` tracks what was last seeded.
`config/version.txt` is rewritten each boot with `UPSTREAM_TAG` so the
in-app update checker reports the right version.

## Updating upstream

The in-app updater (`update.sh`) does not work in a container. To update:

1. Edit `ARG UPSTREAM_TAG=...` at the top of `Dockerfile` to the new
   [release tag](https://github.com/CanaanJC/CanaanCope.Land/releases).
2. Commit and push. Railway rebuilds and redeploys; the entrypoint refreshes
   unmodified engine files on the volume.

## Environment variables

| Variable | Default | Notes |
|---|---|---|
| `PORT` | injected by Railway | Public site port. Falls back to `config` `hosting.port` (9138). |
| `HOST` | `0.0.0.0` | Bind address. |
| `ADMIN_PORT` | `9832` | Admin panel port. **No auth.** Not exposed publicly. |
| `ADMIN_HOST` | `0.0.0.0` | Admin bind address. |
| `DATA_DIR` | `/data` | Volume mount path. |

## Admin panel

The admin panel has no authentication, so it is deliberately not given a
public domain. It is reachable only inside the Railway project's private
network at `<service>.railway.internal:9832`. Options if you need it:

- `railway ssh` into the service and use `curl` against `localhost:9832`.
- Run a second service in the project (e.g. an SSH/VPN bastion or a
  basic-auth reverse proxy) that forwards to the private address.
- A Railway TCP proxy would expose it to the internet **without auth**; avoid
  unless you put something in front of it.

## Backups

The app's built-in backup copies site files to `backup.path` from the admin
panel. Point it inside the volume (for example `/data/backups`) or it will
vanish on redeploy. Railway also offers volume backups from the dashboard.

## Running locally

```bash
docker build -t canaancope .
docker run --rm -p 9138:9138 -p 9832:9832 -v canaancope-data:/data canaancope
```

Site at http://localhost:9138, admin at http://localhost:9832.
