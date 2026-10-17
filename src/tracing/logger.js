import { harnessDb } from '../db/connections.js';

export async function logEpisode({ sessionId, userId, turnNumber, rawMessage, routedSkill, resolvedIntentOrSql, assistantAnswer }) {
  const { rows } = await harnessDb.query(
    `INSERT INTO episodic_log
       (session_id, user_id, turn_number, raw_message, routed_skill, resolved_intent_or_sql, assistant_answer)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id`,
    [sessionId, userId ?? null, turnNumber, rawMessage, routedSkill ?? null, resolvedIntentOrSql ?? null, assistantAnswer ?? null]
  );
  return rows[0].id;
}

export async function updateEpisodeAnswer(turnId, assistantAnswer, resolvedIntentOrSql) {
  await harnessDb.query(
    `UPDATE episodic_log SET assistant_answer = $1, resolved_intent_or_sql = $2 WHERE id = $3`,
    [assistantAnswer, resolvedIntentOrSql ?? null, turnId]
  );
}

/**
 * @param {{ sessionId, turnId, phase, payload, promptSent?, durationMs }} args
 * promptSent: { systemPrompt, userPrompt } — only on LLM phases, stored for frontend inspection
 */
export async function logTrace({ sessionId, turnId, phase, payload, promptSent, durationMs }) {
  await harnessDb.query(
    `INSERT INTO trace_log (session_id, turn_id, phase, payload, prompt_sent, duration_ms)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [
      sessionId,
      turnId ?? null,
      phase,
      JSON.stringify(payload ?? {}),
      promptSent ? JSON.stringify(promptSent) : null,
      durationMs ?? null,
    ]
  );
}

export function startTimer() {
  const t = Date.now();
  return () => Date.now() - t;
}
