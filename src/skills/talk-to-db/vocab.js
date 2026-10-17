import { harnessDb } from '../../db/connections.js';

const CRM_SCHEMA = process.env.CRM_SCHEMA ?? 'schema_3';
const HRM_SCHEMA = process.env.HRM_SCHEMA ?? 'schema_3';

function qualifiedTerm(table, db) {
  const schema = db === 'hrm' ? HRM_SCHEMA : CRM_SCHEMA;
  return `${schema}.${table}`;
}

/**
 * Resolve alias terms in the user's message against vocabulary_map.
 * canonical_term in the DB is a bare table name; schema is injected here
 * from CRM_SCHEMA / HRM_SCHEMA env vars so the DB stays schema-agnostic.
 *
 * Returns an array of matches: { alias, canonical_term, db, confidence }
 * where canonical_term is the fully-qualified schema.table string.
 */
export async function resolveVocabulary(message, userId = null) {
  const { rows } = await harnessDb.query(
    `SELECT alias, canonical_term, db, confidence
       FROM vocabulary_map
      WHERE (user_id = $1 OR user_id IS NULL)
      ORDER BY
        CASE WHEN user_id = $1 THEN 0 ELSE 1 END,
        confidence DESC`,
    [userId]
  );

  const msgLower = message.toLowerCase();
  const matches = [];

  for (const row of rows) {
    if (msgLower.includes(row.alias.toLowerCase())) {
      matches.push({
        alias: row.alias,
        canonical_term: qualifiedTerm(row.canonical_term, row.db),
        db: row.db,
        confidence: row.confidence,
      });
    }
  }

  // Deduplicate by canonical_term (keep highest confidence)
  const seen = new Map();
  for (const m of matches) {
    if (!seen.has(m.canonical_term) || seen.get(m.canonical_term).confidence < m.confidence) {
      seen.set(m.canonical_term, m);
    }
  }

  return [...seen.values()];
}
