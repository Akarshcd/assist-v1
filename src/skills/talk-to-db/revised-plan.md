# Talk2DB Architecture Plan (v2, implementation-ready)

Build order: **(1) session JSON + orchestrator, (2) the LLM calls, (3) frontend call inspector.** Principle: get the pipeline correct first, optimize latency later. Memory layers (episodic/semantic/long-term) are deferred.

---

## 0. Naming (use these names in code)


| Name                         | Type              | Job                                                               |
| ---------------------------- | ----------------- | ----------------------------------------------------------------- |
| **Router**                   | LLM call          | Decide if the message should use Talk2DB at all                   |
| **Call 1: Rephrase/Clarify** | LLM call          | Rephrase to a standalone question, or ask clarification questions |
| **Retrieval**                | pgvector (no LLM) | Top-k query samples + top-k DDLs                                  |
| **Call 2: Planner**          | LLM call          | Produce SQL plan with confidence, or `no_match`                   |
| **Executor**                 | code (no LLM)     | Read-only guard, run SQL, capture rows/errors                     |
| **Call 3: Respond/Validate** | LLM call          | Validate data against the question, write the user-facing reply   |


Every LLM API call is stateless: each request must contain all context it needs.

---

## 1. Flow

```
User message
   │
   ├─ session.pending_clarification set? ──YES──► Call 1 (skip Router)
   │                                               input: session + original prompt + clarification JSON + new message
   NO
   ▼
Router ── not Talk2DB ──► other skill / chitchat
   │ Talk2DB
   ▼
Call 1: Rephrase/Clarify
   ├─ needs_clarification ──► send questions to user, set pending_clarification, END TURN
   ▼ (rephrased_question ready)
Retrieval (top-k samples + top-k DDLs)
   ▼
Call 2: Planner  ◄──────────────┐
   ├─ no_match ─────────────────┼──► Call 3 (outcome B)
   ├─ low confidence ───────────┼──► back to Call 1 as a clarification (once per turn)
   ▼ plan                       │
Executor (read-only guard)      │
   ├─ SQL error, attempt < 3 ───┘ (retry Call 2 with failed SQL + error)
   ├─ SQL error, attempt = 3 ──► FAILURE path (template message + log)
   ▼ rows (including empty)
Call 3: Respond/Validate
   ├─ A: answer + suggested next question
   ├─ B: no relevant data + alternatives (from DDLs/samples)
   └─ C: cannot process
   ▼
Reply to user

```

---

## 2. Call contracts

All calls return strict JSON. Parse, validate against a schema, log both raw and parsed output.

### Router

- **Input:** user message, short session summary.
- **Output:** `{ "skill": "talk2db" | "other" | "chitchat", "confidence": 0-1 }`
- Not run when `pending_clarification` is set.

### Call 1: Rephrase/Clarify

**Input:** user message, session history; when a clarification is pending, also the original prompt and the clarification JSON.

**Output:**

```json
{
  "message_type": "new_question | clarification_answer | new_topic",
  "rephrased_question": "string or null",
  "needs_clarification": false,
  "clarification": {
    "round": 1,
    "questions": [
      { "id": "q1", "text": "Overdue invoices or overdue tasks?", "answer": null },
      { "id": "q2", "text": "For which month?", "answer": null }
    ]
  },
  "assumptions": []
}

```

Rules:

- **Multiple questions allowed** in one clarification. Each has an `id` so free-text replies (WhatsApp) can be mapped back.
- When the user replies, the answers are filled into the same JSON (`answer` per question) and sent back to Call 1 together with session + original prompt. Router is skipped.
- Call 1 classifies the reply:
  - `clarification_answer`: use answers to produce `rephrased_question`.
  - Partial answer: re-ask only the unanswered ids (counts as another round).
  - `new_topic`: clear `pending_clarification`, then run Router normally.
- **Max 2 clarification rounds** per original question. After that, proceed with stated `assumptions` instead of asking again.
- If `needs_clarification` is true, the response to the user is the questions themselves (no DB work this turn).

### Retrieval (pgvector, no LLM)

- Embed `rephrased_question`.
- Fetch top-k **query samples** and top-k **DDLs**; log ids + similarity scores.
- Samples store: question + SQL pairs (new store; save validated good pairs over time).

### Call 2: Planner

