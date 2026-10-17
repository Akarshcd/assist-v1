// ─── Architecture definition ──────────────────────────────────────────────────
const ARCH = [
  {
    id: 'router',
    num: 'R',
    label: 'Router',
    type: 'LLM call',
    sub: 'Decide if message needs Talk2DB',
    phase: 'gate',
    implemented: true,
    decisions: [
      { when: 'skill ≠ "talk_to_db"', action: 'Route to chit-chat / none — exit pipeline' },
      { when: 'pending_clarification set', action: 'Skip router, jump straight to Call 1' },
    ],
  },
  {
    id: 'call1',
    num: '1',
    label: 'Call 1 · Rephrase / Clarify',
    type: 'LLM call',
    sub: 'Rephrase to standalone question, or ask for clarification',
    phase: 'rephrase',
    implemented: true,
    decisions: [
      { when: 'needs_clarification = true', action: 'Return questions to user — END TURN' },
      { when: 'message_type = "new_topic"', action: 'Clear pending_clarification, restart from Router' },
      { when: 'round > 2', action: 'Proceed with assumptions instead of asking again' },
    ],
  },
  {
    id: 'retrieval',
    num: 'V',
    label: 'Retrieval',
    type: 'pgvector (no LLM)',
    sub: 'Top-K DDL chunks via cosine similarity',
    phase: 'retrieve',
    implemented: true,
    decisions: [],
  },
  {
    id: 'call2',
    num: '2',
    label: 'Call 2 · Planner',
    type: 'LLM call',
    sub: 'Produce SQL execution plan with confidence score',
    phase: 'generate_sql',
    implemented: true,
    decisions: [
      { when: 'status = "no_match"', action: 'Skip Executor → Call 3 with no_result context' },
      { when: 'confidence < 0.6', action: 'Send back to Call 1 as clarification (once per turn)' },
      { when: 'SQL error + attempt < 3', action: 'Retry with failed SQL + error fed back' },
      { when: 'attempt = 3 still failing', action: 'FAILURE path — template message, log attempt history' },
    ],
  },
  {
    id: 'executor',
    num: 'E',
    label: 'Executor',
    type: 'Code (no LLM)',
    sub: 'Read-only guard, run SQL, capture rows / errors',
    phase: 'execute',
    implemented: true,
    decisions: [
      { when: 'Non-SELECT detected', action: 'Reject immediately — do not execute' },
      { when: 'depends_on step returned 0 rows', action: 'Skip dependent step' },
      { when: 'SQL error type = sql_error', action: 'Signal Planner to retry (retryable)' },
      { when: 'SQL error type = timeout / permission', action: 'Do not retry — go to failure path' },
    ],
  },
  {
    id: 'call3',
    num: '3',
    label: 'Call 3 · Respond / Validate',
    type: 'LLM call',
    sub: 'Validate data against question, write user-facing reply',
    phase: 'generate_response',
    implemented: true,
    decisions: [
      { when: 'Data does not answer the question', action: 'Use no_relevant_data, offer alternatives' },
      { when: 'Empty result set', action: 'Explain plainly, suggest alternatives' },
    ],
  },
];

// ─── Global state ─────────────────────────────────────────────────────────────
let currentPage      = 'inspector';
let currentSbView    = 'pipe';
let currentSessionId = null;
let currentTurnId    = null;
let currentTrace     = [];
let currentTurnData  = null;
let currentTurns     = [];
let allSessions      = [];
let livePrompts      = { sql: '', respond: '' };
let currentSessionJson = null;   // full session JSON from /api/sessions/:id/json
let sessionJsonTurnTab = 0;      // which turn is active in the Session JSON view

// ─── Init ─────────────────────────────────────────────────────────────────────
(async function init() {
  wireRsz('rsz-nav',  '--nav',  'navW',  false, 180, 400);
  wireRsz('rsz-dock', '--dock', 'dockW', true,  280, 580);
  const nw = localStorage.getItem('navW');  if (nw) css('--nav', nw + 'px');
  const dw = localStorage.getItem('dockW'); if (dw) css('--dock', dw + 'px');

  document.getElementById('pipe-wrap').innerHTML = pipelineSVG('nav-');
  renderArchPage();
  await loadPrompts();
  await checkHealth();
  await loadSessions();
  newSession();
  setInterval(checkHealth, 15000);
  setInterval(() => loadSessions(true), 10000);
  setInterval(() => { if (currentSessionId && !currentTurnId) refreshTurns(); }, 3500);
})();

// ─── Page switching ────────────────────────────────────────────────────────────
function setPage(p) {
  currentPage = p;
  document.getElementById('page-inspector').style.display    = p === 'inspector'    ? '' : 'none';
  document.getElementById('page-session-json').style.display = p === 'session-json' ? '' : 'none';
  document.getElementById('page-plan').style.display         = p === 'plan'         ? '' : 'none';
  document.getElementById('tab-inspector').classList.toggle('on',    p === 'inspector');
  document.getElementById('tab-session-json').classList.toggle('on', p === 'session-json');
  document.getElementById('tab-plan').classList.toggle('on',         p === 'plan');
  if (p === 'session-json') renderSessionJsonPage();
}

function setSbView(v) {
  currentSbView = v;
  document.getElementById('sb-pipe-view').style.display = v === 'pipe' ? '' : 'none';
  document.getElementById('sb-sess-view').style.display = v === 'sess' ? '' : 'none';
  document.getElementById('sbn-pipe').classList.toggle('on', v === 'pipe');
  document.getElementById('sbn-sess').classList.toggle('on', v === 'sess');
}

// ─── Pipeline SVG ─────────────────────────────────────────────────────────────
function pipelineSVG(pfx = '') {
  const W = 204, NH = 32, NW = 188, cx = W / 2, x0 = (W - NW) / 2, gap = 10;
  const nodes = ARCH.map((s, i) => ({ ...s, y: i * (NH + gap) + 4 }));
  const svgH  = nodes[nodes.length - 1].y + NH + 10;
  const mid   = `arr-${pfx}`;

  const defs = `<defs><marker id="${mid}" markerWidth="6" markerHeight="6" refX="4.5" refY="3" orient="auto">
    <path d="M0,0 L6,3 L0,6 z" class="arrowhead"/>
  </marker></defs>`;

  const edges = nodes.slice(0, -1).map(n => {
    const nx = nodes[ARCH.findIndex(s => s.id === n.id) + 1];
    const y1 = n.y + NH, y2 = nx.y;
    return `<g id="${pfx}e-${n.id}">
      <line class="arr" x1="${cx}" y1="${y1}" x2="${cx}" y2="${y2 - 4}" marker-end="url(#${mid})"/>
    </g>`;
  }).join('');

  const nodesSVG = nodes.map(n => {
    const ytiLine = !n.implemented
      ? `<text class="nd" x="${cx}" y="${n.y + NH - 4}" text-anchor="middle">YET TO IMPLEMENT</text>`
      : '';
    return `<g class="node${n.implemented ? '' : ' skip'}" id="${pfx}nd-${n.id}">
      <rect class="bx" x="${x0}" y="${n.y}" width="${NW}" height="${NH}" rx="7"/>
      <text class="nt" x="${cx}" y="${n.y + (n.implemented ? 12 : 10)}" text-anchor="middle" dominant-baseline="middle">${n.label}</text>
      <text class="ns" x="${cx}" y="${n.y + (n.implemented ? 23 : 21)}" text-anchor="middle" dominant-baseline="middle">${n.sub.substring(0, 38)}${n.sub.length > 38 ? '…' : ''}</text>
      ${ytiLine}
    </g>`;
  }).join('');

  return `<svg class="arch" viewBox="0 0 ${W} ${svgH}" xmlns="http://www.w3.org/2000/svg">
    ${defs}${edges}${nodesSVG}</svg>`;
}

// ─── Diagram animation ────────────────────────────────────────────────────────
const PFXS = ['nav-', 'td-'];

function diagSetNode(pfx, id, state) {
  const el = document.getElementById(`${pfx}nd-${id}`);
  if (!el) return;
  el.classList.remove('hot', 'done', 'err', 'skip');
  if (state) el.classList.add(state);
}

function diagSetEdge(pfx, fromId, live) {
  const el = document.querySelector(`#${pfx}e-${fromId} .arr`);
  if (!el) return;
  el.classList.toggle('live', live);
}

function resetDiagram() {
  PFXS.forEach(pfx => {
    ARCH.forEach(s => diagSetNode(pfx, s.id, s.implemented ? '' : 'skip'));
    ARCH.slice(0, -1).forEach(s => diagSetEdge(pfx, s.id, false));
  });
  setSbStatus('');
}

function setSbStatus(html) {
  const a = document.getElementById('sb-status');
  if (a) a.innerHTML = html;
}

