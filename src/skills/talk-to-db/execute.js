import { crmSourceDb, hrmSourceDb } from '../../db/connections.js';

const MAX_ROWS = 200;
const STATEMENT_TIMEOUT_MS = parseInt(process.env.SQL_TIMEOUT_MS ?? '8000', 10);

const CRM_SCHEMA = process.env.CRM_SCHEMA ?? 'schema_3';
const HRM_SCHEMA = process.env.HRM_SCHEMA ?? 'schema_3';

function rewriteSchemas(sql) {
  return sql
    .split('{CRM_SCHEMA}').join(CRM_SCHEMA)
    .split('{HRM_SCHEMA}').join(HRM_SCHEMA);
}

function injectLimit(sql, maxRows) {
  const limitMatch = sql.match(/\bLIMIT\s+(\d+)/i);
  if (limitMatch) {
    const existing = parseInt(limitMatch[1], 10);
    return existing > maxRows ? sql.replace(/\bLIMIT\s+\d+/i, `LIMIT ${maxRows}`) : sql;
  }
  return `${sql.trimEnd().replace(/;$/, '')} LIMIT ${maxRows}`;
}

/**
 * Classify an execution error into a type.
 * retryable: true = Planner can fix it with better SQL.
 * retryable: false = no point retrying (permissions, timeout, etc.).
 */
export function classifyError(err) {
  const msg = err.message ?? '';
  const code = err.code ?? '';

  // Postgres error codes
  if (['42703', '42601', '42P01', '42P02', '42883'].includes(code)) {
    // column does not exist, syntax error, relation does not exist, undefined parameter, function does not exist
    return { type: 'sql_error', retryable: true };
  }
  if (code === '22P02' || code === '22003' || msg.toLowerCase().includes('invalid input syntax')) {
    // invalid input syntax / numeric overflow — bad parameter binding, planner can fix
    return { type: 'sql_error', retryable: true };
  }
  if (code === '57014' || msg.includes('statement timeout') || msg.includes('canceling statement')) {
    return { type: 'timeout', retryable: false };
  }
  if (['42501', '28000', '28P01'].includes(code) || msg.toLowerCase().includes('permission')) {
    return { type: 'permission', retryable: false };
  }
  if (msg.toLowerCase().includes('guard') || msg.includes('SELECT')) {
    return { type: 'guard_rejection', retryable: false };
  }
  return { type: 'unknown', retryable: false };
}

/**
 * Read-only guard: only allow SELECT statements.
 * Returns null if ok, or an error string if rejected.
 */
function guardSQL(sql) {
  const trimmed = sql.trim();
  if (!/^SELECT\b/i.test(trimmed)) {
    return `Non-SELECT statement rejected: ${trimmed.slice(0, 40)}`;
  }
  // Reject multiple statements (semicolon in the middle)
  const withoutStrings = trimmed.replace(/'[^']*'/g, "''");
  const semicolons = (withoutStrings.match(/;/g) ?? []).filter(Boolean);
  if (semicolons.length > 1 || (semicolons.length === 1 && !withoutStrings.trimEnd().endsWith(';'))) {
    return 'Multiple statements are not allowed';
  }
  return null;
}

function buildResultSummary(rows, rowCount) {
  if (!rows || rows.length === 0) return 'No rows returned';
  const cols = Object.keys(rows[0]).join(', ');
  return `${rowCount} row${rowCount !== 1 ? 's' : ''} (columns: ${cols})`;
}

/**
 * Execute a sequential plan of steps.
 *
 * @param {Array<{step, db, sql, depends_on, bind, purpose?}>} steps
 * @returns {Promise<Array<{
 *   step, sql, db, purpose,
 *   rows: Array|null,
 *   rowCount: number,
 *   error: string|null,
 *   errorType: string|null,
 *   retryable: boolean,
 *   durationMs: number,
 *   resultSummary: string,
 *   boundValues: any[]|null,
 *   depends_on: number|null
 * }>>}
 */
