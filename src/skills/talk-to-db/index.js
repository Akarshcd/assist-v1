import { resolveVocabulary } from './vocab.js';
import { retrieveDDL } from './retrieve.js';
import { rephraseOrClarify } from './call1-rephrase.js';
import { planQuery } from './call2-planner.js';
import { executePlan } from './execute.js';
import { generateResponse } from './call3-respond.js';
import { logTrace, startTimer } from '../../tracing/logger.js';
import { harnessDb } from '../../db/connections.js';

const MAX_PLANNER_ATTEMPTS = 3;
const CONFIDENCE_THRESHOLD = parseFloat(process.env.PLANNER_CONFIDENCE_THRESHOLD ?? '0.6');

// ─── talk2db DB helpers ────────────────────────────────────────────────────────

async function upsertTalk2dbSession(sessionId, identity) {
  await harnessDb.query(
    `INSERT INTO talk2db.sessions (session_id, crm_id, employee_id, updated_at)
     VALUES ($1, $2, $3, now())
     ON CONFLICT (session_id) DO UPDATE
       SET crm_id      = COALESCE(EXCLUDED.crm_id, talk2db.sessions.crm_id),
           employee_id = COALESCE(EXCLUDED.employee_id, talk2db.sessions.employee_id),
           updated_at  = now()`,
    [sessionId, identity?.crmUserId ?? null, identity?.employeeId ?? null]
  );
}

async function writePendingClarification(sessionId, pendingClarification) {
  await harnessDb.query(
    `UPDATE talk2db.sessions SET pending_clarification = $2, updated_at = now() WHERE session_id = $1`,
    [sessionId, pendingClarification ? JSON.stringify(pendingClarification) : null]
  );
}

async function readPendingClarification(sessionId) {
  const { rows } = await harnessDb.query(
    `SELECT pending_clarification FROM talk2db.sessions WHERE session_id = $1`,
    [sessionId]
  );
  return rows[0]?.pending_clarification ?? null;
}

async function insertTurn(sessionId, turnNo, userMessage) {
  const { rows } = await harnessDb.query(
    `INSERT INTO talk2db.turns (session_id, turn_no, user_message)
     VALUES ($1, $2, $3) RETURNING turn_id`,
    [sessionId, turnNo, userMessage]
  );
  return rows[0].turn_id;
}

async function updateTurn(turnId, rephrasedQuestion, finalStatus, respondJson) {
  await harnessDb.query(
    `UPDATE talk2db.turns
       SET rephrased_question = $2, final_status = $3, respond = $4
     WHERE turn_id = $1`,
    [turnId, rephrasedQuestion, finalStatus, respondJson ? JSON.stringify(respondJson) : null]
  );
}

async function insertLlmCall(turnId, callName, attempt, input, promptSent, outputRaw, outputParsed, status, latencyMs, model = null, tokensIn = null, tokensOut = null) {
  await harnessDb.query(
    `INSERT INTO talk2db.llm_calls
       (turn_id, call_name, attempt, model, input, rendered_prompt, output_raw, output_parsed, status, latency_ms, tokens_in, tokens_out)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
    [
      turnId, callName, attempt,
      model,
      JSON.stringify(input ?? {}),
      promptSent ? JSON.stringify(promptSent) : null,
      typeof outputRaw === 'string' ? outputRaw : JSON.stringify(outputRaw ?? ''),
      JSON.stringify(outputParsed ?? {}),
      status,
      latencyMs,
      tokensIn,
      tokensOut,
    ]
  );
}

async function insertExecution(turnId, attempt, execResult) {
  await harnessDb.query(
    `INSERT INTO talk2db.executions
       (turn_id, attempt, sql, status, error, error_type, row_count, duration_ms, result_summary)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      turnId, attempt,
      execResult.sql,
      execResult.error ? 'error' : 'ok',
      execResult.error ?? null,
      execResult.errorType ?? null,
      execResult.rowCount,
      execResult.durationMs,
      execResult.resultSummary ?? '',
    ]
  );
}

