# StorePilot AI Deployment

StorePilot AI is deployed with Kamal. The default deployment config targets
staging, and `config/deploy.production.yml` overrides the host settings for
production.

## Kamal workflow

Staging:

```bash
bin/kamal setup
bin/kamal deploy
bin/kamal app exec --interactive --reuse "bin/rails console"
bin/kamal logs -f
```

Production:

```bash
bin/kamal setup -d production
bin/kamal deploy -d production
bin/kamal app exec -d production --interactive --reuse "bin/rails console"
bin/kamal logs -d production -f
```

## Health checks

StorePilot exposes two health endpoints:

- `/up` checks that the Rails app boots and is suitable for basic load balancer checks.
- `/health` checks the Rails app and database connection and is suitable for deployment verification.

The `/health` response only reports service status and does not expose database
connection details or secrets.

## Staging environment

Staging is used for Shopify OAuth, webhook testing, sync jobs, and audit
verification without touching production merchant data.

The staging Rails environment uses `APP_HOST` for generated URLs. Set it to the
real staging domain, `staging.storepilot.ai`.

Minimum staging values:

```bash
RAILS_ENV=staging
APP_HOST=staging.storepilot.ai
DATABASE_URL=postgresql://...
CACHE_DATABASE_URL=postgresql://...
QUEUE_DATABASE_URL=postgresql://...
CABLE_DATABASE_URL=postgresql://...
REDIS_URL=rediss://...
SHOPIFY_APP_URL=https://staging.storepilot.ai
SHOPIFY_REDIRECT_URI=https://staging.storepilot.ai/auth/shopify/callback
SHOPIFY_API_KEY=...
SHOPIFY_API_SECRET=...
RAILS_MASTER_KEY=...
SENTRY_DSN=...
SENTRY_ENVIRONMENT=staging
RESEND_API_KEY=...
MAILER_FROM="StorePilot <noreply@storepilot.ai>"
```

Staging uses its own:

- PostgreSQL database
- Redis instance
- Solid Queue database
- Solid Cable database
- Shopify app credentials and callback URLs

## Production environment

The production destination config in `config/deploy.production.yml` uses:

- production URL `https://app.storepilot.ai`
- HTTPS proxy host `app.storepilot.ai` by default
- the same host for the web server by default
- `APPLICATION_HOST` for Rails mailer URLs and host authorization

Override `APPLICATION_HOST`, `KAMAL_APP_HOST`, and `KAMAL_WEB_HOST` if the final
production DNS name changes.

Before the first production deploy, provide these values from the shell or a
password manager. Do not commit raw values to git.

- `KAMAL_REGISTRY_PASSWORD`
- `RAILS_MASTER_KEY`
- `SHOPIFY_API_KEY`
- `SHOPIFY_API_SECRET`
- `SHOPIFY_APP_URL`
- `SHOPIFY_REDIRECT_URI`
- `DATABASE_URL`
- `REDIS_URL`
- `SENTRY_DSN`
- `SENTRY_ENVIRONMENT`
- `RESEND_API_KEY`
- `MAILER_FROM`

## Production services

PostgreSQL is configured through `DATABASE_URL`. The URL must point at the
managed database for the active environment.

Optional separate database URLs are supported for Solid Cache, Solid Queue, and
Solid Cable:

- `CACHE_DATABASE_URL`
- `QUEUE_DATABASE_URL`
- `CABLE_DATABASE_URL`

When those values are omitted, the app uses `DATABASE_URL` for all PostgreSQL
backed stores in that environment.

Redis is configured through `REDIS_URL`. Use a TLS URL (`rediss://...`) when the
provider supports it. The current Rails cache, job, and cable adapters are
Solid-backed PostgreSQL adapters; Redis is still required as a provisioned
production service for app features that depend on it.

## Data services

Use separate managed PostgreSQL and Redis services for staging and production.
Do not share databases, Redis instances, users, passwords, or backup buckets
between environments.

Required service variables:

| Variable | Required in | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | staging, production | Primary Rails database connection |
| `CACHE_DATABASE_URL` | optional | Solid Cache database; falls back to `DATABASE_URL` |
| `QUEUE_DATABASE_URL` | optional | Solid Queue database; falls back to `DATABASE_URL` |
| `CABLE_DATABASE_URL` | optional | Solid Cable database; falls back to `DATABASE_URL` |
| `REDIS_URL` | staging, production | Redis connection for runtime features that need Redis |

Connection requirements:

- PostgreSQL should require SSL when the provider supports it.
- Redis should use `rediss://` when TLS is available.
- Credentials must be supplied through Kamal secrets or a password manager.
- Staging and production credentials must be rotated independently.
- Application logs must not print full connection URLs.

Backup strategy:

- Production PostgreSQL must have automated daily backups before launch.
- Production backups should be retained for at least 14 days.
- Staging PostgreSQL should have provider snapshots or daily backups when it contains useful test data.
- Backup restore should be tested before launch by restoring to a non-production database.
- Redis is treated as disposable cache/runtime state unless a future feature stores durable data there.
- Document the final provider-specific backup policy in the deployment runbook.

## Runtime notes

- The app image is built from the committed `Dockerfile`.
- The image registry is `ghcr.io/ruby-pl/store_pilot_ai`.
- Static assets are served from the container image.
- Storage is persisted via the mounted `/rails/storage` volume.
- `SOLID_QUEUE_IN_PUMA` is disabled in Kamal config so workers can run as a separate process.
- Staging logs include the Rails environment tag so staging output can be distinguished from production.
- Release deployment, rollback, log, restart, and migration steps are documented in [deployment_runbook.md](deployment_runbook.md).

## Sentry verification

After setting the environment-specific `SENTRY_DSN`, verify error monitoring
from each deployed environment.

Staging:

```bash
bin/kamal app exec --interactive --reuse "bin/rails runner 'ErrorMonitoring.capture_exception(StandardError.new(\"Sentry staging smoke test\"), context: { source: \"deployment_check\" })'"
```

Production:

```bash
bin/kamal app exec -d production --interactive --reuse "bin/rails runner 'ErrorMonitoring.capture_exception(StandardError.new(\"Sentry production smoke test\"), context: { source: \"deployment_check\" })'"
```

Confirm the event appears in the matching Sentry project with environment
`staging` or `production`.

## Production deployment checklist

- DNS for `app.storepilot.ai` points to the production server.
- Registry credentials can pull `ghcr.io/ruby-pl/store_pilot_ai`.
- Production `RAILS_MASTER_KEY` is present only in the deployment secret source.
- Shopify production app uses `https://app.storepilot.ai`.
- Shopify production callback is `https://app.storepilot.ai/auth/shopify/callback`.
- `DATABASE_URL` points at the production PostgreSQL database.
- Optional `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, and `CABLE_DATABASE_URL` are set when using separate databases.
- `REDIS_URL` points at the production Redis instance and uses TLS where available.
- `SENTRY_DSN` and `RESEND_API_KEY` point at production projects/accounts.
- `MAILER_FROM` uses a Resend-verified sending domain.
- `bin/kamal setup -d production` completes successfully.
- `bin/kamal app exec -d production --interactive --reuse "bin/rails db:migrate"` completes successfully.
- `bin/kamal deploy -d production` completes successfully.
- `https://app.storepilot.ai/up` returns healthy.
- `https://app.storepilot.ai/health` returns healthy after migrations.
