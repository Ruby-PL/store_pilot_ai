# StorePilot AI Deployment Architecture

## Decision

StorePilot AI will be deployed with Kamal to two separate environments:

- Staging: `staging.storepilot.ai`
- Production: `app.storepilot.ai`

Each environment runs the same Docker image and the same Rails application code, but with separate secrets, databases, Redis instances, and Shopify app settings.

## Hosting choice

Use a simple container-based VPS deployment:

- Rails app on a dedicated server
- PostgreSQL on the same deployment host or managed separately, depending on the provider
- Redis for cache and job queue support
- Sidekiq as the background worker process
- Cloudflare for DNS and SSL termination
- Sentry for error monitoring
- Resend for transactional email

This keeps the stack small, predictable, and close to the app’s current Rails structure.

## Why this setup

StorePilot AI needs real HTTPS URLs and stable hostnames for:

- Shopify OAuth callback URLs
- Shopify webhooks
- Background job processing
- Merchant testing in a staging environment
- Production rollout without changing application code between environments

Kamal is a good fit because it deploys the same Docker image to staging and production, keeps the release process straightforward, and avoids introducing a heavier platform before the app needs it.

## Environment split

### Staging

Staging is the safe test environment for:

- Shopify OAuth install flow
- Webhook validation
- Sync jobs
- Audit runs
- Merchant demo testing

Staging should use:

- `staging.storepilot.ai`
- Separate Rails credentials and secrets
- Separate PostgreSQL database
- Separate Redis instance
- Separate Shopify Partner app configuration

### Production

Production is the merchant-facing environment for live stores.

Production should use:

- `app.storepilot.ai`
- Separate production credentials and secrets
- Separate PostgreSQL database
- Separate Redis instance
- Separate Shopify Partner app configuration
- Sentry and Resend configured for production delivery

## Services

| Service | Purpose |
| --- | --- |
| Rails | Web application and Shopify integration |
| PostgreSQL | Primary relational database |
| Redis | Background job queue support and app caching |
| Sidekiq | Background job processor for syncs and audits |
| Sentry | Error monitoring and exception reporting |
| Resend | Transactional email delivery |

## Operational notes

- Do not share secrets between staging and production.
- Do not reuse the same Shopify app settings for both environments.
- Keep the staging environment available for merchant demos and test installs.
- Treat production deploys as controlled releases with a rollback path.
