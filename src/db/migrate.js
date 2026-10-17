import 'dotenv/config';
import { harnessDb } from './connections.js';

const SQL = `
-- Enable pgvector (must be done once per DB by a superuser; safe to call again)
CREATE EXTENSION IF NOT EXISTS vector;

-- DDL chunks: one row per table, stores schema+table DDL text + its embedding
CREATE TABLE IF NOT EXISTS ddl_chunks (
  id              SERIAL PRIMARY KEY,
  schema_name     TEXT NOT NULL,
  table_name      TEXT NOT NULL,
  db_label        TEXT NOT NULL,           -- 'crm' | 'hrm'
  chunk_text      TEXT NOT NULL,           -- full DDL text for this table
  embedding       vector(768),             -- gemini-embedding-001 dimension
  cross_schema_refs TEXT[],               -- schemas this table's FKs touch
  content_hash    TEXT NOT NULL,           -- sha256 of chunk_text; skip re-embed if unchanged
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (schema_name, table_name, db_label)
);

CREATE INDEX IF NOT EXISTS ddl_chunks_embedding_idx
  ON ddl_chunks USING hnsw (embedding vector_cosine_ops);

-- Vocabulary map: canonical term resolution (task sheet → timesheet, etc.)
CREATE TABLE IF NOT EXISTS vocabulary_map (
  id             SERIAL PRIMARY KEY,
  canonical_term TEXT NOT NULL,
  alias          TEXT NOT NULL,
  user_id        TEXT,                     -- NULL = global; set = user-specific override
  confidence     REAL NOT NULL DEFAULT 1.0,
  created_at     TIMESTAMPTZ DEFAULT now(),
  updated_at     TIMESTAMPTZ DEFAULT now(),
  UNIQUE (alias, user_id)
);

-- Sessions: one row per chat session, keyed by session_id from the client
CREATE TABLE IF NOT EXISTS sessions (
  id           SERIAL PRIMARY KEY,
  session_id   TEXT NOT NULL UNIQUE,
  user_id      TEXT,
  email        TEXT,
  turn_count   INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ DEFAULT now(),
  last_active  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);
CREATE INDEX IF NOT EXISTS sessions_session_id_idx ON sessions (session_id);

-- Episodic log: every turn, every skill (skill-agnostic)
CREATE TABLE IF NOT EXISTS episodic_log (
  id                       SERIAL PRIMARY KEY,
  session_id               TEXT NOT NULL,
  user_id                  TEXT,
  turn_number              INTEGER NOT NULL,
  raw_message              TEXT NOT NULL,
  routed_skill             TEXT,
  resolved_intent_or_sql   TEXT,
  assistant_answer         TEXT,
  created_at               TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS episodic_log_session_idx ON episodic_log (session_id);
CREATE INDEX IF NOT EXISTS episodic_log_user_idx    ON episodic_log (user_id);

-- Trace log: per-phase tracing for every turn
-- prompt_sent stores the full system+user prompt sent to the LLM (for frontend inspection)
CREATE TABLE IF NOT EXISTS trace_log (
  id          SERIAL PRIMARY KEY,
  session_id  TEXT NOT NULL,
  turn_id     INTEGER,
  phase       TEXT NOT NULL,
  payload     JSONB,
  prompt_sent JSONB,                       -- { systemPrompt, userPrompt } when phase='llm'
  duration_ms INTEGER,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS trace_log_session_idx ON trace_log (session_id);
CREATE INDEX IF NOT EXISTS trace_log_turn_idx    ON trace_log (turn_id);
`;

