/**
 * seed-fake-org.js
 *
 * Creates a `fake_org` schema in HARNESS_DB_URL and populates it with
 * ~100 employees worth of interconnected organizational data.
 *
 * Run: node src/db/seed-fake-org.js
 *
 * Tables (all in schema `fake_org`):
 *
 *   Core:
 *     organizations, departments, roles, users, user_roles, employees
 *
 *   HRM:
 *     leave_policies, leave_requests, attendance, payroll, assets,
 *     job_postings, applicants
 *
 *   CRM/Projects:
 *     clients, contacts, projects, project_members, tasks, timesheets,
 *     invoices, invoice_line_items, proposals, campaigns
 */

import 'dotenv/config';
import pg from 'pg';
import { faker } from '@faker-js/faker';

const { Pool } = pg;
const db = new Pool({ connectionString: process.env.HARNESS_DB_URL });

// ─── helpers ──────────────────────────────────────────────────────────────────

const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
const pickN = (arr, n) => faker.helpers.arrayElements(arr, n);
const randInt = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;
const randDate = (start, end) => faker.date.between({ from: start, to: end });
const fmt = (d) => d.toISOString().split('T')[0]; // 'YYYY-MM-DD'

async function run(sql, params = []) {
  return db.query(sql, params);
}

// ─── SCHEMA + TABLES ──────────────────────────────────────────────────────────

async function createSchema() {
  await run(`DROP SCHEMA IF EXISTS fake_org CASCADE`);
  await run(`CREATE SCHEMA fake_org`);
  console.log('[schema] fake_org created');
}

