# offen-railway

Railway wrapper image for [Offen Fair Web Analytics](https://www.offen.dev/), pinned to
upstream `v1.4.2` by digest.

Published as `ghcr.io/bon5co/offen-railway:1.4.2`.

## What the wrapper changes

**It leaves Offen's login throttle enabled.** Offen swaps its rate limiter for
`ratelimiter.NewNoopRateLimiter()` whenever `OFFEN_SERVER_REVERSEPROXY` is set
(`server/router/router.go:44`), and that limiter is the only brute-force protection in the
product — it guards login, password reset, password change, invitations, account creation
and the user-secret exchange. Every existing Railway template for Offen sets that flag,
because Railway terminates TLS at its edge and upstream's docs recommend it for
reverse-proxy deployments.

The flag is unnecessary here. Offen's throttle keys on the submitted username and on a
single global bucket (`postLogin-%s` and `postLogin-*`), never on the client address, so
the "the proxy is the client" problem the flag exists for does not apply. What the flag
actually costs on Railway is measured: 15 wrong-password POSTs to `/api/login` complete in
**0.3 s** with the flag set and in **7.6 s** without it, the second and later attempts each
blocking for 0.5–1.0 s.

Leaving the flag off also re-enables upstream's stdout access log. That log prints no
client address (the field is a literal `-`) and anonymises non-error status codes, which is
why it is safe to run for a privacy tool.

The entrypoint additionally:

- refuses to boot on an empty `OFFEN_ADMIN_PASSWORD`, `OFFEN_ADMIN_EMAIL`, `OFFEN_SECRET`
  or `DATABASE_URL` instead of coming up in a broken or open state,
- validates `OFFEN_ADMIN_PASSWORD` against upstream's 8–64 character rule and `OFFEN_SECRET`
  as standard base64 before it reaches a boot that would fail on them,
- waits for Postgres, runs `offen migrate`, and seeds the first operator with `offen setup`
  before the server binds a port — the seed is idempotent across redeploys,
- keeps the admin password out of the served process's environment.

Variables that do **not** exist in Offen v1.4.2 and are deliberately not set here:
`OFFEN_SERVER_DOMAIN`, `OFFEN_SERVER_AUTHTOKEN`, `OFFEN_SERVER_COOKIEEXCHANGESECRET`.
The v1.4.2 config struct is `server/config/definition_unix.go`; none of those keys appear
in it, so `envconfig` ignores them.

## Environment

| Variable | Required | Notes |
| --- | --- | --- |
| `DATABASE_URL` | yes | Postgres connection string |
| `OFFEN_SECRET` | yes | standard base64; 64 alphanumeric characters decode to 48 bytes |
| `OFFEN_ADMIN_EMAIL` | yes | login for the operator console |
| `OFFEN_ADMIN_PASSWORD` | yes | 8–64 characters |
| `OFFEN_ACCOUNT_NAME` | no | display name of the first analytics account, default `My Website` |
| `PORT` | injected | Railway's port; Offen is started on it |

## Tracker snippet

The first account is created with a fixed id so the snippet is the same for every deploy:

```html
<script async src="https://YOUR-DOMAIN/script.js"
        data-account-id="8f3a5c21-0d47-4b6e-9a52-1c8e7f40b3d9"></script>
```

## Upstream

- Source: <https://github.com/offen/offen>
- Docs: <https://docs.offen.dev/>
- License: Apache-2.0
