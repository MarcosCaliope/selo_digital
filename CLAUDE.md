# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**Selo Digital** is a Rails 8.0 application (Ruby 3.4.5) backed by PostgreSQL. The app name is `SeloDigital` (module namespace) and the database is named `siscartd`.

The application integrates with the **TJCE (Tribunal de Justiça do Ceará) Selo Digital** SOAP web service using mutual TLS (mTLS) authentication via digital certificate (`.pfx`). It queries and manages digital seals issued by the court system.

Root `/` and `/selos` both point to `SelosController#index`, which calls `SeloDigital::Client` and renders the result. `/empresas` is a standard RESTful CRUD (`resources :empresas`) for managing cartório records, including the digital certificate used for the TJCE connection. `/movimentacao` is a read-only dashboard (`MovimentacaoController#index`) over the legacy `sd_*` tables — see below.

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
bin/importmap audit  # Audit JS dependencies for vulnerabilities
```

CI runs all four of these: `brakeman`, `importmap audit`, `rubocop`, and `rails test test:system`.

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

**Recurring jobs:** Defined in `config/recurring.yml` (Solid Queue scheduler). Currently only one production job: clears finished Solid Queue jobs every hour.

## Database

Development and test both connect to PostgreSQL at `172.24.0.1:5432` (WSL2 host gateway), database `siscartd`. The host defaults to this IP but can be overridden with the `DB_HOST` environment variable. Credentials are set directly in `config/database.yml` (development only; production uses `DATABASE_URL` or env vars).

**`siscartd` is a shared legacy database**, not owned by this app — it's the live database of an existing Delphi-based cartório system ("SIAC") plus a separate legacy **PHP app** (source at `D:\sd\sd` on the Windows host, not in this repo) that already implements the full TJCE Selo Digital business flow. This Rails app only *writes* to `tblempresa`; the `sd_*` tables (`sd_atosPraticados`, `sd_lotes`, `sd_solicitacoes`, `sd_selos`, `sd_tipos_selos`, ...) are read-only from here — see "Movimentação dashboard" below. Because of this:
- **`db/schema.rb` is gitignored**, not committed. `rails db:migrate` dumps the *entire current DB* into `schema.rb` (every legacy table, not just the ones Rails added), so committing it would check in a stale snapshot of someone else's schema. The migration files under `db/migrate/` are the actual source of truth for what this app has changed.
- New migrations against `tblempresa` should be additive (`add_column`, not renaming/dropping legacy columns) since the Delphi app reads/writes that table too.

### `Empresa` model

`app/models/empresa.rb` maps to the pre-existing `tblempresa` table (`self.table_name = "tblempresa"`), which uses legacy Hungarian-notation column names (`snomeempresa`, `sfantasia`, `snocnpj`, etc. — `s` = string, `i` = integer, `c` = currency). Only a subset of its ~50 columns are exposed through the `/empresas` CRUD (identification fields); the many legacy billing/emolumento columns (`cvaloremolumentos`, `cferm1003`, ...) are left alone.

Four columns were added by this app so it no longer depends on Rails credentials for per-cartório webservice config:
- `certificado_digital` (`text`, **encrypted at rest** via Active Record Encryption) — the `.pfx` file content, Base64-encoded before encryption. Populated from a file upload via the virtual attribute `certificado_digital_upload` (see `Empresa#ler_certificado_digital_upload`).
- `senha_certificado_digital` (`text`, **encrypted at rest**) — the PFX password.
- `codigo_serventia` (`string`, plain) — the TJCE serventia code sent in the SOAP header. Not encrypted (not a secret).
- `homologacao` (`boolean`, default `false`) — when true, `SelosController` queries the TJCE homologação endpoint instead of produção. Toggled from the `/empresas` edit form; `/selos` shows a warning banner whenever it's on. Note: homologação and produção are separate TJCE systems with independent certificate registrations, so a cert that works in produção may be rejected in homologação (`MSG101`) until the TJCE registers it there too.

Encryption keys for the two encrypted columns live in `Rails.application.credentials.active_record_encryption` (`encrypts :certificado_digital`, `encrypts :senha_certificado_digital` in the model).

In the edit form, leaving the password field blank keeps the existing value (`EmpresasController#empresa_params` strips a blank `senha_certificado_digital` before mass-assignment) — it's never re-blanked on save.

### Movimentação dashboard (`/movimentacao`)

Read-only view over the `sd_*` tables, mirroring 4 panels of the legacy PHP app's dashboard (`D:\sd\sd\index2.html` + fragment endpoints like `verificaAtosPraticados.php`, `lotesenviados.php`, `verificaEstoque.php`, `verificaSolicitacao.php`). Models (all `self.table_name` pointed at the legacy tables, no writes):
- `AtoPraticado` (`sd_atosPraticados`) — `.pendentes_de_envio` scope replicates the legacy query (`status = 'N' AND lote = 0 AND tipo_selo <> 99`, limit 50): atos praticados not yet submitted to TJCE.
- `Lote` (`sd_lotes`) — `.emitidos_hoje` scope: batches of atos submitted to TJCE today.
- `Solicitacao` (`sd_solicitacoes`) — `.pendentes` scope (`recebido = false`): seal requests sent to TJCE but not yet retrieved.
- `TipoSelo` (`sd_tipos_selos`) — `.com_estoque_local` (raw SQL) joins in a live count of `sd_selos` with `status = 'D'` per tipo. **This is a different number from what `/selos` shows**: `/selos` queries TJCE's remote saldo (selos TJCE will let you request), while this is the local count of selos already downloaded and unused. Note: `sd_tipos_selos` has a column literally named `valid`, which collides with `ActiveRecord::Validations#valid?` — it's excluded via `self.ignored_columns = ["valid"]`.

