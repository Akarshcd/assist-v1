import { llmCall } from '../../llm/client.js';
import { PROMPTS } from '../../prompts/talk-to-db/prompt-store.js';

/**
 * LLM call #2 — turn raw DB results (one or two sets) into a natural language answer.
 *
 * @param {string} question
 * @param {Array<{sql: string, db: string, rows: Array|null, error: Error|null}>} execResults
 * @param {{ crmUserId, employeeId, email }} identity
 * @param {Array} history
 * @returns {Promise<{ answer: string, promptSent: {systemPrompt, userPrompt}|null }>}
 */
export async function generateResponse(question, execResults, identity, history = []) {
  // If ALL queries failed, return error message without LLM call
  const allFailed = execResults.every(r => r.rows === null);
  if (allFailed) {
    const answer = "I wasn't able to retrieve that data — the query ran into an error. Could you rephrase the question?";
    return { answer, promptSent: null };
  }

  // Steps that other steps depend on are intermediate lookups — label them so the
  // LLM knows they are supporting data, not the primary answer.
  const dataSection = execResults.map(r => {
    const label = r.db.toUpperCase();
    const isIntermediate = execResults.some(other => other.depends_on === r.step);
    const role = isIntermediate ? `[${label} step ${r.step} — lookup]` : `[${label} step ${r.step} — results]`;
    if (r.rows === null) return `${role} Query failed: ${r.error?.message ?? 'unknown error'}`;
    if (r.rows.length === 0) return `${role} No rows returned.`;
    return `${role}\n${formatRows(r.rows)}`;
  }).join('\n\n');

  const historySection = history.length
    ? `## Conversation history\n${history.map((h) => `${h.role === 'user' ? 'User' : 'Assistant'}: ${h.content}`).join('\n')}\n\n`
    : '';

  const userPrompt = `${historySection}## Current question\n${question}\n\n## Query results\n${dataSection}`;
  const activePrompt = PROMPTS.respond;
  const promptSent = { systemPrompt: activePrompt, userPrompt };

  const { text } = await llmCall(activePrompt, userPrompt, {
    temperature: 0.3,
    maxTokens: 1024,
  });

  return { answer: text.trim(), promptSent };
}

function formatRows(rows) {
  if (rows.length === 0) return 'No rows.';
  const sample = rows.length > 50 ? rows.slice(0, 50) : rows;
  const truncated = rows.length > 50 ? `\n(${rows.length - 50} more rows not shown)` : '';
  const keys = Object.keys(sample[0]);
  const header = keys.join(' | ');
  const separator = keys.map((k) => '-'.repeat(Math.max(k.length, 6))).join('-|-');
  const rowLines = sample.map((r) => keys.map((k) => String(r[k] ?? '')).join(' | '));
  return [header, separator, ...rowLines, truncated].filter(Boolean).join('\n');
}