async function createTables() {
  const ddl = `
    -- ── organizations ─────────────────────────────────────────────────────────
    CREATE TABLE fake_org.organizations (
      org_id        SERIAL        PRIMARY KEY,
      name          TEXT          NOT NULL UNIQUE,
      industry      TEXT          NOT NULL,
      country       TEXT          NOT NULL,
      founded_year  INT,
      website       TEXT,
      created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );

    -- ── departments ────────────────────────────────────────────────────────────
    -- parent_dept_id → self FK allows arbitrary dept hierarchy
    CREATE TABLE fake_org.departments (
      dept_id         SERIAL      PRIMARY KEY,
      org_id          INT         NOT NULL REFERENCES fake_org.organizations(org_id) ON DELETE CASCADE,
      name            TEXT        NOT NULL,
      parent_dept_id  INT         REFERENCES fake_org.departments(dept_id) ON DELETE SET NULL,
      budget          NUMERIC(14,2),
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- ── roles ──────────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.roles (
      role_id     SERIAL  PRIMARY KEY,
      name        TEXT    NOT NULL UNIQUE,
      level       TEXT    NOT NULL CHECK (level IN ('junior','mid','senior','lead','manager','director','c-level')),
      dept_type   TEXT    -- e.g. 'engineering', 'sales', 'hr', 'finance', 'marketing', 'ops'
    );

    -- ── users ──────────────────────────────────────────────────────────────────
    -- every human (employee, client contact, applicant) gets a user row
    CREATE TABLE fake_org.users (
      user_id       SERIAL        PRIMARY KEY,
      email         TEXT          NOT NULL UNIQUE,
      first_name    TEXT          NOT NULL,
      last_name     TEXT          NOT NULL,
      phone         TEXT,
      avatar_url    TEXT,
      user_type     TEXT          NOT NULL CHECK (user_type IN ('employee','contact','applicant')),
      created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );

    -- ── user_roles ─────────────────────────────────────────────────────────────
    -- M2M: a user can hold multiple roles
    CREATE TABLE fake_org.user_roles (
      user_id   INT   NOT NULL REFERENCES fake_org.users(user_id)   ON DELETE CASCADE,
      role_id   INT   NOT NULL REFERENCES fake_org.roles(role_id)   ON DELETE CASCADE,
      PRIMARY KEY (user_id, role_id)
    );

    -- ── employees ──────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.employees (
      employee_id     SERIAL        PRIMARY KEY,
      user_id         INT           NOT NULL UNIQUE REFERENCES fake_org.users(user_id) ON DELETE CASCADE,
      org_id          INT           NOT NULL REFERENCES fake_org.organizations(org_id),
      dept_id         INT           NOT NULL REFERENCES fake_org.departments(dept_id),
      manager_id      INT           REFERENCES fake_org.employees(employee_id) ON DELETE SET NULL,
      job_title       TEXT          NOT NULL,
      employment_type TEXT          NOT NULL CHECK (employment_type IN ('full-time','part-time','contract','intern')),
      status          TEXT          NOT NULL CHECK (status IN ('active','on-leave','terminated')),
      hire_date       DATE          NOT NULL,
      termination_date DATE,
      salary          NUMERIC(12,2) NOT NULL,
      currency        CHAR(3)       NOT NULL DEFAULT 'USD'
    );

    -- ── leave_policies ─────────────────────────────────────────────────────────
    CREATE TABLE fake_org.leave_policies (
      policy_id     SERIAL  PRIMARY KEY,
      org_id        INT     NOT NULL REFERENCES fake_org.organizations(org_id),
      name          TEXT    NOT NULL,           -- 'Annual Leave', 'Sick Leave', etc.
      days_per_year INT     NOT NULL,
      carry_over    BOOLEAN NOT NULL DEFAULT FALSE
    );

    -- ── leave_requests ─────────────────────────────────────────────────────────
    CREATE TABLE fake_org.leave_requests (
      request_id    SERIAL        PRIMARY KEY,
      employee_id   INT           NOT NULL REFERENCES fake_org.employees(employee_id) ON DELETE CASCADE,
      policy_id     INT           NOT NULL REFERENCES fake_org.leave_policies(policy_id),
      start_date    DATE          NOT NULL,
      end_date      DATE          NOT NULL,
      days_taken    INT           NOT NULL,
      status        TEXT          NOT NULL CHECK (status IN ('pending','approved','rejected','cancelled')),
      approved_by   INT           REFERENCES fake_org.employees(employee_id) ON DELETE SET NULL,
      note          TEXT,
      created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );

    -- ── attendance ─────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.attendance (
      attendance_id   SERIAL      PRIMARY KEY,
      employee_id     INT         NOT NULL REFERENCES fake_org.employees(employee_id) ON DELETE CASCADE,
      work_date       DATE        NOT NULL,
      clock_in        TIME,
      clock_out       TIME,
      hours_worked    NUMERIC(4,2),
      status          TEXT        NOT NULL CHECK (status IN ('present','absent','late','half-day','holiday','weekend')),
      UNIQUE (employee_id, work_date)
    );

    -- ── payroll ────────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.payroll (
      payroll_id      SERIAL        PRIMARY KEY,
      employee_id     INT           NOT NULL REFERENCES fake_org.employees(employee_id) ON DELETE CASCADE,
      pay_period      TEXT          NOT NULL,   -- 'YYYY-MM'
      gross_salary    NUMERIC(12,2) NOT NULL,
      deductions      NUMERIC(12,2) NOT NULL DEFAULT 0,
      net_salary      NUMERIC(12,2) NOT NULL,
      paid_on         DATE,
      status          TEXT          NOT NULL CHECK (status IN ('pending','paid','failed')),
      UNIQUE (employee_id, pay_period)
    );

    -- ── assets ─────────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.assets (
      asset_id        SERIAL      PRIMARY KEY,
      org_id          INT         NOT NULL REFERENCES fake_org.organizations(org_id),
      assigned_to     INT         REFERENCES fake_org.employees(employee_id) ON DELETE SET NULL,
      asset_type      TEXT        NOT NULL CHECK (asset_type IN ('laptop','monitor','phone','tablet','accessory','vehicle','other')),
      brand           TEXT,
      model           TEXT,
      serial_number   TEXT        UNIQUE,
      purchase_date   DATE,
      status          TEXT        NOT NULL CHECK (status IN ('in-use','available','in-repair','retired'))
    );

    -- ── job_postings ───────────────────────────────────────────────────────────
    CREATE TABLE fake_org.job_postings (
      posting_id      SERIAL      PRIMARY KEY,
      org_id          INT         NOT NULL REFERENCES fake_org.organizations(org_id),
      dept_id         INT         NOT NULL REFERENCES fake_org.departments(dept_id),
      role_id         INT         NOT NULL REFERENCES fake_org.roles(role_id),
      title           TEXT        NOT NULL,
      description     TEXT,
      salary_min      NUMERIC(12,2),
      salary_max      NUMERIC(12,2),
      status          TEXT        NOT NULL CHECK (status IN ('open','closed','on-hold')),
      posted_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      closes_at       DATE
    );

    -- ── applicants ─────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.applicants (
      applicant_id    SERIAL      PRIMARY KEY,
      user_id         INT         NOT NULL REFERENCES fake_org.users(user_id) ON DELETE CASCADE,
      posting_id      INT         NOT NULL REFERENCES fake_org.job_postings(posting_id),
      stage           TEXT        NOT NULL CHECK (stage IN ('applied','screening','interview','offer','hired','rejected')),
      applied_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      resume_url      TEXT,
      notes           TEXT
    );

    -- ── clients ────────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.clients (
      client_id       SERIAL      PRIMARY KEY,
      org_id          INT         NOT NULL REFERENCES fake_org.organizations(org_id),
      company_name    TEXT        NOT NULL UNIQUE,
      industry        TEXT,
      country         TEXT,
      website         TEXT,
      tier            TEXT        CHECK (tier IN ('enterprise','mid-market','smb','startup')),
      created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- ── contacts ───────────────────────────────────────────────────────────────
    -- people at client companies
    CREATE TABLE fake_org.contacts (
      contact_id      SERIAL      PRIMARY KEY,
      user_id         INT         NOT NULL REFERENCES fake_org.users(user_id) ON DELETE CASCADE,
      client_id       INT         NOT NULL REFERENCES fake_org.clients(client_id) ON DELETE CASCADE,
      job_title       TEXT,
      is_primary      BOOLEAN     NOT NULL DEFAULT FALSE
    );

    -- ── projects ───────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.projects (
      project_id      SERIAL        PRIMARY KEY,
      org_id          INT           NOT NULL REFERENCES fake_org.organizations(org_id),
      client_id       INT           REFERENCES fake_org.clients(client_id) ON DELETE SET NULL,
      dept_id         INT           NOT NULL REFERENCES fake_org.departments(dept_id),
      name            TEXT          NOT NULL,
      description     TEXT,
      status          TEXT          NOT NULL CHECK (status IN ('planning','active','on-hold','completed','cancelled')),
      priority        TEXT          CHECK (priority IN ('low','medium','high','critical')),
      budget          NUMERIC(14,2),
      start_date      DATE,
      end_date        DATE,
      created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );

    -- ── project_members ────────────────────────────────────────────────────────
    CREATE TABLE fake_org.project_members (
      project_id    INT   NOT NULL REFERENCES fake_org.projects(project_id)  ON DELETE CASCADE,
      employee_id   INT   NOT NULL REFERENCES fake_org.employees(employee_id) ON DELETE CASCADE,
      role_on_project TEXT,   -- 'lead', 'member', 'reviewer'
      joined_at     DATE,
      PRIMARY KEY (project_id, employee_id)
    );

    -- ── tasks ──────────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.tasks (
      task_id         SERIAL        PRIMARY KEY,
      project_id      INT           NOT NULL REFERENCES fake_org.projects(project_id) ON DELETE CASCADE,
      assignee_id     INT           REFERENCES fake_org.employees(employee_id) ON DELETE SET NULL,
      parent_task_id  INT           REFERENCES fake_org.tasks(task_id) ON DELETE SET NULL,
      title           TEXT          NOT NULL,
      description     TEXT,
      status          TEXT          NOT NULL CHECK (status IN ('backlog','todo','in-progress','review','done','cancelled')),
      priority        TEXT          CHECK (priority IN ('low','medium','high','critical')),
      estimated_hours NUMERIC(6,2),
      due_date        DATE,
      created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );

    -- ── timesheets ─────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.timesheets (
      timesheet_id    SERIAL      PRIMARY KEY,
      employee_id     INT         NOT NULL REFERENCES fake_org.employees(employee_id) ON DELETE CASCADE,
      task_id         INT         NOT NULL REFERENCES fake_org.tasks(task_id) ON DELETE CASCADE,
      log_date        DATE        NOT NULL,
      hours_logged    NUMERIC(4,2) NOT NULL CHECK (hours_logged > 0),
      description     TEXT
    );

    -- ── invoices ───────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.invoices (
      invoice_id      SERIAL        PRIMARY KEY,
      project_id      INT           NOT NULL REFERENCES fake_org.projects(project_id),
      client_id       INT           NOT NULL REFERENCES fake_org.clients(client_id),
      invoice_number  TEXT          NOT NULL UNIQUE,
      issued_date     DATE          NOT NULL,
      due_date        DATE          NOT NULL,
      total_amount    NUMERIC(14,2) NOT NULL,
      paid_amount     NUMERIC(14,2) NOT NULL DEFAULT 0,
      status          TEXT          NOT NULL CHECK (status IN ('draft','sent','partial','paid','overdue','cancelled')),
      currency        CHAR(3)       NOT NULL DEFAULT 'USD'
    );

    -- ── invoice_line_items ─────────────────────────────────────────────────────
    CREATE TABLE fake_org.invoice_line_items (
      line_item_id    SERIAL        PRIMARY KEY,
      invoice_id      INT           NOT NULL REFERENCES fake_org.invoices(invoice_id) ON DELETE CASCADE,
      description     TEXT          NOT NULL,
      quantity        NUMERIC(8,2)  NOT NULL,
      unit_price      NUMERIC(12,2) NOT NULL,
      amount          NUMERIC(14,2) NOT NULL
    );

    -- ── proposals ──────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.proposals (
      proposal_id     SERIAL        PRIMARY KEY,
      org_id          INT           NOT NULL REFERENCES fake_org.organizations(org_id),
      client_id       INT           NOT NULL REFERENCES fake_org.clients(client_id),
      created_by      INT           NOT NULL REFERENCES fake_org.employees(employee_id),
      title           TEXT          NOT NULL,
      value           NUMERIC(14,2),
      status          TEXT          NOT NULL CHECK (status IN ('draft','sent','negotiating','won','lost')),
      sent_date       DATE,
      decision_date   DATE,
      notes           TEXT,
      created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );

    -- ── campaigns ──────────────────────────────────────────────────────────────
    CREATE TABLE fake_org.campaigns (
      campaign_id     SERIAL        PRIMARY KEY,
      org_id          INT           NOT NULL REFERENCES fake_org.organizations(org_id),
      owned_by        INT           NOT NULL REFERENCES fake_org.employees(employee_id),
      name            TEXT          NOT NULL,
      channel         TEXT          NOT NULL CHECK (channel IN ('email','social','paid','event','content','referral')),
      status          TEXT          NOT NULL CHECK (status IN ('planning','active','paused','completed')),
      budget          NUMERIC(12,2),
      spend           NUMERIC(12,2) DEFAULT 0,
      leads_generated INT           DEFAULT 0,
      start_date      DATE,
      end_date        DATE,
      created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
    );
  `;

  await run(ddl);
  console.log('[tables] all 20 tables created');
}