function phaseToId(phase) {
  return ARCH.find(s => s.phase === phase)?.id ?? null;
}

async function replayDiagram(trace) {
  resetDiagram();
  // Dedupe: one animation step per phase (show each ARCH node once, in order)
  const seenPhases = new Set();
  const rows = [...trace]
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
    .filter(r => { if (seenPhases.has(r.phase)) return false; seenPhases.add(r.phase); return true; });

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];
    const sid = phaseToId(row.phase);
    if (!sid) continue;
    PFXS.forEach(pfx => diagSetNode(pfx, sid, 'hot'));
    setSbStatus(`<span class="ldot"></span>${ARCH.find(s => s.id === sid)?.label ?? ''}`);
    await sleep(300);
    const op = row.output_parsed ?? row.payload ?? {};
    const bad = (sid === 'call1'    && op.needs_clarification)
             || (sid === 'call2'    && (op.status === 'no_match' || op.noMatch))
             || (sid === 'executor' && (row.payload?.queries ?? []).some(q => q.error));
    PFXS.forEach(pfx => diagSetNode(pfx, sid, bad ? 'err' : 'done'));
    const idx = ARCH.findIndex(s => s.id === sid);
    if (idx < ARCH.length - 1) {
      PFXS.forEach(pfx => diagSetEdge(pfx, sid, true));
      await sleep(140);
      PFXS.forEach(pfx => diagSetEdge(pfx, sid, false));
    }
  }
  // Final status from last respond row
  const respondRow = trace.find(r => r.phase === 'generate_response');
  const finalOutcome = (respondRow?.output_parsed ?? respondRow?.payload)?.outcome;
  setSbStatus(finalOutcome ? `Done · ${finalOutcome}` : 'Done');
}

// ─── Health ───────────────────────────────────────────────────────────────────
async function checkHealth() {
  try {
    const d = await getJSON('/health');
    const ok = d.status === 'ok';
    const dot = document.getElementById('hdot');
    dot.className = 'hdot' + (ok ? '' : ' bad');
    dot.title = JSON.stringify(d.dbs);
  } catch { document.getElementById('hdot').className = 'hdot bad'; }
}

// ─── Sessions ─────────────────────────────────────────────────────────────────
async function loadSessions(silent = false) {
  try {
    allSessions = await getJSON('/api/sessions');
    document.getElementById('sess-count').textContent = `(${allSessions.length})`;
    renderSessList();
  } catch (e) { if (!silent) console.error(e); }
}

function renderSessList() {
  const el = document.getElementById('sess-list');
  el.innerHTML = allSessions.length
    ? allSessions.map(s => `
        <div class="sess-item${s.session_id === currentSessionId ? ' on' : ''}"
             onclick="selectSession('${esc(s.session_id)}')">
          <div style="font-family:var(--mono);font-size:11.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(s.session_id)}</div>
          <div class="sm">${s.turn_count} turns · ${relTime(s.last_active)}</div>
        </div>`).join('')
    : '<div style="padding:6px 14px;font-size:12px;color:var(--ink3)">No sessions yet</div>';
}

function newSession() {
  currentSessionId  = 'sess-' + Math.random().toString(36).slice(2, 10);
  currentTurnId     = null; currentTrace = []; currentTurnData = null; currentTurns = [];
  currentSessionJson = null; sessionJsonTurnTab = 0;
  document.getElementById('dock-sess-lbl').textContent = currentSessionId;
  document.getElementById('topbar-ctx').textContent    = currentSessionId;
  document.getElementById('chatlog').innerHTML = '<div class="bu-asst">New session started. Ask me anything about your CRM or HRM data.</div>';
  renderSessList();
  renderInspectorPage();
  if (currentPage === 'session-json') renderSessionJsonPage();
}

async function selectSession(sid) {
  currentSessionId = sid; currentTurnId = null; currentTrace = []; currentTurnData = null;
  currentSessionJson = null;
  document.getElementById('dock-sess-lbl').textContent = sid;
  document.getElementById('topbar-ctx').textContent    = sid;
  renderSessList();
  await refreshTurns();
  // Load session JSON in background (used by Session JSON tab)
  loadSessionJson(sid);
  try {
    const turns = await getJSON(`/api/sessions/${sid}/turns`);
    const log = document.getElementById('chatlog'); log.innerHTML = '';
    turns.forEach(t => {
      addBubble('user', t.raw_message, null, false);
      if (t.assistant_answer) addBubble('asst', t.assistant_answer, t.resolved_intent_or_sql, false, t.id);
    });
  } catch {}
}

async function loadSessionJson(sid) {
  try {
    currentSessionJson = await getJSON(`/api/sessions/${sid}/json`);
    if (currentPage === 'session-json') renderSessionJsonPage();
  } catch (e) { currentSessionJson = null; }
}

async function refreshTurns() {
  if (!currentSessionId) return;
  try { currentTurns = await getJSON(`/api/sessions/${currentSessionId}/turns`); renderInspectorPage(); } catch {}
}

// ─── Inspector page ───────────────────────────────────────────────────────────
function renderInspectorPage() {
  // Preserve which step cards are open before re-rendering
  const openCards = new Set(
    [...document.querySelectorAll('.step-body.open')].map(el => el.id)
  );
  const el = document.getElementById('page-inspector');
  if (!currentSessionId) {
    el.innerHTML = '<div class="empty-msg">Select a session from the sidebar, then click a turn.</div>';
    return;
  }

  const db = currentTurns.filter(t => t.routed_skill === 'talk_to_db').length;
  const tilesH = `<div class="tiles">
    <div class="tile"><b>${currentTurns.length}</b><span>Turns</span></div>
    <div class="tile"><b>${db}</b><span>DB queries</span></div>
    <div class="tile"><b>${currentTurns.length - db}</b><span>Chit-chat</span></div>
  </div>`;

  const turnsH = currentTurns.length
    ? `<div class="tbl-wrap"><table>
        <thead><tr><th>#</th><th>Message</th><th>Skill</th><th>Status</th><th>Time</th></tr></thead>
        <tbody>${currentTurns.map(t => {
          const status = t.final_status ?? null;
          return `
          <tr class="trow${t.id === currentTurnId ? ' on' : ''}" onclick="selectTurn(${t.id})">
            <td class="meta">${t.turn_number}</td>
            <td style="max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(t.raw_message)}</td>
            <td><span class="pill ${t.routed_skill ?? 'none'}">${t.routed_skill ?? '—'}</span></td>
            <td>${status ? `<span class="pill ${status}">${esc(status)}</span>` : '<span class="meta">—</span>'}</td>
            <td class="meta">${relTime(t.created_at)}</td>
          </tr>`;
        }).join('')}
        </tbody></table></div>`
    : '<div class="empty-msg" style="padding:12px 0">No turns yet — send a message.</div>';

  const traceH = currentTurnId ? buildTraceSection() : '';

  el.innerHTML = tilesH
    + `<h2 class="section">Turns</h2>` + turnsH
    + (currentTurnId
       ? `<h2 class="section" style="margin-top:20px">Step trace — turn #${currentTurnData?.turn_number ?? '?'}</h2>` + traceH
       : '<div class="empty-msg" style="margin-top:14px">Select a turn above to inspect it.</div>');

  // re-wire subtab click handlers rendered inside el
  el.querySelectorAll('[data-iotab]').forEach(btn => {
    btn.addEventListener('click', () => {
      const [stepId, tab] = btn.dataset.iotab.split('|');
      switchIO(stepId, tab, el);
    });
  });

  // Restore previously open step cards
  openCards.forEach(cardId => {
    const body = document.getElementById(cardId);
    if (!body) return;
    body.classList.add('open');
    const head = body.previousElementSibling;
    if (head) head.classList.add('open');
  });
}

// ─── Trace section ─────────────────────────────────────────────────────────────
function buildTraceSection() {
  const byPhase = {};
  currentTrace.forEach(row => { (byPhase[row.phase] = byPhase[row.phase] ?? []).push(row); });

  const cards = ARCH.map(step => buildStepCard(step, byPhase)).join('');

  return `<div class="trace-steps">${cards}</div>`;
}

