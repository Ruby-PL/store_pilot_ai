# StorePilot AI DNS and SSL

Use this checklist to configure Cloudflare DNS and HTTPS for deployed
StorePilot environments.

## Domains

| Environment | Hostname | Purpose |
| --- | --- | --- |
| Staging | `staging.storepilot.ai` | Pre-production Shopify OAuth, webhook, sync, and deploy validation |
| Production | `app.storepilot.ai` | Production merchant app |

## Cloudflare DNS Records

Create one DNS record per environment after the target server IP or provider
hostname is known.

For IP-based servers:

| Type | Name | Value |
| --- | --- | --- |
| `A` | `staging` | staging server IPv4 address |
| `A` | `app` | production server IPv4 address |

For provider hostnames:

| Type | Name | Value |
| --- | --- | --- |
| `CNAME` | `staging` | staging provider hostname |
| `CNAME` | `app` | production provider hostname |

Recommended Cloudflare settings:

- Proxy status: proxied after origin HTTPS is confirmed.
- SSL/TLS mode: Full (strict).
- Always Use HTTPS: enabled.
- Automatic HTTPS Rewrites: enabled.
- Minimum TLS version: TLS 1.2 or newer.
- HSTS: enable only after both environments have been verified over HTTPS.

## Kamal Host Configuration

Staging uses the default `config/deploy.yml` values:

```bash
KAMAL_APP_HOST=staging.storepilot.ai
KAMAL_WEB_HOST=staging.storepilot.ai
APPLICATION_HOST=staging.storepilot.ai
```

Production uses `config/deploy.production.yml` values:

```bash
KAMAL_APP_HOST=app.storepilot.ai
KAMAL_WEB_HOST=app.storepilot.ai
APPLICATION_HOST=app.storepilot.ai
```

Kamal proxy SSL is enabled in both environments. Keep `proxy.ssl: true` so the
deployed app serves HTTPS through the Kamal proxy.

## Verification

After DNS propagation and deploy, verify each environment.

Staging:

```bash
dig +short staging.storepilot.ai
curl -I http://staging.storepilot.ai
curl -I https://staging.storepilot.ai
curl -fsS https://staging.storepilot.ai/up
```

Production:

```bash
dig +short app.storepilot.ai
curl -I http://app.storepilot.ai
curl -I https://app.storepilot.ai
curl -fsS https://app.storepilot.ai/up
```

Expected results:

- DNS resolves to the intended server or provider hostname.
- HTTP redirects to HTTPS.
- HTTPS returns a valid certificate for the hostname.
- `/up` returns a successful response.
- Browser shows no certificate warnings.

## Shopify URL Alignment

Shopify app settings must match these domains exactly.

Staging:

- App URL: `https://staging.storepilot.ai`
- OAuth callback URL: `https://staging.storepilot.ai/auth/shopify/callback`
- App uninstall webhook URL: `https://staging.storepilot.ai/webhooks/shopify/app_uninstalled`

Production:

- App URL: `https://app.storepilot.ai`
- OAuth callback URL: `https://app.storepilot.ai/auth/shopify/callback`
- App uninstall webhook URL: `https://app.storepilot.ai/webhooks/shopify/app_uninstalled`

Do not reuse staging Shopify credentials or webhook URLs in production.
