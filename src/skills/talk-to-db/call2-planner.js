import { llmCall } from '../../llm/client.js';
import { buildCoreContext } from './core-context.js';
import { PLANNER_PROMPT } from '../../prompts/talk-to-db/planner.js';

const CRM_SCHEMA = process.env.CRM_SCHEMA ?? 'schema_3';
const HRM_SCHEMA = process.env.HRM_SCHEMA ?? 'schema_3';
const CONFIDENCE_THRESHOLD = parseFloat(process.env.PLANNER_CONFIDENCE_THRESHOLD ?? '0.6');

function injectSchemas(text) {
  return text.split('{CRM_SCHEMA}').join(CRM_SCHEMA).split('{HRM_SCHEMA}').join(HRM_SCHEMA);
}

/**
 * Call 2: Planner.
 *
 * @param {string} rephrasedQuestion
 * @param {object} call1Result — from rephraseOrClarify
 * @param {Array} ddlChunks — from retrieveDDL
 * @param {{ crmUserId, employeeId, email }} identity
 * @param {Array} history
 * @param {Array} previousAttempts — [{attempt, status, queries, execution}] for retry
 * @returns {Promise<{
 *   status: 'plan'|'no_match',
 *   confidence: number,
 *   queries: Array|null,
 *   reason: string|null,
 *   available: string[],
 *   relevant_ddls: string[],
 *   relevant_samples: string[],
 *   notes: string,
 *   promptSent: object
 * }>}
 */
export async function planQuery(rephrasedQuestion, call1Result, ddlChunks, identity, history = [], previousAttempts = []) {
  const coreContext = injectSchemas(buildCoreContext());
  const ddlSection  = buildDDLSection(ddlChunks);
  const identSect   = buildIdentitySection(identity);
  const histSect    = buildHistorySection(history);
  const clarSect    = buildClarificationSection(call1Result);
  const retrySection = buildRetrySection(previousAttempts);

  const userPrompt = [
    identSect,
    clarSect,
    `<schema>\n<!-- CORE IDENTITY (always present — use for joins/identity resolution) -->\n${coreContext}\n\n<!-- RETRIEVED DDL (tables relevant to this question) -->\n${ddlSection}\n</schema>`,
    histSect,
    retrySection,
    `<question>${rephrasedQuestion}</question>`,
  ].filter(Boolean).join('\n\n');

  const systemPrompt = injectSchemas(PLANNER_PROMPT);
  const promptSent = { systemPrompt, userPrompt };

  let rawText = '';
  let model = null;
  let tokensIn = null;
  let tokensOut = null;
  try {
    const result = await llmCall(systemPrompt, userPrompt, { temperature: 0, maxTokens: 2048 });
    rawText = result.text.trim();
    model = result.model ?? null;
    tokensIn = result.usage?.inputTokens ?? null;
    tokensOut = result.usage?.outputTokens ?? null;
  } catch (err) {
    console.error('[call2] LLM error:', err.message);
    return { status: 'no_match', confidence: 0, queries: null, reason: 'LLM call failed', available: [], relevant_ddls: [], relevant_samples: [], notes: '', promptSent, model, tokensIn, tokensOut };
  }

  const parsed = parsePlannerResponse(rawText);
  return { ...parsed, promptSent, model, tokensIn, tokensOut };
}

function parsePlannerResponse(text) {
  const cleaned = text.replace(/^```(?:json)?/im, '').replace(/```$/m, '').trim();

  // Legacy NO_MATCH plain text
  if (cleaned === 'NO_MATCH' || cleaned.toUpperCase().startsWith('NO_MATCH')) {
    return { status: 'no_match', confidence: 0, queries: null, reason: 'LLM returned NO_MATCH', available: [], relevant_ddls: [], relevant_samples: [], notes: '' };
  }

  let obj;
  try {
    obj = JSON.parse(cleaned);
  } catch {
    const match = cleaned.match(/\{[\s\S]*\}/);
    if (match) { try { obj = JSON.parse(match[0]); } catch {} }
    // Last resort: maybe it's a bare array (legacy format from old generate-sql.js)
    if (!obj) {
      const arrMatch = cleaned.match(/\[[\s\S]*\]/);
      if (arrMatch) {
        try {
          const steps = JSON.parse(arrMatch[0]);
          if (Array.isArray(steps) && steps.length) {
            return {
              status: 'plan', confidence: 0.7,
              queries: normaliseSteps(steps),
              reason: null, available: [], relevant_ddls: [], relevant_samples: [], notes: 'Parsed from legacy array format',
            };
          }
        } catch {}
      }
    }
    if (!obj) {
      return { status: 'no_match', confidence: 0, queries: null, reason: 'Parse failed', available: [], relevant_ddls: [], relevant_samples: [], notes: '' };
    }
  }

  if (obj.status === 'no_match') {
    return {
      status: 'no_match', confidence: 0, queries: null,
      reason: obj.reason ?? 'No match',
      available: Array.isArray(obj.available) ? obj.available : [],
      relevant_ddls: Array.isArray(obj.relevant_ddls) ? obj.relevant_ddls : [],
      relevant_samples: Array.isArray(obj.relevant_samples) ? obj.relevant_samples : [],
      notes: obj.notes ?? '',
    };
  }

  if (obj.status === 'plan') {
    const queries = normaliseSteps(obj.queries ?? []);
    if (!queries.length) {
      return { status: 'no_match', confidence: 0, queries: null, reason: 'Plan had no valid queries', available: [], relevant_ddls: [], relevant_samples: [], notes: '' };
    }
    return {
      status: 'plan',
      confidence: typeof obj.confidence === 'number' ? obj.confidence : 0.7,
      queries,
      reason: null,
      available: [],
      relevant_ddls: Array.isArray(obj.relevant_ddls) ? obj.relevant_ddls : [],
      relevant_samples: Array.isArray(obj.relevant_samples) ? obj.relevant_samples : [],
      notes: obj.notes ?? '',
    };
  }

  return { status: 'no_match', confidence: 0, queries: null, reason: 'Unknown status', available: [], relevant_ddls: [], relevant_samples: [], notes: '' };
}

