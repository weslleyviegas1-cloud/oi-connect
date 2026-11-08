# Supabase migrations — Oi Connect

## One-time setup

Add these three **GitHub Actions repository secrets** in Settings → Secrets and variables → Actions:

- `SUPABASE_ACCESS_TOKEN`: personal access token created in the Supabase account.
- `SUPABASE_DB_PASSWORD`: database password for the existing Supabase project.
- `SUPABASE_PROJECT_ID`: project reference (the short ID in the Supabase project URL).

Never put these values in source code, commits, chat messages, or frontend environment variables.

## First application

1. Merge this pull request into `main`.
2. Add all three secrets above.
3. Open Actions → **Supabase database migrations** → Run workflow.
4. Inspect the run. A successful run applies the Etapa 4 migration and records it in Supabase migration history.

The first run is manual intentionally: it avoids applying schema changes before the project secrets are configured and the existing database is ready.

## Future changes

For every future database change, add a new, uniquely timestamped SQL file under `supabase/migrations/`. Do not edit a migration that has already been applied. After the change reaches `main`, GitHub Actions automatically runs `supabase db push` and applies only pending migrations.

## Important

The existing setup, Etapa 2, and Etapa 3 were originally executed manually in the SQL Editor and are not replayed by this workflow. This migration pipeline starts tracking from Etapa 4 onward. The Etapa 4 migration uses an explicit transaction so a failed run does not leave a partial migration.
