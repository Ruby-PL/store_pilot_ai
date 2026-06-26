# StorePilot AI Deployment

## Kamal workflow

StorePilot AI is configured for container-based deployment with Kamal.

The main commands are:

```bash
bin/kamal setup
bin/kamal deploy
bin/kamal app exec --interactive --reuse "bin/rails console"
bin/kamal logs -f
```

## Required setup

Before the first deploy, provide:

- `KAMAL_REGISTRY_PASSWORD`
- `RAILS_MASTER_KEY`
- Shopify app credentials
- `DATABASE_URL`
- `REDIS_URL`
- `SENTRY_DSN`
- `RESEND_API_KEY`

Keep staging and production values separate.

## Configured defaults

The committed Kamal config uses:

- `service: store_pilot_ai`
- image registry at `ghcr.io/ruby-pl/store_pilot_ai`
- HTTPS proxy host `staging.storepilot.ai` by default
- a separate web host override through `KAMAL_WEB_HOST`

For production, override the environment variables to point at the production host and production secrets.

## Runtime notes

- The app image is built from the committed `Dockerfile`.
- Static assets are served from the container image.
- Storage is persisted via the mounted `/rails/storage` volume.
- `SOLID_QUEUE_IN_PUMA` is disabled in the Kamal default config so the app can later run Sidekiq as a separate process.