// ─── SEED DATA ────────────────────────────────────────────────────────────────

async function seedOrganization() {
  const res = await run(`
    INSERT INTO fake_org.organizations (name, industry, country, founded_year, website)
    VALUES ($1, $2, $3, $4, $5) RETURNING org_id
  `, ['ConceptDash Inc.', 'Technology', 'United States', 2015, 'https://conceptdash.com']);
  return res.rows[0].org_id;
}

const DEPT_NAMES = ['Engineering', 'Product', 'Design', 'Sales', 'Marketing', 'Finance', 'HR', 'Operations', 'Legal', 'Customer Success'];

async function seedDepartments(orgId) {
  const depts = [];
  for (const name of DEPT_NAMES) {
    const r = await run(`
      INSERT INTO fake_org.departments (org_id, name, budget)
      VALUES ($1, $2, $3) RETURNING dept_id
    `, [orgId, name, randInt(200_000, 2_000_000)]);
    depts.push({ dept_id: r.rows[0].dept_id, name });
  }

  // Add a few sub-departments (parent_dept_id set)
  const eng = depts.find(d => d.name === 'Engineering');
  for (const sub of ['Backend', 'Frontend', 'DevOps', 'QA']) {
    const r = await run(`
      INSERT INTO fake_org.departments (org_id, name, parent_dept_id, budget)
      VALUES ($1, $2, $3, $4) RETURNING dept_id
    `, [orgId, sub, eng.dept_id, randInt(100_000, 600_000)]);
    depts.push({ dept_id: r.rows[0].dept_id, name: sub });
  }

  console.log(`[depts] ${depts.length} departments`);
  return depts;
}