function buildStepCard(step, byPhase) {
  const rows = step.phase ? (byPhase[step.phase] ?? []) : [];
  // For planner there may be multiple attempts — use all of them; for others take first
  const row  = rows[0] ?? null;
  const isSkipped = !row;

  // Determine status from the richer data
  const op = row?.output_parsed ?? row?.payload ?? {};
  const isErr  = (step.id === 'call1'    && op.needs_clarification)
              || (step.id === 'call2'    && (op.status === 'no_match' || op.noMatch))
              || (step.id === 'executor' && (row?.payload?.queries ?? []).some(q => q.error));
  const isWarn = step.id === 'call1' && op.needs_clarification;

  const statusBadge = isSkipped ? `<span class="bx skip">skipped</span>`
                    : isWarn    ? `<span class="bx warn">clarification</span>`
                    : isErr     ? `<span class="bx err">${step.id === 'call2' ? 'no_match' : 'error'}</span>`
                    :             `<span class="bx ok">ok</span>`;

  const durMs  = row?.duration_ms ?? null;
  const durBadge = durMs != null ? `<span class="dur">${durMs}ms</span>` : '';
  const modelBadge = row?.model ? `<span class="bx info" style="font-size:10px">${esc(row.model)}</span>` : '';
  const tokenBadge = (row?.tokens_in != null)
    ? `<span class="dur" style="color:var(--ink3)">${row.tokens_in}↓ ${row.tokens_out}↑</span>` : '';

  // For planner, show attempt count
  const attemptBadge = rows.length > 1
    ? `<span class="bx warn" style="font-size:10px">${rows.length} attempts</span>` : '';

  const bodyContent = isSkipped
    ? `<div class="io-pane"><div class="empty-msg" style="padding:8px 0">Skipped this turn</div></div>`
    : buildIOTabs(step, row, rows, byPhase);

  return `<div class="step-card">
    <div class="step-hd open" onclick="toggleCard('sc-${step.id}','sh-${step.id}')">
      <div class="step-icon implemented" id="sh-${step.id}">${step.num}</div>
      <div class="step-info">
        <div class="step-title">${esc(step.label)}</div>
        <div class="step-sub">${esc(step.type)} · ${esc(step.sub)}</div>
      </div>
      <div class="step-badges">${tokenBadge}${durBadge}${modelBadge}${attemptBadge}${statusBadge}</div>
    </div>
    <div class="step-body open" id="sc-${step.id}">${bodyContent}</div>
  </div>`;
}

function toggleCard(bodyId, headId) {
  const body = document.getElementById(bodyId); if (!body) return;
  const head = document.querySelector(`#${bodyId}`).previousElementSibling;
  const isOpen = body.classList.toggle('open');
  if (head) head.classList.toggle('open', isOpen);
}

// ─── IO tabs body ──────────────────────────────────────────────────────────────
// row = first (or only) trace row for this step
// allRows = all rows for this phase (planner may have multiple attempts)
function buildIOTabs(step, row, allRows, byPhase) {
  const { inputH, outputH } = buildStepIO(step, row, allRows, byPhase);

  // Raw: prefer output_parsed (richer), fall back to payload
  const rawObj = row?.output_parsed ?? row?.payload ?? {};
  const rawH = `<pre class="code-block" style="max-height:300px">${esc(JSON.stringify(rawObj, null, 2))}</pre>`;

  // Prompt tab: rendered_prompt from talk2db.llm_calls (has systemPrompt + userPrompt)
  const promptData = row?.prompt_sent ?? null;
  const promptH = promptData
    ? `<div class="kk">System prompt</div>
       <pre class="code-block" style="margin-bottom:10px;max-height:280px">${esc(promptData.systemPrompt ?? '')}</pre>
       <div class="kk">User prompt</div>
       <pre class="code-block" style="max-height:360px">${esc(promptData.userPrompt ?? '')}</pre>`
    : '<div class="empty-msg" style="padding:8px 0">No prompt recorded for this step</div>';

  const hasPrmt = !!promptData;

  // History tab: show session history sent to this LLM call
  const historyData = row?.llm_input?.history ?? null;
  const hasHistory  = Array.isArray(historyData) && historyData.length > 0;
  const historyH    = hasHistory
    ? buildHistoryTabContent(historyData, row?.llm_input)
    : '<div class="empty-msg" style="padding:8px 0">No session history sent to this call</div>';

  // Context tab: session/identity meta from llm_input
  const ctxH = buildContextTabContent(row?.llm_input ?? {});

  return `<div class="io-tabbar">
    <button class="io-tab on" data-iotab="${step.id}|input">Input</button>
    <button class="io-tab"    data-iotab="${step.id}|output">Output</button>
    ${hasPrmt ? `<button class="io-tab" data-iotab="${step.id}|prompt">Prompt</button>` : ''}
    <button class="io-tab"    data-iotab="${step.id}|history">History${hasHistory ? ` <span class="top-tab-badge">${historyData.length}</span>` : ''}</button>
    <button class="io-tab"    data-iotab="${step.id}|context">Context</button>
    <button class="io-tab"    data-iotab="${step.id}|raw">Raw JSON</button>
  </div>
  <div class="io-pane" id="iop-${step.id}-input">${inputH}</div>
  <div class="io-pane hide" id="iop-${step.id}-output">${outputH}</div>
  ${hasPrmt ? `<div class="io-pane hide" id="iop-${step.id}-prompt">${promptH}</div>` : ''}
  <div class="io-pane hide" id="iop-${step.id}-history">${historyH}</div>
  <div class="io-pane hide" id="iop-${step.id}-context">${ctxH}</div>
  <div class="io-pane hide" id="iop-${step.id}-raw">${rawH}</div>`;
}

function switchIO(stepId, tab, root) {
  const panes = (root ?? document).querySelectorAll(`[id^="iop-${stepId}-"]`);
  panes.forEach(p => p.classList.toggle('hide', !p.id.endsWith(`-${tab}`)));
  const tabs = (root ?? document).querySelectorAll(`[data-iotab^="${stepId}|"]`);
  tabs.forEach(btn => btn.classList.toggle('on', btn.dataset.iotab === `${stepId}|${tab}`));
}

// ─── History tab content ──────────────────────────────────────────────────────
function buildHistoryTabContent(history, llmInput) {
  if (!history?.length) return '<div class="empty-msg" style="padding:8px 0">No history</div>';

  const bubbles = history.map(h => {
    const isUser = h.role === 'user';
    const sqlNote = h.sql ? `<div style="font-size:10.5px;color:var(--accent);margin-top:4px;font-family:var(--mono);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(h.sql.slice(0, 80))}${h.sql.length > 80 ? '…' : ''}</div>` : '';
    return `<div style="display:flex;flex-direction:column;align-items:${isUser ? 'flex-end' : 'flex-start'};gap:2px;margin-bottom:8px">
      <div style="font-size:9.5px;font-weight:700;text-transform:uppercase;letter-spacing:.07em;color:var(--ink3);margin-bottom:2px">${isUser ? 'User' : 'Assistant'}</div>
      <div style="max-width:88%;background:${isUser ? 'var(--accent-soft)' : 'var(--panel2)'};border:1px solid ${isUser ? 'var(--accent)' : 'var(--line)'};border-radius:10px;padding:7px 11px;font-size:12.5px;color:var(--ink)">${esc(h.content ?? h.text ?? '')}</div>
      ${sqlNote}
    </div>`;
  }).join('');

  return `<div class="kk" style="margin-top:0">Session history sent to this call (last ${history.length} turn${history.length !== 1 ? 's' : ''})</div>
    <div style="display:flex;flex-direction:column;padding:4px 0">${bubbles}</div>`;
}

// ─── Context tab content ──────────────────────────────────────────────────────
function buildContextTabContent(llmInput) {
  if (!llmInput || typeof llmInput !== 'object') {
    return '<div class="empty-msg" style="padding:8px 0">No context data</div>';
  }
  const rows = [];
  if (llmInput.sessionId)   rows.push(['Session ID',  llmInput.sessionId]);
  if (llmInput.turnNo != null) rows.push(['Turn #',   llmInput.turnNo]);
  if (llmInput.identity) {
    const id = llmInput.identity;
    if (id.email)      rows.push(['Identity · email',    id.email]);
    if (id.crmUserId)  rows.push(['Identity · CRM ID',   id.crmUserId]);
    if (id.employeeId) rows.push(['Identity · Emp ID',   id.employeeId]);
  }
  if (llmInput.historyLen != null) rows.push(['History turns sent', llmInput.historyLen]);
  if (llmInput.ddlCount   != null) rows.push(['DDL chunks sent',    llmInput.ddlCount]);
  if (llmInput.message)            rows.push(['Raw message',        llmInput.message]);
  if (llmInput.rephrasedQuestion)  rows.push(['Rephrased question', llmInput.rephrasedQuestion]);
  if (llmInput.previousAttempts != null) rows.push(['Previous planner attempts', llmInput.previousAttempts]);
  if (llmInput.execRowCount != null)     rows.push(['Exec row count (to Call 3)', llmInput.execRowCount]);

  if (!rows.length) return `<pre class="code-block" style="max-height:200px">${esc(JSON.stringify(llmInput, null, 2))}</pre>`;

  const tableRows = rows.map(([k, v]) => `<tr>
    <td style="color:var(--ink3);font-weight:600;white-space:nowrap">${esc(k)}</td>
    <td style="font-family:var(--mono);font-size:11.5px;word-break:break-all">${esc(String(v))}</td>
  </tr>`).join('');

  return `<div class="kk" style="margin-top:0">Session context passed to this LLM call</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Field</th><th>Value</th></tr></thead>
      <tbody>${tableRows}</tbody>
    </table></div>`;
}