function normaliseSteps(steps) {
  if (!Array.isArray(steps)) return [];
  const valid = [];
  for (const s of steps) {
    if (!s.sql || !/^\s*SELECT/i.test(s.sql)) continue;
    valid.push({
      step:       s.step ?? (valid.length + 1),
      db:         ['crm', 'hrm'].includes(s.db) ? s.db : 'crm',
      sql:        s.sql,
      purpose:    s.purpose ?? '',
      depends_on: s.depends_on ?? null,
      bind:       s.bind ?? null,
    });
  }
  valid.sort((a, b) => a.step - b.step);
  return valid;
}

function buildDDLSection(chunks) {
  const warnings = chunks
    .filter(c => c.hasCrossSchemaRefs)
    .map(c => `  - ${c.schema_name}.${c.table_name} references: ${c.cross_schema_refs.join(', ')}`);

  const ddlText = chunks.map(c => c.chunk_text).join('\n\n');
  const warn = warnings.length
    ? `⚠️ Cross-schema FK warning — do NOT join across these unless the FK is explicit:\n${warnings.join('\n')}\n\n`
    : '';
  return warn + ddlText;
}

function buildIdentitySection(identity) {
  if (!identity) return '';
  const parts = [];
  if (identity.email)       parts.push(`email: ${identity.email}`);
  if (identity.crmUserId)   parts.push(`CRM user_id: ${identity.crmUserId}`);
  if (identity.employeeId)  parts.push(`HRM emp_id: ${identity.employeeId}`);
  return parts.length ? `<identity>\n${parts.join(', ')}\n</identity>` : '';
}

function buildHistorySection(history) {
  if (!history.length) return '';
  const lines = history.map(h => {
    if (h.role === 'user') return `User: ${h.content}`;
    const sqlNote = h.sql ? ` [SQL: ${h.sql.slice(0, 80)}…]` : '';
    return `Assistant: ${h.content}${sqlNote}`;
  });
  return `<session_history>\n${lines.join('\n')}\n</session_history>`;
}

function buildClarificationSection(call1Result) {
  if (!call1Result) return '';
  const parts = [];
  if (call1Result.rephrased_question) parts.push(`Rephrased question: ${call1Result.rephrased_question}`);
  if (call1Result.assumptions?.length) parts.push(`Assumptions: ${call1Result.assumptions.join('; ')}`);
  if (call1Result.clarification?.questions?.length) {
    const answered = call1Result.clarification.questions
      .filter(q => q.answer)
      .map(q => `  [${q.id}] ${q.text} → ${q.answer}`);
    if (answered.length) parts.push(`Clarification answers:\n${answered.join('\n')}`);
  }
  return parts.length ? `<clarification>\n${parts.join('\n')}\n</clarification>` : '';
}

function buildRetrySection(previousAttempts) {
  if (!previousAttempts.length) return '';
  const blocks = previousAttempts.map(a => {
    const sqls = (a.queries ?? []).map(q => `  Step ${q.step} [${q.db}]: ${q.sql}`).join('\n');
    const err = a.execution?.error ? `  Error: ${a.execution.error}` : '  (no execution error recorded)';
    return `Attempt ${a.attempt}:\n${sqls}\n${err}`;
  });
  return `<previous_attempts>\nThese attempts FAILED. Your new queries must fix the errors.\n${blocks.join('\n\n')}\n</previous_attempts>`;
}
