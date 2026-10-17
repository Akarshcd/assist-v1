# Skill: Talk-to-Database — Implementation Plan

Prerequisite: `01_SETUP.md` fully checked off (harness DB provisioned, read-only source DB confirmed, LLM key wired through a thin client, harness tables created, DDL extraction script working).

## Step 0 — Routing gate (harness-level, runs before this skill is even invoked)

Every incoming turn passes through `routeTurn()` (built in setup step 7) first. This is **not part of the talk-to-db skill itself** — it's the harness's entry point, and talk-to-db is just one of the things it can route to. Do not call the DDL retrieval, vocabulary lookup, or SQL-generation LLM call unless the gate has already decided this turn needs the DB skill.

- If `routeTurn()` returns `chit_chat` or `none`: respond conversationally (or do nothing DB- related) and skip straight to episodic logging (step 9). No DDL retrieval, no SQL LLM call — this is the whole point of the gate, it saves cost and latency on non-DB turns.
- If it returns `talk_to_db`: proceed to Step 1 onward below.
- Log the gate's decision itself to `trace_log` (phase: `gate`) regardless of outcome, and write an `episodic_log` row for every turn regardless of routing (see setup doc — the episodic log is skill-agnostic, not scoped to this skill).
- Building this gate generically now (returns a skill name, not a DB-specific boolean) means skill #2 (email, reminders, etc.) plugs into the same gate later without rework.

## Flow (as designed, once the gate has routed to this skill)

```
Question + scoped DDL + semantic memory  --> LLM --> SQL, or "no matching data"
        SQL --> execute against source DB (read-only)
        [on execution error] --> feed error + SQL back to LLM --> retry (max N attempts)
        data + original question --> LLM --> natural-language answer for user
                                              (+ visualization suggestion, or a clarifying
                                               question, e.g. "want me to pull his phone
                                               number too?")

```

Two LLM calls per turn minimum: one to generate SQL, one to turn results into a natural answer. Build these as two distinct, separately-testable functions, not one prompt.

## Step 1 — DDL chunking strategy

Chunk **per table**, not per schema and not per column. Each chunk should contain:

- Schema name + table name
- Column list with types
- Primary key
- Foreign keys (both directions if feasible: what this table references, and — as a separate lightweight index, not embedded — what references this table)
- A short one-line human description if you have one (helps retrieval match natural language phrasing to the right table)

Do NOT chunk per-column — too granular, retrieval will return fragments that don't tell the LLM enough to write correct SQL. Do NOT embed the whole schema as one chunk — defeats the point of selective retrieval and reintroduces the "full DDL injection" problem you already moved away from.

For tables with foreign keys to other schemas, tag the chunk explicitly with a `cross_schema_refs` field listing the target schema(s). This is your guard rail against the known cross-schema SQL failure mode — the retrieval step and the SQL-generation prompt should both be able to check this before trusting a join across schemas.

## Step 2 — Embedding and storage

- Embed each chunk (table description + columns + FK info) and store in `ddl_chunks` on the harness DB, with metadata columns: `schema_name`, `table_name`, `cross_schema_refs`.
- Re-run the embedding step whenever the DDL extraction script (from setup) detects a schema change — don't re-embed everything every time; diff against what's stored and only re-embed changed/new tables.

## Step 3 — Retrieval

- Given the user's question, embed it and do a similarity search against `ddl_chunks`.
- Return only the top-K matching table chunks (start with K=5, tune from there) — this is the "get only DDL tables those are needed" requirement.
- Before passing retrieved chunks to the LLM, run a quick schema-consistency check: if multiple retrieved tables span schemas that shouldn't be joined, flag this in the prompt context explicitly (e.g. "these tables are in different schemas — do not write a cross- schema join") rather than relying on the LLM to infer it.

## Step 4 — Semantic/vocabulary lookup

- Before or alongside DDL retrieval, check the user's question against `vocabulary_map` (user-specific rows first, then global rows) to resolve ambiguous terms ("task sheet" → canonical term → which table it maps to).
- Pass resolved canonical terms into the DDL retrieval query (step 3) to improve match quality — resolving vocabulary first, then retrieving DDL, generally works better than the reverse.

## Step 5 — Identity resolution

- Every call to this skill runs the identity resolution lookup (built in setup step 6) first, unconditionally. Attach CRM ID + employee ID to the context passed to the LLM, since every fetch is tied to some person.

## Step 6 — SQL generation (LLM call #1)

- Prompt inputs: question, resolved vocabulary terms, retrieved DDL chunks (with cross- schema warnings if any), identity context.
- Output: either a SQL statement, or an explicit "no matching data" signal — don't let the LLM silently hallucinate a query against tables that weren't retrieved.
- Constrain the LLM to SELECT-only (belt-and-braces on top of the read-only DB role from setup).

## Step 7 — Execution + error-retry loop

- Execute the generated SQL against `SOURCE_DB_URL`.
- On failure (syntax error, permission error, cross-schema mistake): feed the exact error message + the failed SQL back to the LLM, ask it to correct and retry. Cap retries (e.g. 2 attempts) before giving up and telling the user the query couldn't be completed.
- Log every attempt (success or failure) to `trace_log`.

## Step 8 — Response generation (LLM call #2)

- Prompt inputs: original question, returned data (or empty result), identity context.
- Output: natural-language answer. If the data suggests a natural visualization (e.g. a time series or category breakdown), say so as a follow-up suggestion rather than trying to render it inline. If the answer is ambiguous or partial, ask a clarifying question (e.g. "want me to also pull their phone number?") instead of guessing.

## Step 9 — Episodic logging

- After every turn, write one row to `episodic_log`: raw question, resolved SQL (or failure), turn number, session id. This is the raw material for later semantic consolidation (v2 — do not build the consolidation job yet, just make sure logging is happening from day one so there's data to consolidate later).

## Step 10 — Tracing

- Emit trace events to `trace_log` at each phase: `turn_start`, `gate` (the routing decision from Step 0), `llm` (both calls, with token counts/cost if available from the provider response), `tool` (DB execution), `turn_end`. Include duration_ms per phase.
- This is what the developer/observability dashboard will read from later — get the log data right now, build the UI later.

## Definition of done for v1

- A chit-chat message is correctly routed away from the DB skill entirely (gate works).
- A DB-relevant question is routed to this skill, resolves through vocabulary + DDL retrieval, generates correct SQL for at least the core CRM/HRM tables, executes read-only, recovers from at least one class of SQL error via retry, and returns a natural-language answer.
- Every turn (chit-chat or DB) has a row in `episodic_log`, and every phase of a DB turn is traced to `trace_log`.

