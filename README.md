# StorePilot AI

StorePilot AI is a Rails 8 application for connecting Shopify stores and powering merchant workflows.

## Requirements

- Ruby 3.4.7
- PostgreSQL 9.5+
- Bundler

## Setup

1. Install dependencies:

   ```bash
   bundle install
   ```

2. Create the development and test databases:

   ```bash
   bin/rails db:prepare
   ```

3. Start the app:

   ```bash
   bin/rails server
   ```

The app will be available at `http://localhost:3000`.

## Database configuration

PostgreSQL is configured in `config/database.yml` with these default database names:

- `store_pilot_ai_development`
- `store_pilot_ai_test`
- `store_pilot_ai_production`

Production uses the `STORE_PILOT_AI_DATABASE_PASSWORD` environment variable for the primary database password.

## Useful commands

Run the test suite:

```bash
bin/rails test
```

Run basic application diagnostics:

```bash
bin/rails about
```
