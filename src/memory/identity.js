import { crmSourceDb, hrmSourceDb } from '../db/connections.js';

/**
 * Resolve a session/user to their CRM user_id and HRM emp_id.
 * Called unconditionally at the start of every turn.
 *
 * Cross-DB bridge: schema_3.hrm_employees.crm_id = CRM public.auth.user_id
 *
 * @param {{ userId?: string, email?: string, sessionId: string }} ctx
 * @returns {Promise<{ crmUserId: number|null, employeeId: number|null, email: string|null }>}
 */
export async function resolveIdentity({ userId, email, sessionId }) {
  const result = { crmUserId: null, employeeId: null, email: email ?? null };

  if (!email && !userId) return result;

  await Promise.all([
    resolveCrmUser(email, userId).then((id) => { result.crmUserId = id; }).catch(() => {}),
    resolveHrmEmployee(email, userId).then((id) => { result.employeeId = id; }).catch(() => {}),
  ]);

  return result;
}

async function resolveCrmUser(email, userId) {
  // CRM: public.auth is the auth source; user_id is the stable identifier
  if (email) {
    const { rows } = await crmSourceDb.query(
      'SELECT user_id FROM public.auth WHERE email = $1 LIMIT 1',
      [email]
    );
    if (rows.length) return rows[0].user_id;
  }
  if (userId) {
    const { rows } = await crmSourceDb.query(
      'SELECT user_id FROM public.auth WHERE user_id = $1 LIMIT 1',
      [parseInt(userId, 10)]
    );
    if (rows.length) return rows[0].user_id;
  }
  return null;
}

async function resolveHrmEmployee(email, userId) {
  // HRM_SCHEMA from env (schema_3). Bridge: hrm_employees.crm_id = CRM public.auth.user_id
  const HRM_SCHEMA = process.env.HRM_SCHEMA ?? 'schema_3';
  if (email) {
    const { rows } = await hrmSourceDb.query(
      `SELECT e.emp_id
         FROM public.hrm_auth a
         JOIN ${HRM_SCHEMA}.hrm_employees e ON e.auth_id = a.auth_id
        WHERE a.email = $1
        LIMIT 1`,
      [email]
    );
    if (rows.length) return rows[0].emp_id;
  }
  // Fallback: look up via crm_id bridge column
  if (userId) {
    const { rows } = await hrmSourceDb.query(
      `SELECT emp_id FROM ${HRM_SCHEMA}.hrm_employees WHERE crm_id = $1 LIMIT 1`,
      [parseInt(userId, 10)]
    );
    if (rows.length) return rows[0].emp_id;
  }
  return null;
}
