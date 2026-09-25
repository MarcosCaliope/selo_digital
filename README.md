# Selo Digital

Rails 8.0 app (Ruby 3.4.5) backed by PostgreSQL, integrating with the **TJCE
(Tribunal de Justiça do Ceará) Selo Digital** SOAP web service via mutual TLS
(`.pfx` certificate) to query and manage digital seals issued by the court
system.

It also serves as a dashboard (`/movimentacao`) over the legacy `sd_*` tables
shared with an existing Delphi cartório system ("SIAC") and a separate legacy
PHP app, for sending atos, requesting/receiving selos, and retificação.

For details on the architecture, the shared legacy database, and the TJCE
integration, see `CLAUDE.md`. For a non-technical walkthrough of every screen,
see `docs/manual/README.md`. For the TJCE WSDL/XSD reference, see
`docs/tjce/README.md`.

## Ruby version

Ruby 3.4.5 (see `.ruby-version`).

## System dependencies

- PostgreSQL (development/test connect to a shared instance at
  `172.24.0.1:5432`, database `siscartd` — override with `DB_HOST`)
- A `.pfx` digital certificate for TJCE mTLS (provisioned manually per
  environment under the gitignored `certs/` directory, or per-`Empresa` via
  the `/empresas` UI)

## Configuration

Development database credentials are set directly in `config/database.yml`.
Production uses `DATABASE_URL` or individual env vars, plus `RAILS_MASTER_KEY`
for Rails credentials. See `CLAUDE.md` for the full list of environment
variables (`APP_MODO_EXECUCAO`, `TS_AUTHKEY`, `DB_PROXY_PORT`, etc.) used in
deployment.

## Database creation / initialization

```bash
bin/setup            # install deps, prepare DB, start server
bin/rails db:prepare  # create/migrate
bin/rails db:migrate
bin/rails db:seed
```

`siscartd` is a **shared legacy database**, not owned by this app — most
`sd_*` tables are read-only from here. `db/schema.rb` is gitignored; the
migrations under `db/migrate/` are the source of truth for what this app has
changed. See `CLAUDE.md` for details.

## How to run the test suite

```bash
bin/rails test           # run all tests
bin/rails test:system    # run system tests (Capybara/Selenium)
```

## Linting / static analysis

```bash
bin/rubocop           # lint (rubocop-rails-omakase style)
bin/brakeman           # security static analysis
bin/importmap audit    # audit JS dependencies for vulnerabilities
```

CI (`.github/workflows/ci.yml`) runs all four of these plus the test suite.

## Services

No job queue, cache, or Action Cable backend is used (Solid Queue/Cache/Cable
were removed — the shared PostgreSQL instance is too old to support the
`ON CONFLICT`/`FOR UPDATE SKIP LOCKED` features they rely on). Background work
(automatic ato submission) runs from a plain in-process thread instead. See
`CLAUDE.md` for details.

## Deployment

Kamal (`config/deploy.yml`) for self-hosted servers, or Render (`render.yaml`,
Docker runtime). Both build the same production `Dockerfile`. See `CLAUDE.md`
for details, including the Tailscale-based DB proxying used when the app runs
outside the cartório's own network.