// ─── Step I/O builders ────────────────────────────────────────────────────────
// row = primary trace row; allRows = all rows for this phase; byPhase = full trace grouped
function buildStepIO(step, row, allRows, byPhase) {
  switch (step.id) {
    case 'router':    return routerIO(row);
    case 'call1':     return call1IO(row);
    case 'retrieval': return retrievalIO(row);
    case 'call2':     return call2IO(row, allRows, byPhase);
    case 'executor':  return executorIO(row, byPhase);
    case 'call3':     return call3IO(row, byPhase);
    default:          return { inputH: '<div class="empty-msg">—</div>', outputH: '<div class="empty-msg">—</div>' };
  }
}

// ─── Router ───────────────────────────────────────────────────────────────────
function routerIO(row) {
  const p = row?.payload ?? {};
  const ctxRows = [
    ['Session ID',  p.sessionId  ?? currentSessionId ?? '—'],
    ['Turn #',      p.turnNumber ?? '—'],
    ['User ID',     p.userId     ?? '—'],
    ['Email',       p.email      ?? '—'],
  ].map(([k, v]) => `<tr><td style="color:var(--ink3);font-weight:600;white-space:nowrap">${esc(k)}</td><td style="font-family:var(--mono);font-size:11.5px">${esc(String(v))}</td></tr>`).join('');

  const inputH = `
    <div class="kk" style="color:var(--accent)">↓ Input</div>
    <div class="ic"><strong>User message</strong><br><span style="color:var(--ink2)">${esc(p.message ?? currentTurnData?.raw_message ?? '—')}</span></div>
    <div class="kk">Session context</div>
    <div class="tbl-wrap"><table><thead><tr><th>Field</th><th>Value</th></tr></thead><tbody>${ctxRows}</tbody></table></div>`;

  const skillColour = p.skill === 'talk_to_db' ? 'var(--good)' : p.skill === 'chit_chat' ? 'var(--accent)' : 'var(--bad)';
  const outputH = `
    <div class="kk" style="color:var(--good)">↑ Output</div>
    <div class="ic">
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:8px">
        <span style="font-size:13px;font-weight:700;color:${skillColour}">${esc(p.skill ?? '—')}</span>
        <span class="meta">skill</span>
      </div>
      <div class="conf-row">
        <span class="conf-val">${p.confidence != null ? Math.round(p.confidence * 100) + '%' : '—'}</span>
        <div class="conf-bg"><div class="conf-fill${(p.confidence ?? 1) < 0.5 ? ' low' : ''}" style="width:${Math.round((p.confidence ?? 0) * 100)}%"></div></div>
        <span class="conf-thresh">confidence</span>
      </div>
      ${p.reason ? `<div style="font-size:12px;color:var(--ink3);margin-top:6px">${esc(p.reason)}</div>` : ''}
    </div>`;
  return { inputH, outputH };
}

// ─── Call 1 · Rephrase / Clarify ──────────────────────────────────────────────
function call1IO(row) {
  // For LLM calls: structured input is in row.llm_input, output in row.output_parsed
  const inp = row?.llm_input ?? {};
  const op  = row?.output_parsed ?? row?.payload ?? {};

  const pendingClar = inp.pendingClarification;
  const pendingSection = pendingClar
    ? `<div class="ic" style="border-color:var(--accent)"><strong>Router skipped — clarification pending</strong><br>
       <div style="margin-top:6px">
         <div class="kk" style="margin-top:0">Original prompt</div>
         <div style="font-size:12px;color:var(--ink2)">${esc(pendingClar.original_prompt ?? '—')}</div>
         ${(pendingClar.questions ?? []).length ? `
         <div class="kk">Prior questions</div>
         <div class="tbl-wrap"><table>
           <thead><tr><th>id</th><th>Question</th><th>Answer</th></tr></thead>
           <tbody>${(pendingClar.questions ?? []).map(q =>
             `<tr><td style="font-family:var(--mono);font-size:11px">${esc(q.id)}</td>
              <td>${esc(q.text)}</td>
              <td>${q.answer != null ? `<span style="color:var(--good)">${esc(String(q.answer))}</span>` : '<span style="color:var(--ink3)">—</span>'}</td></tr>`
           ).join('')}</tbody>
         </table></div>` : ''}
       </div></div>`
    : `<div class="ic"><strong>No pending clarification</strong><br><span style="font-size:12px;color:var(--ink2)">Fresh question — router ran normally.</span></div>`;

  const histLen = inp.historyLen ?? 0;

  const inputH = `
    <div class="kk" style="color:var(--accent)">↓ Input</div>
    <div class="ic"><strong>User message</strong><br><span style="color:var(--ink2)">${esc(inp.message ?? currentTurnData?.raw_message ?? '—')}</span></div>
    <div class="ic"><strong>Session history</strong><br><span class="meta">${histLen} prior turn${histLen !== 1 ? 's' : ''} sent as context</span></div>
    ${pendingSection}`;

  const mtColour = op.message_type === 'new_topic' ? 'var(--warn)' : op.message_type === 'clarification_answer' ? 'var(--accent)' : 'var(--good)';

  let clarSection = '';
  if (op.needs_clarification && op.clarification?.questions?.length) {
    const qRows = op.clarification.questions.map(q =>
      `<tr><td style="font-family:var(--mono);font-size:11px">${esc(q.id)}</td>
       <td>${esc(q.text)}</td>
       <td>${q.answer != null ? `<span style="color:var(--good)">${esc(String(q.answer))}</span>` : '<span style="color:var(--ink3)">—</span>'}</td></tr>`
    ).join('');
    clarSection = `
      <div class="kk" style="color:var(--warn)">Clarification questions asked (round ${op.clarification.round ?? 1})</div>
      <div class="tbl-wrap"><table>
        <thead><tr><th>id</th><th>Question</th><th>Answer</th></tr></thead>
        <tbody>${qRows}</tbody>
      </table></div>`;
  }

  const assumptionSection = (op.assumptions ?? []).length
    ? `<div class="kk">Assumptions made</div>
       <div class="ic">${op.assumptions.map(a => `<div style="font-size:12px;color:var(--ink2);margin-bottom:3px">• ${esc(a)}</div>`).join('')}</div>`
    : '';

  const outputH = `
    <div class="kk" style="color:var(--good)">↑ Output</div>
    <div class="ic">
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:8px">
        <span style="font-size:12px;font-weight:700;color:${mtColour}">${esc(op.message_type ?? '—')}</span>
        <span class="meta">message_type</span>
        ${op.needs_clarification ? `<span class="bx warn">clarification needed</span>` : `<span class="bx ok">rephrased</span>`}
      </div>
      ${op.rephrased_question ? `<div style="font-size:13px;color:var(--ink);font-style:italic;margin-bottom:6px">"${esc(op.rephrased_question)}"</div>` : ''}
    </div>
    ${clarSection}
    ${assumptionSection}`;

  return { inputH, outputH };
}

// ─── Retrieval ────────────────────────────────────────────────────────────────
function retrievalIO(row) {
  const p      = row?.payload ?? {};
  const tables = p.tables ?? [];

  const rephrasedQ = (currentTrace.find(r => r.phase === 'rephrase')?.output_parsed ?? currentTrace.find(r => r.phase === 'rephrase')?.payload)?.rephrased_question
    ?? currentTurnData?.raw_message ?? '—';

  const inputH = `
    <div class="kk" style="color:var(--accent)">↓ Input</div>
    <div class="ic"><strong>Query embedded</strong> <span class="meta">gemini-embedding-001, dim 768</span><br>
      <span style="color:var(--ink2);font-style:italic">"${esc(rephrasedQ)}"</span></div>
    ${(p.matches ?? []).length
      ? `<div class="ic"><strong>Vocab matches applied</strong><br><span style="font-size:12px;color:var(--ink2)">${(p.matches).map(v => `"${esc(v.alias)}" → ${esc(v.canonical_term)}`).join(', ')}</span></div>`
      : ''}`;

  const tableRows = tables.map((t, i) => `<tr>
    <td class="meta">${i + 1}</td>
    <td><span class="badge ${t.label ?? 'crm'}">${(t.label ?? 'crm').toUpperCase()}</span></td>
    <td><code>${esc(t.schema)}.${esc(t.table)}</code></td>
    <td style="min-width:120px">
      <div class="sim-row"><div class="sim-bg"><div class="sim-fill" style="width:${Math.round((t.similarity ?? 0) * 100)}%"></div></div>
      <span class="meta">${((t.similarity ?? 0) * 100).toFixed(1)}%</span></div>
    </td></tr>`).join('');

  const outputH = tables.length
    ? `<div class="kk" style="color:var(--good)">↑ DDL chunks retrieved (top-K = ${tables.length})</div>
       <div class="tbl-wrap"><table>
         <thead><tr><th>#</th><th>DB</th><th>Table</th><th>Cosine similarity</th></tr></thead>
         <tbody>${tableRows}</tbody></table></div>`
    : '<div class="empty-msg">No DDL retrieved</div>';
  return { inputH, outputH };
}

