# Initial Setup — Before Writing the Talk-to-DB Skill

Do these in order. Nothing here touches LLM logic yet — this is pure infra/plumbing so the skill has something solid to sit on.

## 1. Provision the harness's own memory database

- [ ] Create a free Supabase or Neon Postgres project (separate from ConceptDash's DB).
- [ ] Enable the `pgvector` extension on it.
- [ ] Save connection string as `HARNESS_DB_URL` in `.env` (never commit `.env`).

## 2. Confirm read-only access to the real CRM/HRM DB

- [ ] Confirm the DB user/role you're using against ConceptDash's Postgres has **read-only** privileges (SELECT only — no INSERT/UPDATE/DELETE/DDL grants). If the current credentials are broader than read-only, create a dedicated read-only role now, before writing any query-generation code, so a bad generated SQL statement can't mutate data.
- [ ] Save connection string as `SOURCE_DB_URL` (read-only) in `.env`.
- [ ] Note down which schemas exist and confirm schema boundaries (this project has hit cross-schema reference bugs before — e.g. hrm_db querying schema_3.users — so write down explicitly which schema(s) each tenant/module lives in before building retrieval).



## 3. Get an LLM key (free tier)

- [ ] Create a Google AI Studio account, get a Gemini API key (no card required).
- [ ] Optionally get a Groq API key as a failover (OpenAI-compatible client, easy swap).
- [ ] Save both as `LLM_PRIMARY_KEY` / `LLM_FALLBACK_KEY` in `.env`.
- [ ] Write a single thin `llmClient` wrapper module now (even a stub) so every future skill calls through one interface, not a provider SDK directly. This is what makes the "swap models later" decision free.