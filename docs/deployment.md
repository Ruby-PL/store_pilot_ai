# StorePilot AI Deployment Notes

## Staging environment

StorePilot AI uses a separate staging environment for Shopify OAuth, webhook
testing, sync jobs, and audit verification.

The staging app host is configured with `APP_HOST`. Set it to the real staging
domain you control, for example `staging.storepilot.example`.

Staging uses its own:

- Rails environment: `staging`
- PostgreSQL database
- Redis instance
- Solid Queue database
- Solid Cable database
- Shopify app credentials and callback URLs
```bash
bin/kamal setup
bin/kamal deploy
bin/kamal setup -d production
bin/kamal deploy -d production
bin/kamal app exec --interactive --reuse "bin/rails console"
bin/kamal logs -f
```

## Required setup

Before the first production deploy, provide these values from the shell or a
password manager. Do not commit raw values to git.

### Staging env values

Minimum values to set on the staging server:

```bash
RAILS_ENV=staging
APP_HOST=staging.storepilot.example
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
SHOPIFY_APP_URL=https://staging.storepilot.example
SHOPIFY_REDIRECT_URI=https://staging.storepilot.example/auth/shopify/callback
SHOPIFY_API_KEY=...
SHOPIFY_API_SECRET=...
RAILS_MASTER_KEY=...
SENTRY_DSN=...
RESEND_API_KEY=...
```
Optional separate database URLs are supported for Solid Cache, Solid Queue, and
Solid Cable:

- `CACHE_DATABASE_URL`
- `QUEUE_DATABASE_URL`
- `CABLE_DATABASE_URL`

When those values are omitted, the app uses `DATABASE_URL` for all PostgreSQL
backed production stores.

## Configured defaults

## Why staging is separate

Staging keeps merchant testing isolated from production and lets us verify:

- Shopify OAuth
- webhook delivery
- background jobs
- product and order syncs
- audit runs
The production destination config in `config/deploy.production.yml` uses:

- production URL `https://app.storepilot.ai`
- HTTPS proxy host `app.storepilot.ai` by default
- the same host for the web server by default
- `APPLICATION_HOST` for Rails mailer URLs and host authorization

Override `APPLICATION_HOST`, `KAMAL_APP_HOST`, and `KAMAL_WEB_HOST` if the final
production DNS name changes.

## Production services

PostgreSQL is configured through `DATABASE_URL`. The URL must point at the
managed production database. If cache, queue, or cable data should be isolated,
set the optional `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, and
`CABLE_DATABASE_URL` values.

Redis is configured through `REDIS_URL`. Use a TLS URL (`rediss://...`) when the
provider supports it. The current Rails cache, job, and cable adapters are
Solid-backed PostgreSQL adapters; Redis is still required as a provisioned
production service for app features that depend on it.

## Logging

The staging environment tags logs with `staging` so deployment and runtime
output can be distinguished from production.
- The app image is built from the committed `Dockerfile`.
- Static assets are served from the container image.
- Storage is persisted via the mounted `/rails/storage` volume.
- `SOLID_QUEUE_IN_PUMA` is disabled in the Kamal default config so the app can later run Sidekiq as a separate process.

## Production deployment checklist

- DNS for `app.storepilot.ai` points to the production server.
- Registry credentials can pull `ghcr.io/ruby-pl/store_pilot_ai`.
- Production `RAILS_MASTER_KEY` is present only in the deployment secret source.
- Shopify production app uses `https://app.storepilot.ai` and callback `https://app.storepilot.ai/auth/shopify/callback`.
- `DATABASE_URL` points at the production PostgreSQL database.
- Optional `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, and `CABLE_DATABASE_URL` are set when using separate databases.
- `REDIS_URL` points at the production Redis instance and uses TLS where available.
- `SENTRY_DSN` and `RESEND_API_KEY` point at production projects/accounts.
- `bin/kamal setup -d production` completes successfully.
- `bin/kamal app exec -d production --interactive --reuse "bin/rails db:migrate"` completes successfully.
- `bin/kamal deploy -d production` completes successfully.
- `https://app.storepilot.ai/up` returns healthy.
