# StorePilot AI Deployment Runbook

Use this runbook for repeatable staging and production releases. StorePilot is
deployed with Kamal. The default Kamal destination is staging; production uses
the `production` destination.

## Preconditions

- Working tree is clean and the release commit is pushed.
- CI checks have passed for the release branch.
- Required secrets are available through the shell, Kamal secrets, or the team password manager.
- PostgreSQL and Redis service URLs are configured for the target environment.
- Shopify callback and webhook URLs match the target environment.
- DNS points at the target server before running the first setup.

## Staging Deploy

Use staging for release validation before production.

```bash
git fetch origin
git switch main
git pull --ff-only origin main
bin/kamal setup
bin/kamal deploy
```

Run migrations if they were not completed by app boot:

```bash
bin/kamal app exec --interactive --reuse "bin/rails db:migrate"
```

Verify staging:

```bash
bin/kamal app exec --interactive --reuse "bin/rails db:version"
bin/kamal app exec --interactive --reuse "bin/rails runner 'puts Rails.env'"
curl -fsS https://staging.storepilot.ai/up
curl -fsS https://staging.storepilot.ai/health
```

## Production Deploy

Production deploys must happen after staging validation.

```bash
git fetch origin
git switch main
git pull --ff-only origin main
bin/kamal setup -d production
bin/kamal deploy -d production
```

Run migrations if they were not completed by app boot:

```bash
bin/kamal app exec -d production --interactive --reuse "bin/rails db:migrate"
```

Verify production:

```bash
bin/kamal app exec -d production --interactive --reuse "bin/rails db:version"
bin/kamal app exec -d production --interactive --reuse "bin/rails runner 'puts Rails.env'"
curl -fsS https://app.storepilot.ai/up
curl -fsS https://app.storepilot.ai/health
```

## Logs

Follow app logs:

```bash
bin/kamal logs -f
bin/kamal logs -d production -f
```

Open a shell for targeted inspection:

```bash
bin/kamal app exec --interactive --reuse "bash"
bin/kamal app exec -d production --interactive --reuse "bash"
```

Open the Rails console:

```bash
bin/kamal app exec --interactive --reuse "bin/rails console"
bin/kamal app exec -d production --interactive --reuse "bin/rails console"
```

## Restart Rails

Redeploying is the preferred restart path because it keeps image, env, and
process state aligned:

```bash
bin/kamal deploy
bin/kamal deploy -d production
```

If a direct process restart is needed, use the Kamal app commands available in
the installed Kamal version and then verify `/up` and `/health`.

## Restart Background Jobs

Background jobs run through Solid Queue using the `bin/jobs` command when a
separate job role is enabled in `config/deploy.yml`.

Preferred restart path:

```bash
bin/kamal deploy
bin/kamal deploy -d production
```

If a dedicated job role is enabled, inspect job logs after deploy:

```bash
bin/kamal logs -f
bin/kamal logs -d production -f
```

If StorePilot later switches to Sidekiq, update this section with the protected
Sidekiq process and dashboard commands before enabling it in production.

## Migrations

Check migration status:

```bash
bin/kamal app exec --interactive --reuse "bin/rails db:migrate:status"
bin/kamal app exec -d production --interactive --reuse "bin/rails db:migrate:status"
```

Run migrations:

```bash
bin/kamal app exec --interactive --reuse "bin/rails db:migrate"
bin/kamal app exec -d production --interactive --reuse "bin/rails db:migrate"
```

After migrations:

```bash
bin/kamal app exec --interactive --reuse "bin/rails db:version"
bin/kamal app exec -d production --interactive --reuse "bin/rails db:version"
```

## Rollback

Rollback should restore the last known-good app image and verify database
compatibility. Avoid destructive database rollbacks unless the migration is
explicitly reversible and the data impact is understood.

1. Identify the last known-good git SHA and image.
2. Confirm whether the failed release included migrations.
3. If no irreversible migration ran, redeploy the last known-good commit/image.
4. If migrations ran, decide whether a forward fix is safer than rollback.
5. Verify `/up`, `/health`, Shopify OAuth, webhooks, and sync jobs.

Useful commands:

```bash
git log --oneline -10
bin/kamal app exec --interactive --reuse "bin/rails db:version"
bin/kamal app exec -d production --interactive --reuse "bin/rails db:version"
bin/kamal logs -f
bin/kamal logs -d production -f
```

## Post-Deploy Checklist

- App responds over HTTPS.
- `/up` returns healthy.
- `/health` returns healthy.
- Rails environment matches the target environment.
- Database version is the expected migration version.
- Shopify OAuth callback works in the target Shopify app.
- App uninstall webhook returns success for valid Shopify signatures.
- Product sync job can be queued and completes.
- Order sync job can be queued and completes.
- Sentry is receiving errors for the target environment.
- Email provider configuration is valid when transactional emails are enabled.
