// Core identity tables always injected into every Call 2 prompt.
// These tables are needed for identity resolution and cross-DB joins on every query.
// DO NOT include tables that are already in ddl_chunks (pgvector retrieves those).
// Uses {CRM_SCHEMA} / {HRM_SCHEMA} placeholders — call2-planner.js substitutes at runtime.

export function buildCoreContext() {
  return `
-- CROSS-DB BRIDGE: {HRM_SCHEMA}.hrm_employees.crm_id (HRM DB) = public.auth.user_id (CRM DB)
-- Identity resolution: to get a user's name → public.auth or {CRM_SCHEMA}.users (CRM DB)
--                      to get their HRM record → {HRM_SCHEMA}.hrm_employees via crm_id

-- CRM DB | public.auth  (primary user identity — user_id is the universal key)
CREATE TABLE public.auth (
  user_id   INTEGER NOT NULL,
  email     VARCHAR(255),
  tenent_id INTEGER
);

-- CRM DB | {CRM_SCHEMA}.users  (user profile + org structure)
CREATE TABLE {CRM_SCHEMA}.users (
  user_id           INTEGER NOT NULL,
  auth_id           INTEGER,
  email             VARCHAR(255),
  first_name        VARCHAR(100),
  last_name         VARCHAR(100),
  role              VARCHAR(50),
  status            VARCHAR(50),
  dept_id           INTEGER,
  direct_manager_id INTEGER
);

-- CRM DB | {CRM_SCHEMA}.employee  (employment details — joins to users via user_id)
CREATE TABLE {CRM_SCHEMA}.employee (
  employee_id       INTEGER,
  user_id           INTEGER,
  email_id          VARCHAR(100),
  date_of_joining   DATE,
  job_title         VARCHAR(100),
  department        VARCHAR(100),
  office_location   VARCHAR(100),
  manager           VARCHAR(100),
  employment_type   VARCHAR(100),
  date_of_last_promotion DATE
);

-- HRM DB | public.hrm_auth  (HRM-side user identity)
CREATE TABLE public.hrm_auth (
  auth_id   INTEGER NOT NULL,
  email     VARCHAR(255) NOT NULL
);
`.trim();
}