export async function executePlan(steps) {
  const resultsByStep = new Map();
  const results = [];

  for (const s of steps) {
    const tStart = Date.now();
    let sql = rewriteSchemas(s.sql);
    let params = [];
    let boundValues = null;

    // Inject prior step's results for dependent steps
    if (s.depends_on != null && s.bind) {
      const prior = resultsByStep.get(s.depends_on);
      if (!prior || !prior.rows || prior.rows.length === 0) {
        console.log(`  [execute:step${s.step}] Skipped — dependency step ${s.depends_on} returned no rows`);
        const result = makeResult(s, sql, [], null, null, false, 0, 'Skipped: dependency returned no rows', null);
        resultsByStep.set(s.step, result);
        results.push(result);
        continue;
      }

      boundValues = prior.rows.map(r => r[s.bind]).filter(v => v != null);

      if (boundValues.length === 0) {
        console.log(`  [execute:step${s.step}] Skipped — bind column "${s.bind}" had no non-null values`);
        const result = makeResult(s, sql, [], null, null, false, 0, 'Skipped: bind column had no values', []);
        resultsByStep.set(s.step, result);
        results.push(result);
        continue;
      }

      sql = sql.replace(/\$prior/g, '$1');
      // Pass a scalar when there's only one value and the SQL uses = $1 (not ANY/IN).
      // Pass an array when the SQL uses = ANY($1) or multiple values are needed.
      const usesAny = /=\s*ANY\s*\(\s*\$1\s*\)/i.test(sql) || /\bIN\s*\(\s*\$1\s*\)/i.test(sql);
      params = [usesAny ? boundValues : boundValues.length === 1 ? boundValues[0] : boundValues];
      console.log(`  [execute:step${s.step}] Bound ${boundValues.length} value(s) from step ${s.depends_on}.${s.bind}`);
    }

    // Guard check
    const guardErr = guardSQL(sql);
    if (guardErr) {
      console.warn(`  [execute:step${s.step}] GUARD REJECTED: ${guardErr}`);
      const result = makeResult(s, sql, null, guardErr, 'guard_rejection', false, Date.now() - tStart, '', boundValues);
      resultsByStep.set(s.step, result);
      results.push(result);
      continue;
    }

    const safeSql = injectLimit(sql, MAX_ROWS);
    const pool = s.db === 'hrm' ? hrmSourceDb : crmSourceDb;

    console.log(`  [execute:${s.db}:step${s.step}] SQL: ${safeSql.slice(0, 120)}${safeSql.length > 120 ? '...' : ''}`);

    try {
      await pool.query(`SET statement_timeout = ${STATEMENT_TIMEOUT_MS}`);
      const { rows } = params.length ? await pool.query(safeSql, params) : await pool.query(safeSql);
      const durationMs = Date.now() - tStart;
      console.log(`  [execute:${s.db}:step${s.step}] ✓ ${rows.length} rows (${durationMs}ms)`);

      const result = makeResult(s, safeSql, rows, null, null, false, durationMs, buildResultSummary(rows, rows.length), boundValues);
      resultsByStep.set(s.step, result);
      results.push(result);
    } catch (err) {
      const durationMs = Date.now() - tStart;
      const { type, retryable } = classifyError(err);
      console.warn(`  [execute:${s.db}:step${s.step}] ✗ FAILED [${type}, retryable=${retryable}]: ${err.message}`);
      const result = makeResult(s, safeSql, null, err.message, type, retryable, durationMs, '', boundValues);
      resultsByStep.set(s.step, result);
      results.push(result);
    }
  }

  return results;
}

function makeResult(s, sql, rows, error, errorType, retryable, durationMs, resultSummary, boundValues) {
  return {
    step:          s.step,
    sql,
    db:            s.db,
    purpose:       s.purpose ?? '',
    rows:          rows,
    rowCount:      rows?.length ?? 0,
    error:         error,
    errorType:     errorType,
    retryable:     retryable,
    durationMs,
    resultSummary,
    boundValues,
    depends_on:    s.depends_on ?? null,
  };
}