**Input:** session history, `rephrased_question` (with clarification answers/assumptions), top-k samples, top-k DDLs. On retry: also `previous_attempts` (failed SQL + error message for each).

**Output (one of):**

```json
{
  "status": "plan",
  "confidence": 0.82,
  "queries": [ { "sql": "SELECT ...", "purpose": "..." } ],
  "relevant_ddls": ["d_04", "d_11"],
  "relevant_samples": ["s_12"],
  "notes": "string"
}

```

```json
{
  "status": "no_match",
  "reason": "string",
  "available": ["what data IS present, so the user can ask for it"],
  "relevant_ddls": ["..."],
  "relevant_samples": ["..."]
}

```

Rules:

- **Confidence below threshold** (start at 0.6, make configurable): do not execute. Send back to Call 1 as a clarification (at most once per turn, counts toward the 2-round cap).
- `no_match` goes straight to Call 3 (outcome B). No execution.

### Executor (code)

- **Read-only guard:** allow SELECT only (parse, e.g. with a SQL parser; reject INSERT/UPDATE/DELETE/DDL/multiple statements), set a statement timeout, enforce a row limit, set the correct tenant schema/search_path.
- Capture: status, row_count, rows (bounded), duration_ms, error.

### Retry policy (Planner)

- **Retry only on SQL errors** (syntax, missing column/table). Feed back the failed SQL + error message each attempt so attempt N+1 doesn't repeat attempt N.
- **Do not retry** on: empty result (valid, goes to Call 3), timeouts, permission errors, guard rejections.
- **Max 3 attempts.** After the 3rd failure: FAILURE path.

### FAILURE path

- Send the user a fixed template message (no extra LLM call), e.g. "I couldn't process that request. Could you try rephrasing it?"
- Log the full attempt history (SQL + error per attempt) in the session JSON for debugging.
- Clear any pending state.

### Call 3: Respond/Validate

**Input:** session history, original + rephrased question (and clarification JSON), SQL executed, DB result (summary + bounded rows), relevant DDLs, relevant samples.

**Output (one of three outcomes):**

```json
{
  "outcome": "answer",
  "validated": true,
  "response": "user-facing text",
  "suggested_next": "a follow-up question or what the user may want next"
}

```

```json
{
  "outcome": "no_relevant_data",
  "response": "user-facing text",
  "alternatives": ["things the user can ask instead, drawn from DDLs/samples"]
}

```

```json
{
  "outcome": "cannot_process",
  "response": "user-facing text",
  "reason": "string"
}

```

Rules:

- If the data does not actually answer the question (validation fails), do not present it as an answer; use `no_relevant_data` or `cannot_process`.
- Empty result: explain plainly and offer alternatives.
- On a validated `answer`, optionally save the (question, SQL) pair to the samples store.

---

## 3. Session JSON log

Single source of truth for every call and for the frontend inspector. Structured log, not a raw message dump, so richer memory layers can be added later as a retrieval layer without changing storage.

```json
{
  "session_id": "uuid",
  "user": { "crm_id": 123, "employee_id": 456 },
  "created_at": "ISO-8601",
  "pending_clarification": null,
  "turns": [
    {
      "turn_id": 1,
      "timestamp": "ISO-8601",
      "user_message": "raw text",
      "routing": { "skill": "talk2db", "confidence": 0.94, "skipped": false },
      "rephrase": {
        "message_type": "new_question",
        "rephrased_question": "...",
        "needs_clarification": false,
        "assumptions": []
      },
      "clarification": {
        "round": 1,
        "original_prompt": "show me the overdue ones",
        "questions": [
          { "id": "q1", "text": "Overdue invoices or tasks?", "answer": "invoices" },
          { "id": "q2", "text": "For which month?", "answer": null }
        ]
      },
      "retrieval": {
        "samples": [ { "id": "s_12", "score": 0.88 } ],
        "ddls": [ { "id": "d_04", "table": "users", "score": 0.91 } ]
      },
      "planner_attempts": [
        {
          "attempt": 1,
          "status": "plan",
          "confidence": 0.82,
          "queries": [ { "sql": "SELECT ...", "purpose": "..." } ],
          "execution": {
            "status": "error",
            "error": "column x does not exist",
            "row_count": null,
            "duration_ms": 14
          }
        },
        {
          "attempt": 2,
          "status": "plan",
          "confidence": 0.85,
          "queries": [ { "sql": "SELECT ...", "purpose": "..." } ],
          "execution": {
            "status": "ok",
            "error": null,
            "row_count": 14,
            "duration_ms": 120,
            "result_summary": "14 overdue invoices for September"
          }
        }
      ],
      "respond": {
        "outcome": "answer",
        "validated": true,
        "response": "...",
        "suggested_next": "..."
      },
      "final_status": "answered | clarification_requested | no_relevant_data | cannot_process | failed_after_retries",
      "llm_calls": [
        {
          "call": "router | rephrase | planner | respond",
          "attempt": 1,
          "model": "...",
          "input": {},
          "output_raw": "",
          "output_parsed": {},
          "tokens_in": 0,
          "tokens_out": 0,
          "latency_ms": 0
        }
      ]
    }
  ]
}

```

