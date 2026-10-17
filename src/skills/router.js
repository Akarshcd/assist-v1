import { llmCall } from '../llm/client.js';
import { ROUTE_TURN_PROMPT } from '../prompts/router/route-turn.js';

const KNOWN_SKILLS = ['talk_to_db', 'chit_chat', 'none'];

/**
 * Route a user turn to the appropriate skill.
 * This is the harness entry point — runs before any skill logic.
 *
 * @param {string} message
 * @param {{ userId?: string, sessionId: string }} context
 * @returns {Promise<{ skill: 'talk_to_db'|'chit_chat'|'none', confidence: number, reason: string }>}
 */
export async function routeTurn(message, context) {
  const userPrompt = `User message: "${message}"\nSession ID: ${context.sessionId}`;

  let result;
  try {
    const { text } = await llmCall(ROUTE_TURN_PROMPT, userPrompt, {
      temperature: 0,
      maxTokens: 128,
    });
    result = parseRouterResponse(text);
  } catch (err) {
    console.error('[router] LLM call failed, defaulting to chit_chat:', err.message);
    result = { skill: 'chit_chat', confidence: 0, reason: 'Router LLM failed' };
  }

  if (!KNOWN_SKILLS.includes(result.skill)) {
    result.skill = 'none';
  }

  console.log(`[router] → skill="${result.skill}" confidence=${result.confidence} reason="${result.reason}"`);
  return result;
}

function parseRouterResponse(text) {
  // Strip markdown fences if the model wraps anyway
  const cleaned = text.replace(/```(?:json)?/g, '').trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    // Best-effort extraction if the model adds prose
    const match = cleaned.match(/\{[^}]+\}/);
    if (match) return JSON.parse(match[0]);
    return { skill: 'chit_chat', confidence: 0, reason: 'Parse failed' };
  }
}
