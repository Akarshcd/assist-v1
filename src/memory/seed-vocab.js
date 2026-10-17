/**
 * Seeds vocabulary_map with known alias → canonical term mappings.
 * canonical_term stores only the table name — schema is injected at query time
 * from CRM_SCHEMA / HRM_SCHEMA env vars so it never needs updating here.
 *
 * Run: npm run seed-vocab
 */

import 'dotenv/config';
import { harnessDb } from '../db/connections.js';

// Global mappings (user_id = NULL)
// canonical_term = bare table name only (no schema prefix)
// db = 'crm' | 'hrm'  — determines which schema env var to use at runtime
const SEEDS = [
  // Timesheets (HRM)
  { alias: 'task sheet',    canonical_term: 'employee_timesheet',  db: 'hrm', confidence: 1.0 },
  { alias: 'tasksheet',     canonical_term: 'employee_timesheet',  db: 'hrm', confidence: 1.0 },
  { alias: 'timesheet',     canonical_term: 'employee_timesheet',  db: 'hrm', confidence: 1.0 },
  { alias: 'time sheet',    canonical_term: 'employee_timesheet',  db: 'hrm', confidence: 1.0 },
  { alias: 'daily update',  canonical_term: 'daily_sheet_update',  db: 'hrm', confidence: 0.9 },

  // People / Contacts (CRM)
  { alias: 'contact',       canonical_term: 'people',              db: 'crm', confidence: 0.95 },
  { alias: 'lead',          canonical_term: 'people',              db: 'crm', confidence: 0.9  },
  { alias: 'client contact',canonical_term: 'people',              db: 'crm', confidence: 0.9  },
  { alias: 'person',        canonical_term: 'people',              db: 'crm', confidence: 0.85 },

  // Organizations / Clients (CRM)
  { alias: 'company',       canonical_term: 'organization',        db: 'crm', confidence: 0.95 },
  { alias: 'client',        canonical_term: 'organization',        db: 'crm', confidence: 0.9  },
  { alias: 'organisation',  canonical_term: 'organization',        db: 'crm', confidence: 1.0  },
  { alias: 'tenant',        canonical_term: 'tenents',             db: 'crm', confidence: 0.9  },

  // Projects (CRM)
  { alias: 'project',       canonical_term: 'projects',            db: 'crm', confidence: 1.0  },
  { alias: 'job',           canonical_term: 'projects',            db: 'crm', confidence: 0.8  },

  // Tasks (CRM)
  { alias: 'task',          canonical_term: 'tasks',               db: 'crm', confidence: 1.0  },
  { alias: 'to-do',         canonical_term: 'tasks',               db: 'crm', confidence: 0.9  },
  { alias: 'todo',          canonical_term: 'tasks',               db: 'crm', confidence: 0.9  },

  // Invoices (CRM)
  { alias: 'invoice',       canonical_term: 'invoices',            db: 'crm', confidence: 1.0  },
  { alias: 'bill',          canonical_term: 'invoices',            db: 'crm', confidence: 0.85 },
  { alias: 'purchase order',canonical_term: 'purchase_orders',     db: 'crm', confidence: 1.0  },
  { alias: 'PO',            canonical_term: 'purchase_orders',     db: 'crm', confidence: 0.9  },

  // Employees (HRM)
  { alias: 'employee',      canonical_term: 'hrm_employees',       db: 'hrm', confidence: 1.0  },
  { alias: 'staff',         canonical_term: 'hrm_employees',       db: 'hrm', confidence: 0.9  },
  { alias: 'worker',        canonical_term: 'hrm_employees',       db: 'hrm', confidence: 0.85 },

  // Leave (HRM)
  { alias: 'leave',         canonical_term: 'leave_policy',        db: 'hrm', confidence: 0.9  },
  { alias: 'leave request', canonical_term: 'leave_policy',        db: 'hrm', confidence: 0.95 },
  { alias: 'time off',      canonical_term: 'leave_policy',        db: 'hrm', confidence: 0.9  },
  { alias: 'vacation',      canonical_term: 'leave_policy',        db: 'hrm', confidence: 0.85 },

  // Proposals (CRM)
  { alias: 'proposal',      canonical_term: 'proposals',           db: 'crm', confidence: 1.0  },
  { alias: 'bid',           canonical_term: 'proposals',           db: 'crm', confidence: 0.85 },
  { alias: 'rfp',           canonical_term: 'rfps',                db: 'crm', confidence: 1.0  },
  { alias: 'request for proposal', canonical_term: 'rfps',         db: 'crm', confidence: 1.0  },

  // Campaigns (CRM)
  { alias: 'campaign',      canonical_term: 'campaign',            db: 'crm', confidence: 1.0  },
  { alias: 'email campaign',canonical_term: 'campaign',            db: 'crm', confidence: 0.95 },

  // Users (CRM)
  { alias: 'user',          canonical_term: 'users',               db: 'crm', confidence: 0.9  },
  { alias: 'team member',   canonical_term: 'users',               db: 'crm', confidence: 0.8  },
];

async function seed() {
  console.log(`[seed-vocab] Seeding ${SEEDS.length} vocabulary mappings...`);
  const client = await harnessDb.connect();
  try {
    // Wipe existing global seeds so stale schema-prefixed rows don't linger
    await client.query(`DELETE FROM vocabulary_map WHERE user_id IS NULL`);
    let inserted = 0;
    for (const row of SEEDS) {
      await client.query(
        `INSERT INTO vocabulary_map (alias, canonical_term, db, user_id, confidence)
         VALUES ($1, $2, $3, NULL, $4)
         ON CONFLICT (alias, user_id) DO UPDATE
           SET canonical_term = EXCLUDED.canonical_term,
               db             = EXCLUDED.db,
               confidence     = EXCLUDED.confidence,
               updated_at     = now()`,
        [row.alias.toLowerCase(), row.canonical_term, row.db, row.confidence]
      );
      inserted++;
    }
    console.log(`[seed-vocab] Done. ${inserted} rows upserted.`);
  } finally {
    client.release();
    await harnessDb.end();
  }
}

seed().catch((err) => {
  console.error('[seed-vocab] Failed:', err.message);
  process.exit(1);
});
