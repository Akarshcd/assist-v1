// ── Global state ───────────────────────────────────────────────────────────────
let statsData      = null;
let allTurns       = [];   // for observability trace table
let traceFilter    = 'all';
let skillFilter    = 'all';
let intFilter      = 'All';
let chatSessionId  = null;
let chatTurnCount  = 0;
let chatSending    = false;

// ── Static data ────────────────────────────────────────────────────────────────
const SKILLS = [
  { name: 'Talk to DB',         icon: '🗄',  desc: 'Converts natural language questions into SQL and queries the database in real time.', status: 'active', triggers: null },
  { name: 'Chit-chat',          icon: '💬',  desc: 'Friendly conversational fallback for greetings and out-of-scope questions.',           status: 'active', triggers: null },
  { name: 'Skill Router',       icon: '⚡',  desc: 'LLM-powered gate that decides which skill should handle each incoming message.',       status: 'active', triggers: null },
  { name: 'DDL Retrieval',      icon: '🔍',  desc: 'Fetches the most relevant schema chunks from pgvector via cosine similarity.',         status: 'active', triggers: null },
  { name: 'SQL Planner',        icon: '📐',  desc: 'Produces an SQL execution plan with a confidence score before running queries.',       status: 'active', triggers: null },
  { name: 'SQL Executor',       icon: '▶',   desc: 'Read-only guard that runs SQL and captures rows, errors and retries.',                 status: 'active', triggers: null },
  { name: 'Response Writer',    icon: '✍',   desc: 'Validates query results against the question and writes the user-facing reply.',       status: 'active', triggers: null },
  { name: 'Clarifier',          icon: '❓',  desc: 'Asks clarifying questions when the user intent is ambiguous.',                        status: 'active', triggers: null },
  { name: 'WhatsApp relay',     icon: '📱',  desc: 'Routes incoming WhatsApp messages to the assistant and sends formatted replies.',     status: 'beta',   triggers: null },
  { name: 'Document reader',    icon: '📄',  desc: 'Reads uploaded documents and PDFs to answer questions against their content.',         status: 'inactive', triggers: null },
];

const INTEGRATIONS = [
  { name: 'PostgreSQL (CRM)',   icon: '🐘',  desc: 'CRM source database — read-only. Projects, tasks, contacts, clients.',              category: 'Database',     enabled: true,  connected: 'crm-db (read-only)' },
  { name: 'PostgreSQL (HRM)',   icon: '🐘',  desc: 'HRM source database — read-only. Employees, timesheets, invoices, leave.',          category: 'Database',     enabled: true,  connected: 'hrm-db (read-only)' },
  { name: 'Harness DB',         icon: '🗃',  desc: 'Sessions, episodic logs, traces and talk2db tables with pgvector.',                  category: 'Database',     enabled: true,  connected: 'harness-db + pgvector' },
  { name: 'Google Generative AI', icon: '✦', desc: 'Primary LLM for routing, rephrasing, SQL planning and response generation.',        category: 'AI',           enabled: true,  connected: 'gemini-2.0-flash' },
  { name: 'OpenAI',             icon: '◈',   desc: 'Fallback LLM provider via compatible API endpoint.',                                  category: 'AI',           enabled: false },
  { name: 'WhatsApp Business',  icon: '📱',  desc: 'Send and receive messages from users via WhatsApp.',                                  category: 'Messaging',    enabled: false },
  { name: 'Slack',              icon: '#',   desc: 'Post session summaries and alerts to Slack channels.',                                category: 'Messaging',    enabled: false },
  { name: 'Email (SMTP)',       icon: '✉',   desc: 'Send daily digests and incident reports via email.',                                  category: 'Messaging',    enabled: false },
  { name: 'Webhook',            icon: '⚡',  desc: 'Push session events to any external HTTP endpoint.',                                  category: 'Developer',    enabled: false },
  { name: 'REST API',           icon: '{}',  desc: 'Expose the assistant as a REST API for custom front-ends and integrations.',          category: 'Developer',    enabled: true,  connected: 'localhost:3000' },
];

const STATUS_CLASS = { active: 'green', beta: 'amber', inactive: 'red' };
const STATUS_LABEL = { active: 'Active', beta: 'Beta', inactive: 'Inactive' };

