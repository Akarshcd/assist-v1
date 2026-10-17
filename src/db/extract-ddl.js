/**
 * DDL Extraction — parses local db-scripts SQL files (no live DB connection needed).
 *
 * Schema names are stored as placeholders {CRM_SCHEMA} and {HRM_SCHEMA} in chunk_text
 * so the codebase never hardcodes a schema number. The embedding step strips placeholders
 * before calling the embedding API (vectors are schema-agnostic). At query time,
 * retrieve.js substitutes the actual env-var values before sending DDL to the LLM.
 *
 * Run: npm run extract-ddl
 * Output: src/db/ddl-chunks.json
 */

import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_SCRIPTS = path.resolve(__dirname, '../../db-scripts');

// Only these 4 files — CRM and HRM, public + tenant schemas (prod only)
const SOURCES = [
  { file: `${DB_SCRIPTS}/crm/public.sql`,          dbLabel: 'crm', schemaPlaceholder: 'public' },
  { file: `${DB_SCRIPTS}/crm/schema_3.sql`,         dbLabel: 'crm', schemaPlaceholder: '{CRM_SCHEMA}' },
  { file: `${DB_SCRIPTS}/hrm/public.sql`,           dbLabel: 'hrm', schemaPlaceholder: 'public' },
  { file: `${DB_SCRIPTS}/hrm/schema_3(prod).sql`,   dbLabel: 'hrm', schemaPlaceholder: '{HRM_SCHEMA}' },
];

// All known hardcoded schema identifiers from the dump files → replace with placeholder
// This handles any FK references that cross into the tenant schema
const CRM_SCHEMA_ALIASES = ['schema_3'];
const HRM_SCHEMA_ALIASES = ['schema_3', 'schema_118', 'schema_172', 'schema_173', 'schema_1'];

function replaceSchemasWithPlaceholder(text, dbLabel) {
  let out = text;
  // Always replace tenant schema aliases for both DBs — cross-DB FK refs can appear anywhere
  for (const alias of CRM_SCHEMA_ALIASES) {
    out = out.split(`${alias}.`).join('{CRM_SCHEMA}.');
  }
  for (const alias of HRM_SCHEMA_ALIASES) {
    out = out.split(`${alias}.`).join('{HRM_SCHEMA}.');
  }
  return out;
}

function parseChunks(sql, dbLabel, schemaPlaceholder) {
  const chunks = [];
  const tableRegex = /CREATE TABLE (\S+)\s*\(([\s\S]*?)\);/g;
  let match;

  while ((match = tableRegex.exec(sql)) !== null) {
    const fullTableName = match[1]; // e.g. schema_3.people or public.auth
    const body = match[2];

    const parts = fullTableName.split('.');
    const rawSchema = parts.length > 1 ? parts[0] : null;
    const table_name = parts.length > 1 ? parts[1] : parts[0];

    // Determine which placeholder this table belongs to
    // public schema tables always stay as 'public'
    const isPublic = rawSchema === 'public' || (!rawSchema && schemaPlaceholder === 'public');
    const schema_name = isPublic ? 'public' : schemaPlaceholder;

    const lines = body.split('\n').map((l) => l.trim()).filter(Boolean);
    const columns = [];
    const primaryKeys = [];
    const foreignKeys = [];
    const crossSchemaRefs = new Set();

    for (const line of lines) {
      if (/^PRIMARY KEY\s*\(/i.test(line)) {
        const cols = line.match(/\(([^)]+)\)/)?.[1] ?? '';
        primaryKeys.push(...cols.split(',').map((c) => c.trim()));
        continue;
      }

      if (/^FOREIGN KEY\s*\(/i.test(line)) {
        const fromCol = line.match(/FOREIGN KEY\s*\(([^)]+)\)/i)?.[1]?.trim();
        const refFull = line.match(/REFERENCES\s+(\S+)\s*\(([^)]+)\)/i);
        if (refFull) {
          const refTable = refFull[1];
          const refCol = refFull[2].trim();
          const refSchema = refTable.includes('.') ? refTable.split('.')[0] : (rawSchema ?? 'public');
          // Replace hardcoded schema aliases in FK reference
          const refTablePlaceholdered = replaceSchemasWithPlaceholder(refTable, dbLabel);
          foreignKeys.push({ column: fromCol, references: `${refTablePlaceholdered}(${refCol})` });
          if (refSchema !== rawSchema && refSchema !== 'public') {
            crossSchemaRefs.add(dbLabel === 'crm' ? '{CRM_SCHEMA}' : '{HRM_SCHEMA}');
          }
        }
        continue;
      }

      if (/^(CONSTRAINT|UNIQUE|CHECK)/i.test(line)) continue;

      const colMatch = line.match(/^"?(\w+)"?\s+(.+)/);
      if (colMatch) {
        const colName = colMatch[1];
        const rest = colMatch[2];
        const typeMatch = rest.match(/^([A-Z][A-Z0-9 _]*(?:\([^)]*\))?)/i);
        const colType = typeMatch ? typeMatch[1].trim() : rest.split(' ')[0];
        const nullable = !/NOT NULL/i.test(rest);
        const hasPkInline = /PRIMARY KEY/i.test(rest);
        if (hasPkInline) primaryKeys.push(colName);
        columns.push({ name: colName, type: colType, nullable });
      }
    }

    const colLines = columns.map(
      (c) => `  ${c.name} ${c.type}${c.nullable ? '' : ' NOT NULL'}`
    );
    const pkLine = primaryKeys.length ? `  PRIMARY KEY (${primaryKeys.join(', ')})` : null;
    const fkLines = foreignKeys.map(
      (fk) => `  FOREIGN KEY (${fk.column}) REFERENCES ${fk.references}`
    );

    const chunkParts = [
      `-- ${dbLabel.toUpperCase()} | ${schema_name}.${table_name}`,
      `CREATE TABLE ${schema_name}.${table_name} (`,
      [...colLines, ...(pkLine ? [pkLine] : []), ...fkLines].join(',\n'),
      ');',
    ];

    if (crossSchemaRefs.size) {
      chunkParts.push(`-- CROSS-SCHEMA REFS: ${[...crossSchemaRefs].join(', ')}`);
    }

    // Replace any remaining hardcoded schema numbers in the full chunk text
    const rawChunkText = chunkParts.join('\n');
    const cleanChunkText = replaceSchemasWithPlaceholder(rawChunkText, dbLabel);

    chunks.push({
      schema_name,
      table_name,
      db_label: dbLabel,
      chunk_text: cleanChunkText,
      cross_schema_refs: [...crossSchemaRefs],
    });
  }

  return chunks;
}

function main() {
  const allChunks = [];

  for (const { file, dbLabel, schemaPlaceholder } of SOURCES) {
    console.log(`[extract-ddl] Parsing ${path.basename(file)} (${dbLabel}, schema→${schemaPlaceholder})...`);
    const sql = readFileSync(file, 'utf8');
    const chunks = parseChunks(sql, dbLabel, schemaPlaceholder);
    console.log(`  → ${chunks.length} tables`);
    allChunks.push(...chunks);
  }

  // Deduplicate: prefer later entries (prod > staging) on same db_label + table_name
  const seen = new Map();
  for (const c of allChunks) {
    seen.set(`${c.db_label}.${c.schema_name}.${c.table_name}`, c);
  }
  const deduped = [...seen.values()];

  const outPath = path.join(__dirname, 'ddl-chunks.json');
  writeFileSync(outPath, JSON.stringify(deduped, null, 2));
  console.log(`\n[extract-ddl] Done. ${deduped.length} unique chunks → ${outPath}`);
}

main();