async function insertRetrievalLog(turnId, ddlChunks) {
  for (let i = 0; i < ddlChunks.length; i++) {
    const c = ddlChunks[i];
    await harnessDb.query(
      `INSERT INTO talk2db.retrieval_log (turn_id, kind, item_id, rank, score, included)
       VALUES ($1,'ddl',$2,$3,$4,true)`,
      [turnId, `${c.db_label}/${c.schema_name}.${c.table_name}`, i + 1, c.similarity ?? null]
    );
  }
}

// ─── Main orchestrator ─────────────────────────────────────────────────────────

/**
 * @param {string} message
 * @param {{ sessionId, userId?, email? }} context
 * @param {{ crmUserId, employeeId, email }} identity
 * @param {number} harnessTurnId — episodic_log id from the main server
 * @param {Array} history — [{role, content, sql?}]
 * @param {number} turnNumber
 * @returns {Promise<{
 *   answer: string,
 *   sql: string|null,
 *   rowCount: number|null,
 *   finalStatus: string,
 *   clarificationRequested: boolean,
 *   clarificationQuestions: Array|null,
 * }>}
 */
export async function runTalkToDb(message, context, identity, harnessTurnId, history = [], turnNumber = 1) {
  const { sessionId } = context;

  console.log(`\n${'='.repeat(60)}`);
  console.log(`[talk-to-db] NEW TURN | session: ${sessionId}`);
  console.log(`[talk-to-db] Message: "${message}"`);

  // Ensure talk2db session row exists
  await upsertTalk2dbSession(sessionId, identity);

  // Insert talk2db turn row
  const talk2dbTurnId = await insertTurn(sessionId, turnNumber, message);

  await logTrace({ sessionId, turnId: harnessTurnId, phase: 'turn_start', payload: { message, talk2dbTurnId } });

  // ─── Vocab lookup (unchanged — keep vocab layer) ─────────────────────────────
  console.log(`\n[step: vocab]`);
  const tVocab = startTimer();
  const vocabMatches = await resolveVocabulary(message, context.userId);
  const vocabDuration = tVocab();
  if (vocabMatches.length) {
    console.log(`  ✓ ${vocabMatches.length} vocab match(es): ${vocabMatches.map(v => `"${v.alias}" → ${v.canonical_term}`).join(', ')}`);
  }
  await logTrace({ sessionId, turnId: harnessTurnId, phase: 'vocab', payload: { matches: vocabMatches }, durationMs: vocabDuration });

  // ─── Read pending clarification state ────────────────────────────────────────
  const pendingClarification = await readPendingClarification(sessionId);
  const skipRouter = !!pendingClarification;
  console.log(`\n[step: clarification-state] pending=${skipRouter}`);

  // ─── Call 1: Rephrase / Clarify ───────────────────────────────────────────────
  console.log(`\n[step: call1-rephrase]`);
  const tCall1 = startTimer();
  const call1 = await rephraseOrClarify(message, history, pendingClarification);
  const call1Duration = tCall1();

  await insertLlmCall(
    talk2dbTurnId, 'rephrase', 1,
    { message, pendingClarification, historyLen: history.length, history: history.slice(-6),
      sessionId, turnNo: turnNumber, identity: identity ?? null },
    call1.promptSent,
    JSON.stringify(call1),
    { message_type: call1.message_type, rephrased_question: call1.rephrased_question, needs_clarification: call1.needs_clarification, clarification: call1.clarification, assumptions: call1.assumptions },
    'ok',
    call1Duration,
    call1.model,
    call1.tokensIn,
    call1.tokensOut
  );

  await logTrace({
    sessionId, turnId: harnessTurnId, phase: 'rephrase',
    payload: {
      message_type: call1.message_type,
      rephrased_question: call1.rephrased_question,
      needs_clarification: call1.needs_clarification,
      clarification: call1.clarification,
      assumptions: call1.assumptions,
      skipped_router: skipRouter,
    },
    promptSent: call1.promptSent,
    durationMs: call1Duration,
  });

  // Handle new_topic: clear pending, restart fresh (but don't recurse — just proceed without pending)
  if (call1.message_type === 'new_topic' && pendingClarification) {
    console.log(`  → new_topic: clearing pending clarification`);
    await writePendingClarification(sessionId, null);
    // Re-run call1 without pending context
    const call1Fresh = await rephraseOrClarify(message, history, null);
    Object.assign(call1, call1Fresh);
  }

  // Handle clarification needed
  if (call1.needs_clarification && call1.clarification) {
    const newPending = {
      original_prompt: pendingClarification?.original_prompt ?? message,
      round: (pendingClarification?.round ?? 0) + 1,
      questions: call1.clarification.questions,
    };
    await writePendingClarification(sessionId, newPending);

    const clarText = formatClarificationQuestions(call1.clarification.questions);
    await updateTurn(talk2dbTurnId, null, 'clarification_requested', null);

    console.log(`  → clarification requested (round ${newPending.round})`);
    console.log(`${'='.repeat(60)}\n`);

    return {
      answer: clarText,
      sql: null,
      rowCount: null,
      finalStatus: 'clarification_requested',
      clarificationRequested: true,
      clarificationQuestions: call1.clarification.questions,
    };
  }

  // Clarification resolved — clear pending state
  if (pendingClarification) {
    await writePendingClarification(sessionId, null);
  }

  const rephrasedQuestion = call1.rephrased_question ?? message;
  console.log(`  ✓ rephrased: "${rephrasedQuestion}"`);

  // ─── Retrieval (DDL chunks) ───────────────────────────────────────────────────
  console.log(`\n[step: retrieval]`);
  const tRetrieve = startTimer();
  const ddlChunks = await retrieveDDL(rephrasedQuestion, vocabMatches);
  const retrieveDuration = tRetrieve();
  console.log(`  ✓ ${ddlChunks.length} DDL chunks retrieved`);

  await insertRetrievalLog(talk2dbTurnId, ddlChunks);
  await logTrace({
    sessionId, turnId: harnessTurnId, phase: 'retrieve',
    payload: {
      dbLabel: ddlChunks[0]?.db_label ?? null,
      tables: ddlChunks.map(c => ({ label: c.db_label, schema: c.schema_name, table: c.table_name, similarity: c.similarity })),
    },
    durationMs: retrieveDuration,
  });

  // ─── Call 2 + Executor retry loop ────────────────────────────────────────────
  const plannerAttempts = [];
  let execResults = [];
  let finalPlanResult = null;
  let bounced = false; // confidence bounce back to call1 — max once per turn

  for (let attempt = 1; attempt <= MAX_PLANNER_ATTEMPTS; attempt++) {
    console.log(`\n[step: call2-planner attempt ${attempt}/${MAX_PLANNER_ATTEMPTS}]`);
    const tPlan = startTimer();
    const planResult = await planQuery(
      rephrasedQuestion, call1, ddlChunks, identity, history,
      plannerAttempts // previous attempts for retry context
    );
    const planDuration = tPlan();

    await insertLlmCall(
      talk2dbTurnId, 'planner', attempt,
      { rephrasedQuestion, ddlCount: ddlChunks.length, previousAttempts: plannerAttempts.length,
        history: history.slice(-6), sessionId, turnNo: turnNumber, identity: identity ?? null },
      planResult.promptSent,
      JSON.stringify(planResult),
      { status: planResult.status, confidence: planResult.confidence, queries: planResult.queries, reason: planResult.reason, available: planResult.available, notes: planResult.notes },
      'ok',
      planDuration,
      planResult.model,
      planResult.tokensIn,
      planResult.tokensOut
    );

    await logTrace({
      sessionId, turnId: harnessTurnId, phase: 'generate_sql',
      payload: {
        attempt,
        status: planResult.status,
        confidence: planResult.confidence,
        steps: planResult.queries?.map(q => ({ step: q.step, sql: q.sql, db: q.db, purpose: q.purpose, depends_on: q.depends_on, bind: q.bind })) ?? null,
        queries: planResult.queries?.map(q => ({ sql: q.sql, db: q.db })) ?? null,
        sql: planResult.queries?.[0]?.sql ?? null,
        noMatch: planResult.status === 'no_match',
        rejected: false,
        reason: planResult.reason,
        available: planResult.available,
        dbLabel: planResult.queries?.[0]?.db ?? ddlChunks[0]?.db_label ?? 'crm',
      },
      promptSent: planResult.promptSent,
      durationMs: planDuration,
    });

    // no_match → go straight to Call 3 (outcome B)
    if (planResult.status === 'no_match') {
      console.log(`  ✗ no_match: ${planResult.reason}`);
      finalPlanResult = planResult;
      execResults = [];
      break;
    }

    // Low confidence → bounce back to Call 1 as clarification (once per turn)
    if (planResult.confidence < CONFIDENCE_THRESHOLD && !bounced) {
      bounced = true;
      console.log(`  ⚠ low confidence ${planResult.confidence} < ${CONFIDENCE_THRESHOLD} — bouncing to clarification`);

      const clarText = `I want to make sure I answer correctly. ${planResult.notes || 'Could you give me more details?'}`;
      const newPending = {
        original_prompt: message,
        round: 1,
        questions: [{ id: 'q1', text: 'Could you clarify what you are looking for?', answer: null }],
      };
      await writePendingClarification(sessionId, newPending);
      await updateTurn(talk2dbTurnId, rephrasedQuestion, 'clarification_requested', null);

      return {
        answer: clarText,
        sql: null,
        rowCount: null,
        finalStatus: 'clarification_requested',
        clarificationRequested: true,
        clarificationQuestions: newPending.questions,
      };
    }

    // Execute
    console.log(`\n[step: executor attempt ${attempt}]`);
    const tExec = startTimer();
    const results = await executePlan(planResult.queries);
    const execDuration = tExec();

    const anyError   = results.some(r => r.error);
    const anyRetry   = results.some(r => r.retryable);
    const totalRows  = results.reduce((s, r) => s + (r.rowCount ?? 0), 0);

    // Log executions in talk2db.executions
    for (const r of results) {
      await insertExecution(talk2dbTurnId, attempt, r);
    }

    // Record attempt for retry context
    plannerAttempts.push({
      attempt,
      status: planResult.status,
      confidence: planResult.confidence,
      queries: planResult.queries,
      execution: {
        status: anyError ? 'error' : 'ok',
        error: anyError ? results.find(r => r.error)?.error : null,
        row_count: totalRows,
        duration_ms: execDuration,
        result_summary: results.map(r => r.resultSummary).filter(Boolean).join('; '),
      },
    });

    await logTrace({
      sessionId, turnId: harnessTurnId, phase: 'execute',
      payload: {
        attempt,
        crossDb: planResult.queries.some(q => q.depends_on != null),
        queries: results.map(r => ({
          step: r.step, db: r.db, sql: r.sql, rowCount: r.rowCount,
          rows: r.rows ? r.rows.slice(0, 50) : null,
          error: r.error ?? null, errorType: r.errorType ?? null,
          retryable: r.retryable, durationMs: r.durationMs,
          boundValues: r.boundValues ? r.boundValues.slice(0, 10) : null,
          depends_on: r.depends_on ?? null,
        })),
        sql: results[0]?.sql ?? null,
        dbLabel: results[0]?.db ?? 'crm',
        rowCount: totalRows,
        error: anyError ? results.find(r => r.error)?.error : null,
      },
      durationMs: execDuration,
    });

    if (!anyError) {
      // Success
      finalPlanResult = planResult;
      execResults = results;
      break;
    }

    // Error — check if retryable
    if (!anyRetry || attempt >= MAX_PLANNER_ATTEMPTS) {
      console.log(`  ✗ Execution failed (${anyRetry ? 'max attempts reached' : 'non-retryable error'})`);
      // Fall through to failure path below
      finalPlanResult = null;
      execResults = results;
      break;
    }

    console.log(`  ↻ Retryable error — attempt ${attempt + 1}`);
  }

  // ─── Failure path ─────────────────────────────────────────────────────────────
  const allFailed = execResults.length > 0 && execResults.every(r => r.error) && finalPlanResult === null;
  const noMatchPath = finalPlanResult?.status === 'no_match';

  if (allFailed && !noMatchPath) {
    const failureAnswer = "I couldn't process that request — the query ran into errors after multiple attempts. Could you try rephrasing it?";
    await updateTurn(talk2dbTurnId, rephrasedQuestion, 'failed_after_retries', null);
    await logTrace({ sessionId, turnId: harnessTurnId, phase: 'turn_end', payload: { outcome: 'failed_after_retries' } });
    console.log(`[talk-to-db] FAILED after retries`);
    console.log(`${'='.repeat(60)}\n`);
    return { answer: failureAnswer, sql: null, rowCount: null, finalStatus: 'failed_after_retries', clarificationRequested: false, clarificationQuestions: null };
  }

  // ─── Call 3: Respond / Validate ───────────────────────────────────────────────
  console.log(`\n[step: call3-respond]`);
  const tCall3 = startTimer();
  const respond = await generateResponse(message, call1, plannerAttempts, execResults, ddlChunks, history);
  const call3Duration = tCall3();

  await insertLlmCall(
    talk2dbTurnId, 'respond', 1,
    { rephrasedQuestion, plannerAttempts: plannerAttempts.length,
      execRowCount: execResults.reduce((s, r) => s + (r.rowCount ?? 0), 0),
      history: history.slice(-6), sessionId, turnNo: turnNumber, identity: identity ?? null },
    respond.promptSent,
    JSON.stringify(respond),
    { outcome: respond.outcome, validated: respond.validated, response: respond.response, suggested_next: respond.suggested_next, alternatives: respond.alternatives },
    'ok',
    call3Duration,
    respond.model,
    respond.tokensIn,
    respond.tokensOut
  );

  const finalStatus = respond.outcome === 'answer' ? 'answered'
    : respond.outcome === 'no_relevant_data' ? 'no_relevant_data'
    : 'cannot_process';

  await updateTurn(talk2dbTurnId, rephrasedQuestion, finalStatus, {
    outcome: respond.outcome,
    validated: respond.validated,
    response: respond.response,
    suggested_next: respond.suggested_next,
    alternatives: respond.alternatives,
  });

  await logTrace({
    sessionId, turnId: harnessTurnId, phase: 'generate_response',
    payload: {
      outcome: respond.outcome,
      validated: respond.validated,
      rowCount: execResults.reduce((s, r) => s + (r.rowCount ?? 0), 0),
      suggested_next: respond.suggested_next,
    },
    promptSent: respond.promptSent,
    durationMs: call3Duration,
  });

  await logTrace({
    sessionId, turnId: harnessTurnId, phase: 'turn_end',
    payload: { outcome: finalStatus },
  });

  const sql = plannerAttempts.find(a => a.execution?.status === 'ok')?.queries?.[0]?.sql
    ?? execResults[0]?.sql
    ?? null;
  const totalRows = execResults.reduce((s, r) => s + (r.rowCount ?? 0), 0);

  console.log(`[talk-to-db] Done. outcome=${respond.outcome} rows=${totalRows}`);
  console.log(`${'='.repeat(60)}\n`);

  return {
    answer: respond.response,
    sql,
    rowCount: totalRows,
    finalStatus,
    clarificationRequested: false,
    clarificationQuestions: null,
    suggestedNext: respond.suggested_next,
    alternatives: respond.alternatives,
  };
}

function formatClarificationQuestions(questions) {
  if (!questions?.length) return "Could you clarify your question?";
  if (questions.length === 1) return questions[0].text;
  const lines = questions.map((q, i) => `${i + 1}. ${q.text}`);
  return `I have a couple of questions to make sure I give you the right answer:\n\n${lines.join('\n')}`;
}