// ─── Call 2 · Planner ─────────────────────────────────────────────────────────
function call2IO(row, allRows, byPhase) {
  // allRows = all planner attempts sorted by attempt number
  const attempts = [...allRows].sort((a, b) => (a.attempt ?? 1) - (b.attempt ?? 1));
  const isRetry = attempts.length > 1;

  // Input uses the first attempt's llm_input (rephrased question etc.)
  const inp = row?.llm_input ?? {};
  const rephrasedQ = inp.rephrasedQuestion
    ?? (byPhase?.['rephrase'] ?? [])[0]?.output_parsed?.rephrased_question
    ?? currentTurnData?.raw_message ?? '—';

  const inputH = `
    <div class="kk" style="color:var(--accent)">↓ Input</div>
    <div class="ic"><strong>Rephrased question</strong><br><span style="color:var(--ink2);font-style:italic">"${esc(rephrasedQ)}"</span></div>
    <div class="ic"><strong>DDL context</strong><br><span class="meta">${inp.ddlCount ?? '?'} DDL chunk${(inp.ddlCount ?? 0) !== 1 ? 's' : ''} sent to LLM</span></div>
    ${isRetry ? `<div class="ic" style="border-color:var(--warn)"><strong>Retry context</strong><br><span style="font-size:12px;color:var(--warn)">${attempts.length - 1} prior failed attempt${attempts.length > 2 ? 's' : ''} fed back to planner</span></div>` : ''}`;

  // Output: show each attempt in order
  const attemptBlocks = attempts.map((ar, idx) => {
    const op = ar.output_parsed ?? ar.payload ?? {};
    const isLast = idx === attempts.length - 1;
    const attemptNum = ar.attempt ?? idx + 1;
    const label = attempts.length > 1
      ? `<div style="font-size:11px;font-weight:700;color:${isLast ? 'var(--ink2)' : 'var(--warn)'};margin-bottom:8px">Attempt ${attemptNum}${isLast ? ' (final)' : ' — failed'}</div>`
      : '';

    if (op.status === 'no_match') {
      return `${label}<div class="ic" style="border-color:var(--warn)">
        <span style="color:var(--warn);font-weight:700">no_match</span>
        ${op.reason ? `<div style="font-size:12px;color:var(--ink2);margin-top:4px">${esc(op.reason)}</div>` : ''}
      </div>
      ${(op.available ?? []).length ? `<div class="kk">What IS available</div>
        <div class="ic">${op.available.map(a => `<div style="font-size:12px;color:var(--ink2);margin-bottom:3px">• ${esc(a)}</div>`).join('')}</div>` : ''}`;
    }

    const queries = op.queries ?? [];
    const conf = op.confidence ?? null;
    const THRESHOLD = 0.6;
    const confH = conf != null ? `
      <div class="kk">Confidence</div>
      <div class="conf-row">
        <span class="conf-val">${Math.round(conf * 100)}%</span>
        <div class="conf-bg" style="position:relative">
          <div class="conf-fill${conf < THRESHOLD ? ' low' : ''}" style="width:${Math.round(conf * 100)}%"></div>
          <div style="position:absolute;top:-1px;bottom:-1px;left:${THRESHOLD * 100}%;width:1px;background:var(--warn);opacity:.7"></div>
        </div>
        <span class="conf-thresh">threshold ${THRESHOLD}</span>
      </div>` : '';

    const sqlBlocks = queries.map(s => {
      const dep = s.depends_on != null
        ? `<div style="font-size:11px;color:var(--accent);margin-bottom:5px">← injects <code>${esc(s.bind ?? '?')}</code> from step ${s.depends_on}</div>`
        : '';
      return `<div style="margin-bottom:12px">
        <div style="display:flex;align-items:center;gap:7px;margin-bottom:4px">
          <span class="badge ${s.db ?? 'crm'}">${(s.db ?? 'crm').toUpperCase()}</span>
          <span style="font-size:12px;font-weight:700">Step ${s.step}</span>
          ${s.depends_on != null ? `<span class="bx info" style="font-size:10px">cross-DB</span>` : ''}
        </div>
        ${s.purpose ? `<div style="font-size:11.5px;color:var(--ink2);margin-bottom:4px;font-style:italic">${esc(s.purpose)}</div>` : ''}
        ${dep}
        <pre class="code-block">${esc(s.sql ?? '')}</pre>
      </div>`;
    }).join('');

    return `${label}${confH}${sqlBlocks || '<div class="empty-msg">No queries planned</div>'}`;
  }).join('<hr style="border:none;border-top:1px dashed var(--line2);margin:12px 0">');

  return { inputH, outputH: `<div class="kk" style="color:var(--good)">↑ Output</div>${attemptBlocks}` };
}

// ─── Executor ─────────────────────────────────────────────────────────────────
function executorIO(row, byPhase) {
  const p  = row?.payload ?? {};
  const qs = Array.isArray(p.queries) ? p.queries : [];

  // Get SQL from last successful planner attempt
  const plannerRows = [...(byPhase['generate_sql'] ?? [])].sort((a, b) => (a.attempt ?? 1) - (b.attempt ?? 1));
  const lastPlan = plannerRows[plannerRows.length - 1];
  const planQueries = lastPlan?.output_parsed?.queries ?? lastPlan?.payload?.queries ?? [];

  const sqlIn = planQueries.map(s => `
    <div style="margin-bottom:10px">
      <div style="display:flex;align-items:center;gap:7px;margin-bottom:6px">
        <span class="badge ${s.db ?? 'crm'}">${(s.db ?? 'crm').toUpperCase()}</span>
        <span style="font-size:12px;font-weight:700">Step ${s.step}</span>
        ${s.depends_on != null ? `<span class="bx info" style="font-size:10px">cross-DB</span>` : ''}
      </div>
      ${s.purpose ? `<div style="font-size:11.5px;color:var(--ink2);margin-bottom:4px;font-style:italic">${esc(s.purpose)}</div>` : ''}
      <pre class="code-block">${esc(s.sql ?? '')}</pre>
    </div>`).join('');

  const inputH = `
    <div class="kk" style="color:var(--accent)">↓ Input — SQL plan from Planner</div>
    ${sqlIn || '<div class="empty-msg">No SQL plan recorded</div>'}
    <div class="ic" style="margin-top:6px">
      <strong>Guards applied</strong><br>
      <span style="font-size:12px;color:var(--ink2)">SELECT-only · row cap 200 · {CRM_SCHEMA}/{HRM_SCHEMA} substituted · statement timeout enforced</span>
    </div>`;

  const resultBlocks = qs.map(q => {
    const bv = (q.boundValues ?? []).length
      ? `<div style="font-size:11px;color:var(--accent);margin-bottom:6px;font-family:var(--mono)">Bound ${q.boundValues.length} value(s) from step ${q.depends_on}: [${q.boundValues.slice(0, 6).map(v => esc(String(v))).join(', ')}${q.boundValues.length > 6 ? '…' : ''}]</div>`
      : '';
    const header = `<div style="display:flex;align-items:center;gap:7px;margin-bottom:6px">
      <span class="badge ${q.db ?? 'crm'}">${(q.db ?? '').toUpperCase()}</span>
      <span style="font-size:12px;font-weight:700">Step ${q.step ?? '?'}</span>
      ${q.error ? `<span class="bx err">error</span>` : `<span class="bx ok">${q.rowCount ?? 0} rows · ${q.durationMs ?? q.duration_ms ?? '?'}ms</span>`}
      ${q.depends_on != null ? `<span class="bx info" style="font-size:10px">cross-DB</span>` : ''}
    </div>`;
    if (q.error) return `<div style="margin-bottom:12px">${header}${bv}
      <div style="font-size:12px;color:var(--bad);padding:8px 10px;background:var(--bad-soft);border-radius:var(--r);font-family:var(--mono)">${esc(q.error)}</div>
      ${q.errorType ? `<div style="font-size:11px;color:var(--ink3);margin-top:3px">type: ${esc(q.errorType)} · retryable: ${q.retryable ? 'yes' : 'no'}</div>` : ''}
    </div>`;
    return `<div style="margin-bottom:12px">${header}${bv}${buildResultTable(q.rows, q.rowCount, null)}</div>`;
  });

  const outputH = `<div class="kk" style="color:var(--good)">↑ Output — execution results</div>`
    + (resultBlocks.length ? resultBlocks.join('') : '<div class="empty-msg">No execution results recorded</div>');

  return { inputH, outputH };
}