const ROLES = [
  { name: 'Software Engineer',         level: 'mid',      dept_type: 'engineering' },
  { name: 'Senior Software Engineer',  level: 'senior',   dept_type: 'engineering' },
  { name: 'Lead Engineer',             level: 'lead',     dept_type: 'engineering' },
  { name: 'Engineering Manager',       level: 'manager',  dept_type: 'engineering' },
  { name: 'DevOps Engineer',           level: 'mid',      dept_type: 'engineering' },
  { name: 'QA Engineer',               level: 'mid',      dept_type: 'engineering' },
  { name: 'Product Manager',           level: 'mid',      dept_type: 'product' },
  { name: 'Senior Product Manager',    level: 'senior',   dept_type: 'product' },
  { name: 'UX Designer',              level: 'mid',      dept_type: 'design' },
  { name: 'UI Designer',              level: 'junior',   dept_type: 'design' },
  { name: 'Sales Executive',           level: 'mid',      dept_type: 'sales' },
  { name: 'Account Manager',          level: 'senior',   dept_type: 'sales' },
  { name: 'Sales Director',            level: 'director', dept_type: 'sales' },
  { name: 'Marketing Specialist',      level: 'mid',      dept_type: 'marketing' },
  { name: 'Content Strategist',        level: 'mid',      dept_type: 'marketing' },
  { name: 'Finance Analyst',           level: 'mid',      dept_type: 'finance' },
  { name: 'Finance Manager',           level: 'manager',  dept_type: 'finance' },
  { name: 'HR Specialist',             level: 'mid',      dept_type: 'hr' },
  { name: 'HR Manager',                level: 'manager',  dept_type: 'hr' },
  { name: 'Operations Manager',        level: 'manager',  dept_type: 'ops' },
  { name: 'Legal Counsel',             level: 'senior',   dept_type: 'legal' },
  { name: 'Customer Success Manager',  level: 'mid',      dept_type: 'ops' },
  { name: 'CTO',                       level: 'c-level',  dept_type: 'engineering' },
  { name: 'CEO',                       level: 'c-level',  dept_type: 'ops' },
  { name: 'CFO',                       level: 'c-level',  dept_type: 'finance' },
  { name: 'Intern',                    level: 'junior',   dept_type: 'engineering' },
];

async function seedRoles() {
  const result = [];
  for (const r of ROLES) {
    const res = await run(`
      INSERT INTO fake_org.roles (name, level, dept_type)
      VALUES ($1, $2, $3) RETURNING role_id
    `, [r.name, r.level, r.dept_type]);
    result.push({ role_id: res.rows[0].role_id, ...r });
  }
  console.log(`[roles] ${result.length} roles`);
  return result;
}

