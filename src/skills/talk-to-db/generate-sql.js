import { llmCall } from '../../llm/client.js';
import { PROMPTS } from '../../prompts/talk-to-db/prompt-store.js';

/**
 * LLM call #1 — generate a sequential execution plan (array of steps).
 *
 * @param {string} question
 * @param {Array} ddlChunks
 * @param {string} coreContext
 * @param {Array} vocabMatches
 * @param {{ crmUserId, employeeId, email }} identity
 * @param {Array} history
 * @returns {Promise<{
 *   steps: Array<{step:number, db:string, sql:string, depends_on:number|null, bind:string|null}> | null,
 *   noMatch: boolean,
 *   rejected: boolean,
 *   promptSent: {systemPrompt, userPrompt}
 * }>}
 */
export async function generateSQL(question, ddlChunks, coreContext, vocabMatches, identity, history = []) {
  const ddlSection = buildDDLSection(ddlChunks);
  const vocabSection = buildVocabSection(vocabMatches);
  const identitySection = buildIdentitySection(identity);
  const historySection = buildHistorySection(history);

  const userPrompt = [
    identitySection,
    vocabSection,
    coreContext,
    `## Retrieved DDL (top-K similarity matches)\n${ddlSection}`,
    historySection,
    `## Current question\n${question}`,
  ].filter(Boolean).join('\n\n');

  // Use live prompt from store (may have been edited via frontend)
  const activePrompt = PROMPTS.sql;
  const promptSent = { systemPrompt: activePrompt, userPrompt };

  const { text } = await llmCall(activePrompt, userPrompt, {
    temperature: 0,
    maxTokens: 2048,
  });

  const cleaned = text.trim();

  if (cleaned === 'NO_MATCH' || cleaned.toUpperCase().includes('NO_MATCH')) {
    return { steps: null, noMatch: true, rejected: false, promptSent };
  }

  const jsonText = cleaned.replace(/^```(?:json)?/i, '').replace(/```$/, '').trim();

  let steps;
  try {
    steps = JSON.parse(jsonText);
  } catch {
    console.warn('[generate-sql] Non-JSON response, trying as plain SQL:', jsonText.slice(0, 80));
    if (!/^\s*SELECT/i.test(jsonText)) {
      return { steps: null, noMatch: false, rejected: true, promptSent };
    }
    // Legacy plain SQL fallback — wrap as step 1
    steps = [{ step: 1, db: 'crm', sql: jsonText, depends_on: null, bind: null }];
  }

  if (!Array.isArray(steps) || steps.length === 0) {
    return { steps: null, noMatch: false, rejected: true, promptSent };
  }

  // Normalize and validate
  for (const s of steps) {
    if (!s.sql || !/^\s*SELECT/i.test(s.sql)) {
      console.warn('[generate-sql] Non-SELECT step, rejecting:', JSON.stringify(s).slice(0, 80));
      return { steps: null, noMatch: false, rejected: true, promptSent };
    }
    if (!['crm', 'hrm'].includes(s.db)) s.db = 'crm';
    s.depends_on = s.depends_on ?? null;
    s.bind = s.bind ?? null;
    s.step = s.step ?? (steps.indexOf(s) + 1);
  }

  // Sort by step number so execution order is guaranteed
  steps.sort((a, b) => a.step - b.step);

  return { steps, noMatch: false, rejected: false, promptSent };
}

function buildDDLSection(chunks) {
  const crossSchemaWarnings = chunks
    .filter((c) => c.hasCrossSchemaRefs)
    .map((c) => `  - ${c.schema_name}.${c.table_name} references schemas: ${c.cross_schema_refs.join(', ')}`);

  const ddlText = chunks.map((c) => c.chunk_text).join('\n\n');

  const warning = crossSchemaWarnings.length
    ? `⚠️ Cross-schema FK warning — do NOT join across these unless the FK is explicit:\n${crossSchemaWarnings.join('\n')}\n\n`
    : '';

  return warning + ddlText;
}

function buildVocabSection(vocabMatches) {
  if (!vocabMatches.length) return '';
  const lines = vocabMatches.map((v) => `  "${v.alias}" → ${v.canonical_term}`);
  return `## Resolved terminology\n${lines.join('\n')}`;
}

function buildIdentitySection(identity) {
  if (!identity) return '';
  const parts = [];
  if (identity.email) parts.push(`email: ${identity.email}`);
  if (identity.crmUserId) parts.push(`CRM user_id: ${identity.crmUserId}`);
  if (identity.employeeId) parts.push(`HRM emp_id: ${identity.employeeId}`);
  if (!parts.length) return '';
  return `## Requesting user context\n${parts.join(', ')}`;
}

function buildHistorySection(history) {
  if (!history.length) return '';
  const lines = history.map((h) => {
    if (h.role === 'user') return `User: ${h.content}`;
    const sqlNote = h.sql ? ` [SQL: ${h.sql.slice(0, 80)}...]` : '';
    return `Assistant: ${h.content}${sqlNote}`;
  });
  return `## Conversation history (most recent last)\n${lines.join('\n')}`;
}
