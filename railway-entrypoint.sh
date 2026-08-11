#!/bin/sh
# Railway entrypoint for Offen Fair Web Analytics.
#
# Responsibilities, in order:
#   1. refuse to boot on a missing/empty credential rather than coming up open
#   2. keep Offen's built-in login throttle enabled (see the REVERSEPROXY note)
#   3. wait for Postgres, run migrations
#   4. seed the first operator account before the server binds a port
#   5. exec the stock server
set -eu

log() { printf '[railway] %s\n' "$1"; }

require() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    log "$name is empty - refusing to boot."
    exit 1
  fi
}

require DATABASE_URL
require OFFEN_SECRET
require OFFEN_ADMIN_EMAIL
require OFFEN_ADMIN_PASSWORD

case "$OFFEN_ADMIN_EMAIL" in
  *@*) ;;
  *)
    log "OFFEN_ADMIN_EMAIL must be an email address - refusing to boot."
    exit 1
    ;;
esac

# offen/server/keys/password.go: 8 <= len(password) <= 64, enforced at bootstrap.
password_length=${#OFFEN_ADMIN_PASSWORD}
if [ "$password_length" -lt 8 ] || [ "$password_length" -gt 64 ]; then
  log "OFFEN_ADMIN_PASSWORD must be between 8 and 64 characters - refusing to boot."
  exit 1
fi

# offen/server/config/bytes.go decodes OFFEN_SECRET as standard base64 and
# fails the whole boot if it is not decodable.
if ! printf '%s' "$OFFEN_SECRET" | base64 -d >/dev/null 2>&1; then
  log "OFFEN_SECRET is not valid base64 - refusing to boot."
  exit 1
fi

# Railway terminates TLS at its edge, so it is tempting to set
# OFFEN_SERVER_REVERSEPROXY=true here. Do not: offen/server/router/router.go:44
# swaps the throttler for ratelimiter.NewNoopRateLimiter() whenever that flag is
# set, and that throttler is the only brute-force protection Offen has. It keys
# on the username and on a global bucket, never on the client address, so the
# proxy-awareness problem the flag exists for does not apply behind Railway.
# Leaving it off costs a stdout access log (no client address, status codes
# anonymised) and buys a throttle on login, password reset, invitations and the
# user-secret exchange.
unset OFFEN_SERVER_REVERSEPROXY

export OFFEN_SERVER_PORT="${PORT:-8080}"
export OFFEN_DATABASE_DIALECT=postgres
export OFFEN_DATABASE_CONNECTIONSTRING="$DATABASE_URL"
export OFFEN_DATABASE_CONNECTIONRETRIES=20
export OFFEN_APP_SINGLENODE=true
export OFFEN_APP_ROOTACCOUNT="$OFFEN_ROOT_ACCOUNT_ID"

admin_email="$OFFEN_ADMIN_EMAIL"
admin_password="$OFFEN_ADMIN_PASSWORD"
account_name="${OFFEN_ACCOUNT_NAME:-My Website}"

# The password must not survive into the served process's environment.
unset OFFEN_ADMIN_PASSWORD

attempt=1
until offen migrate; do
  if [ "$attempt" -ge 40 ]; then
    log "database migrations did not succeed after 80 seconds."
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 2
done

setup_log=$(mktemp)
if offen setup \
  -email "$admin_email" \
  -name "$account_name" \
  -password "$admin_password" \
  -forceid "$OFFEN_ROOT_ACCOUNT_ID" >"$setup_log" 2>&1
then
  log "seeded the initial operator account ($admin_email)."
elif grep -Fq 'action would overwrite existing data - not allowed' "$setup_log"; then
  log "operator account already exists, leaving it alone."
else
  cat "$setup_log" >&2
  log "could not seed the initial operator account."
  exit 1
fi
rm -f "$setup_log"

log "starting offen on port $OFFEN_SERVER_PORT with the login throttle enabled."
exec offen serve