// ─── Call 3 · Respond / Validate ──────────────────────────────────────────────
function call3IO(row, byPhase) {
  const inp = row?.llm_input ?? {};
  const op  = row?.output_parsed ?? row?.payload ?? {};

  const rephrasedQ = inp.rephrasedQuestion
    ?? (byPhase?.['rephrase'] ?? [])[0]?.output_parsed?.rephrased_question
    ?? currentTurnData?.raw_message ?? '—';

  const execRowCount = inp.execRowCount ?? 0;

  const inputH = `
    <div class="kk" style="color:var(--accent)">↓ Input</div>
    <div class="ic"><strong>Original question</strong><br><span style="color:var(--ink2)">${esc(currentTurnData?.raw_message ?? '—')}</span></div>
    ${rephrasedQ !== currentTurnData?.raw_message
      ? `<div class="ic"><strong>Rephrased (from Call 1)</strong><br><span style="color:var(--ink2);font-style:italic">"${esc(rephrasedQ)}"</span></div>`
      : ''}
    <div class="ic"><strong>DB result</strong><br><span class="meta">${execRowCount} row${execRowCount !== 1 ? 's' : ''} from executor · ${inp.plannerAttempts ?? '?'} planner attempt${(inp.plannerAttempts ?? 1) !== 1 ? 's' : ''}</span></div>`;

  const outcome = op.outcome;
  const outcomeColour = outcome === 'answer' ? 'var(--good)' : outcome === 'no_relevant_data' ? 'var(--warn)' : 'var(--bad)';
  const validatedBadge = op.validated
    ? `<span class="bx ok" style="font-size:10px">validated ✓</span>`
    : outcome === 'answer' ? `<span class="bx warn" style="font-size:10px">unvalidated</span>` : '';

  const responseText = op.response ?? currentTurnData?.assistant_answer ?? '';

  const suggestedNext = op.suggested_next
    ? `<div class="kk">Suggested next question</div>
       <div class="ic" style="border-color:var(--accent);font-style:italic;font-size:12.5px">"${esc(op.suggested_next)}"</div>`
    : '';

  const alternatives = (op.alternatives ?? []).length
    ? `<div class="kk">Alternatives offered</div>
       <div class="ic">${op.alternatives.map(a => `<div style="font-size:12px;color:var(--ink2);margin-bottom:3px">• ${esc(a)}</div>`).join('')}</div>`
    : '';

  const outputH = `
    <div class="kk" style="color:var(--good)">↑ Output</div>
    <div class="ic">
      <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">
        <span style="font-size:13px;font-weight:700;color:${outcomeColour}">${esc(outcome ?? '—')}</span>
        <span class="meta">outcome</span>
        ${validatedBadge}
      </div>
      <div style="white-space:pre-wrap;font-size:13px;line-height:1.7;color:var(--ink)">${esc(responseText) || '<span style="color:var(--ink3)">No answer recorded</span>'}</div>
    </div>
    ${suggestedNext}
    ${alternatives}`;

  return { inputH, outputH };
}

// ─── Session JSON page ────────────────────────────────────────────────────────
function renderSessionJsonPage() {
  const el = document.getElementById('page-session-json');
  if (!currentSessionId) {
    el.innerHTML = '<div class="empty-msg">Select a session from the sidebar to view its JSON.</div>';
    return;
  }
  if (!currentSessionJson) {
    el.innerHTML = '<div class="empty-msg">Loading session JSON…</div>';
    return;
  }
  const s = currentSessionJson;
  const turns = s.turns ?? [];

  // Header meta
  const headerH = `
    <div class="tiles" style="margin-bottom:16px">
      <div class="tile"><b style="font-size:14px;word-break:break-all">${esc(s.session_id)}</b><span>Session ID</span></div>
      <div class="tile"><b>${turns.length}</b><span>Turns</span></div>
      <div class="tile"><b>${s.user?.email ?? s.user?.crm_id ?? '—'}</b><span>User</span></div>
      <div class="tile"><b>${relTime(s.session_started)}</b><span>Started</span></div>
    </div>`;

  // Pending clarification banner
  const pendingH = s.pending_clarification
    ? `<div class="ic" style="border-color:var(--warn);margin-bottom:12px">
         <strong style="color:var(--warn)">Pending clarification</strong>
         <pre class="code-block" style="margin-top:8px;max-height:160px">${esc(JSON.stringify(s.pending_clarification, null, 2))}</pre>
       </div>` : '';

  // Turn sub-tab bar
  if (!turns.length) {
    el.innerHTML = headerH + pendingH + '<div class="empty-msg">No turns yet.</div>';
    return;
  }
  const validIdx = Math.min(sessionJsonTurnTab, turns.length - 1);
  sessionJsonTurnTab = validIdx;

  const turnTabBar = `<div class="io-tabbar" style="flex-wrap:wrap;gap:2px;padding:4px 8px;border-radius:var(--r) var(--r) 0 0;border:1px solid var(--line);border-bottom:none;background:var(--panel2)">
    ${turns.map((t, i) => `
      <button class="io-tab${i === validIdx ? ' on' : ''}" style="font-size:11px;padding:6px 10px"
        onclick="setSjTurnTab(${i})">
        #${t.turn_no} · <span style="max-width:100px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;display:inline-block;vertical-align:bottom">${esc((t.user_message ?? '').slice(0, 28))}${(t.user_message ?? '').length > 28 ? '…' : ''}</span>
        ${t.final_status ? `<span class="pill ${t.final_status}" style="font-size:9.5px;padding:1px 5px;margin-left:4px">${esc(t.final_status)}</span>` : ''}
      </button>`).join('')}
  </div>`;

  const turn = turns[validIdx];
  const turnContentH = buildSjTurnContent(turn);

  // Raw full JSON tab
  const rawJsonH = `
    <h2 class="section" style="margin-top:20px">Full Session JSON (raw)</h2>
    <pre class="code-block" style="max-height:500px">${esc(JSON.stringify(s, null, 2))}</pre>`;

  el.innerHTML = headerH + pendingH
    + `<h2 class="section">Turn-by-turn data</h2>`
    + turnTabBar
    + `<div style="border:1px solid var(--line);border-radius:0 0 var(--r) var(--r);background:var(--panel);padding:14px 16px">${turnContentH}</div>`
    + rawJsonH;

  // Wire subtab click handlers
  el.querySelectorAll('[data-iotab]').forEach(btn => {
    btn.addEventListener('click', () => {
      const [stepId, tab] = btn.dataset.iotab.split('|');
      switchIO(stepId, tab, el);
    });
  });
}

function setSjTurnTab(idx) {
  sessionJsonTurnTab = idx;
  renderSessionJsonPage();
}

function buildSjTurnContent(t) {
  if (!t) return '<div class="empty-msg">No turn data</div>';

  // Overview row
  const overviewH = `
    <div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px">
      <div class="ic" style="flex:1;min-width:180px">
        <div class="kk" style="margin-top:0">User message</div>
        <div style="font-size:13px;color:var(--ink)">${esc(t.user_message ?? '—')}</div>
        ${t.rephrased_question && t.rephrased_question !== t.user_message
          ? `<div class="kk">Rephrased</div><div style="font-size:12.5px;color:var(--ink2);font-style:italic">"${esc(t.rephrased_question)}"</div>` : ''}
      </div>
      <div class="ic" style="flex:1;min-width:180px">
        <div class="kk" style="margin-top:0">Assistant answer</div>
        <div style="font-size:13px;color:var(--ink)">${esc(t.assistant_answer ?? '—')}</div>
      </div>
    </div>
    <div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:14px">
      ${t.routed_skill ? `<span class="pill ${t.routed_skill}">${esc(t.routed_skill)}</span>` : ''}
      ${t.final_status ? `<span class="pill ${t.final_status}">${esc(t.final_status)}</span>` : ''}
      <span class="meta">${relTime(t.created_at)}</span>
    </div>`;

  // LLM calls sub-section with their own inline tabs
  const llmH = buildSjLlmCalls(t.llm_calls ?? [], t.turn_id);

  // Executions
  const execH = buildSjExecutions(t.executions ?? []);

  // Retrieval
  const retH = buildSjRetrieval(t.retrieval ?? []);

  return overviewH + llmH + execH + retH;
}