Rules:

- `pending_clarification` (top level) holds the open clarification JSON + original prompt while waiting for the user. `null` otherwise.
- Store result **summaries**, not full raw rows (keep rows in a separate store by reference if needed).
- Log raw and parsed output for every call; persist after every turn.
- Keep the user identity linkage (CRM id, employee id) and recent referenced entity ids easy to pull for pronoun resolution.

---

## 4. Orchestrator pseudocode

```
handle_message(session, text):
  if session.pending_clarification:
      r = call1(session, text, pending=session.pending_clarification)   # Router skipped
      if r.message_type == "new_topic":
          session.pending_clarification = None
          return handle_message(session, text)                         # fresh, runs Router
  else:
      route = router(session, text)
      if route.skill != "talk2db": return other_flow(...)
      r = call1(session, text)

  if r.needs_clarification:
      if round > MAX_CLARIFICATION_ROUNDS: proceed with r.assumptions
      else:
          session.pending_clarification = {original_prompt, questions, round}
          return render_questions(r.clarification)

  session.pending_clarification = None
  ctx = retrieve(r.rephrased_question)
  attempts = []
  for i in 1..3:
      plan = call2(session, r, ctx, previous_attempts=attempts)
      if plan.status == "no_match": return call3(..., no_result=plan)
      if plan.confidence < THRESHOLD and not already_bounced:
          return clarify_via_call1(...)
      exec = executor.run(plan.queries)                                # guard + timeout + limit
      attempts.append({plan, exec})
      if exec.status == "ok": return call3(session, r, plan, exec, ctx)
      if exec.error_type not in RETRYABLE: break
  return failure_template(), log(attempts)

```

---

## 5. Prompt structure (all calls)

- Role-tagged messages: `system` for instructions, `user` for turn content.
- Reference data in tagged blocks: `<session_history>`, `<schema>`, `<examples>`, `<clarification>`, `<previous_attempts>`, `<sql>`, `<db_result>`.
- In Calls 1 and 3, label explicitly: original question, rephrased question, clarification answers, DB result.
- Force JSON output (response schema / JSON mode) and validate it; on parse failure, retry the same call once.
- Pass summarized history (question, SQL, result summary per turn), not raw rows.

---

## 6. Frontend: call inspector (structured input/output for every LLM call)

Goal: for every LLM call in a turn (including each planner retry), see **exactly what went in and what came out, in structured form**, not a text blob. The UI renders from the same structured `input` object the prompt builder uses, so what you see is what the model got.

### Layout

- **Left:** session list, then turn list for the selected session (with `final_status` badge per turn).
- **Center:** turn timeline of steps in order: Router, Call 1, Retrieval, Call 2 (attempt N), Executor, Call 3. Skipped steps show as "skipped: pending clarification".
- **Right:** detail for the selected step with tabs **Input | Output | Raw**.

### Step header (every step)

Call name, attempt number, model, status (`ok | parse_error | retried | skipped`), latency, tokens in/out.

### Input tab (structured sections per call)


