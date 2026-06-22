# StorePilot AI

StorePilot AI is a Rails 8 application for connecting Shopify stores and powering merchant workflows.

## Requirements

- Ruby 3.4.7
- Bundler
- Docker with Docker Compose

## Start development

Run the complete local stack with one command:

```bash
bin/setup
```

This installs Ruby dependencies, starts PostgreSQL and Redis in Docker, prepares
the database, clears temporary files, and starts Rails. The app is available at
`http://localhost:3000`.

After the initial setup, use `bin/dev` when the dependency containers are
already running. To start or stop only the dependencies:

```bash
docker compose up --detach --wait
docker compose down
```

PostgreSQL data and Redis data are retained in named Docker volumes. Run
`docker compose down --volumes` only when you intentionally want to erase both.

## Environment variables

The local setup has working defaults, so creating an `.env` file is optional.
When you need overrides, copy [.env.example](.env.example) to `.env` and edit
the values. `bin/setup` and `bin/dev` load it automatically; variables already
present in the shell take precedence.

| Variable | Default | Purpose |
| --- | --- | --- |
| `POSTGRES_PORT` | `5432` | PostgreSQL port exposed on the host |
| `REDIS_PORT` | `6379` | Redis port exposed on the host |
| `POSTGRES_USER` | `store_pilot_ai` | Local PostgreSQL user |
| `POSTGRES_PASSWORD` | `store_pilot_ai` | Local PostgreSQL password |
| `DATABASE_URL` | Local development database URL | Rails database connection |
| `REDIS_URL` | `redis://127.0.0.1:6379/0` | Redis connection |
| `PORT` | `3000` | Rails server port |

For example, when port 5432 is already in use:

```bash
POSTGRES_PORT=5433 DATABASE_URL=postgresql://store_pilot_ai:store_pilot_ai@127.0.0.1:5433/store_pilot_ai_development bin/setup
```

Production uses `STORE_PILOT_AI_DATABASE_PASSWORD` for the primary database
password. Never commit `.env`, Rails master keys, or credential keys.

## Useful commands

Run the test suite:

```bash
bin/rails test
```

Run basic application diagnostics:

```bash
bin/rails about
```