function buildSjLlmCalls(calls, turnId) {
  if (!calls.length) return '<div class="empty-msg" style="margin-bottom:10px">No LLM calls recorded</div>';

  const callBlocks = calls.map((c, i) => {
    const sid = `sj-llm-${turnId}-${i}`;
    const modelBadge = c.model ? `<span class="bx info" style="font-size:10px">${esc(c.model)}</span>` : '';
    const tokenBadge = c.tokens_in != null ? `<span class="dur">${c.tokens_in}↓ ${c.tokens_out}↑</span>` : '';
    const latBadge   = c.latency_ms != null ? `<span class="dur">${c.latency_ms}ms</span>` : '';
    const statusBadge = c.status === 'ok' ? `<span class="bx ok">ok</span>` : `<span class="bx err">${esc(c.status ?? '?')}</span>`;

    const inputH = `<pre class="code-block" style="max-height:260px">${esc(JSON.stringify(c.input, null, 2))}</pre>`;
    const outputH = `<pre class="code-block" style="max-height:260px">${esc(JSON.stringify(c.output_parsed, null, 2))}</pre>`;
    const promptH = c.rendered_prompt
      ? `<div class="kk">System prompt</div>
         <pre class="code-block" style="max-height:220px;margin-bottom:8px">${esc((c.rendered_prompt?.systemPrompt ?? ''))}</pre>
         <div class="kk">User prompt</div>
         <pre class="code-block" style="max-height:300px">${esc((c.rendered_prompt?.userPrompt ?? ''))}</pre>`
      : '<div class="empty-msg" style="padding:8px 0">No prompt recorded</div>';

    return `<div class="step-card" style="margin-bottom:6px">
      <div class="step-hd open" onclick="toggleCard('${sid}','${sid}-h')">
        <div class="step-icon implemented" id="${sid}-h">${esc(c.call_name?.slice(0,2) ?? '?')}</div>
        <div class="step-info">
          <div class="step-title">${esc(c.call_name)} — attempt ${c.attempt ?? 1}</div>
          <div class="step-sub">LLM call · turn ${esc(String(turnId))}</div>
        </div>
        <div class="step-badges">${tokenBadge}${latBadge}${modelBadge}${statusBadge}</div>
      </div>
      <div class="step-body open" id="${sid}">
        <div class="io-tabbar">
          <button class="io-tab on"  data-iotab="${sid}|input">Input</button>
          <button class="io-tab"     data-iotab="${sid}|output">Output</button>
          <button class="io-tab"     data-iotab="${sid}|prompt">Prompt</button>
        </div>
        <div class="io-pane"      id="iop-${sid}-input">${inputH}</div>
        <div class="io-pane hide" id="iop-${sid}-output">${outputH}</div>
        <div class="io-pane hide" id="iop-${sid}-prompt">${promptH}</div>
      </div>
    </div>`;
  }).join('');

  return `<div class="kk">LLM Calls (${calls.length})</div>${callBlocks}`;
}

function buildSjExecutions(execs) {
  if (!execs.length) return '';
  const rows = execs.map(e => `<tr>
    <td class="meta">${e.attempt}</td>
    <td><span class="bx ${e.status === 'ok' ? 'ok' : 'err'}">${esc(e.status)}</span></td>
    <td style="max-width:300px"><pre class="code-block" style="margin:0;padding:4px 8px;font-size:11px;max-height:80px">${esc(e.sql ?? '—')}</pre></td>
    <td class="meta">${e.row_count ?? '—'}</td>
    <td class="meta">${e.duration_ms != null ? e.duration_ms + 'ms' : '—'}</td>
    <td style="max-width:200px;color:var(--bad);font-size:11.5px">${esc(e.error ?? '')}</td>
  </tr>`).join('');
  return `<div class="kk" style="margin-top:14px">Executions (${execs.length})</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>Attempt</th><th>Status</th><th>SQL</th><th>Rows</th><th>Duration</th><th>Error</th></tr></thead>
      <tbody>${rows}</tbody>
    </table></div>`;
}

function buildSjRetrieval(ret) {
  if (!ret.length) return '';
  const rows = ret.map(r => `<tr>
    <td class="meta">${r.rank}</td>
    <td style="font-family:var(--mono);font-size:11.5px">${esc(r.item_id ?? '—')}</td>
    <td style="min-width:120px">
      <div class="sim-row"><div class="sim-bg"><div class="sim-fill" style="width:${Math.round((r.score ?? 0) * 100)}%"></div></div>
      <span class="meta">${((r.score ?? 0) * 100).toFixed(1)}%</span></div>
    </td>
    <td><span class="bx ${r.included ? 'ok' : 'skip'}">${r.included ? 'included' : 'excluded'}</span></td>
  </tr>`).join('');
  return `<div class="kk" style="margin-top:14px">DDL Retrieval (${ret.length} chunks)</div>
    <div class="tbl-wrap"><table>
      <thead><tr><th>#</th><th>Table</th><th>Cosine similarity</th><th>Used</th></tr></thead>
      <tbody>${rows}</tbody>
    </table></div>`;
}

// ─── Arch Plan page ────────────────────────────────────────────────────────────
function renderArchPage() {
  const el = document.getElementById('page-plan');

  const hero = `<div class="arch-page">
    <div class="arch-hero">
      <h1>Talk-to-DB · Architecture Reference</h1>
      <p>Full pipeline from user message to reply. Every step is live on the backend. Select a session turn in the Inspector tab to see actual input/output data for each step.</p>
    </div>`;

  const flowCards = ARCH.map((step, i) => {
    const decs = step.decisions.length
      ? `<div class="branch-box">
           <div class="bh">Decision branches</div>
           <ul>${step.decisions.map(d => `<li style="margin-bottom:4px"><strong>When</strong> ${esc(d.when)}<br><span style="color:var(--ink3)">→ ${esc(d.action)}</span></li>`).join('')}</ul>
         </div>` : '';

    const arrow = i < ARCH.length - 1
      ? `<div style="display:flex;justify-content:center;padding:4px 0;color:var(--ink3);font-size:20px">↓</div>` : '';

    return `<div class="flow-node impl-node">
      <div style="display:flex;align-items:flex-start;gap:12px;margin-bottom:10px">
        <div>
          <div class="fn-num">${step.num} · ${esc(step.type)}</div>
          <div class="fn-title">${esc(step.label)}</div>
          <div class="fn-sub">${esc(step.sub)}</div>
        </div>
        <div style="margin-left:auto"><span class="bx ok">Live</span></div>
      </div>
      ${decs}
    </div>${arrow}`;
  }).join('');

  // Session JSON schema
  const sessionSchema = `{
  "session_id": "uuid",
  "user": { "crm_id": 123, "employee_id": 456 },
  "pending_clarification": null,            // open clarification JSON while waiting for user
  "turns": [{
    "turn_id": 1,
    "user_message": "raw text",
    "routing":   { "skill": "talk_to_db", "confidence": 0.94, "skipped": false },
    "rephrase":  { "message_type": "new_question", "rephrased_question": "...", "needs_clarification": false, "assumptions": [] },
    "clarification": { "round": 1, "original_prompt": "...", "questions": [{ "id": "q1", "text": "...", "answer": null }] },
    "retrieval": { "samples": [{ "id": "s_12", "score": 0.88 }], "ddls": [{ "id": "d_04", "table": "users", "score": 0.91 }] },
    "planner_attempts": [{
      "attempt": 1, "status": "plan", "confidence": 0.82,
      "queries": [{ "sql": "SELECT ...", "purpose": "..." }],
      "execution": { "status": "error", "error": "column x does not exist", "row_count": null, "duration_ms": 14 }
    }, {
      "attempt": 2, "status": "plan", "confidence": 0.85,
      "queries": [{ "sql": "SELECT ...", "purpose": "..." }],
      "execution": { "status": "ok", "error": null, "row_count": 14, "duration_ms": 120, "result_summary": "14 overdue invoices" }
    }],
    "respond": { "outcome": "answer", "validated": true, "response": "...", "suggested_next": "..." },
    "final_status": "answered",
    "llm_calls": [{ "call": "router", "attempt": 1, "model": "...", "tokens_in": 0, "tokens_out": 0, "latency_ms": 0 }]
  }]
}`;

  el.innerHTML = hero
    + `<h2 class="section">Pipeline flow — step by step</h2>
       <div style="max-width:780px">${flowCards}</div>
       <h2 class="section" style="margin-top:28px">Session JSON schema (logical view)</h2>
       <div class="schema-box">
         <h3>Session JSON — logical view (stored across 5 talk2db.* tables)</h3>
         <pre class="code-block" style="max-height:400px">${esc(sessionSchema)}</pre>
       </div>
       <h2 class="section">DB tables</h2>
       <div class="schema-box">
         <h3>Harness DB (current)</h3>
         <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:8px;font-size:12.5px">
           ${['sessions','episodic_log','trace_log','ddl_chunks','vocabulary_map'].map(t =>
             `<div class="fn-io-box"><code>${t}</code><div style="color:var(--ink3);font-size:11px;margin-top:3px">exists</div></div>`).join('')}
         </div>
       </div>
       <div class="schema-box" style="margin-top:10px">
         <h3>Talk2DB schema (run <code>npm run migrate</code> to create)</h3>
         <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:8px;font-size:12.5px">
           ${['talk2db.sessions','talk2db.turns','talk2db.llm_calls','talk2db.executions','talk2db.retrieval_log'].map(t =>
             `<div class="fn-io-box"><code>${t}</code><div style="color:var(--good);font-size:11px;margin-top:3px">live</div></div>`).join('')}
         </div>
       </div>
    </div>`;
}

