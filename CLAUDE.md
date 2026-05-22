# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**Selo Digital** is a Rails 8.0 application (Ruby 3.4.5) backed by PostgreSQL. The app name is `SeloDigital` (module namespace) and the database is named `siscartd`.

The application integrates with the **TJCE (Tribunal de Justiça do Ceará) Selo Digital** SOAP web service using mutual TLS (mTLS) authentication via digital certificate (`.pfx`). It queries and manages digital seals issued by the court system.

## Common Commands

```bash
bin/setup          # Install deps, prepare DB, start server
bin/dev            # Start development server (rails server)

bin/rails db:prepare   # Create/migrate DB
bin/rails db:migrate
bin/rails db:seed

bin/rails test                          # Run all tests
bin/rails test test/models/foo_test.rb  # Run a single test file
bin/rails test:system                   # Run system tests (Capybara/Selenium)

bin/rubocop        # Lint (rubocop-rails-omakase style)
bin/brakeman       # Security static analysis
```

## Architecture

**All backing services use database adapters** — no Redis or external services required in development:
- **Solid Queue** — background jobs (runs inside Puma via `SOLID_QUEUE_IN_PUMA=true`; schema in `db/queue_schema.rb`)
- **Solid Cache** — Rails.cache (schema in `db/cache_schema.rb`)
- **Solid Cable** — Action Cable (schema in `db/cable_schema.rb`)

**Frontend stack:**
- **Propshaft** — asset pipeline (replaces Sprockets)
- **importmap-rails** — JS modules without bundling
- **Hotwire** (Turbo + Stimulus) — SPA-like interactions

**Deployment:** Kamal (`config/deploy.yml`) — builds a Docker image and deploys to configured servers. Secrets via `.kamal/secrets`, master key via `RAILS_MASTER_KEY`.

**Recurring jobs:** Defined in `config/recurring.yml` (Solid Queue scheduler).

## Database

Development and test both connect to PostgreSQL at `172.24.0.1:5432` (WSL2 host gateway), database `siscartd`. The host defaults to this IP but can be overridden with the `DB_HOST` environment variable. Credentials are set directly in `config/database.yml` (development only; production uses `DATABASE_URL` or env vars).

The app currently has **no application-level models or migrations** — it is purely a service integration layer with no persisted data of its own.

## External Service Integration

The SOAP client lives in `app/services/selo_digital/client.rb` as `SeloDigital::Client`. It does **not** use the Savon gem — it builds raw SOAP XML envelopes and posts them via `Net::HTTP` with `OpenSSL` for mTLS.

**Endpoints:**
- Homologação (ambiente=1): `https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/SelosDisponiveis`
- Produção (ambiente=2): `https://selodigital.tjce.jus.br/wsselodigital/SelosDisponiveis`

**Certificate authentication (mTLS):** The server requires mutual TLS. The client accepts either:
1. A `.pfx` file (`pfx_path:` + `pfx_password:`) — loaded via `OpenSSL::PKCS12`
2. Pre-extracted cert/key files (`cert_path:` + `key_path:`)

To extract cert and key from a `.pfx` (required if the PFX uses the legacy RC2-40-CBC algorithm):
```bash
openssl pkcs12 -legacy -in certs/arquivo.pfx -clcerts -nokeys -out certs/client.crt
openssl pkcs12 -legacy -in certs/arquivo.pfx -nocerts -nodes -out certs/client.key
```

**The `certs/` directory is gitignored** — certificate files must be provisioned manually on each environment.

**Configuration:** `codigo_serventia` is read from `Rails.application.credentials.dig(:selo_digital, :codigo_serventia)` or falls back to the `SELO_DIGITAL_SERVENTIA` env var (default `"000401"`). The PFX path and password are currently hardcoded in `SelosController` — these should be moved to credentials or env vars.

**Response parsing:** `Nokogiri::XML` parses the SOAP response. `SeloDigital::Error` is the custom error class raised on invalid responses.