async function seedUsersAndEmployees(orgId, depts, roles) {
  const employees = [];
  const usedEmails = new Set();
  const mainDepts = depts.filter(d => !['Backend', 'Frontend', 'DevOps', 'QA'].includes(d.name));
  const engSubDepts = depts.filter(d => ['Backend', 'Frontend', 'DevOps', 'QA'].includes(d.name));

  // Dept → matching roles map
  const deptRoleMap = {
    'Engineering': roles.filter(r => r.dept_type === 'engineering'),
    'Backend': roles.filter(r => ['Software Engineer','Senior Software Engineer','Lead Engineer','Engineering Manager'].includes(r.name)),
    'Frontend': roles.filter(r => ['Software Engineer','Senior Software Engineer','Lead Engineer','Engineering Manager'].includes(r.name)),
    'DevOps': roles.filter(r => r.name === 'DevOps Engineer' || r.level === 'lead'),
    'QA': roles.filter(r => r.name === 'QA Engineer'),
    'Product': roles.filter(r => r.dept_type === 'product'),
    'Design': roles.filter(r => r.dept_type === 'design'),
    'Sales': roles.filter(r => r.dept_type === 'sales'),
    'Marketing': roles.filter(r => r.dept_type === 'marketing'),
    'Finance': roles.filter(r => r.dept_type === 'finance'),
    'HR': roles.filter(r => r.dept_type === 'hr'),
    'Operations': roles.filter(r => r.dept_type === 'ops'),
    'Legal': roles.filter(r => r.dept_type === 'legal'),
    'Customer Success': roles.filter(r => r.name === 'Customer Success Manager'),
  };

  for (let i = 0; i < 100; i++) {
    const firstName = faker.person.firstName();
    const lastName = faker.person.lastName();
    let email = `${firstName.toLowerCase()}.${lastName.toLowerCase()}@conceptdash.com`;
    if (usedEmails.has(email)) email = `${firstName.toLowerCase()}.${lastName.toLowerCase()}${i}@conceptdash.com`;
    usedEmails.add(email);

    const userRes = await run(`
      INSERT INTO fake_org.users (email, first_name, last_name, phone, user_type)
      VALUES ($1, $2, $3, $4, 'employee') RETURNING user_id
    `, [email, firstName, lastName, faker.phone.number()]);
    const userId = userRes.rows[0].user_id;

    // Pick a dept
    const dept = i === 0 ? depts.find(d => d.name === 'Operations')   // CEO goes to Ops
                : i === 1 ? depts.find(d => d.name === 'Engineering')  // CTO goes to Eng
                : i === 2 ? depts.find(d => d.name === 'Finance')      // CFO goes to Finance
                : pick([...mainDepts, ...engSubDepts]);

    // Pick role matching the dept
    const pool = deptRoleMap[dept.name] ?? roles;
    const role = (i === 0) ? roles.find(r => r.name === 'CEO')
               : (i === 1) ? roles.find(r => r.name === 'CTO')
               : (i === 2) ? roles.find(r => r.name === 'CFO')
               : pick(pool.length ? pool : roles);

    const employmentTypes = ['full-time', 'full-time', 'full-time', 'part-time', 'contract', 'intern'];
    const statuses = ['active', 'active', 'active', 'active', 'on-leave', 'terminated'];
    const hireDate = randDate('2016-01-01', '2024-06-01');
    const isTerminated = pick(statuses) === 'terminated' && i > 2;
    const salaryRange = { 'junior': [40000, 65000], 'mid': [65000, 100000], 'senior': [100000, 140000], 'lead': [130000, 160000], 'manager': [140000, 180000], 'director': [160000, 220000], 'c-level': [200000, 350000] };
    const [sMin, sMax] = salaryRange[role.level] ?? [50000, 100000];

    const empRes = await run(`
      INSERT INTO fake_org.employees
        (user_id, org_id, dept_id, job_title, employment_type, status, hire_date, termination_date, salary)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING employee_id
    `, [
      userId, orgId, dept.dept_id, role.name,
      i < 3 ? 'full-time' : pick(employmentTypes),
      isTerminated ? 'terminated' : (i < 3 ? 'active' : pick(['active','active','active','active','on-leave'])),
      fmt(hireDate),
      isTerminated ? fmt(randDate(hireDate, new Date())) : null,
      randInt(sMin, sMax)
    ]);
    const empId = empRes.rows[0].employee_id;

    // Assign role in user_roles
    await run(`INSERT INTO fake_org.user_roles (user_id, role_id) VALUES ($1, $2)`, [userId, role.role_id]);

    employees.push({ employee_id: empId, user_id: userId, dept_id: dept.dept_id, dept_name: dept.name, role, salary: randInt(sMin, sMax) });
  }

  // Wire up managers: each employee (except CEO) gets a manager from same or parent dept
  const ceoId = employees[0].employee_id;
  const ctoId = employees[1].employee_id;
  const cfoId = employees[2].employee_id;

  for (let i = 3; i < employees.length; i++) {
    const emp = employees[i];
    // Finance dept → CFO as manager; Engineering depts → CTO; others → CEO
    let managerId;
    if (['Finance'].includes(emp.dept_name)) managerId = cfoId;
    else if (['Engineering','Backend','Frontend','DevOps','QA','Product','Design'].includes(emp.dept_name)) managerId = ctoId;
    else managerId = ceoId;

    // 30% chance: pick a mid-level manager from same dept already in list
    const deptManagers = employees.slice(0, i).filter(e =>
      e.dept_id === emp.dept_id &&
      ['manager','lead','director'].includes(e.role.level)
    );
    if (deptManagers.length && Math.random() < 0.7) {
      managerId = pick(deptManagers).employee_id;
    }

    await run(`UPDATE fake_org.employees SET manager_id = $1 WHERE employee_id = $2`, [managerId, emp.employee_id]);
  }

  // CEO reports to no one (already null), CTO/CFO report to CEO
  await run(`UPDATE fake_org.employees SET manager_id = $1 WHERE employee_id = $2`, [ceoId, ctoId]);
  await run(`UPDATE fake_org.employees SET manager_id = $1 WHERE employee_id = $2`, [ceoId, cfoId]);

  console.log(`[employees] 100 employees, manager tree wired`);
  return employees;
}

async function seedLeavePolicies(orgId) {
  const policies = [
    { name: 'Annual Leave',      days_per_year: 20, carry_over: true },
    { name: 'Sick Leave',        days_per_year: 10, carry_over: false },
    { name: 'Maternity Leave',   days_per_year: 90, carry_over: false },
    { name: 'Paternity Leave',   days_per_year: 14, carry_over: false },
    { name: 'Unpaid Leave',      days_per_year: 30, carry_over: false },
    { name: 'Bereavement Leave', days_per_year: 5,  carry_over: false },
    { name: 'Study Leave',       days_per_year: 7,  carry_over: false },
  ];
  const result = [];
  for (const p of policies) {
    const r = await run(`
      INSERT INTO fake_org.leave_policies (org_id, name, days_per_year, carry_over)
      VALUES ($1, $2, $3, $4) RETURNING policy_id
    `, [orgId, p.name, p.days_per_year, p.carry_over]);
    result.push({ policy_id: r.rows[0].policy_id, ...p });
  }
  console.log(`[leave_policies] ${result.length} policies`);
  return result;
}

async function seedLeaveRequests(employees, policies) {
  const statuses = ['approved', 'approved', 'pending', 'rejected', 'cancelled'];
  let count = 0;
  const activeEmps = employees.filter(e => e.role.level !== 'c-level');

  for (const emp of activeEmps) {
    const numRequests = randInt(1, 4);
    for (let i = 0; i < numRequests; i++) {
      const policy = pick(policies);
      const startDate = randDate('2024-01-01', '2025-10-01');
      const days = randInt(1, Math.min(7, policy.days_per_year));
      const endDate = new Date(startDate);
      endDate.setDate(endDate.getDate() + days - 1);

      const status = pick(statuses);
      const approver = pick(employees.filter(e => e.employee_id !== emp.employee_id && ['manager','director','c-level'].includes(e.role.level)));

      await run(`
        INSERT INTO fake_org.leave_requests
          (employee_id, policy_id, start_date, end_date, days_taken, status, approved_by)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
      `, [emp.employee_id, policy.policy_id, fmt(startDate), fmt(endDate), days, status, approver?.employee_id ?? null]);
      count++;
    }
  }
  console.log(`[leave_requests] ${count} records`);
}

