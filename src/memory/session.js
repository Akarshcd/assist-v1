import { harnessDb } from '../db/connections.js';

const HISTORY_WINDOW = 6; // last N turns to pass as conversation context

/**
 * Create a session row if it doesn't exist, or update last_active + turn_count.
 * Called at the start of every turn.
 */
export async function createOrTouchSession({ sessionId, userId, email }) {
  await harnessDb.query(
    `INSERT INTO sessions (session_id, user_id, email, turn_count, last_active)
     VALUES ($1, $2, $3, 1, now())
     ON CONFLICT (session_id) DO UPDATE
       SET last_active = now(),
           turn_count  = sessions.turn_count + 1,
           user_id     = COALESCE(EXCLUDED.user_id, sessions.user_id),
           email       = COALESCE(EXCLUDED.email, sessions.email)`,
    [sessionId, userId ?? null, email ?? null]
  );
}

/**
 * Load the last HISTORY_WINDOW turns for this session from episodic_log.
 * Returns a compact array used as conversation context in LLM prompts.
 *
 * @returns {Array<{ role: 'user'|'assistant', content: string, sql?: string|null }>}
 */
export async function loadConversationHistory(sessionId) {
  const { rows } = await harnessDb.query(
    `SELECT raw_message, assistant_answer, resolved_intent_or_sql
       FROM episodic_log
      WHERE session_id = $1
      ORDER BY turn_number DESC
      LIMIT $2`,
    [sessionId, HISTORY_WINDOW]
  );

  // Reverse so oldest first, build alternating user/assistant pairs
  return rows.reverse().flatMap((row) => {
    const turns = [{ role: 'user', content: row.raw_message }];
    if (row.assistant_answer) {
      turns.push({
        role: 'assistant',
        content: row.assistant_answer,
        sql: row.resolved_intent_or_sql ?? null,
      });
    }
    return turns;
  });
}

/**
 * List all sessions, most recent first.
 */
export async function listSessions({ limit = 50 } = {}) {
  const { rows } = await harnessDb.query(
    `SELECT session_id, user_id, email, turn_count, created_at, last_active
       FROM sessions
      ORDER BY last_active DESC
      LIMIT $1`,
    [limit]
  );
  return rows;
}
