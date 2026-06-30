# Shopify Partner app setup

This project uses a Shopify Partner app named `StorePilot AI`.

## Dashboard configuration

Configure the app in the Shopify Dev Dashboard with these values for local development:

| Field | Value |
| --- | --- |
| App URL | `http://localhost:3005` |
| Embedded in Shopify admin | Off |
| Preferences URL | Leave empty |
| Webhooks API version | `2026-04` |
| Required scopes | `read_products,write_products,read_orders` |
| Optional scopes | Leave empty |
| Legacy install flow | Off |
| Redirect URL | `http://localhost:3005/auth/shopify/callback` |
| Embedded in Shopify POS | Off |
| App proxy prefix/subpath/URL | Leave empty |

Release the version after changing these values so the app configuration becomes active.

## Credentials

Copy `.env.example` to `.env` and fill these values from the Shopify Dev Dashboard:

```bash
SHOPIFY_API_KEY=your_client_id
SHOPIFY_API_SECRET=your_client_secret
SHOPIFY_APP_URL=http://localhost:3005
SHOPIFY_REDIRECT_URI=http://localhost:3005/auth/shopify/callback
SHOPIFY_SCOPES=read_products,write_products,read_orders
SHOPIFY_API_VERSION=2026-04
SHOPIFY_REQUIRE_CREDENTIALS=false
```

`SHOPIFY_API_KEY` is the public client ID. `SHOPIFY_API_SECRET` is sensitive and must never be committed.

The committed `shopify.app.toml` documents the app settings used by Shopify CLI. Replace `replace-with-shopify-client-id` with the real client ID locally, or run:

```bash
shopify app config link
```

Do not commit a secret value. Shopify app secrets belong in `.env` or Rails credentials.

Rails reads Shopify configuration from environment variables in
`config/initializers/shopify.rb` and exposes it at:

```ruby
Rails.application.config.x.shopify
```

Set `SHOPIFY_REQUIRE_CREDENTIALS=true` in environments where the app must fail fast when the Shopify client ID or secret is missing.

## Scope rationale

- `read_products` is needed for product sync/import work.
- `write_products` is needed for local demo product seeding.
- `read_orders` is needed for reading recent order data for analytics.

Additional scopes should be added only when a ticket requires the app to access more Shopify resources.

## Staging app settings

Use a separate Shopify Partner app for staging so OAuth, webhook, and sync
testing cannot affect production configuration.

Configure the staging app with:

| Field | Value |
| --- | --- |
| App URL | `https://staging.storepilot.ai` |
| Embedded in Shopify admin | Off |
| Preferences URL | Leave empty |
| Webhooks API version | `2026-04` |
| Required scopes | `read_products,read_orders` |
| Optional local/demo scope | `write_products` only when demo product seeding is needed |
| Legacy install flow | Off |
| Redirect URL | `https://staging.storepilot.ai/auth/shopify/callback` |
| App uninstall webhook | `https://staging.storepilot.ai/webhooks/shopify/app_uninstalled` |
| Embedded in Shopify POS | Off |
| App proxy prefix/subpath/URL | Leave empty |

Staging environment values:

```bash
SHOPIFY_API_KEY=staging_client_id
SHOPIFY_API_SECRET=staging_client_secret
SHOPIFY_APP_URL=https://staging.storepilot.ai
SHOPIFY_REDIRECT_URI=https://staging.storepilot.ai/auth/shopify/callback
SHOPIFY_SCOPES=read_products,read_orders
SHOPIFY_API_VERSION=2026-04
SHOPIFY_REQUIRE_CREDENTIALS=true
```

If demo product seeding is required in a staging development store, temporarily
include `write_products` in the staging scopes and release the updated Shopify
app configuration before installing.

## Staging install test

Use a Shopify development store that is dedicated to staging validation.

1. Confirm `https://staging.storepilot.ai/up` returns healthy.
2. Confirm the staging Shopify Partner app has the URLs and scopes listed above.
3. Set staging secrets in Kamal or the password manager.
4. Open `https://staging.storepilot.ai/auth/shopify?shop=your-dev-store.myshopify.com`.
5. Complete the Shopify install and OAuth approval flow.
6. Confirm StorePilot redirects to the merchant dashboard.
7. Confirm the store record is active in Rails console:

```ruby
Store.find_by!(shopify_domain: "your-dev-store.myshopify.com").active?
```

8. Trigger a product/order sync from the dashboard and confirm the jobs complete.

Do not use production Shopify app credentials in staging.
