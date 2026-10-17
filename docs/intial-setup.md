# Initial Setup — Before Writing the Talk-to-DB Skill

Do these in order. Nothing here touches LLM logic yet — this is pure infra/plumbing so the
skill has something solid to sit on.

## 1. Provision the harness's own memory database
- [ ] Create a free Supabase or Neon Postgres project (separate from ConceptDash's DB).
- [ ] Enable the `pgvector` extension on it.
- [ ] Save connection string as `HARNESS_DB_URL` in `.env` (never commit `.env`).

## 2. Confirm read-only access to the real CRM/HRM DB
- [ ] Confirm the DB user/role you're using against ConceptDash's Postgres has **read-only**
      privileges (SELECT only — no INSERT/UPDATE/DELETE/DDL grants). If the current
      credentials are broader than read-only, create a dedicated read-only role now, before
      writing any query-generation code, so a bad generated SQL statement can't mutate data.
- [ ] Save connection string as `SOURCE_DB_URL` (read-only) in `.env`.
- [ ] Note down which schemas exist and confirm schema boundaries (this project has hit
      cross-schema reference bugs before — e.g. hrm_db querying schema_3.users — so write
      down explicitly which schema(s) each tenant/module lives in before building retrieval).

## 3. Get an LLM key (free tier)
- [ ] Create a Google AI Studio account, get a Gemini API key (no card required).
- [ ] Optionally get a Groq API key as a failover (OpenAI-compatible client, easy swap).
- [ ] Save both as `LLM_PRIMARY_KEY` / `LLM_FALLBACK_KEY` in `.env`.
- [ ] Write a single thin `llmClient` wrapper module now (even a stub) so every future skill
      calls through one interface, not a provider SDK directly. This is what makes the
      "swap models later" decision free.

## 4. Set up the DDL extraction script
Since connection details + a local DDL dump already exist:
- [ ] Write (or confirm you have) a script that re-pulls DDL programmatically from
      `SOURCE_DB_URL` — table name, schema, columns, types, primary keys, foreign keys —
      rather than relying only on the hand-saved local copy. This becomes the ongoing sync
      mechanism when schema changes (new modules, altered columns).
- [ ] Output format: one JSON/text object per table, tagged with its schema name. This is
      the raw input to the chunking step in the skill implementation doc.

## 5. Create the harness-owned tables (on `HARNESS_DB_URL`, not the source DB)
- [ ] `ddl_chunks` — vector store table (chunk text, embedding, schema name, table name, metadata)
- [ ] `vocabulary_map` — columns: `id`, `canonical_term`, `alias`, `user_id` (nullable),
      `confidence`, `created_at`, `updated_at`
- [ ] `episodic_log` — **skill-agnostic, logs every turn regardless of routing** — columns:
      `id`, `session_id`, `user_id`, `turn_number`, `raw_message`, `routed_skill` (nullable —
      e.g. `talk_to_db`, `chit_chat`, `none`), `resolved_intent_or_sql` (nullable),
      `created_at`. Every turn gets a row here, including chit-chat — this is what makes the
      log reusable once more skills exist, so don't scope it to talk-to-db only.
- [ ] `trace_log` — columns: `id`, `session_id`, `turn_id`, `phase` (turn_start / gate / llm /
      tool / turn_end), `payload` (jsonb), `duration_ms`, `created_at`
- [ ] Hand-seed `vocabulary_map` with 10–20 known mappings (e.g. "task sheet" / "timesheet")
      before building the skill, so v1 has something to resolve against immediately.

## 6. Identity resolution stub
- [ ] Write the deterministic lookup function: given a session/user id, return CRM ID +
      employee ID from the source DB. Keep it a plain function call for now (no caching yet)
      — this is the "always fetched" context every future skill call will use.

## 7. Routing gate stub
- [ ] Write a single function, `routeTurn(message, context) -> { skill: 'talk_to_db' |
      'chit_chat' | 'none', confidence }`. This is the harness-level entry point every turn
      passes through *before* any skill logic runs — it decides whether to call talk-to-db
      at all, or just respond conversationally, or (later) route to a different skill.
- [ ] Implement it as one fast, cheap LLM call (can use the same `llmClient` wrapper from
      step 3, but keep the prompt short — this call should be cheap, not the main reasoning
      call). A non-LLM classifier is fine too if you want to skip a network call for obvious
      chit-chat, but start with an LLM call for simplicity and optimize later.
- [ ] This function is the harness's actual skill router going forward — build it generic
      (returns a skill name, not a boolean "is this DB related") so adding skill #2 later
      means adding a case, not rewriting the gate.

## 8. Repo/project scaffolding
- [ ] One backend service (Node/Express), directories: `/skills`, `/memory`, `/llm`, `/tracing`.
- [ ] `.env.example` listing all keys above without values.
- [ ] Basic health-check route to confirm both DB connections (`HARNESS_DB_URL`,
      `SOURCE_DB_URL`) are reachable before writing any skill code.

Once all of the above is checked off, move to `02_talk_to_db_skill.md`.