// ── Init ───────────────────────────────────────────────────────────────────────
(async function init() {
  // Set date header
  document.getElementById('dash-date').textContent =
    'Overview of Aura virtual assistant — ' + new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });

  // Set chat init time
  document.getElementById('chat-init-time').textContent = now();

  // Check health
  checkHealth();

  // Load stats
  loadStats();

  // Render static pages
  renderSkills();
  renderIntegrations();

  // Generate session ID for chat
  chatSessionId = 'aura-' + Date.now();
  document.getElementById('sn-id').textContent = chatSessionId;

  // Load turns for observability
  loadTurns();

  // Theme from localStorage
  const saved = localStorage.getItem('aura-theme');
  if (saved) applyTheme(saved);
})();

// ── Theme ──────────────────────────────────────────────────────────────────────
function toggleTheme() {
  const cur = document.documentElement.getAttribute('data-theme') || 'light';
  const next = cur === 'light' ? 'dark' : 'light';
  applyTheme(next);
  localStorage.setItem('aura-theme', next);
}

function applyTheme(t) {
  document.documentElement.setAttribute('data-theme', t);
  document.getElementById('theme-btn').textContent = t === 'light' ? '◑' : '○';
}

// ── Health ─────────────────────────────────────────────────────────────────────
async function checkHealth() {
  const dot = document.getElementById('health-dot');
  try {
    const r = await fetch('/health');
    const j = await r.json();
    if (j.status === 'ok') {
      dot.style.background = 'var(--green)';
    } else {
      dot.style.background = 'var(--amber)';
    }
  } catch {
    dot.style.background = 'var(--red)';
  }
}

// ── Stats ──────────────────────────────────────────────────────────────────────
async function loadStats() {
  try {
    const r = await fetch('/api/dashboard/stats');
    const data = await r.json();
    statsData = data;
    renderStats(data);
    renderSparkline(data.dailyCounts || []);
    renderRecentSessions(data.recentSessions || []);
    renderSkillDist(data.skills || [], 'skill-dist');
    renderObservability(data);
  } catch (e) {
    console.error('stats error', e);
  }
}

function fmt(n) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1_000)     return (n / 1_000).toFixed(1) + 'K';
  return String(n);
}

function renderStats(d) {
  document.getElementById('st-sess').textContent   = fmt(d.sessions.total);
  document.getElementById('st-sess-d').textContent = `↑ ${d.sessions.today} today`;
  document.getElementById('st-sess-d').className   = 'stat-delta up';

  document.getElementById('st-turns').textContent  = fmt(d.turns.total);
  document.getElementById('st-turns-d').textContent= `↑ ${d.turns.today} today`;
  document.getElementById('st-turns-d').className  = 'stat-delta up';

  document.getElementById('st-tokens').textContent = fmt(d.tokens.total);
  document.getElementById('st-tokens-d').textContent = `avg ${d.tokens.avg} / turn`;
  document.getElementById('st-tokens-d').className = 'stat-delta neu';

  const ms = d.latency.avg_ms;
  document.getElementById('st-lat').textContent    = ms ? ms + 'ms' : '—';
  document.getElementById('st-lat-d').textContent  = ms ? (ms < 500 ? '↓ fast' : ms < 1000 ? '↔ moderate' : '↑ slow') : '';
  document.getElementById('st-lat-d').className    = 'stat-delta ' + (ms < 500 ? 'up' : ms < 1000 ? 'neu' : 'down');
}

function renderSparkline(daily) {
  const wrap = document.getElementById('spark-wrap');
  // Ensure 12 slots (pad with 0 if fewer days)
  const today = new Date();
  const slots = [];
  for (let i = 11; i >= 0; i--) {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    const row = daily.find(r => r.day && r.day.startsWith(key));
    slots.push({ day: key, count: row ? +row.count : 0 });
  }
  const max = Math.max(...slots.map(s => s.count), 1);
  wrap.innerHTML = slots.map((s, i) => {
    const pct = Math.max((s.count / max) * 100, 2);
    const hi  = i === slots.length - 1 ? ' hi' : '';
    return `<div class="spark-bar${hi}" style="height:${pct}%" title="${s.day}: ${s.count} sessions"></div>`;
  }).join('');
}

