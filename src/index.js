import 'dotenv/config';
import express from 'express';
import { fileURLToPath } from 'url';
import path from 'path';
import { checkConnections } from './db/connections.js';
import { routeTurn } from './skills/router.js';
import { resolveIdentity } from './memory/identity.js';
import { createOrTouchSession, loadConversationHistory, listSessions } from './memory/session.js';
import { runTalkToDb } from './skills/talk-to-db/index.js';
import { logEpisode, logTrace, updateEpisodeAnswer, startTimer } from './tracing/logger.js';
import { harnessDb } from './db/connections.js';
import { startRepl } from './repl.js';
import { PROMPTS } from './prompts/talk-to-db/prompt-store.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

if (process.env.REPL === 'true') {
  startRepl();
  process.exit;
}

const app = express();
app.use(express.json());
// New Aura dashboard is the default root — serve dashboard.html at /
app.get('/', (_req, res) => res.sendFile(path.join(__dirname, '../public/dashboard.html')));
// Old dev console lives at /console
app.get('/console', (_req, res) => res.sendFile(path.join(__dirname, '../public/index.html')));
app.use(express.static(path.join(__dirname, '../public')));

// ─── Turn counter (in-memory; sessions table is authoritative for persistence) ───
const sessionTurnCount = new Map();

// ─── Health ───────────────────────────────────────────────────────────────────
app.get('/health', async (req, res) => {
  const dbs = await checkConnections();
  const allOk = Object.values(dbs).every(Boolean);
  res.status(allOk ? 200 : 503).json({ status: allOk ? 'ok' : 'degraded', dbs, timestamp: new Date().toISOString() });
});

// ─── Main turn endpoint ───────────────────────────────────────────────────────
app.post('/turn', async (req, res) => {
  const { message, sessionId, userId, email } = req.body;
  if (!message || !sessionId) {
    return res.status(400).json({ error: 'message and sessionId are required' });
  }

  const tTurn = startTimer();
  console.log(`\n[harness] Incoming turn | session=${sessionId} | message="${message}"`);

  // Session: create or touch
  await createOrTouchSession({ sessionId, userId, email });

  // Turn counter
  const turnNumber = (sessionTurnCount.get(sessionId) ?? 0) + 1;
  sessionTurnCount.set(sessionId, turnNumber);

  // Load conversation history before routing (used by talk_to_db)
  const history = await loadConversationHistory(sessionId);

  // Gate
  const tGate = startTimer();
  const route = await routeTurn(message, { sessionId, userId });
  const gateDuration = tGate();

  // Identity
  const identity = await resolveIdentity({ userId, email, sessionId });

  // Episodic log (answer filled in after skill runs)
  const turnId = await logEpisode({
    sessionId,
    userId: userId ?? null,
    turnNumber,
    rawMessage: message,
    routedSkill: route.skill,
    resolvedIntentOrSql: null,
    assistantAnswer: null,
  });

  await logTrace({
    sessionId, turnId, phase: 'gate',
    payload: {
      skill: route.skill, confidence: route.confidence, reason: route.reason,
      sessionId, turnNumber, userId: userId ?? null, email: email ?? null,
      message,
    },
    durationMs: gateDuration,
  });

  let response;

  if (route.skill === 'talk_to_db') {
    const result = await runTalkToDb(message, { sessionId, userId, email }, identity, turnId, history, turnNumber);
    await updateEpisodeAnswer(turnId, result.answer, result.sql);
    response = {
      skill: 'talk_to_db',
      answer: result.answer,
      finalStatus: result.finalStatus,
      clarificationRequested: result.clarificationRequested ?? false,
      clarificationQuestions: result.clarificationQuestions ?? null,
      suggestedNext: result.suggestedNext ?? null,
      alternatives: result.alternatives ?? [],
      meta: { rowCount: result.rowCount, sql: result.sql },
    };
  } else if (route.skill === 'chit_chat') {
    const answer = 'Hi! How can I help you?';
    await updateEpisodeAnswer(turnId, answer, null);
    response = { skill: 'chit_chat', answer };
  } else {
    const answer = "I'm not sure how to help with that.";
    await updateEpisodeAnswer(turnId, answer, null);
    response = { skill: 'none', answer };
  }

  await logTrace({
    sessionId, turnId, phase: 'turn_end',
    payload: { skill: route.skill, totalDurationMs: tTurn() },
    durationMs: tTurn(),
  });

  return res.json({ ...response, turnId, sessionId });
});

