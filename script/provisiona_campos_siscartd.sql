-- Provisiona no banco siscartd (Windows) os campos/tabelas que este app Rails
-- (Selo Digital) precisa e que ainda não existem por lá.
--
-- Por que este script existe: siscartd é um banco legado compartilhado com o
-- sistema Delphi (SIAC) e um app PHP antigo (ver CLAUDE.md). As migrations
-- deste repo (db/migrate/) nunca foram rodadas contra a cópia do banco no
-- Windows — não existe nem a tabela schema_migrations lá. Rodar
-- `bin/rails db:migrate` apontando pra esse host também resolveria (e é o
-- caminho recomendado, se o Ruby/bundler estiver disponível na máquina
-- Windows), mas este script cobre o caso de só ter psql/pgAdmin à mão.
--
-- Verificado em 2026-08-31 contra siscartd (PostgreSQL 9.4.5) via
-- 172.24.0.1:5432: tblempresa não tinha nenhuma das 6 colunas abaixo, e as
-- tabelas retificacao_partes / ato_falhas não existiam. As tabelas legadas
-- sd_atosPraticados, sd_lotes, sd_solicitacoes, sd_selos, sd_tipos_selos já
-- tinham todas as colunas que o app usa (inclusive as de retificação:
-- retificacao, sqAto_idOriginal, sqAto_tj_retificacao,
-- data_retorno_tj_retificacao, data_atualizacao_tj_retificacao) — não
-- precisam de nada aqui.
--
-- IMPORTANTE — compatibilidade com PostgreSQL 9.4: essa é a mesma versão
-- antiga que já forçou a remoção de Solid Queue/Cache/Cable deste app (ver
-- CLAUDE.md). `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS` e
-- `ON CONFLICT` só existem a partir do Postgres 9.5/9.6, então nada disso
-- pode ser usado aqui — por isso os blocos DO $$ ... $$ abaixo, que checam o
-- catálogo manualmente antes de cada ALTER/CREATE/INSERT.
--
-- Uso:
--   psql -h <host> -U postgres -d siscartd -f script/provisiona_campos_siscartd.sql
--
-- Idempotente: pode ser rodado mais de uma vez sem erro. Ao final, registra
-- as versões em schema_migrations no formato que o Rails espera, para que um
-- futuro `bin/rails db:migrate` nessa base reconheça essas migrations como
-- já aplicadas e não tente rodá-las de novo.

BEGIN;

-- 20260713140839_add_certificado_digital_to_tblempresa
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tblempresa' AND column_name = 'certificado_digital') THEN
    ALTER TABLE tblempresa ADD COLUMN certificado_digital text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tblempresa' AND column_name = 'senha_certificado_digital') THEN
    ALTER TABLE tblempresa ADD COLUMN senha_certificado_digital text;
  END IF;
END $$;

-- 20260713143018_add_codigo_serventia_to_tblempresa
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tblempresa' AND column_name = 'codigo_serventia') THEN
    ALTER TABLE tblempresa ADD COLUMN codigo_serventia varchar;
  END IF;
END $$;

-- 20260713145945_add_homologacao_to_tblempresa
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tblempresa' AND column_name = 'homologacao') THEN
    ALTER TABLE tblempresa ADD COLUMN homologacao boolean DEFAULT false NOT NULL;
  END IF;
END $$;

-- 20260717180812_add_intervalo_envio_minutos_to_tblempresa
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tblempresa' AND column_name = 'intervalo_envio_minutos') THEN
    ALTER TABLE tblempresa ADD COLUMN intervalo_envio_minutos integer DEFAULT 0 NOT NULL;
  END IF;
END $$;

-- 20260731163013_add_modo_execucao_to_tblempresa
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'tblempresa' AND column_name = 'modo_execucao') THEN
    ALTER TABLE tblempresa ADD COLUMN modo_execucao varchar DEFAULT 'web' NOT NULL;
  END IF;
END $$;

-- 20260717121338_create_retificacao_partes
-- Tabela nova, própria deste app. ato_praticado_id aponta pro id de
-- sd_atosPraticados sem FK de banco (tabela legada, fora do controle de
-- migrations deste app).
CREATE TABLE IF NOT EXISTS retificacao_partes (
  id bigserial PRIMARY KEY,
  ato_praticado_id bigint NOT NULL,
  nome_pessoa varchar,
  tipo_documento integer,
  numero_documento varchar,
  descricao_documento varchar,
  orgao_emissor varchar,
  data_emissao_documento date,
  descricao_logradouro varchar,
  numero_endereco varchar,
  bairro varchar,
  complemento varchar,
  cidade integer,
  uf varchar,
  cep varchar,
  created_at timestamp(6) NOT NULL,
  updated_at timestamp(6) NOT NULL
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'index_retificacao_partes_on_ato_praticado_id') THEN
    CREATE UNIQUE INDEX index_retificacao_partes_on_ato_praticado_id
      ON retificacao_partes (ato_praticado_id);
  END IF;
END $$;

-- 20260717131725_create_ato_falhas
-- Idem: tabela nova, própria deste app, guarda a última rejeição do TJCE
-- (movimentar_atos) por ato.
CREATE TABLE IF NOT EXISTS ato_falhas (
  id bigserial PRIMARY KEY,
  ato_praticado_id bigint NOT NULL,
  codigo varchar,
  mensagem varchar,
  status_ato_tj varchar,
  ocorrida_em timestamp(6),
  created_at timestamp(6) NOT NULL,
  updated_at timestamp(6) NOT NULL
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'index_ato_falhas_on_ato_praticado_id') THEN
    CREATE UNIQUE INDEX index_ato_falhas_on_ato_praticado_id
      ON ato_falhas (ato_praticado_id);
  END IF;
END $$;

-- Registra as migrations como aplicadas, no formato que o Rails usa
-- (schema_migrations.version é a parte numérica do nome do arquivo).
CREATE TABLE IF NOT EXISTS schema_migrations (
  version character varying NOT NULL PRIMARY KEY
);

DO $$
DECLARE
  v varchar;
BEGIN
  FOREACH v IN ARRAY ARRAY[
    '20260713140839',
    '20260713143018',
    '20260713145945',
    '20260717121338',
    '20260717131725',
    '20260717180812',
    '20260731163013'
  ]
  LOOP
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = v) THEN
      INSERT INTO schema_migrations (version) VALUES (v);
    END IF;
  END LOOP;
END $$;

COMMIT;