function renderRecentSessions(sessions) {
  const el = document.getElementById('recent-sess');
  if (!sessions.length) { el.innerHTML = '<div class="loading">No sessions yet</div>'; return; }
  el.innerHTML = sessions.map(s => {
    const initials = (s.email || s.user_id || '??').slice(0, 2).toUpperCase();
    const preview  = s.last_message ? '"' + truncate(s.last_message, 40) + '"' : 'No messages yet';
    const ago      = timeAgo(s.created_at);
    const turns    = s.turn_count || 0;
    return `<div class="sess-row">
      <div class="sess-avatar">${initials}</div>
      <div class="sess-body">
        <div class="sess-id">${s.session_id}</div>
        <div class="sess-preview">${preview}</div>
      </div>
      <div class="sess-meta">
        <div class="sess-time">${ago}</div>
        <div class="sess-turns">${turns} turn${turns !== 1 ? 's' : ''}</div>
      </div>
    </div>`;
  }).join('');
}

function renderSkillDist(skills, targetId) {
  const el = document.getElementById(targetId);
  if (!skills.length) { el.innerHTML = '<div class="loading">No data yet</div>'; return; }
  const total = skills.reduce((s, r) => s + +r.count, 0) || 1;
  el.innerHTML = skills.map(s => {
    const pct = Math.round((+s.count / total) * 100);
    const label = s.skill === 'talk_to_db' ? 'Talk to DB' : s.skill === 'chit_chat' ? 'Chit-chat' : s.skill || 'Unknown';
    return `<div class="skill-dist-row">
      <div class="skill-dist-name">${label}</div>
      <div class="skill-dist-track"><div class="skill-dist-fill" style="width:${pct}%"></div></div>
      <div class="skill-dist-pct">${pct}%</div>
    </div>`;
  }).join('');
}

// ── Nav ────────────────────────────────────────────────────────────────────────
function nav(btn, pageId) {
  document.querySelectorAll('.nav-item').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  btn.classList.add('active');
  document.getElementById('page-' + pageId).classList.add('active');
  if (pageId === 'observability') renderObsTurns();
}

// ── Skills page ────────────────────────────────────────────────────────────────
function renderSkills() {
  renderSkillGrid(skillFilter);
}

function filterSkills(btn, f) {
  skillFilter = f;
  document.querySelectorAll('#skill-filters .filter-btn').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
  renderSkillGrid(f);
}

function renderSkillGrid(f) {
  const grid = document.getElementById('skill-grid');
  const items = f === 'all' ? SKILLS : SKILLS.filter(s => s.status === f);
  // Enrich trigger counts from statsData if available
  const tdbCount   = statsData ? +( statsData.skills.find(s => s.skill === 'talk_to_db')?.count || 0) : null;
  const ccCount    = statsData ? +( statsData.skills.find(s => s.skill === 'chit_chat')?.count  || 0) : null;
  grid.innerHTML = items.map(s => {
    let triggers = '—';
    if (s.name === 'Talk to DB' && tdbCount !== null) triggers = tdbCount;
    if (s.name === 'Chit-chat'  && ccCount  !== null) triggers = ccCount;
    return `<div class="skill-card">
      <div style="display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:12px">
        <div class="skill-icon">${s.icon}</div>
        <span class="badge ${STATUS_CLASS[s.status]}">${STATUS_LABEL[s.status]}</span>
      </div>
      <div class="skill-name">${s.name}</div>
      <div class="skill-desc">${s.desc}</div>
      <div class="skill-footer">
        <span class="skill-meta">${triggers !== '—' ? triggers + ' triggers' : 'No data yet'}</span>
        <button class="btn-cfg">Configure</button>
      </div>
    </div>`;
  }).join('');
}

// ── Integrations page ──────────────────────────────────────────────────────────
function renderIntegrations() {
  renderIntList(intFilter);
}

function filterInt(btn, f) {
  intFilter = f;
  document.querySelectorAll('#int-filters .filter-btn').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
  renderIntList(f);
}

