import { llmCall } from '../../llm/client.js';
import { REPHRASE_PROMPT, MAX_CLARIFICATION_ROUNDS } from '../../prompts/talk-to-db/rephrase.js';

const CONFIDENCE_THRESHOLD = parseFloat(process.env.PLANNER_CONFIDENCE_THRESHOLD ?? '0.6');

/**
 * Call 1: Rephrase or Clarify.
 *
 * @param {string} message — current user turn text
 * @param {Array} history — [{role, content, sql?}] last N turns
 * @param {object|null} pendingClarification — {round, original_prompt, questions:[{id,text,answer}]}
 * @returns {Promise<{
 *   message_type: string,
 *   rephrased_question: string|null,
 *   needs_clarification: boolean,
 *   clarification: object|null,
 *   assumptions: string[],
 *   promptSent: {systemPrompt, userPrompt}
 * }>}
 */
export async function rephraseOrClarify(message, history = [], pendingClarification = null) {
  const historySection = history.length
    ? `<session_history>\n${history.map(h => `${h.role === 'user' ? 'User' : 'Assistant'}: ${h.content}`).join('\n')}\n</session_history>`
    : '';

  const clarSection = pendingClarification
    ? `<pending_clarification>
Round: ${pendingClarification.round}
Original prompt: ${pendingClarification.original_prompt}
Questions and answers so far:
${pendingClarification.questions.map(q => `  [${q.id}] ${q.text}\n  Answer: ${q.answer ?? '(not answered)'}`).join('\n')}
</pending_clarification>`
    : '';

  const roundNote = pendingClarification
    ? `This is clarification round ${pendingClarification.round + 1} of ${MAX_CLARIFICATION_ROUNDS}. ${
        pendingClarification.round + 1 >= MAX_CLARIFICATION_ROUNDS
          ? `This is the FINAL round — you MUST produce rephrased_question now using assumptions, do NOT ask again.`
          : ''
      }`
    : '';

  const userPrompt = [
    historySection,
    clarSection,
    roundNote,
    `<user_message>${message}</user_message>`,
  ].filter(Boolean).join('\n\n');

  const promptSent = { systemPrompt: REPHRASE_PROMPT, userPrompt };

  let parsed;
  let rawText = '';
  let model = null;
  let tokensIn = null;
  let tokensOut = null;
  try {
    const result = await llmCall(REPHRASE_PROMPT, userPrompt, { temperature: 0, maxTokens: 1024 });
    rawText = result.text.trim();
    model = result.model ?? null;
    tokensIn = result.usage?.inputTokens ?? null;
    tokensOut = result.usage?.outputTokens ?? null;
    parsed = parseCall1Response(rawText);
  } catch (err) {
    console.error('[call1] LLM error:', err.message);
    parsed = fallback(message);
  }

  // Hard cap: if round would exceed max, force proceed with assumptions
  if (parsed.needs_clarification && pendingClarification) {
    const nextRound = pendingClarification.round + 1;
    if (nextRound >= MAX_CLARIFICATION_ROUNDS) {
      parsed.needs_clarification = false;
      parsed.rephrased_question = parsed.rephrased_question
        ?? `${pendingClarification.original_prompt} (proceeding with available information)`;
      parsed.assumptions = parsed.assumptions?.length
        ? parsed.assumptions
        : ['Proceeding without full clarification answers after max rounds'];
    }
  }

  return { ...parsed, promptSent, model, tokensIn, tokensOut };
}

function parseCall1Response(text) {
  const cleaned = text.replace(/^```(?:json)?/im, '').replace(/```$/m, '').trim();
  try {
    const obj = JSON.parse(cleaned);
    return normalise(obj);
  } catch {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (match) {
      try { return normalise(JSON.parse(match[0])); } catch {}
    }
    return fallback(text);
  }
}

function normalise(obj) {
  return {
    message_type:       obj.message_type ?? 'new_question',
    rephrased_question: obj.rephrased_question ?? null,
    needs_clarification: !!obj.needs_clarification,
    clarification:      obj.clarification ?? null,
    assumptions:        Array.isArray(obj.assumptions) ? obj.assumptions : [],
  };
}

function fallback(originalMessage) {
  return {
    message_type:       'new_question',
    rephrased_question: typeof originalMessage === 'string' ? originalMessage : 'Unknown question',
    needs_clarification: false,
    clarification:      null,
    assumptions:        ['Call 1 parse failed — using raw message as-is'],
  };
}