// ─── Shared UI helpers ─────────────────────────────────────────────────────────
function buildResultTable(rows, rowCount, error) {
  if (error) return `<div style="font-size:12px;color:var(--bad);padding:8px 10px;background:var(--bad-soft);border-radius:var(--r)">Error: ${esc(error)}</div>`;
  if (!rows || !rows.length) return `<div style="font-size:12px;color:var(--ink3);font-style:italic;margin-top:4px">No rows returned</div>`;
  const cols = Object.keys(rows[0]);
  const tr   = `<tr>${cols.map(c => `<th>${esc(c)}</th>`).join('')}</tr>`;
  const body = rows.map(r =>
    `<tr>${cols.map(c => `<td title="${esc(String(r[c] ?? ''))}">${esc(String(r[c] ?? ''))}</td>`).join('')}</tr>`
  ).join('');
  const foot = rowCount > rows.length
    ? `<tr><td colspan="${cols.length}" style="text-align:center;color:var(--ink3);font-size:11px">…${rowCount - rows.length} more rows (showing first ${rows.length})</td></tr>` : '';
  return `<div class="rt-wrap"><table><thead style="position:sticky;top:0;background:var(--panel);z-index:1">${tr}</thead><tbody>${body}${foot}</tbody></table></div>`;
}

// ─── Chat ──────────────────────────────────────────────────────────────────────
async function send() {
  const ta  = document.getElementById('chat-in');
  const msg = ta.value.trim();
  if (!msg || !currentSessionId) return;
  ta.value = ''; ta.style.height = '';
  document.getElementById('send-btn').disabled = true;
  addBubble('user', msg);
  typing(true);
  resetDiagram();
  PFXS.forEach(pfx => diagSetNode(pfx, 'router', 'hot'));
  setSbStatus(`<span class="ldot"></span>Routing…`);
  try {
    const data = await postJSON('/turn', { message: msg, sessionId: currentSessionId });
    typing(false);
    addBubble('asst', data.answer, data.meta?.sql, true, data.turnId);

    // Show suggested next question as a dismissible chip
    if (data.suggestedNext) {
      addSuggestedNext(data.suggestedNext);
    }
    // Show alternatives as chips if no_relevant_data
    if (data.finalStatus === 'no_relevant_data' && data.alternatives?.length) {
      addAlternatives(data.alternatives);
    }

    if (data.turnId) await selectTurn(data.turnId);
    await loadSessions(true);
    loadSessionJson(currentSessionId);
  } catch (e) {
    typing(false);
    addBubble('asst', 'Error: ' + e.message);
    resetDiagram();
  } finally {
    document.getElementById('send-btn').disabled = false;
  }
}

function addBubble(role, text, sql, scroll = true, turnId = null) {
  const log = document.getElementById('chatlog');
  const d = document.createElement('div');
  d.className = role === 'user' ? 'bu-user' : 'bu-asst';
  if (turnId) d.dataset.turnId = turnId;
  d.textContent = text;
  log.appendChild(d);
  if (sql && turnId) {
    const m = document.createElement('div');
    m.className  = 'bu-meta';
    m.title      = sql;
    m.textContent = sql.slice(0, 85) + (sql.length > 85 ? '…' : '');
    m.onclick    = () => selectTurn(turnId);
    log.appendChild(m);
  }
  if (scroll) log.scrollTop = log.scrollHeight;
}

function addSuggestedNext(text) {
  const log = document.getElementById('chatlog');
  const d = document.createElement('div');
  d.style.cssText = 'display:flex;align-items:center;gap:6px;padding:2px 0';
  d.innerHTML = `<span style="font-size:10.5px;color:var(--ink3)">Next:</span>
    <span class="sug" style="font-size:11.5px" onclick="document.getElementById('chat-in').value=this.textContent.trim();document.getElementById('chat-in').focus()">${esc(text)}</span>`;
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
}

function addAlternatives(alts) {
  const log = document.getElementById('chatlog');
  const d = document.createElement('div');
  d.style.cssText = 'padding:4px 0';
  d.innerHTML = `<div style="font-size:10.5px;color:var(--ink3);margin-bottom:4px">You could ask:</div>
    <div style="display:flex;flex-wrap:wrap;gap:4px">
      ${alts.map(a => `<span class="sug" style="font-size:11px" onclick="document.getElementById('chat-in').value=this.textContent.trim();document.getElementById('chat-in').focus()">${esc(a)}</span>`).join('')}
    </div>`;
  log.appendChild(d);
  log.scrollTop = log.scrollHeight;
}

function typing(on) {
  document.getElementById('typing-row').className = 'typing-row' + (on ? ' on' : '');
}
function onKey(e) { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } }
function useSug(el) { document.getElementById('chat-in').value = el.textContent.trim(); document.getElementById('chat-in').focus(); }

// ─── Turn selection ────────────────────────────────────────────────────────────
async function selectTurn(turnId) {
  currentTurnId = turnId;
  setPage('inspector');
  try {
    const [trace, turns] = await Promise.all([
      getJSON(`/api/turns/${turnId}/trace`),
      getJSON(`/api/sessions/${currentSessionId}/turns`),
    ]);
    currentTrace    = trace;
    currentTurns    = turns;
    currentTurnData = turns.find(t => t.id === turnId) ?? null;
    renderInspectorPage();
    replayDiagram(trace);
  } catch (e) { console.error(e); }
}

// ─── Prompts ───────────────────────────────────────────────────────────────────
async function loadPrompts() {
  try { livePrompts = await getJSON('/api/prompts'); } catch {}
}
async function savePrompt(key) {
  const ta = document.getElementById(`pt-${key}`);
  const btn = document.getElementById(`pb-${key}`);
  if (!ta || !btn) return;
  btn.disabled = true; btn.textContent = 'Saving…';
  try {
    const r = await postJSON('/api/prompts', { [key]: ta.value }, 'PATCH');
    livePrompts = r;
    btn.textContent = 'Saved'; btn.classList.add('saved');
    setTimeout(() => { btn.textContent = 'Save'; btn.classList.remove('saved'); btn.disabled = false; }, 2000);
  } catch { btn.textContent = 'Error'; setTimeout(() => { btn.textContent = 'Save'; btn.disabled = false; }, 2000); }
}

// ─── Resizers ──────────────────────────────────────────────────────────────────
function wireRsz(id, cssVar, key, fromRight, min, max) {
  const el = document.getElementById(id); if (!el) return;
  el.onmousedown = e => {
    e.preventDefault(); document.body.classList.add('rsz-drag');
    const mv = ev => {
      let w = fromRight ? window.innerWidth - ev.clientX : ev.clientX;
      w = Math.max(min, Math.min(max, w));
      css(cssVar, w + 'px'); localStorage.setItem(key, w);
    };
    const up = () => { document.body.classList.remove('rsz-drag'); removeEventListener('mousemove', mv); removeEventListener('mouseup', up); };
    addEventListener('mousemove', mv); addEventListener('mouseup', up);
  };
}

// ─── Utils ────────────────────────────────────────────────────────────────────
async function getJSON(url) { const r = await fetch(url); if (!r.ok) throw new Error(r.status); return r.json(); }
async function postJSON(url, body, method = 'POST') {
  const r = await fetch(url, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(r.status); return r.json();
}
function css(k, v) { document.documentElement.style.setProperty(k, v); }
function esc(s) {
  if (s == null) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function relTime(iso) {
  if (!iso) return ''; const d = Date.now() - new Date(iso).getTime();
  if (d < 60000) return 'just now'; if (d < 3600000) return ~~(d / 60000) + 'm ago';
  if (d < 86400000) return ~~(d / 3600000) + 'h ago'; return ~~(d / 86400000) + 'd ago';
}
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