function renderIntList(f) {
  const list   = document.getElementById('int-list');
  const items  = f === 'All' ? INTEGRATIONS : INTEGRATIONS.filter(i => i.category === f);
  list.innerHTML = items.map(i => {
    const connHtml = i.connected && i.enabled
      ? `<div class="int-connected">● Connected — ${i.connected}</div>` : '';
    return `<div class="int-row">
      <div class="int-icon">${i.icon}</div>
      <div class="int-body">
        <div class="int-name">${i.name}</div>
        <div class="int-desc">${i.desc}</div>
        ${connHtml}
      </div>
      <div style="display:flex;align-items:center;gap:8px">
        <span style="font-size:11px;font-weight:500;min-width:28px;text-align:right;color:${i.enabled ? 'var(--green)' : 'var(--ink3)'}">${i.enabled ? 'On' : 'Off'}</span>
        <label class="toggle">
          <input type="checkbox" ${i.enabled ? 'checked' : ''} onchange="toggleInt('${i.name}',this)">
          <span class="toggle-track"></span>
        </label>
      </div>
    </div>`;
  }).join('');
}

function toggleInt(name, cb) {
  const item = INTEGRATIONS.find(i => i.name === name);
  if (item) item.enabled = cb.checked;
  renderIntList(intFilter);
}

// ── Observability ──────────────────────────────────────────────────────────────
async function loadTurns() {
  // Fetch all sessions first, then pick up turns from statsData
  // For the trace table we load recent sessions turns
  try {
    const r = await fetch('/api/sessions');
    const sessions = await r.json();
    if (!sessions.length) { allTurns = []; return; }
    // Load turns for most recent 5 sessions
    const recent = sessions.slice(0, 5);
    const turnArrays = await Promise.all(
      recent.map(s => fetch(`/api/sessions/${s.session_id}/turns`).then(r => r.json()))
    );
    allTurns = turnArrays.flat();
  } catch { allTurns = []; }
}

function renderObservability(d) {
  if (!d) return;
  const tdbCount   = +(d.skills.find(s => s.skill === 'talk_to_db')?.count || 0);
  const ccCount    = +(d.skills.find(s => s.skill === 'chit_chat')?.count  || 0);
  document.getElementById('obs-turns').textContent = d.turns.today;
  document.getElementById('obs-tdb').textContent   = tdbCount;
  document.getElementById('obs-cc').textContent    = ccCount;
  document.getElementById('obs-tok').textContent   = d.tokens.avg || '—';
  renderSkillDist(d.skills, 'obs-skill-dist');
  renderObsTurns();
}

function filterTrace(btn, f) {
  traceFilter = f;
  document.querySelectorAll('#trace-filters .filter-btn').forEach(b => b.classList.remove('on'));
  btn.classList.add('on');
  renderObsTurns();
}

function renderObsTurns() {
  const wrap = document.getElementById('trace-table-wrap');
  let turns = allTurns;
  if (traceFilter !== 'all') turns = turns.filter(t => t.routed_skill === traceFilter);
  if (!turns.length) { wrap.innerHTML = '<div class="loading">No turns yet — send a message in the Sessions tab.</div>'; return; }
  const maxTokens = Math.max(...turns.map(t => +(t.tokens_in || 0) + +(t.tokens_out || 0)), 1);
  wrap.innerHTML = `<table class="trace-table">
    <thead><tr><th>Turn</th><th>Session</th><th>Message</th><th>Skill</th><th>Status</th><th>Time</th></tr></thead>
    <tbody>${turns.slice(0, 30).map(t => {
      const skill     = t.routed_skill || '—';
      const skillClass = skill === 'talk_to_db' ? 'teal' : skill === 'chit_chat' ? 'purple' : 'amber';
      const skillLabel = skill === 'talk_to_db' ? 'Talk to DB' : skill === 'chit_chat' ? 'Chit-chat' : skill;
      const status    = t.final_status || (t.assistant_answer ? 'answered' : '—');
      const sc        = status === 'answered' ? 'green' : status === 'failed_after_retries' ? 'red' : 'amber';
      return `<tr>
        <td style="font-weight:600;color:var(--ink);font-size:12px;font-variant-numeric:tabular-nums">#${t.turn_number || t.id || '?'}</td>
        <td style="font-size:11px;font-variant-numeric:tabular-nums;max-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${t.session_id || '—'}</td>
        <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${truncate(t.raw_message || '', 40)}</td>
        <td><span class="badge ${skillClass}" style="font-size:11px">${skillLabel}</span></td>
        <td><span class="badge ${sc}" style="font-size:11px">${status}</span></td>
        <td style="font-size:11.5px;font-variant-numeric:tabular-nums">${t.created_at ? fmtTime(t.created_at) : '—'}</td>
      </tr>`;
    }).join('')}</tbody>
  </table>`;
}

