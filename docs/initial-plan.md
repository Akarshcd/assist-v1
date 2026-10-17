# AI Assistant Harness — Project Plan

## What we're building
A single harness (one unified backend service, not microservices/MCP for now) that exposes
pluggable "skills" to end users. The harness core is generic and reusable; each skill is a
module with a clean interface into the harness's shared memory and tool-routing loop.

This unifies what were previously two separate ideas: a WhatsApp-facing CRM/HRM assistant and
a standalone assistant for the co-founder. Both are now front ends on top of the same shared core.

## Core architectural decisions

- **Single service, not microservices.** All skills live in one backend process for now.
  No MCP servers, no separate deployables per skill. Revisit only if a real scaling/reuse
  need appears later.
- **Harness orchestrator stays thin.** Its only jobs: route to the right skill, hold shared
  memory pillars (identity resolution, etc.), run the conversation loop, and log traces.
  All skill-specific logic lives inside the skill module, not the orchestrator.
- **Skills are either lightweight or heavyweight.**
  - Lightweight: a markdown/config file + a thin function. Little state, little infra.
  - Heavyweight: a full subsystem with its own DB connections, own memory access, own
    retrieval logic — exposed to the harness through a defined tool interface (inputs/outputs).
  - Talk-to-DB is the anchor heavyweight skill (build first).
- **Model-agnostic by design.** The LLM is a commodity — SQL generation, extraction, and
  summarization all work with any capable model. Don't hardcode model-specific logic into
  skill modules; keep the model call behind a thin adapter so it can be swapped.
- **Read-only against real company data, always.** The harness only ever reads from the
  actual CRM/HRM Postgres DB. All harness-owned memory (DDL cache, vocabulary table,
  episodic/session logs) lives in a separate, harness-owned Postgres instance. Never write
  to or host company data on the separate instance.
- **Plug-and-play connection model.** A new user/business should be able to self-serve
  connect their own DB (credentials) or their own Outlook/Teams account without bespoke
  per-user engineering. Design skill "connectors" with this in mind from the start, even
  in the prototype (e.g. don't hardcode ConceptDash's schema name inside skill logic).

## Memory architecture (three pillars + episodic→semantic pipeline)

1. **DDL memory** — vector store of schema chunks (one per table, or per table + its FKs),
   kept in sync as the schema evolves. Retrieval must return *only* the tables relevant to
   the current question, never the full schema, and must never let generated SQL cross
   schema boundaries (known failure mode from earlier work: cross-schema references like
   `hrm_db` querying `schema_3.users`).
2. **Vocabulary/semantic memory** — a flat Postgres table: `canonical_term`, `alias`,
   `user_id` (nullable = global), `confidence`. Deliberately not a graph/temporal system
   (evaluated Graphiti/Zep, rejected — priority is cost + accuracy, not tracking vocabulary
   drift over time). Hand-seed the first 10–20 obvious mappings before relying on
   auto-consolidation.
3. **Identity resolution** — a deterministic (non-vector) lookup: given a session/user,
   resolve CRM ID + employee ID. Runs before retrieval on every turn; result is always
   attached to context, since every fetch is tied to some person.
4. **Episodic → semantic consolidation** — every turn logged raw to a relational log table.
   A consolidation pass (trigger: session end, or every ~20 turns) scans recent episodes,
   looks for a phrase resolving to the same table/column repeatedly, and only then promotes
   it into the semantic vocabulary table. This is a v2 concern — don't block skill v1 on it.

## Skill roadmap (build talk-to-DB first, others later)

1. **Talk-to-database** (heavyweight, anchor skill — build first)
2. Email send/read across providers — Gmail/Outlook/Zoho (heavyweight, per-provider OAuth adapters)
3. Calendar/scheduling (light-medium, can share the email OAuth layer)
4. Reminders/task nudges (lightweight)
5. S3 document/file retrieval (medium)
6. HRM leave/time-off requests (medium — talk-to-DB + write-action/approval layer)
7. Payroll query (lightweight if read-only, reuses talk-to-DB with tighter access control)
8. WhatsApp/notification delivery formatting (lightweight, presentation adapter)
9. Meeting notes/call summarization (medium — ingestion + LLM summarization)
10. Onboarding/offboarding checklist tracking (medium — workflow state machine)
11. Idea/project assistant — conversational skill, backed by an LLM, that can write up a
    project, converse about it, and do web research on the user's behalf

## Free-tier build stack (prototype phase)

- **LLM**: Google AI Studio / Gemini Flash as primary (no-card, high daily quota, large
  context window — good fit for DDL-heavy prompts). Groq or Cerebras as failover if quota
  is hit (Groq is OpenAI-compatible, easy adapter swap).
- **Harness memory DB**: Supabase or Neon — free-tier Postgres with pgvector. This is
  *separate* from ConceptDash's real database.
- **Real data**: ConceptDash's existing AWS Postgres CRM/HRM DB — read-only connection,
  used to build/test against, not as the product itself long-term.

## Dashboards (build after talk-to-DB skill v1 works end to end)

1. **End-user settings dashboard** — connect accounts (Outlook/Teams login), upload a DDL,
   manage own settings.
2. **Developer/observability dashboard** (waku-style) — per-user cost, monthly spend,
   prompts/interactions, tracing view for evaluation.
3. **Client dashboard** — business logs in, connects Teams/Outlook, uploads DDLs/data sources.

## Go-to-market (context, not build-blocking)

Lead with connecting to a prospect's *existing* CRM (via schema access or auth tokens)
rather than requiring migration onto an in-house CRM/HRM platform first. Migration is a
later upsell once a business already depends on the assistant.

## Sequencing note
Don't parallelize the three dashboards with skill-building. Get talk-to-DB working
end-to-end (including error-retry on bad SQL) before touching dashboard UI. Tracing hooks
should be built *into* the skill from day one (cheap to add), but the dashboard that
visualizes traces can lag behind.