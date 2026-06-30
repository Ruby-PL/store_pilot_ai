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

## Staging environment

Staging is used for Shopify OAuth, webhook testing, sync jobs, and audit
verification without touching production merchant data.

The staging Rails environment uses `APP_HOST` for generated URLs. Set it to the
real staging domain you control, for example `staging.storepilot.example`.

Minimum staging values:

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
- `RESEND_API_KEY`

## Production services

PostgreSQL is configured through `DATABASE_URL`. The URL must point at the
managed production database.

Optional separate database URLs are supported for Solid Cache, Solid Queue, and
Solid Cable:

- `CACHE_DATABASE_URL`
- `QUEUE_DATABASE_URL`
- `CABLE_DATABASE_URL`

When those values are omitted, the app uses `DATABASE_URL` for all PostgreSQL
backed production stores.

Redis is configured through `REDIS_URL`. Use a TLS URL (`rediss://...`) when the
provider supports it. The current Rails cache, job, and cable adapters are
Solid-backed PostgreSQL adapters; Redis is still required as a provisioned
production service for app features that depend on it.

## Background jobs

StorePilot uses Rails Solid Queue for background jobs. The sprint tickets may
refer to Sidekiq, but the deployed job process is `bin/jobs` and runs as the
Kamal `job` role in both staging and production.

Set `KAMAL_JOB_HOST` when the worker should run on a different host than the web
process. Set `JOB_CONCURRENCY` to control Solid Queue worker processes per
container; it defaults to `1`.

Staging worker commands:

```bash
bin/kamal app exec --role job --reuse "bin/jobs --help"
bin/kamal app logs --roles job -f
bin/kamal app exec --interactive --reuse "bin/rails runner 'puts SolidQueue::FailedExecution.count'"
```

Production worker commands:

```bash
bin/kamal app exec -d production --role job --reuse "bin/jobs --help"
bin/kamal app logs -d production --roles job -f
bin/kamal app exec -d production --interactive --reuse "bin/rails runner 'puts SolidQueue::FailedExecution.count'"
```

Run product or order sync jobs remotely from a Rails runner or console once the
target job class and shop are known. For example:

```bash
bin/kamal app exec --interactive --reuse "bin/rails console"
```

Failed jobs are visible through Solid Queue records in the Rails console. Do not
expose a public job dashboard without authentication.

## Runtime notes

- The app image is built from the committed `Dockerfile`.
- The image registry is `ghcr.io/ruby-pl/store_pilot_ai`.
- Static assets are served from the container image.
- Storage is persisted via the mounted `/rails/storage` volume.
- `SOLID_QUEUE_IN_PUMA` is disabled in Kamal config so workers run through the separate `job` role.
- Staging logs include the Rails environment tag so staging output can be distinguished from production.

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
- `bin/kamal setup -d production` completes successfully.
- `bin/kamal app exec -d production --interactive --reuse "bin/rails db:migrate"` completes successfully.
- `bin/kamal deploy -d production` completes successfully.
- `bin/kamal app logs -d production --roles job -f` shows the job process running.
- `https://app.storepilot.ai/up` returns healthy.