// ─── Observability API ────────────────────────────────────────────────────────

// List sessions
app.get('/api/sessions', async (req, res) => {
  const sessions = await listSessions({ limit: 100 });
  res.json(sessions);
});

// Turns for a session — episodic_log joined with talk2db.turns final_status
app.get('/api/sessions/:sessionId/turns', async (req, res) => {
  const { sessionId } = req.params;
  const { rows: turns } = await harnessDb.query(
    `SELECT e.id, e.turn_number, e.raw_message, e.routed_skill, e.resolved_intent_or_sql,
            e.assistant_answer, e.created_at,
            t2.turn_id AS talk2db_turn_id, t2.final_status, t2.rephrased_question
       FROM episodic_log e
       LEFT JOIN talk2db.turns t2
         ON t2.session_id = e.session_id AND t2.turn_no = e.turn_number
      WHERE e.session_id = $1
      ORDER BY e.turn_number ASC`,
    [sessionId]
  );
  res.json(turns);
});

// Full trace for a single turn — merges trace_log (routing/retrieval/execute phases)
// with talk2db.llm_calls (full structured input/output/prompt for every LLM call).
// Returns rows in the shape {phase, payload, prompt_sent, duration_ms, id} that the
// frontend step-builder already understands.
app.get('/api/turns/:turnId/trace', async (req, res) => {
  const { turnId } = req.params;
  const turnIdInt = parseInt(turnId, 10);

  // Always fetch trace_log rows (gate, vocab, retrieve, execute, turn_start, turn_end)
  const { rows: traceRows } = await harnessDb.query(
    `SELECT id, phase, payload, prompt_sent, duration_ms, created_at
       FROM trace_log
      WHERE turn_id = $1
      ORDER BY id ASC`,
    [turnIdInt]
  );

  // Check if this is a talk_to_db turn (talk2db.turns linked via session_id+turn_no)
  const { rows: t2Rows } = await harnessDb.query(
    `SELECT t2.turn_id
       FROM talk2db.turns t2
       JOIN episodic_log e ON e.session_id = t2.session_id AND e.turn_number = t2.turn_no
      WHERE e.id = $1
      LIMIT 1`,
    [turnIdInt]
  );

  if (!t2Rows.length) {
    // Not a talk2db turn — return plain trace_log rows
    return res.json(traceRows);
  }

  const talk2dbTurnId = t2Rows[0].turn_id;

  // Fetch talk2db LLM calls with full structured data
  const { rows: llmRows } = await harnessDb.query(
    `SELECT id, call_name, attempt, model, input, rendered_prompt,
            output_raw, output_parsed, status, tokens_in, tokens_out, latency_ms, created_at
       FROM talk2db.llm_calls
      WHERE turn_id = $1
      ORDER BY created_at ASC`,
    [talk2dbTurnId]
  );

  // Map call_name → phase name used by the frontend ARCH step definitions
  const callNameToPhase = { rephrase: 'rephrase', planner: 'generate_sql', respond: 'generate_response' };

  // Build merged trace: start with trace_log rows, then inject/replace LLM phases
  // with richer data from talk2db.llm_calls.
  // The trace_log rows for rephrase/generate_sql/generate_response only have payload (no full prompt).
  // talk2db.llm_calls has input + rendered_prompt + output_parsed.

  const llmPhasesSeen = new Set(llmRows.map(r => callNameToPhase[r.call_name]).filter(Boolean));

  // Keep trace_log rows whose phase is NOT covered by a talk2db LLM call
  const baseRows = traceRows.filter(r => !llmPhasesSeen.has(r.phase));

  // Build synthetic trace rows from talk2db.llm_calls
  const llmTraceRows = llmRows.map(r => {
    const phase = callNameToPhase[r.call_name] ?? r.call_name;
    return {
      id: `llm-${r.id}`,
      phase,
      payload: {
        ...(r.output_parsed ?? {}),
        // inject attempt number so the frontend retry diff works
        attempt: r.attempt,
        // carry through relevant fields from output_parsed
      },
      // structured input stored as a separate key for frontend IO tabs
      llm_input: r.input,
      prompt_sent: r.rendered_prompt,
      output_raw: r.output_raw,
      output_parsed: r.output_parsed,
      model: r.model,
      tokens_in: r.tokens_in,
      tokens_out: r.tokens_out,
      duration_ms: r.latency_ms,
      created_at: r.created_at,
      call_name: r.call_name,
      attempt: r.attempt,
      status: r.status,
    };
  });

  // Merge: sort all rows chronologically
  const merged = [...baseRows, ...llmTraceRows].sort(
    (a, b) => new Date(a.created_at) - new Date(b.created_at)
  );

  res.json(merged);
});

