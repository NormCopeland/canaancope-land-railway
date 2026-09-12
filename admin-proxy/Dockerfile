# Basic-auth reverse proxy in front of the CanaanCope.Land admin panel.
# Runs as a second Railway service in the same project; reaches the app over
# Railway's private network. Credentials come from Railway variables:
#   ADMIN_USER            username
#   ADMIN_PASSWORD_HASH   bcrypt hash (e.g. `caddy hash-password` or `htpasswd -nbB`)
#   ADMIN_UPSTREAM        host:port of the admin server (default below)
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