async function seedAttendance(employees) {
  let count = 0;
  const activeEmps = employees.filter((_, i) => i < 40); // last 30 working days for 40 employees to keep it manageable

  const today = new Date('2026-10-16');
  const workDays = [];
  for (let d = new Date('2026-09-01'); d <= today; d.setDate(d.getDate() + 1)) {
    const day = d.getDay();
    if (day !== 0 && day !== 6) workDays.push(fmt(new Date(d)));
  }

  for (const emp of activeEmps) {
    for (const day of workDays) {
      const r = Math.random();
      let status, clockIn, clockOut, hours;
      if (r < 0.78) {
        status = 'present';
        clockIn = `0${randInt(8,9)}:${randInt(0,5)}${randInt(0,9)}`;
        clockOut = `1${randInt(7,9)}:${randInt(0,5)}${randInt(0,9)}`;
        hours = (8 + Math.random()).toFixed(2);
      } else if (r < 0.87) {
        status = 'late';
        clockIn = `1${randInt(0,1)}:${randInt(0,5)}${randInt(0,9)}`;
        clockOut = `19:${randInt(0,5)}${randInt(0,9)}`;
        hours = (6 + Math.random() * 2).toFixed(2);
      } else if (r < 0.92) {
        status = 'absent'; clockIn = null; clockOut = null; hours = 0;
      } else {
        status = 'half-day'; clockIn = '09:00'; clockOut = '13:30'; hours = 4.5;
      }

      await run(`
        INSERT INTO fake_org.attendance (employee_id, work_date, clock_in, clock_out, hours_worked, status)
        VALUES ($1, $2, $3, $4, $5, $6)
        ON CONFLICT (employee_id, work_date) DO NOTHING
      `, [emp.employee_id, day, clockIn, clockOut, hours, status]);
      count++;
    }
  }
  console.log(`[attendance] ${count} records`);
}

async function seedPayroll(employees) {
  let count = 0;
  const months = ['2026-07','2026-08','2026-09','2026-10'];
  for (const emp of employees) {
    for (const month of months) {
      const gross = emp.salary / 12;
      const deductions = gross * 0.25;
      const net = gross - deductions;
      const isPaid = month !== '2026-10';
      await run(`
        INSERT INTO fake_org.payroll (employee_id, pay_period, gross_salary, deductions, net_salary, paid_on, status)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (employee_id, pay_period) DO NOTHING
      `, [emp.employee_id, month, gross.toFixed(2), deductions.toFixed(2), net.toFixed(2),
          isPaid ? fmt(new Date(`${month}-28`)) : null,
          isPaid ? 'paid' : 'pending']);
      count++;
    }
  }
  console.log(`[payroll] ${count} records`);
}

async function seedAssets(orgId, employees) {
  const types = ['laptop','laptop','laptop','monitor','phone','tablet','accessory','vehicle'];
  const brands = { laptop: ['Apple','Dell','Lenovo','HP'], monitor: ['LG','Dell','Samsung'], phone: ['Apple','Samsung','Google'], tablet: ['Apple','Samsung'], accessory: ['Logitech','Sony'], vehicle: ['Toyota','Ford'] };
  let count = 0;
  for (const emp of employees) {
    if (Math.random() < 0.85) {
      const assetType = pick(types);
      const brand = pick(brands[assetType] ?? ['Generic']);
      await run(`
        INSERT INTO fake_org.assets (org_id, assigned_to, asset_type, brand, model, serial_number, purchase_date, status)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `, [orgId, emp.employee_id, assetType, brand,
          faker.commerce.productName(),
          faker.string.alphanumeric(12).toUpperCase(),
          fmt(faker.date.between({ from: '2019-01-01', to: '2024-01-01' })),
          'in-use']);
      count++;
    }
  }
  // Some unassigned available assets
  for (let i = 0; i < 10; i++) {
    const assetType = pick(['laptop','monitor','phone']);
    const brand = pick(['Apple','Dell','LG']);
    await run(`
      INSERT INTO fake_org.assets (org_id, assigned_to, asset_type, brand, model, serial_number, purchase_date, status)
      VALUES ($1, NULL, $2, $3, $4, $5, $6, 'available')
    `, [orgId, assetType, brand, faker.commerce.productName(),
        faker.string.alphanumeric(12).toUpperCase(),
        fmt(faker.date.between({ from: '2022-01-01', to: '2024-01-01' }))]);
    count++;
  }
  console.log(`[assets] ${count} records`);
}

async function seedJobPostingsAndApplicants(orgId, depts, roles) {
  const postings = [];
  for (let i = 0; i < 12; i++) {
    const role = pick(roles.filter(r => !['c-level'].includes(r.level)));
    const dept = pick(depts);
    const status = pick(['open','open','open','closed','on-hold']);
    const postedAt = randDate('2025-10-01', '2026-09-01');
    const closes = new Date(postedAt);
    closes.setDate(closes.getDate() + 60);

    const r = await run(`
      INSERT INTO fake_org.job_postings (org_id, dept_id, role_id, title, salary_min, salary_max, status, posted_at, closes_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING posting_id
    `, [orgId, dept.dept_id, role.role_id,
        role.name, randInt(50000, 90000), randInt(100000, 160000),
        status, postedAt.toISOString(), fmt(closes)]);
    postings.push(r.rows[0].posting_id);
  }

  const usedEmails = new Set();
  let appCount = 0;
  for (const postingId of postings) {
    const numApplicants = randInt(3, 10);
    for (let i = 0; i < numApplicants; i++) {
      const firstName = faker.person.firstName();
      const lastName = faker.person.lastName();
      let email = faker.internet.email({ firstName, lastName });
      if (usedEmails.has(email)) email = `${firstName.toLowerCase()}${randInt(100,999)}@${faker.internet.domainName()}`;
      usedEmails.add(email);

      const uRes = await run(`
        INSERT INTO fake_org.users (email, first_name, last_name, phone, user_type)
        VALUES ($1, $2, $3, $4, 'applicant') RETURNING user_id
      `, [email, firstName, lastName, faker.phone.number()]);

      const stages = ['applied','applied','screening','interview','offer','hired','rejected'];
      await run(`
        INSERT INTO fake_org.applicants (user_id, posting_id, stage, applied_at)
        VALUES ($1, $2, $3, $4)
      `, [uRes.rows[0].user_id, postingId, pick(stages), randDate('2025-10-01', '2026-10-01').toISOString()]);
      appCount++;
    }
  }
  console.log(`[job_postings] ${postings.length} postings, ${appCount} applicants`);
  return postings;
}