// Session detail (metadata)
app.get('/api/sessions/:sessionId', async (req, res) => {
  const { sessionId } = req.params;
  const { rows } = await harnessDb.query(
    `SELECT * FROM sessions WHERE session_id = $1`,
    [sessionId]
  );
  if (!rows.length) return res.status(404).json({ error: 'session not found' });
  res.json(rows[0]);
});

// Session full JSON — assembles complete session snapshot from all talk2db tables
app.get('/api/sessions/:sessionId/json', async (req, res) => {
  const { sessionId } = req.params;
  try {
    // Session header
    const { rows: sessRows } = await harnessDb.query(
      `SELECT s.session_id, s.crm_id, s.employee_id, s.pending_clarification, s.updated_at,
              es.user_id, es.email, es.created_at AS session_started
         FROM talk2db.sessions s
         LEFT JOIN sessions es ON es.session_id = s.session_id
        WHERE s.session_id = $1`,
      [sessionId]
    );
    if (!sessRows.length) return res.status(404).json({ error: 'session not found' });
    const sess = sessRows[0];

    // All turns
    const { rows: turns } = await harnessDb.query(
      `SELECT t2.turn_id, t2.turn_no, t2.user_message, t2.rephrased_question,
              t2.final_status, t2.respond, t2.created_at,
              e.routed_skill, e.assistant_answer
         FROM talk2db.turns t2
         LEFT JOIN episodic_log e ON e.session_id = t2.session_id AND e.turn_number = t2.turn_no
        WHERE t2.session_id = $1
        ORDER BY t2.turn_no ASC`,
      [sessionId]
    );

    // All LLM calls for this session
    const { rows: llmCalls } = await harnessDb.query(
      `SELECT lc.id, lc.turn_id, lc.call_name, lc.attempt, lc.model,
              lc.input, lc.rendered_prompt, lc.output_raw, lc.output_parsed,
              lc.status, lc.tokens_in, lc.tokens_out, lc.latency_ms, lc.created_at
         FROM talk2db.llm_calls lc
         JOIN talk2db.turns t2 ON t2.turn_id = lc.turn_id
        WHERE t2.session_id = $1
        ORDER BY lc.created_at ASC`,
      [sessionId]
    );

    // All executions
    const { rows: executions } = await harnessDb.query(
      `SELECT ex.id, ex.turn_id, ex.attempt, ex.sql, ex.status, ex.error,
              ex.error_type, ex.row_count, ex.duration_ms, ex.result_summary, ex.created_at
         FROM talk2db.executions ex
         JOIN talk2db.turns t2 ON t2.turn_id = ex.turn_id
        WHERE t2.session_id = $1
        ORDER BY ex.created_at ASC`,
      [sessionId]
    );

    // All retrieval logs
    const { rows: retrieval } = await harnessDb.query(
      `SELECT rl.turn_id, rl.kind, rl.item_id, rl.rank, rl.score, rl.included
         FROM talk2db.retrieval_log rl
         JOIN talk2db.turns t2 ON t2.turn_id = rl.turn_id
        WHERE t2.session_id = $1
        ORDER BY rl.turn_id ASC, rl.rank ASC`,
      [sessionId]
    );

    // Index by turn_id
    const llmByTurn = {};
    llmCalls.forEach(r => { (llmByTurn[r.turn_id] = llmByTurn[r.turn_id] ?? []).push(r); });
    const execByTurn = {};
    executions.forEach(r => { (execByTurn[r.turn_id] = execByTurn[r.turn_id] ?? []).push(r); });
    const retByTurn = {};
    retrieval.forEach(r => { (retByTurn[r.turn_id] = retByTurn[r.turn_id] ?? []).push(r); });

    const sessionJson = {
      session_id: sess.session_id,
      user: {
        user_id: sess.user_id ?? null,
        email: sess.email ?? null,
        crm_id: sess.crm_id ?? null,
        employee_id: sess.employee_id ?? null,
      },
      session_started: sess.session_started,
      last_updated: sess.updated_at,
      pending_clarification: sess.pending_clarification ?? null,
      turns: turns.map(t => ({
        turn_id: t.turn_id,
        turn_no: t.turn_no,
        user_message: t.user_message,
        routed_skill: t.routed_skill ?? null,
        rephrased_question: t.rephrased_question ?? null,
        final_status: t.final_status ?? null,
        assistant_answer: t.assistant_answer ?? null,
        respond: t.respond ?? null,
        created_at: t.created_at,
        retrieval: (retByTurn[t.turn_id] ?? []).map(r => ({
          kind: r.kind, item_id: r.item_id, rank: r.rank, score: r.score, included: r.included,
        })),
        llm_calls: (llmByTurn[t.turn_id] ?? []).map(r => ({
          id: r.id,
          call_name: r.call_name,
          attempt: r.attempt,
          model: r.model,
          tokens_in: r.tokens_in,
          tokens_out: r.tokens_out,
          latency_ms: r.latency_ms,
          status: r.status,
          input: r.input,
          output_parsed: r.output_parsed,
          rendered_prompt: r.rendered_prompt,
        })),
        executions: (execByTurn[t.turn_id] ?? []).map(r => ({
          id: r.id,
          attempt: r.attempt,
          sql: r.sql,
          status: r.status,
          error: r.error ?? null,
          error_type: r.error_type ?? null,
          row_count: r.row_count,
          duration_ms: r.duration_ms,
          result_summary: r.result_summary,
        })),
      })),
    };

    res.json(sessionJson);
  } catch (e) {
    console.error('[api/sessions/json]', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ─── Talk2DB structured trace API ────────────────────────────────────────────

// GET /api/talk2db/sessions/:sessionId/turns — turns with final_status
app.get('/api/talk2db/sessions/:sessionId/turns', async (req, res) => {
  const { sessionId } = req.params;
  try {
    const { rows } = await harnessDb.query(
      `SELECT turn_id, turn_no, user_message, rephrased_question, final_status, respond, created_at
         FROM talk2db.turns
        WHERE session_id = $1
        ORDER BY turn_no ASC`,
      [sessionId]
    );
    res.json(rows);
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// GET /api/talk2db/turns/:turnId/trace — all LLM calls + executions for a turn
app.get('/api/talk2db/turns/:turnId/trace', async (req, res) => {
  const { turnId } = req.params;
  try {
    const [llm, exec, retrieval] = await Promise.all([
      harnessDb.query(
        `SELECT id, call_name, attempt, model, input, rendered_prompt, output_raw, output_parsed, status, tokens_in, tokens_out, latency_ms, created_at
           FROM talk2db.llm_calls WHERE turn_id = $1 ORDER BY created_at ASC`,
        [turnId]
      ),
      harnessDb.query(
        `SELECT id, attempt, sql, status, error, error_type, row_count, duration_ms, result_summary, created_at
           FROM talk2db.executions WHERE turn_id = $1 ORDER BY attempt ASC`,
        [turnId]
      ),
      harnessDb.query(
        `SELECT kind, item_id, rank, score, included FROM talk2db.retrieval_log WHERE turn_id = $1 ORDER BY rank ASC`,
        [turnId]
      ),
    ]);
    res.json({ llm_calls: llm.rows, executions: exec.rows, retrieval: retrieval.rows });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

// ─── Prompts API ─────────────────────────────────────────────────────────────

// GET /api/prompts — return current active prompts
app.get('/api/prompts', (req, res) => {
  res.json({ sql: PROMPTS.sql, respond: PROMPTS.respond });
});

// PATCH /api/prompts — update one or both prompts in-memory
app.patch('/api/prompts', (req, res) => {
  const { sql, respond } = req.body;
  if (sql != null) {
    if (typeof sql !== 'string' || sql.trim().length < 10) return res.status(400).json({ error: 'sql prompt too short' });
    PROMPTS.sql = sql;
  }
  if (respond != null) {
    if (typeof respond !== 'string' || respond.trim().length < 10) return res.status(400).json({ error: 'respond prompt too short' });
    PROMPTS.respond = respond;
  }
  console.log(`[prompts] Updated: ${sql ? 'sql' : ''}${sql && respond ? '+' : ''}${respond ? 'respond' : ''}`);
  res.json({ ok: true, sql: PROMPTS.sql, respond: PROMPTS.respond });
});

// ─── Dashboard stats API ─────────────────────────────────────────────────────
app.get('/api/dashboard/stats', async (_req, res) => {
  try {
    const [sessRow, turnRow, tokenRow, latRow, skillRow, recentRow, dailyRow] = await Promise.all([
      // Total sessions & sessions today
      harnessDb.query(`
        SELECT COUNT(*) AS total,
               COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE) AS today
          FROM sessions`),
      // Total turns & turns today
      harnessDb.query(`
        SELECT COUNT(*) AS total,
               COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE) AS today
          FROM episodic_log`),
      // Token usage from talk2db llm_calls (all time)
      harnessDb.query(`
        SELECT COALESCE(SUM(tokens_in + tokens_out), 0) AS total_tokens,
               COALESCE(AVG(tokens_in + tokens_out), 0) AS avg_tokens
          FROM talk2db.llm_calls`),
      // Avg latency (today vs yesterday) from talk2db.turns
      harnessDb.query(`
        SELECT ROUND(AVG(EXTRACT(EPOCH FROM (updated_at - created_at)) * 1000)) AS avg_ms
          FROM talk2db.turns
         WHERE created_at >= CURRENT_DATE`),
      // Skill distribution
      harnessDb.query(`
        SELECT routed_skill AS skill, COUNT(*) AS count
          FROM episodic_log
         GROUP BY routed_skill
         ORDER BY count DESC`),
      // Recent sessions (last 8)
      harnessDb.query(`
        SELECT s.session_id,
               s.email,
               s.user_id,
               s.created_at,
               COUNT(e.id) AS turn_count,
               MAX(e.raw_message) AS last_message
          FROM sessions s
          LEFT JOIN episodic_log e ON e.session_id = s.session_id
         GROUP BY s.session_id, s.email, s.user_id, s.created_at
         ORDER BY s.created_at DESC
         LIMIT 8`),
      // Daily session counts for last 12 days
      harnessDb.query(`
        SELECT DATE(created_at) AS day, COUNT(*) AS count
          FROM sessions
         WHERE created_at >= CURRENT_DATE - INTERVAL '11 days'
         GROUP BY day
         ORDER BY day ASC`),
    ]);

    res.json({
      sessions:     { total: +sessRow.rows[0].total, today: +sessRow.rows[0].today },
      turns:        { total: +turnRow.rows[0].total, today: +turnRow.rows[0].today },
      tokens:       { total: +tokenRow.rows[0].total_tokens, avg: Math.round(+tokenRow.rows[0].avg_tokens) },
      latency:      { avg_ms: +latRow.rows[0]?.avg_ms || 0 },
      skills:       skillRow.rows,
      recentSessions: recentRow.rows,
      dailyCounts:  dailyRow.rows,
    });
  } catch (e) {
    console.error('[dashboard/stats]', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ─── Start ────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT ?? 3000;
app.listen(PORT, () => {
  console.log(`[harness] Listening on port ${PORT}`);
  console.log(`[harness] Observability UI → http://localhost:${PORT}`);
});
