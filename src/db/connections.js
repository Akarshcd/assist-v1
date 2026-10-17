import pg from 'pg';

const { Pool } = pg;

// Harness-owned memory DB (Supabase/Neon with pgvector)
export const harnessDb = new Pool({
  connectionString: process.env.HARNESS_DB_URL,
  max: 5,
  idleTimeoutMillis: 30000,
});

const SOURCE_SSL = { ssl: { rejectUnauthorized: false } }; // required for AWS RDS

const isProd = (process.env.DB_ENV ?? 'staging') === 'production';
const crmUrl = isProd ? process.env.PROD_CRM_SOURCE_DB_URL : process.env.CRM_SOURCE_DB_URL;
const hrmUrl = isProd ? process.env.PROD_HRM_SOURCE_DB_URL : process.env.HRM_SOURCE_DB_URL;

console.log(`[connections] DB_ENV=${process.env.DB_ENV ?? 'staging'} → using ${isProd ? 'PRODUCTION' : 'staging'} source DBs`);

// ConceptDash CRM source DB — read-only role, never write to this
export const crmSourceDb = new Pool({
  connectionString: crmUrl,
  ...SOURCE_SSL,
  max: 5,
  idleTimeoutMillis: 30000,
});

// ConceptDash HRM source DB — read-only role, never write to this
export const hrmSourceDb = new Pool({
  connectionString: hrmUrl,
  ...SOURCE_SSL,
  max: 5,
  idleTimeoutMillis: 30000,
});

/**
 * Check all three DB connections are reachable.
 * Returns { harness, crm, hrm } with true/false per connection.
 */
export async function checkConnections() {
  const results = { harness: false, crm: false, hrm: false };

  await Promise.all([
    harnessDb.query('SELECT 1').then(() => { results.harness = true; }).catch(() => {}),
    crmSourceDb.query('SELECT 1').then(() => { results.crm = true; }).catch(() => {}),
    hrmSourceDb.query('SELECT 1').then(() => { results.hrm = true; }).catch(() => {}),
  ]);

  return results;
}
