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

View + write actions over the `sd_*` tables, mirroring 4 panels of the legacy PHP app's dashboard (`D:\sd\sd\index2.html` + fragment endpoints like `verificaAtosPraticados.php`, `lotesenviados.php`, `verificaEstoque.php`, `verificaSolicitacao.php`). Models (all `self.table_name` pointed at the legacy tables):
- `AtoPraticado` (`sd_atosPraticados`) — `.pendentes_de_envio` scope replicates the legacy query (`status = 'N' AND lote = 0 AND tipo_selo <> 99`, limit 50): atos praticados not yet submitted to TJCE.
- `Lote` (`sd_lotes`) — `.emitidos_hoje` scope: batches of atos submitted to TJCE today. `Lote.enviar_atos!(empresa, atos)` creates a lote, submits it via `movimentar_atos`, and updates both the lote and each ato from the response.
- `Solicitacao` (`sd_solicitacoes`) — `.pendentes` scope (`recebido = false`): seal requests sent to TJCE but not yet retrieved. `#receber!(empresa)` calls `receber_selos` and writes the returned seals into `Selo`.
- `TipoSelo` (`sd_tipos_selos`) — `.com_estoque_local` (raw SQL) joins in a live count of `sd_selos` with `status = 'D'` per tipo. **This is a different number from what `/selos` shows**: `/selos` queries TJCE's remote saldo (selos TJCE will let you request), while this is the local count of selos already downloaded and unused. Note: `sd_tipos_selos` has a column literally named `valid`, which collides with `ActiveRecord::Validations#valid?` — it's excluded via `self.ignored_columns = ["valid"]`. `#solicitar!(empresa)` raises unless `estoque_local < estoque_min` (the dashboard only renders the "Solicitar" button under that same condition, so the guard is normally invisible — it matters if this gets called from anywhere else); when allowed, it requests `qte_pedido` units via `solicita_selos` and creates the resulting `Solicitacao`.
- `Selo` (`sd_selos`) — write target for seals downloaded via `Solicitacao#receber!`.

**Write actions** (`MovimentacaoController#solicitar_selos` / `#receber_selos` / `#enviar_atos`, each a `button_to`/`form_with` with `turbo_confirm` on the dashboard) replicate the legacy PHP's full flow, which used to run automatically (`AUTOsolicitar_selos.php` every ~4.5 min, `AUTOverificaAtosPraticados.php` every ~5 min) but **that PHP automation has been deactivated** — this Rails app is now the only thing driving these operations, triggered manually per-click rather than on a timer. `Empresa#selo_digital_client` builds the configured `SeloDigital::Client`, using `snomeresponsavel`/`snocpfresponsavel`/`sfone1`/`semail` as the TJCE "informante"/"solicitante" identity (same fields already used for the `/empresas` cadastro).