**The legacy PHP app already automates the full write flow** (not reimplemented here yet): when local stock drops below `estoque_min`, it calls the TJCE `SolicitacaoSelo` operation to request more seals (`solicitar_selos.php`, auto-triggered by `AUTOsolicitar_selos.php` polling every 4.5 min), then `ReceberSelos` to download them (`recebe_selos.php`), and separately auto-submits any ato pending >30 min via the TJCE `MovimentarAtos` operation (`AUTOverificaAtosPraticados.php`, polling every 5 min) or manually via the "Enviar" button (`enviarSelosAtosPraticados.php`). None of these three SOAP operations (`solicitaSelos`, `receberSelos`, `movimentarAtos`) exist in `SeloDigital::Client` yet — only `consultaSelosDisponiveis` does. If/when that gets built, the exact envelope shapes are in `D:\sd\sd\envelope_solicita_selos.php`, `envelope_recebe_selos.php`, and `envelope_soap_atoGenerico.php` + `envelope_soap_cabecalho.php`/`envelope_soap_rodape.php`. `D:\sd\sd\vars.php` also has the endpoint URLs — but treat it as reference only, it hardcodes the cert password and a real person's PII in plaintext.

## External Service Integration

The SOAP client lives in `app/services/selo_digital/client.rb` as `SeloDigital::Client`. It does **not** use the Savon gem — it builds raw SOAP XML envelopes and posts them via `Net::HTTP` with `OpenSSL` for mTLS.

**Endpoints:** selected via the `homologacao:` boolean kwarg on `SeloDigital::Client.new` (default `false`, i.e. produção). The `ambiente:` kwarg is unrelated — it's just a value sent in the SOAP header (always `1`, for both homologação and produção).
- `homologacao: false` (default) → `https://selodigital.tjce.jus.br/wsselodigital/SelosDisponiveis`
- `homologacao: true` → `https://homologacao-selodigital.tjce.jus.br/wsselodigital-homologacao/SelosDisponiveis`

**Certificate authentication (mTLS):** The server requires mutual TLS. The client accepts any one of:
1. Raw PFX content already in memory (`pfx_content:` + `pfx_password:`) — loaded via `OpenSSL::PKCS12`. This is what `SelosController` uses, sourced from the `Empresa` record (see below) rather than a file on disk.
2. A `.pfx` file path (`pfx_path:` + `pfx_password:`) — same loading, but reads from disk first.
3. Pre-extracted cert/key files (`cert_path:` + `key_path:`)

To extract cert and key from a `.pfx` (required if the PFX uses the legacy RC2-40-CBC algorithm):
```bash
openssl pkcs12 -legacy -in certs/arquivo.pfx -clcerts -nokeys -out certs/client.crt
openssl pkcs12 -legacy -in certs/arquivo.pfx -nocerts -nodes -out certs/client.key
```

**The `certs/` directory is gitignored** — certificate files must be provisioned manually on each environment.

**Configuration:** `SelosController` sources everything from `Empresa.first` — `certificado_digital`, `senha_certificado_digital`, and `codigo_serventia`. `Rails.application.credentials.selo_digital` is **no longer read anywhere in the app**; any `pfx_path` / `pfx_password` / `codigo_serventia` keys still present under `selo_digital` in credentials are stale leftovers from before this migration and only useful for manual/console use of `SeloDigital::Client`.

**Return structure** of `SeloDigital::Client#consulta_selos_disponiveis`:
```ruby
{
  codigo:   String,   # response code
  status:   Integer,  # 0 = success
  mensagem: String,
  selos: [
    { codigo_selo: Integer, saldo: Integer, cota: Integer }
  ]
}
```
`SeloDigital::Error` is raised on missing or invalid responses.

**Response parsing:** `Nokogiri::XML` parses the SOAP response. Namespaces are stripped with `remove_namespaces!` before XPath queries.

**Request logging:** every outgoing SOAP request is written to `log/soap/request_<timestamp>.xml` (created on demand, gitignored). Useful for debugging TJCE integration issues but grows unbounded — no cleanup job exists.

## Known Technical Debt

- **`VERIFY_NONE` in `SeloDigital::Client#post`**: server TLS certificate is not verified (`OpenSSL::SSL::VERIFY_NONE`). This should be replaced with proper CA verification in production.
- **No test coverage**: `test/` only contains scaffolding (no actual test files), even though CI invokes `rails test test:system`.
- **`bin/brakeman` currently fails before scanning**: it's invoked with `--ensure-latest`, and the installed gem (8.0.4) is behind the latest released version (8.0.5), so it exits immediately with no report. Needs a `bundle update brakeman` (or removing `--ensure-latest`) to unblock CI.
- **Single-tenant assumption**: `SelosController` calls `Empresa.first` to pick which cartório's certificate/codigo_serventia to use, even though `/empresas` supports multiple records. Fine while there's one cartório (current state); would need an explicit selection mechanism if that changes.
