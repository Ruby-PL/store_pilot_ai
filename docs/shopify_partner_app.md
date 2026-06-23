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
| Required scopes | `read_products,read_orders` |
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
SHOPIFY_SCOPES=read_products,read_orders
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
- `read_orders` is needed for reading recent order data for analytics.

Additional scopes should be added only when a ticket requires the app to access more Shopify resources.