`movimentar_atos` (and thus "Enviar selecionados ao TJCE") **was fired end-to-end against production on 2026-07-15 and confirmed working** (real `AtoPraticado` accepted, `sqAto_tj` returned). Getting there required two rounds of fixes to `ato_xml` in `client.rb`, both discovered from the TJCE's own error responses rather than any schema doc: `numeroTalao` and `tipoGeracao` aren't legal elements of the `CGenerica` type at all (removed); and `<numeroAtendimento>` (filled from `ato.numeroTalao` — there's no column literally named `numeroAtendimento`) is required immediately after `<valorFermoju>` in element order — the service performs real (order-sensitive) XML Schema validation, not just presence checks. One thing worth knowing before relying on it further: the `<partePessoa>` block it sends is still mostly a **hardcoded generic placeholder** ("Generico", fake CPF `0123456789`, fake address) — copied verbatim from what legacy production already sends for every single ato, not derived from real party data. TJCE accepted it as-is in the successful test, so it does appear to pass validation, but it's still not real party data for most atos.

`movimentar_atos` requires `id_lote:` (in addition to `atos:`) — `<idLote>` (`xs:long`, required in `TMovimentacaoAtos`, positioned right after all `<atos>` elements) was missing from the request entirely until this was found on 2026-07-16 from a real production error ("O idLote já foi enviado anteriormente por essa serventia") on a resend attempt: TJCE apparently treats a missing required `xs:long` as an implicit fixed value (probably `0`), which is accepted once per serventia and then rejected as a duplicate on every later call, no matter which atos are actually being sent. Fixed by mirroring what the legacy PHP always did — `Lote.enviar_atos!` now creates the `Lote` row *before* calling `movimentar_atos` (instead of after, as introduced by the anti-orphan fix below) specifically to get a fresh, real `sd_lotes.id` to send as `<idLote>`; if the SOAP call raises, that just-created empty `Lote` is destroyed in the `rescue` and re-raised, so atos stay untouched for retry with a genuinely different `id_lote` next time — the ordering only changed enough to source `id_lote`, the "call TJCE, only write to atos from the response" guarantee is otherwise intact. **Confirmed fixed against production on 2026-07-16**: the exact ato that had triggered the duplicate-idLote error (selo ACE137736-E7P9, `sd_atosPraticados.id` 519984) was resubmitted and accepted (`sqAto_tj` 70471591, `status` "E", `lote` 221291).

`nomePessoa`/`documento` are the one part of `partePessoa` **not** always fake: `AtoPraticado#parte_pessoa_dados` dispatches on `stiposelagem` and supplies real data for four known values, falling back to the generic placeholder for a blank/unrecognized `stiposelagem` or whenever a lookup can't produce confident data — the same "never block the send" fallback rule applies to all four branches below, since submitting with the placeholder is known-safe (it's what legacy production already does for every ordinary ato).
- `"D"` — título de protesto, not a regular cartório ato. `id_ato` is the `protocolo` of a row in the separate legacy `cbl_tit`/`cbl_dev` domain (protest/collections module, not `sd_*`) — `CblTit` (`cbl_tit`, PK `protocolo`) holds `tipo_doc`/`cpf_cgc`, joined to `CblDev` (`cbl_dev`, PK `id_dev`, indexed on `(tipo_doc, cpf_cgc)`) which is the actual devedor (debtor) master record with the real `nome`. `tipoDocumento` is mapped from `tipo_doc` via `AtoPraticado::TIPO_DOCUMENTO_POR_TIPO_DOC` (`"CGC" => 1`, `"CPF" => 2`) — other observed `tipo_doc` values (`PF`, `CI`, `GC`) have no mapping, so `nil`/placeholder.
- `"C"` — certidão. `id_ato` is `icodigo` of a row in `tblcontcertidoes` (yet another separate legacy domain) — `TblContCertidoes` (PK `icodigo`) has `snome` (real name) and `scpfcnpj`, a single column holding either a CPF or a CNPJ with no separate type column (unlike `cbl_tit`/`cbl_dev`).
- `"E"` — escritura. `id_ato` is `id` of a row in `bd_escr` (yet another separate legacy domain, notary-deed module) — `BdEscr` (PK `id`, Rails default) has `gant1` ("outorgante" — grantor, the real name) and `cpfcgc_n`, same single-combined-field situation as `tblcontcertidoes.scpfcnpj` but formatted with punctuation (`.`/`-`/`/`) rather than plain digits.
- `"T"` — testamento. `id_ato` is `id` of a row in `bd_test` (yet another separate legacy domain, will/testament module) — `BdTest` (PK `id`, Rails default) has `testador` (real name) and `qualifica1`, a free-text "qualification" field. Unlike the other three, this branch only ever maps to CPF (`AtoPraticado::TIPO_DOCUMENTO_CPF`), never CNPJ — a testador is always a natural person — so it doesn't reuse the shared digit-count helper below; `qualifica1` must strip to exactly 11 digits or it's `nil`/placeholder. `qualifica1` is dirtier than the CPF/CNPJ fields above: plenty of older rows hold an RG instead (e.g. `"RG Nº 330.559-SSP-CE"`) or junk (`"***"`), which correctly fall through to the placeholder.

`"C"` and `"E"` share `AtoPraticado#tipo_e_numero_documento_por_digitos`: strips everything but digits from the raw value, then maps by resulting digit count (11 → CPF, 14 → CNPJ — the standard Brazilian convention for an untyped combined field); anything else — non-numeric junk (`tblcontcertidoes` has literal values like `"Não Apresentou"`), missing-leading-zero values landing on some other length, or two documents concatenated for joint ownership (`bd_escr` has real rows like this, digit count 22+) — falls back to `nil`/placeholder rather than guess.

Endereço and the other `documento` sub-fields (`descricao`/`orgaoEmissor`/`dataEmissao`, all `minOccurs="0"` in the XSD) stay the generic placeholder regardless of branch. None of the four branches has been fired against production yet with a matching real ato in the queue.

**The actual WSDL/XSD for `movimentarAtos` is checked in at `docs/tjce/`** (fetched straight from the TJCE production endpoint, `?wsdl` / `?wsdl=MovimentarAtosService.wsdl`) — use it instead of reverse-engineering `ato_xml` from error messages again. Notably: `CGenerica` extends `Ato` → `AtoSelado`, and `Ato` has an optional `sqAtoRetificado` (`xs:long`) field for retifying an already-submitted ato (send the same `CGenerica` payload again with that field set to the original ato's `sqAto_tj`). Retification **is implemented**: `AtoPraticado#retificacao?` (true when `retificacao == 1`) and `sqAto_idOriginal` (the original ato's TJCE-assigned `sqAto`, populated by the legacy PHP flow) drive `ato_xml` in `client.rb` to emit `<sqAtoRetificado>` right after `<codigoAto>` when set; the dashboard shows a "Retificação" badge on those atos. **Not yet tested against production** — no retification ato has been in the queue to fire for real. The schema also exposes a `consultaMovimentacao(idLote, idAto?)` operation (query status of an already-submitted lote/ato) that isn't used anywhere in this app either. See `docs/tjce/README.md` for details.

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