async function seedClients(orgId) {
  const clients = [];
  const tiers = ['enterprise','mid-market','smb','startup'];
  for (let i = 0; i < 20; i++) {
    const name = faker.company.name() + (i > 0 ? ` ${i}` : ''); // ensure uniqueness
    const r = await run(`
      INSERT INTO fake_org.clients (org_id, company_name, industry, country, website, tier)
      VALUES ($1, $2, $3, $4, $5, $6) RETURNING client_id
    `, [orgId, name, faker.commerce.department(), faker.location.country(),
        faker.internet.url(), pick(tiers)]);
    clients.push(r.rows[0].client_id);
  }

  // Seed contacts (client-side users)
  let contactCount = 0;
  for (const clientId of clients) {
    const n = randInt(1, 3);
    for (let i = 0; i < n; i++) {
      const firstName = faker.person.firstName();
      const lastName = faker.person.lastName();
      const email = faker.internet.email({ firstName, lastName });
      const uRes = await run(`
        INSERT INTO fake_org.users (email, first_name, last_name, phone, user_type)
        VALUES ($1, $2, $3, $4, 'contact') RETURNING user_id
        ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email RETURNING user_id
      `, [email, firstName, lastName, faker.phone.number()]);
      await run(`
        INSERT INTO fake_org.contacts (user_id, client_id, job_title, is_primary)
        VALUES ($1, $2, $3, $4)
      `, [uRes.rows[0].user_id, clientId, faker.person.jobTitle(), i === 0]);
      contactCount++;
    }
  }
  console.log(`[clients] ${clients.length} clients, ${contactCount} contacts`);
  return clients;
}

async function seedProjectsAndTasks(orgId, employees, depts, clients) {
  const projectNames = [
    'CRM Overhaul', 'Mobile App v2', 'Data Pipeline', 'Brand Refresh', 'Cloud Migration',
    'Sales Automation', 'HR Portal', 'Analytics Dashboard', 'API Gateway', 'Customer Portal',
    'Security Audit', 'ERP Integration', 'DevOps Revamp', 'Marketing Automation', 'Compliance Engine',
    'Billing System', 'Inventory Module', 'Reporting Suite', 'Identity Platform', 'AI Assistant'
  ];
  const projects = [];

  for (let i = 0; i < projectNames.length; i++) {
    const dept = pick(depts);
    const client = Math.random() < 0.7 ? pick(clients) : null;
    const startDate = randDate('2024-01-01', '2025-06-01');
    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + randInt(60, 365));

    const r = await run(`
      INSERT INTO fake_org.projects (org_id, client_id, dept_id, name, status, priority, budget, start_date, end_date)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING project_id
    `, [orgId, client, dept.dept_id, projectNames[i],
        pick(['planning','active','active','active','on-hold','completed','cancelled']),
        pick(['low','medium','high','high','critical']),
        randInt(50_000, 500_000),
        fmt(startDate), fmt(endDate)]);
    const projectId = r.rows[0].project_id;

    // Project members (3-8 employees)
    const members = pickN(employees, randInt(3, 8));
    for (const [idx, mem] of members.entries()) {
      await run(`
        INSERT INTO fake_org.project_members (project_id, employee_id, role_on_project, joined_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT DO NOTHING
      `, [projectId, mem.employee_id, idx === 0 ? 'lead' : pick(['member','member','reviewer']), fmt(startDate)]);
    }

    // Tasks (5-15 per project)
    const taskIds = [];
    const numTasks = randInt(5, 15);
    for (let t = 0; t < numTasks; t++) {
      const assignee = pick(members);
      const dueDate = new Date(startDate);
      dueDate.setDate(dueDate.getDate() + randInt(7, 200));

      const tr = await run(`
        INSERT INTO fake_org.tasks (project_id, assignee_id, title, status, priority, estimated_hours, due_date)
        VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING task_id
      `, [projectId, assignee.employee_id,
          faker.hacker.phrase(),
          pick(['backlog','todo','in-progress','in-progress','review','done','done','cancelled']),
          pick(['low','medium','high','critical']),
          randInt(2, 40),
          fmt(dueDate)]);
      taskIds.push({ task_id: tr.rows[0].task_id, assignee });
    }

    // A few sub-tasks (parent_task_id)
    for (let s = 0; s < randInt(2, 4); s++) {
      const parentTask = pick(taskIds);
      const assignee = pick(members);
      const dueDate = new Date(startDate);
      dueDate.setDate(dueDate.getDate() + randInt(7, 100));
      const sr = await run(`
        INSERT INTO fake_org.tasks (project_id, assignee_id, parent_task_id, title, status, priority, estimated_hours, due_date)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING task_id
      `, [projectId, assignee.employee_id, parentTask.task_id,
          faker.hacker.phrase(),
          pick(['todo','in-progress','done']),
          pick(['low','medium','high']),
          randInt(1, 10),
          fmt(dueDate)]);
      taskIds.push({ task_id: sr.rows[0].task_id, assignee });
    }

    projects.push({ project_id: projectId, client_id: client, tasks: taskIds, members });
  }

  // Timesheets: log hours against tasks
  let tsCount = 0;
  for (const proj of projects) {
    for (const task of proj.tasks) {
      const numLogs = randInt(1, 5);
      for (let l = 0; l < numLogs; l++) {
        const logDate = randDate('2024-06-01', '2026-10-01');
        await run(`
          INSERT INTO fake_org.timesheets (employee_id, task_id, log_date, hours_logged, description)
          VALUES ($1, $2, $3, $4, $5)
        `, [task.assignee.employee_id, task.task_id, fmt(logDate),
            (randInt(1, 8)).toFixed(2), faker.lorem.sentence()]);
        tsCount++;
      }
    }
  }

  console.log(`[projects] ${projects.length} projects with tasks and timesheets (${tsCount} timesheet rows)`);
  return projects;
}

