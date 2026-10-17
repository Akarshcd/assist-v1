/**
 * Embeds ddl-chunks.json using gemini-embedding-001 (dim=768 via Matryoshka)
 * and upserts into the ddl_chunks table on the harness DB.
 *
 * Skips tables whose chunk_text hasn't changed (content_hash check).
 * Safe to re-run after schema changes — only re-embeds what changed.
 *
 * Run: npm run embed-ddl
 */

import 'dotenv/config';
import { readFileSync } from 'fs';
import { createHash } from 'crypto';
import { fileURLToPath } from 'url';
import path from 'path';
import { GoogleGenAI } from '@google/genai';
import { harnessDb } from './connections.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const EMBEDDING_MODEL = 'gemini-embedding-001';
const OUTPUT_DIM = 768; // Matryoshka truncation — keeps storage lean on free-tier pgvector
const BATCH_SIZE = 5;   // AI Studio free tier: stay well under rate limits
const DELAY_MS = 1000;  // 1s between batches

function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function embedTexts(client, texts) {
  const results = [];
  for (const text of texts) {
    const res = await client.models.embedContent({
      model: EMBEDDING_MODEL,
      contents: text,
      config: {
        taskType: 'RETRIEVAL_DOCUMENT',
        outputDimensionality: OUTPUT_DIM,
      },
    });
    results.push(res.embeddings[0].values);
  }
  return results;
}

async function main() {
  const chunksPath = path.join(__dirname, 'ddl-chunks.json');
  const chunks = JSON.parse(readFileSync(chunksPath, 'utf8'));
  console.log(`[embed-ddl] Loaded ${chunks.length} chunks from ddl-chunks.json`);

  const gemini = new GoogleGenAI({ apiKey: process.env.LLM_PRIMARY_KEY });
  const db = harnessDb;

  // Load existing hashes so we can skip unchanged tables
  const { rows: existing } = await db.query(
    'SELECT schema_name, table_name, db_label, content_hash FROM ddl_chunks'
  );
  const existingMap = new Map(
    existing.map((r) => [`${r.db_label}.${r.schema_name}.${r.table_name}`, r.content_hash])
  );

  // Strip schema placeholders before embedding so vectors are schema-agnostic
  function stripPlaceholders(text) {
    return text
      .split('{CRM_SCHEMA}.').join('')
      .split('{HRM_SCHEMA}.').join('');
  }

  // Filter to only chunks that are new or changed
  const toEmbed = chunks.filter((c) => {
    const key = `${c.db_label}.${c.schema_name}.${c.table_name}`;
    const hash = sha256(c.chunk_text);
    return existingMap.get(key) !== hash;
  });

  if (toEmbed.length === 0) {
    console.log('[embed-ddl] All chunks up to date. Nothing to embed.');
    await db.end();
    return;
  }

  console.log(`[embed-ddl] ${toEmbed.length} chunks need embedding (${chunks.length - toEmbed.length} unchanged, skipped)`);

  let done = 0;
  for (let i = 0; i < toEmbed.length; i += BATCH_SIZE) {
    const batch = toEmbed.slice(i, i + BATCH_SIZE);
    const texts = batch.map((c) => stripPlaceholders(c.chunk_text));

    let embeddings;
    try {
      embeddings = await embedTexts(gemini, texts);
    } catch (err) {
      console.error(`[embed-ddl] Embedding failed for batch at index ${i}:`, err.message);
      // Wait longer on rate limit errors and retry once
      await sleep(5000);
      try {
        embeddings = await embedTexts(gemini, texts);
      } catch (retryErr) {
        console.error('[embed-ddl] Retry also failed, skipping batch:', retryErr.message);
        continue;
      }
    }

    for (let j = 0; j < batch.length; j++) {
      const chunk = batch[j];
      const embedding = embeddings[j];
      const hash = sha256(chunk.chunk_text);

      // pgvector expects the vector as a string like '[0.1,0.2,...]'
      const vectorStr = `[${embedding.join(',')}]`;

      await db.query(
        `INSERT INTO ddl_chunks
           (schema_name, table_name, db_label, chunk_text, embedding, cross_schema_refs, content_hash, updated_at)
         VALUES ($1, $2, $3, $4, $5::vector, $6, $7, now())
         ON CONFLICT (schema_name, table_name, db_label)
         DO UPDATE SET
           chunk_text        = EXCLUDED.chunk_text,
           embedding         = EXCLUDED.embedding,
           cross_schema_refs = EXCLUDED.cross_schema_refs,
           content_hash      = EXCLUDED.content_hash,
           updated_at        = now()`,
        [chunk.schema_name, chunk.table_name, chunk.db_label, chunk.chunk_text, vectorStr, chunk.cross_schema_refs, hash]
      );
    }

    done += batch.length;
    console.log(`[embed-ddl] ${done}/${toEmbed.length} embedded...`);

    if (i + BATCH_SIZE < toEmbed.length) await sleep(DELAY_MS);
  }

  console.log(`[embed-ddl] Done. ${done} chunks embedded into ddl_chunks.`);
  await db.end();
}

main().catch((err) => {
  console.error('[embed-ddl] Fatal:', err.message);
  process.exit(1);
});