| Call      | Sections shown                                                                                                                           |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Router    | User message; session summary                                                                                                            |
| Call 1    | User message; session history as turn cards (question, rephrased, SQL, result summary); pending clarification table (`id                 |
| Retrieval | Embedded text; DDL hits table (`rank                                                                                                     |
| Call 2    | Rephrased question; clarification answers + assumptions; DDLs passed (table); samples passed (table); previous failed attempts (`attempt |
| Executor  | SQL (syntax highlighted); guard verdict; tenant schema; timeout and row limit                                                            |
| Call 3    | Original + rephrased question; clarification Q&A; SQL executed; result summary + first N rows as a table; DDLs; samples                  |


Every Input tab also has a collapsed **Final rendered prompt** section (system + user messages exactly as sent).

### Output tab (structured rendering of parsed JSON)


| Call   | Rendering                                                                                                                                                                                                     |
| ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Router | Skill badge + confidence bar                                                                                                                                                                                  |
| Call 1 | `message_type` badge; rephrased question; clarification questions table; assumptions list                                                                                                                     |
| Call 2 | Status badge; confidence gauge with the threshold marked; each query as a code block with its `purpose`; relevant DDL/sample chips that link back to the Input tab; for `no_match`: reason + "available" list |
| Call 3 | Outcome badge; validated tick; response shown as a chat bubble preview; `suggested_next` or `alternatives` as chips                                                                                           |


**Raw tab:** toggle between parsed JSON and the raw model output (for debugging parse errors).

### Extras

- **Diff view** between planner attempts (SQL and error side by side).
- **Filters:** failed turns, retries, low confidence, clarification requested, `no_match`.
- **Live mode:** steps appear as they complete (SSE).

### API (suggested)

- `GET /api/talk2db/sessions` : list sessions
- `GET /api/talk2db/sessions/:id` : session + turns
- `GET /api/talk2db/turns/:turnId/trace` : ordered steps 
  ```json
  [  {    "step": "call2",    "attempt": 2,    "status": "ok",    "meta": { "model": "...", "latency_ms": 0, "tokens_in": 0, "tokens_out": 0 },    "input": {},    "rendered_prompt": [],    "output_parsed": {},    "output_raw": ""  }]

  ```
- `GET /api/talk2db/turns/:turnId/stream` : SSE of steps as they finish

### Requirements

- Store `input` (structured) and `rendered_prompt` for every call; the prompt builder takes the `input` object so the two never drift.
- Admin-only, tenant-scoped access. Mask phone numbers and secrets in stored inputs; set a retention period for `llm_calls`.
- Render from the normalized tables in section 9 (not from scraped logs).

---

## 7. Decisions and assumptions

- Max 2 clarification rounds; then proceed with stated assumptions.
- Planner confidence threshold starts at 0.6 (configurable).
- Planner retries only on SQL errors, max 3 attempts, with failed SQL + error fed back.
- After 3 failed attempts: fixed template message to the user (no extra LLM call), full attempt history logged. **Open:** confirm that the orchestrator (not an LLM) sends this message.
- Worst-case calls per turn: Router + Call 1 + 3x Call 2 + Call 3 = 6. Log retry frequency before optimizing.
- Local timing: ~4 s max per chain with Gemini; expecting 5-6 s in production. Optimize (merge/parallelize) after measuring.
- Deferred: episodic/semantic/long-term memory layers.

---

## 8. Sample query seeding (DDL to validated question/SQL pairs)

Goal: build the query-sample store before users arrive, and keep growing it from validated runtime answers. Nothing enters the retrievable store unless it was actually executed and judged correct.

### 8.1 Offline seeding job (per DDL / table group)

1. **Pick targets:** each table, plus common join groups (a table with its FK neighbors) taken from the DDL store. Include the tenant schema scope (e.g. which `schema_N` it applies to).
2. **Generate candidates (LLM):** input = the DDL(s) + FK-related DDLs + schema rules (see below). Output = N `{question, sql, intent_tags}` candidates per target. Ask for variety: simple filters, aggregations, date ranges, joins, top-N, "my X" questions that use the identity linkage.
3. **Static checks (code, before running):**
  - SELECT-only, single statement (same guard as the Executor).
  - Every referenced schema/table/column exists in the DDL store. **Reject cross-database / wrong-schema references** (known failure: e.g. `hrm_db` querying `schema_3.users`).
  - Hard-blocked schemas (e.g. `schema_118`) rejected.
4. **Run it:** `EXPLAIN` first, then execute with `LIMIT` and a statement timeout, using a **read-only role** against a dev/seed tenant (or a safe tenant with test data).
5. **Validate the result:**
  - Execution must succeed.
  - Empty result is allowed only if the question was intentionally narrow; flag it.
  - **LLM judge** (same shape as Call 3 validation): "does this SQL + result answer this question?" returns `validated` + short reason + score.
6. **Dedupe:** skip if normalized-SQL hash already exists, or question embedding similarity to an existing sample is above ~0.95.
7. **Embed and save** to `query_samples` (section 9) with `source='seed'`, `status='validated'`, and the validation details.
8. **Failures:** keep them in a rejected list with the reason (useful to improve the generator prompt); do not make them retrievable.

### 8.2 Runtime learning

- When Call 3 returns `outcome='answer'` with `validated=true`, insert the (rephrased question, SQL) as `source='runtime'`, `status='candidate'`.
- Promote `candidate` to `validated` after a repeat success, positive feedback, or the judge check above. Only `validated`/`approved` rows are retrievable (decision below).
- Update `usage_count`, `success_count`, `last_used_at` whenever a sample is retrieved and the final answer was validated.

### 8.3 Keeping samples in sync with schema changes

- Each sample stores the `ddl_hash`/version of the tables it uses.
- When a DDL changes, mark affected samples `stale`, then re-run the validation steps (4 to 5); promote back or reject.

### 8.4 Multi-tenant SQL

- Store SQL with a schema placeholder (e.g. `{{schema}}`) and substitute the tenant schema at runtime. This keeps one sample reusable across tenants. **Open decision:** confirm placeholder approach vs per-tenant samples.

### 8.5 Decisions to confirm

- Retrieval uses `validated` + `approved` only, or `approved` only (needs a human review queue)? Suggested: `validated` and `approved`, with approved ranked higher.
- Number of candidates per table and the similarity threshold for dedupe.

---

## 9. Database tables

**Cannot be assumed from this plan: the existing tables must be audited first.** Step 0 of the checklist is for Claude Code to inspect the current database and decide, per table below, whether to CREATE or ALTER.

### 9.1 Audit task (run against the real database)

```sql
-- what exists already (look for session, vector, sample, ddl, entity/vocabulary, log tables)
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog','information_schema')
  AND (table_name ILIKE '%session%' OR table_name ILIKE '%sample%'
       OR table_name ILIKE '%ddl%' OR table_name ILIKE '%embed%'
       OR table_name ILIKE '%vector%' OR table_name ILIKE '%chat%'
       OR table_name ILIKE '%entity%' OR table_name ILIKE '%vocab%');

-- columns of anything found
SELECT table_schema, table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name IN (/* tables found above */)
ORDER BY table_schema, table_name, ordinal_position;

-- pgvector installed? embedding dimension in use?
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';

```

Compare the findings with the proposed tables below, then write migrations: `ALTER` where a table exists (add missing columns, indexes), `CREATE` where it does not. Do not drop or rewrite existing tables.

### 9.2 Where they live

Put the Talk2DB tables in their own schema (e.g. `talk2db`), not inside any tenant schema, so they are separated from tenant data and from hard-blocked schemas. Keep the app role's grants to this schema explicit.

### 9.3 `query_samples` (vector store for validated question/SQL pairs)

```sql
CREATE TABLE talk2db.query_samples (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  question         text NOT NULL,
  question_embedding vector(/* match the DDL store's embedding dimension */) NOT NULL,
  sql_template     text NOT NULL,              -- uses {{schema}} placeholder
  sql_hash         text NOT NULL UNIQUE,       -- hash of normalized SQL, for dedupe
  tables_used      text[] NOT NULL,
  ddl_ids          text[] NOT NULL,            -- ids in the DDL vector store
  ddl_hash         text,                       -- version of DDLs at validation time
  intent_tags      text[],
  source           text NOT NULL CHECK (source IN ('seed','runtime','manual')),
  status           text NOT NULL CHECK (status IN ('candidate','validated','approved','rejected','stale')),
  validation       jsonb,                      -- {row_count, duration_ms, judge_score, judge_reason, validated_at}
  usage_count      int NOT NULL DEFAULT 0,
  success_count    int NOT NULL DEFAULT 0,
  last_used_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON talk2db.query_samples USING hnsw (question_embedding vector_cosine_ops);
CREATE INDEX ON talk2db.query_samples (status);
CREATE INDEX ON talk2db.query_samples USING gin (tables_used);

```

Use the same embedding model (and dimension) as the DDL store so retrieval scores are comparable.

### 9.4 Session and trace tables

Check the existing session storage first (the plan assumes session-stored CRM IDs already exist). The target shape:

```sql
-- session header + open clarification state
talk2db.sessions (
  session_id uuid PK, channel text, external_ref text,   -- e.g. WhatsApp number (masked/hashed)
  crm_id bigint, employee_id bigint,
  pending_clarification jsonb,                           -- null when none
  recent_entities jsonb,                                 -- ids for pronoun resolution
  created_at timestamptz, updated_at timestamptz
);

-- one row per user message
talk2db.turns (
  turn_id uuid PK, session_id uuid FK, turn_no int,
  user_message text, rephrased_question text,
  final_status text,   -- answered | clarification_requested | no_relevant_data | cannot_process | failed_after_retries
  respond jsonb, created_at timestamptz
);

-- one row per LLM call (drives the frontend inspector)
talk2db.llm_calls (
  id uuid PK, turn_id uuid FK,
  call_name text,      -- router | rephrase | planner | respond
  attempt int, model text,
  input jsonb, rendered_prompt jsonb,
  output_raw text, output_parsed jsonb,
  status text,         -- ok | parse_error | skipped
  tokens_in int, tokens_out int, latency_ms int,
  created_at timestamptz
);

-- one row per SQL execution attempt
talk2db.executions (
  id uuid PK, turn_id uuid FK, attempt int,
  sql text, status text, error text, error_type text,
  row_count int, duration_ms int, result_summary text, created_at timestamptz
);

-- what retrieval returned (for the inspector and tuning)
talk2db.retrieval_log (
  id uuid PK, turn_id uuid FK,
  kind text,           -- ddl | sample
  item_id text, rank int, score real, included boolean
);

```

Notes:

- The session JSON in section 3 is the **logical** view; these tables are how it is stored and queried. `turns`, `llm_calls`, `executions`, and `retrieval_log` together reconstruct it.
- Index `turns(session_id, turn_no)`, `llm_calls(turn_id)`, `executions(turn_id)`.
- Store masked/hashed phone identifiers; define a retention period for `llm_calls.input` / `rendered_prompt`, since they contain user data.

### 9.5 Existing stores to reuse (verify, do not recreate)

- DDL vector store (already used for selective DDL retrieval).
- Entity/keyword mapping table for per-user vocabulary (planned; check if it exists).

---

## 10. Implementation checklist (suggested order for Claude Code)

1. [ ] **Audit the database** (section 9.1): list existing session/vector/sample/DDL/entity tables and columns, check pgvector and the embedding dimension, then write migrations (ALTER vs CREATE)
2. [ ] Migrations for `query_samples` and the session/trace tables (section 9)
3. [ ] Session JSON schema + read/write helpers (including `pending_clarification`, `planner_attempts`, `llm_calls`); persist into the tables above
4. [ ] JSON schemas/validators for each call's output
5. [ ] pgvector retrieval for DDLs and samples, logging ids + scores into `retrieval_log`
6. [ ] Executor: read-only guard, statement timeout, row limit, tenant schema handling, error classification (retryable vs not)
7. [ ] **Sample seeding job** (section 8.1): generate, static-check, run, judge, dedupe, embed, save; plus rejected-list output
8. [ ] Router call
9. [ ] Call 1: rephrase/clarify, including multi-question JSON, partial answers, `new_topic` detection, 2-round cap
10. [ ] Call 2: planner with `plan` / `no_match`, confidence gate, retry loop (max 3) with `previous_attempts`
11. [ ] Call 3: respond/validate with the three outcomes
12. [ ] Runtime learning (section 8.2): save validated answers as candidate samples, promotion rules, usage counters
13. [ ] Schema-change hook (section 8.3): mark samples stale when DDLs change and re-validate
14. [ ] Orchestrator wiring: Router bypass when clarification pending, failure template path
15. [ ] Test cases: multi-question clarification, partial answer, user changes topic mid-clarification, SQL error then recovery, 3 failures, empty result, `no_match`, low-confidence bounce, seeding rejects cross-schema SQL, duplicate sample skipped
16. [ ] Frontend inspector (section 6): trace API, step timeline, structured Input/Output tabs per call, attempt diff, filters
17. [ ] End-to-end timing per call