async function seedInvoices(projects) {
  let invCount = 0, lineCount = 0;
  let invoiceNum = 1000;

  for (const proj of projects) {
    if (!proj.client_id) continue;
    const numInvoices = randInt(1, 3);
    for (let i = 0; i < numInvoices; i++) {
      const issuedDate = randDate('2024-06-01', '2026-09-01');
      const dueDate = new Date(issuedDate);
      dueDate.setDate(dueDate.getDate() + 30);
      const total = randInt(5000, 80000);
      const status = pick(['draft','sent','partial','paid','paid','overdue']);
      const paid = status === 'paid' ? total : status === 'partial' ? Math.floor(total * 0.5) : 0;

      const r = await run(`
        INSERT INTO fake_org.invoices (project_id, client_id, invoice_number, issued_date, due_date, total_amount, paid_amount, status)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING invoice_id
      `, [proj.project_id, proj.client_id, `INV-${++invoiceNum}`,
          fmt(issuedDate), fmt(dueDate), total, paid, status]);
      const invoiceId = r.rows[0].invoice_id;

      // Line items
      const numLines = randInt(2, 5);
      for (let l = 0; l < numLines; l++) {
        const qty = randInt(1, 20);
        const unit = randInt(100, 5000);
        await run(`
          INSERT INTO fake_org.invoice_line_items (invoice_id, description, quantity, unit_price, amount)
          VALUES ($1, $2, $3, $4, $5)
        `, [invoiceId, faker.commerce.productName(), qty, unit, qty * unit]);
        lineCount++;
      }
      invCount++;
    }
  }
  console.log(`[invoices] ${invCount} invoices, ${lineCount} line items`);
}

async function seedProposals(orgId, employees, clients) {
  const salesPeople = employees.filter(e => e.role.dept_type === 'sales');
  const proposers = salesPeople.length ? salesPeople : employees.slice(0, 10);
  let count = 0;

  for (const clientId of clients) {
    const numProposals = randInt(0, 2);
    for (let i = 0; i < numProposals; i++) {
      const creator = pick(proposers);
      const sentDate = randDate('2024-01-01', '2026-09-01');
      const decisionDate = new Date(sentDate);
      decisionDate.setDate(decisionDate.getDate() + randInt(14, 60));
      const status = pick(['draft','sent','sent','negotiating','won','won','lost']);

      await run(`
        INSERT INTO fake_org.proposals (org_id, client_id, created_by, title, value, status, sent_date, decision_date)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      `, [orgId, clientId, creator.employee_id,
          `${faker.company.buzzPhrase()} Proposal`,
          randInt(10000, 300000), status,
          ['draft'].includes(status) ? null : fmt(sentDate),
          ['won','lost'].includes(status) ? fmt(decisionDate) : null]);
      count++;
    }
  }
  console.log(`[proposals] ${count} records`);
}

async function seedCampaigns(orgId, employees) {
  const marketers = employees.filter(e => e.role.dept_type === 'marketing');
  const owners = marketers.length ? marketers : employees.slice(10, 20);
  const channels = ['email','social','paid','event','content','referral'];
  const names = ['Q4 Growth Push','Brand Awareness 2025','Inbound Revival','Product Launch Wave','Partner Referral Drive','Summer Re-engagement','Developer Outreach','Enterprise ABM'];
  let count = 0;

  for (const name of names) {
    const owner = pick(owners);
    const budget = randInt(5000, 80000);
    const spend = Math.floor(budget * Math.random());
    const startDate = randDate('2025-01-01', '2026-07-01');
    const endDate = new Date(startDate);
    endDate.setDate(endDate.getDate() + randInt(30, 120));

    await run(`
      INSERT INTO fake_org.campaigns (org_id, owned_by, name, channel, status, budget, spend, leads_generated, start_date, end_date)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    `, [orgId, owner.employee_id, name,
        pick(channels),
        pick(['planning','active','active','paused','completed']),
        budget, spend, randInt(0, 300),
        fmt(startDate), fmt(endDate)]);
    count++;
  }
  console.log(`[campaigns] ${count} records`);
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

async function main() {
  try {
    console.log('=== fake_org seed starting ===');

    await createSchema();
    await createTables();

    const orgId = await seedOrganization();
    const depts = await seedDepartments(orgId);
    const roles = await seedRoles();
    const employees = await seedUsersAndEmployees(orgId, depts, roles);
    const policies = await seedLeavePolicies(orgId);

    await seedLeaveRequests(employees, policies);
    await seedAttendance(employees);
    await seedPayroll(employees);
    await seedAssets(orgId, employees);
    await seedJobPostingsAndApplicants(orgId, depts, roles);

    const clients = await seedClients(orgId);
    const projects = await seedProjectsAndTasks(orgId, employees, depts, clients);

    await seedInvoices(projects);
    await seedProposals(orgId, employees, clients);
    await seedCampaigns(orgId, employees);

    console.log('\n=== fake_org seed complete ===');
  } catch (err) {
    console.error('[SEED ERROR]', err);
    process.exit(1);
  } finally {
    await db.end();
  }
}

main();