// Additive migrations — safe to run on existing DBs
const MIGRATIONS = `
ALTER TABLE episodic_log    ADD COLUMN IF NOT EXISTS assistant_answer TEXT;
ALTER TABLE trace_log       ADD COLUMN IF NOT EXISTS prompt_sent JSONB;
ALTER TABLE vocabulary_map  ADD COLUMN IF NOT EXISTS db TEXT NOT NULL DEFAULT 'crm';

-- talk2db schema: isolated from tenant data and harness tables
CREATE SCHEMA IF NOT EXISTS talk2db;

-- Session header + open clarification state (replaces harness sessions for talk2db context)
CREATE TABLE IF NOT EXISTS talk2db.sessions (
  session_id            TEXT PRIMARY KEY,
  channel               TEXT NOT NULL DEFAULT 'web',
  crm_id                BIGINT,
  employee_id           BIGINT,
  pending_clarification JSONB,
  recent_entities       JSONB,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One row per user message turn
CREATE TABLE IF NOT EXISTS talk2db.turns (
  turn_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id           TEXT NOT NULL REFERENCES talk2db.sessions(session_id),
  turn_no              INT NOT NULL,
  user_message         TEXT NOT NULL,
  rephrased_question   TEXT,
  final_status         TEXT,
  respond              JSONB,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS talk2db_turns_session_idx ON talk2db.turns (session_id, turn_no);

-- One row per LLM call (drives the frontend inspector)
CREATE TABLE IF NOT EXISTS talk2db.llm_calls (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turn_id         UUID NOT NULL REFERENCES talk2db.turns(turn_id),
  call_name       TEXT NOT NULL,
  attempt         INT NOT NULL DEFAULT 1,
  model           TEXT,
  input           JSONB,
  rendered_prompt JSONB,
  output_raw      TEXT,
  output_parsed   JSONB,
  status          TEXT,
  tokens_in       INT,
  tokens_out      INT,
  latency_ms      INT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS talk2db_llm_calls_turn_idx ON talk2db.llm_calls (turn_id);

-- One row per SQL execution attempt
CREATE TABLE IF NOT EXISTS talk2db.executions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turn_id        UUID NOT NULL REFERENCES talk2db.turns(turn_id),
  attempt        INT NOT NULL DEFAULT 1,
  sql            TEXT,
  status         TEXT,
  error          TEXT,
  error_type     TEXT,
  row_count      INT,
  duration_ms    INT,
  result_summary TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS talk2db_executions_turn_idx ON talk2db.executions (turn_id);

-- What retrieval returned (for inspector and tuning)
CREATE TABLE IF NOT EXISTS talk2db.retrieval_log (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  turn_id    UUID NOT NULL REFERENCES talk2db.turns(turn_id),
  kind       TEXT NOT NULL,
  item_id    TEXT,
  rank       INT,
  score      REAL,
  included   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS talk2db_retrieval_log_turn_idx ON talk2db.retrieval_log (turn_id);

-- Validated question/SQL pairs for retrieval (query samples store)
CREATE TABLE IF NOT EXISTS talk2db.query_samples (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question           TEXT NOT NULL,
  question_embedding vector(768),
  sql_template       TEXT NOT NULL,
  sql_hash           TEXT NOT NULL,
  tables_used        TEXT[],
  ddl_ids            TEXT[],
  ddl_hash           TEXT,
  intent_tags        TEXT[],
  source             TEXT NOT NULL CHECK (source IN ('seed','runtime','manual')),
  status             TEXT NOT NULL CHECK (status IN ('candidate','validated','approved','rejected','stale')),
  validation         JSONB,
  usage_count        INT NOT NULL DEFAULT 0,
  success_count      INT NOT NULL DEFAULT 0,
  last_used_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sql_hash)
);
CREATE INDEX IF NOT EXISTS talk2db_query_samples_status_idx ON talk2db.query_samples (status);
CREATE INDEX IF NOT EXISTS talk2db_query_samples_embedding_idx ON talk2db.query_samples USING hnsw (question_embedding vector_cosine_ops);
`;

async function migrate() {
  console.log('[migrate] Running harness DB migrations...');
  const client = await harnessDb.connect();
  try {
    await client.query(SQL);
    await client.query(MIGRATIONS);
    console.log('[migrate] Done.');
  } finally {
    client.release();
    await harnessDb.end();
  }
}

migrate().catch((err) => {
  console.error('[migrate] Failed:', err.message);
  process.exit(1);
});