// ── Chat / Sessions ────────────────────────────────────────────────────────────
function handleChip(el) {
  document.getElementById('chat-in').value = el.textContent;
  chatSend();
}

function onChatKey(e) {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); chatSend(); }
}

async function chatSend() {
  const input = document.getElementById('chat-in');
  const msg   = input.value.trim();
  if (!msg || chatSending) return;
  input.value = '';
  chatSending = true;
  document.getElementById('chat-send').disabled = true;

  chatTurnCount++;
  document.getElementById('sn-turns').textContent = chatTurnCount;

  addMsg('user', msg);

  // Show typing
  const typingId = 'typing-' + Date.now();
  const chatMsgs = document.getElementById('chat-msgs');
  const typingEl = document.createElement('div');
  typingEl.id = typingId;
  typingEl.className = 'msg bot';
  typingEl.innerHTML = `<div class="msg-bubble" style="color:var(--ink3)">Thinking…</div>`;
  chatMsgs.appendChild(typingEl);
  chatMsgs.scrollTop = chatMsgs.scrollHeight;

  try {
    const r = await fetch('/turn', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: msg, sessionId: chatSessionId, userId: 'aura-user' }),
    });
    const data = await r.json();

    // Remove typing indicator
    const te = document.getElementById(typingId);
    if (te) te.remove();

    // Update session info
    document.getElementById('sn-skill').textContent  = data.skill === 'talk_to_db' ? 'Talk to DB' : data.skill === 'chit_chat' ? 'Chit-chat' : data.skill || '—';
    document.getElementById('sn-status').textContent = data.finalStatus || 'answered';

    // Render response
    let bubbleContent = data.answer || 'No response.';
    if (data.meta?.sql) {
      bubbleContent += `\n\n<div class="msg-tbl-wrap">
        <div style="font-size:10.5px;color:var(--ink3);margin-bottom:4px;font-family:monospace;word-break:break-all">${escHtml(data.meta.sql)}</div>
      </div>`;
    }
    if (data.meta?.rowCount !== undefined && data.meta.rowCount !== null) {
      bubbleContent += `\n\n<span style="font-size:11px;color:var(--ink3)">${data.meta.rowCount} row${data.meta.rowCount !== 1 ? 's' : ''} returned</span>`;
    }

    addMsg('bot', bubbleContent, true);

    // Reload turns for observability
    await loadTurns();
    if (document.querySelector('[data-page="observability"]')?.classList.contains('active')) {
      renderObsTurns();
    }
  } catch (e) {
    const te = document.getElementById(typingId);
    if (te) te.remove();
    addMsg('bot', 'Error: could not reach the server. Is the backend running on port 3000?');
    document.getElementById('sn-status').textContent = 'Error';
  }

  chatSending = false;
  document.getElementById('chat-send').disabled = false;
  document.getElementById('chat-in').focus();
}

function addMsg(role, text, raw = false) {
  const chatMsgs = document.getElementById('chat-msgs');
  const el = document.createElement('div');
  el.className = 'msg ' + role;
  if (raw) {
    el.innerHTML = `<div class="msg-bubble">${text}</div><div class="msg-time">${now()}</div>`;
  } else {
    el.innerHTML = `<div class="msg-bubble">${escHtml(text)}</div><div class="msg-time">${now()}</div>`;
  }
  chatMsgs.appendChild(el);
  chatMsgs.scrollTop = chatMsgs.scrollHeight;
}

// ── Helpers ────────────────────────────────────────────────────────────────────
function now() {
  return new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
}

function truncate(s, n) {
  return s.length > n ? s.slice(0, n) + '…' : s;
}

function timeAgo(iso) {
  if (!iso) return '—';
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1)   return 'just now';
  if (m < 60)  return m + 'm ago';
  const h = Math.floor(m / 60);
  if (h < 24)  return h + 'h ago';
  return Math.floor(h / 24) + 'd ago';
}

function fmtTime(iso) {
  try {
    return new Date(iso).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  } catch { return '—'; }
}

function escHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