`SeloDigital::Client` also has three write operations, added alongside the `/movimentacao` write actions (see above):
- `solicita_selos(codigo_tipo_selo:, quantidade:, id_solicitacao:)` → `{ codigo:, mensagem:, chave:, data_hora: }`. Unlike the other operations, its response doesn't follow the `return > codigoRetorno > codigo/status/mensagem` shape — parsing uses document-wide XPath (`//codigo`, `//chave`, ...) matching the legacy PHP's own defensive approach, since the exact schema isn't documented anywhere available. **Still never fired against production.**
- `receber_selos(chave:)` → `{ codigo:, status:, mensagem:, selos: [{ numero_serie:, validador:, codigo_selo: }] }`. **Still never fired against production.**
- `movimentar_atos(atos:, id_lote:)` → array of `{ id_ato:, falha:, sq_ato_tj:, status_ato_tj:, codigo_falha: }`, one per submitted ato (see caveats in the Movimentação section above). `falha` is `true` when the item came back under `statusFalha` instead of `sqAto`/`statusAto` — `sq_ato_tj` is `nil` and `codigo_falha` holds the TJ error code in that case (there's no `sqAto` on a rejected ato, so the two must not be conflated). `Lote.enviar_atos!` uses this to set the ato's `status` to `"F"` (rejected) vs `"E"` (accepted) and excludes failures from the lote's confirmed count. **Verified against production**, including the `id_lote:` param (see above).

**Response parsing:** `Nokogiri::XML` parses the SOAP response. Namespaces are stripped with `remove_namespaces!` before XPath queries. `parse_movimentar_atos` raises `SeloDigital::Error` on a SOAP `<Fault>`, on a blank response body, and on a `<codigoRetorno>` block with no `<itensLote>` (the TJCE uses this same `<return><codigoRetorno>` shape — shared with `consulta_selos_disponiveis`/`receber_selos` — for global validation errors on this operation too, and notably its `status` can be `0` there even though `0` means success in those other two operations; `codigo`/`mensagem` are what actually distinguish an error here). Before this, a global error came back as an empty-but-successful `itensLote: []`, which silently looked identical to "0 atos confirmed" and let `Lote.enviar_atos!` create an empty orphaned `Lote` without surfacing anything to the user.

**Request/response logging:** every outgoing SOAP request and its raw response are written to `log/soap/request_<timestamp>.xml` / `response_<timestamp>.xml` (same timestamp pairs them, created on demand, gitignored). The response is written with `File.binwrite`, not `File.write` — TJCE responses aren't guaranteed valid UTF-8, and re-encoding raised `Encoding::UndefinedConversionError` in production during testing. Useful for debugging TJCE integration issues but grows unbounded — no cleanup job exists.

## Known Technical Debt

- **`VERIFY_NONE` in `SeloDigital::Client#post`**: server TLS certificate is not verified (`OpenSSL::SSL::VERIFY_NONE`). This should be replaced with proper CA verification in production.
- **No test coverage**: `test/` only contains scaffolding (no actual test files), even though CI invokes `rails test test:system`.
- **`bin/brakeman` currently fails before scanning**: it's invoked with `--ensure-latest`, and the installed gem (8.0.4) is behind the latest released version (8.0.5), so it exits immediately with no report. Needs a `bundle update brakeman` (or removing `--ensure-latest`) to unblock CI.
- **Single-tenant assumption**: `SelosController` calls `Empresa.first` to pick which cartório's certificate/codigo_serventia to use, even though `/empresas` supports multiple records. Fine while there's one cartório (current state); would need an explicit selection mechanism if that changes. `MovimentacaoController` does the same.
- **`solicita_selos`/`receber_selos` are still unverified against the real TJCE service** — built from reverse-engineered PHP, offline-validated for well-formed XML and correct field mapping, but never fired for real (`movimentar_atos` *was* fired and fixed — see External Service Integration above; the same class of bug, element order/naming mismatches only discoverable from a real error response, likely applies to these two as well). Test carefully (ideally against homologação once a cert is registered there) before relying on them; each consumes real TJCE-controlled resources (seal quota) with no dry-run mode.
