import { llmCall } from '../../llm/client.js';
import { RESPOND_PROMPT } from '../../prompts/talk-to-db/respond.js';

/**
 * Call 3: Respond / Validate.
 *
 * @param {string} originalQuestion
 * @param {object} call1Result — { rephrased_question, clarification, assumptions }
 * @param {Array} plannerAttempts — [{attempt, status, queries, execution}]
 * @param {Array} execResults — from executePlan
 * @param {Array} ddlChunks — for alternatives on no_match
 * @param {Array} history
 * @returns {Promise<{
 *   outcome: 'answer'|'no_relevant_data'|'cannot_process',
 *   validated: boolean,
 *   response: string,
 *   suggested_next: string|null,
 *   alternatives: string[],
 *   reason: string|null,
 *   promptSent: object
 * }>}
 */
export async function generateResponse(originalQuestion, call1Result, plannerAttempts, execResults, ddlChunks = [], history = []) {
  // If all queries failed with non-retryable errors, use cannot_process without LLM
  const allFailed = execResults.length > 0 && execResults.every(r => r.error && !r.retryable);
  if (allFailed && execResults[0]?.errorType !== 'sql_error') {
    const response = "I wasn't able to retrieve that data. There was a technical issue. Could you try again or rephrase your question?";
    return { outcome: 'cannot_process', validated: false, response, suggested_next: null, alternatives: [], reason: execResults[0]?.error ?? 'execution error', promptSent: null };
  }

  const rephrasedQ    = call1Result?.rephrased_question ?? originalQuestion;
  const assumptions   = call1Result?.assumptions ?? [];
  const clarAnswers   = buildClarAnswers(call1Result);

  const questionSection = [
    `Original question: ${originalQuestion}`,
    rephrasedQ !== originalQuestion ? `Rephrased: ${rephrasedQ}` : null,
    clarAnswers ? `Clarification context: ${clarAnswers}` : null,
    assumptions.length ? `Assumptions made: ${assumptions.join('; ')}` : null,
  ].filter(Boolean).join('\n');

  const sqlSection = plannerAttempts.map(a => {
    const sqls = (a.queries ?? []).map(q => `  Step ${q.step} [${q.db}]: ${q.sql}`).join('\n');
    return `Attempt ${a.attempt}:\n${sqls}`;
  }).join('\n\n');

  const dataSection = execResults.map(r => {
    const label = r.db.toUpperCase();
    const isIntermediate = execResults.some(other => other.depends_on === r.step);
    const role = isIntermediate ? `[${label} step ${r.step} — lookup data]` : `[${label} step ${r.step} — results]`;
    if (r.error) return `${role} Query failed: ${r.error}`;
    if (r.rowCount === 0) return `${role} No rows returned.`;
    return `${role} ${r.resultSummary}\n${formatRows(r.rows)}`;
  }).join('\n\n');

  const availableTables = ddlChunks.map(c => `${c.schema_name}.${c.table_name}`).join(', ');

  const histSection = history.length
    ? `<session_history>\n${history.map(h => `${h.role === 'user' ? 'User' : 'Assistant'}: ${h.content}`).join('\n')}\n</session_history>`
    : '';

  const userPrompt = [
    histSection,
    `<question>\n${questionSection}\n</question>`,
    sqlSection ? `<sql_executed>\n${sqlSection}\n</sql_executed>` : null,
    `<db_result>\n${dataSection || 'No results.'}\n</db_result>`,
    availableTables ? `<available_tables>${availableTables}</available_tables>` : null,
  ].filter(Boolean).join('\n\n');

  const promptSent = { systemPrompt: RESPOND_PROMPT, userPrompt };

  let rawText = '';
  let model = null;
  let tokensIn = null;
  let tokensOut = null;
  try {
    const result = await llmCall(RESPOND_PROMPT, userPrompt, { temperature: 0.3, maxTokens: 1024 });
    rawText = result.text.trim();
    model = result.model ?? null;
    tokensIn = result.usage?.inputTokens ?? null;
    tokensOut = result.usage?.outputTokens ?? null;
  } catch (err) {
    console.error('[call3] LLM error:', err.message);
    return { outcome: 'cannot_process', validated: false, response: "I had trouble generating a response. Please try again.", suggested_next: null, alternatives: [], reason: err.message, promptSent, model, tokensIn, tokensOut };
  }

  const parsed = parseCall3Response(rawText, execResults);
  return { ...parsed, promptSent, model, tokensIn, tokensOut };
}

function parseCall3Response(text, execResults) {
  const cleaned = text.replace(/^```(?:json)?/im, '').replace(/```$/m, '').trim();
  let obj;
  try {
    obj = JSON.parse(cleaned);
  } catch {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (match) { try { obj = JSON.parse(match[0]); } catch {} }
    if (!obj) {
      // Fallback: treat as plain text answer
      return { outcome: 'answer', validated: true, response: text.trim(), suggested_next: null, alternatives: [], reason: null };
    }
  }

  const outcome = ['answer', 'no_relevant_data', 'cannot_process'].includes(obj.outcome)
    ? obj.outcome : 'answer';

  return {
    outcome,
    validated: outcome === 'answer' ? (obj.validated !== false) : false,
    response:  obj.response ?? 'No response generated.',
    suggested_next: obj.suggested_next ?? null,
    alternatives:   Array.isArray(obj.alternatives) ? obj.alternatives : [],
    reason:         obj.reason ?? null,
  };
}

function buildClarAnswers(call1Result) {
  if (!call1Result?.clarification?.questions?.length) return null;
  const answered = call1Result.clarification.questions
    .filter(q => q.answer)
    .map(q => `${q.text}: ${q.answer}`);
  return answered.length ? answered.join('; ') : null;
}

function formatRows(rows) {
  if (!rows || rows.length === 0) return 'No rows.';
  const sample = rows.length > 50 ? rows.slice(0, 50) : rows;
  const truncated = rows.length > 50 ? `\n(${rows.length - 50} more rows not shown)` : '';
  const keys = Object.keys(sample[0]);
  const header = keys.join(' | ');
  const separator = keys.map(k => '-'.repeat(Math.max(k.length, 6))).join('-|-');
  const rowLines = sample.map(r => keys.map(k => String(r[k] ?? '')).join(' | '));
  return [header, separator, ...rowLines, truncated].filter(Boolean).join('\n');
}
