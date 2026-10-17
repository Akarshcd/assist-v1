import { GoogleGenAI } from '@google/genai';
import { harnessDb } from '../../db/connections.js';

const CRM_SCHEMA = process.env.CRM_SCHEMA ?? 'schema_3';
const HRM_SCHEMA = process.env.HRM_SCHEMA ?? 'schema_3';

function injectSchemas(text) {
  return text
    .split('{CRM_SCHEMA}').join(CRM_SCHEMA)
    .split('{HRM_SCHEMA}').join(HRM_SCHEMA);
}

const EMBEDDING_MODEL = 'gemini-embedding-001';
const OUTPUT_DIM = 768;
const TOP_K = 6; // retrieve top-6, enough context without overloading the SQL gen prompt

let genai = null;
function getGenAI() {
  if (!genai) genai = new GoogleGenAI({ apiKey: process.env.LLM_PRIMARY_KEY });
  return genai;
}

/**
 * Embed the user question + resolved vocab terms, then similarity-search ddl_chunks.
 * Returns top-K chunks with cross-schema warning flags attached.
 *
 * @param {string} message — original user question
 * @param {Array<{alias, canonical_term}>} vocabMatches — from resolveVocabulary()
 * @returns {Promise<Array<{schema_name, table_name, db_label, chunk_text, cross_schema_refs, similarity}>>}
 */
export async function retrieveDDL(message, vocabMatches = []) {
  // Enrich query with canonical terms so embedding is closer to the DDL text
  const vocabHint = vocabMatches.length
    ? `\nRelevant tables: ${vocabMatches.map((v) => v.canonical_term).join(', ')}`
    : '';
  const queryText = message + vocabHint;

  // Embed the query
  const res = await getGenAI().models.embedContent({
    model: EMBEDDING_MODEL,
    contents: queryText,
    config: {
      taskType: 'RETRIEVAL_QUERY',
      outputDimensionality: OUTPUT_DIM,
    },
  });
  const queryVector = `[${res.embeddings[0].values.join(',')}]`;

  // Cosine similarity search
  const { rows } = await harnessDb.query(
    `SELECT
        schema_name,
        table_name,
        db_label,
        chunk_text,
        cross_schema_refs,
        1 - (embedding <=> $1::vector) AS similarity
     FROM ddl_chunks
     ORDER BY embedding <=> $1::vector
     LIMIT $2`,
    [queryVector, TOP_K]
  );

  // Inject real schema names and flag cross-schema hazards
  return rows.map((row) => ({
    ...row,
    chunk_text: injectSchemas(row.chunk_text),
    hasCrossSchemaRefs: row.cross_schema_refs && row.cross_schema_refs.length > 0,
  }));
}
