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

## Why staging is separate

Staging keeps merchant testing isolated from production and lets us verify:

- Shopify OAuth
- webhook delivery
- background jobs
- product and order syncs
- audit runs

## Logging

The staging environment tags logs with `staging` so deployment and runtime
output can be distinguished from production.
