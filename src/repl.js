/**
 * Terminal REPL mode — enabled via REPL=true in .env or environment.
 * Lets you converse with the harness directly from the terminal.
 * All console logs stay in place so you can see every step.
 *
 * Usage: REPL=true npm start
 */

import readline from 'readline';
import { randomUUID } from 'crypto';
import { routeTurn } from './skills/router.js';
import { resolveIdentity } from './memory/identity.js';
import { createOrTouchSession, loadConversationHistory } from './memory/session.js';
import { runTalkToDb } from './skills/talk-to-db/index.js';
import { logEpisode, logTrace, updateEpisodeAnswer, startTimer } from './tracing/logger.js';

const SESSION_ID = `repl-${randomUUID().slice(0, 8)}`;
const sessionTurnCount = new Map();

export function startRepl() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '\n\x1b[36mYou:\x1b[0m ',
  });

  console.log('\n\x1b[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1b[0m');
  console.log('\x1b[32m  Virtual Assistant — Terminal REPL\x1b[0m');
  console.log(`\x1b[90m  Session: ${SESSION_ID}\x1b[0m`);
  console.log('\x1b[90m  Type your question. Ctrl+C to exit.\x1b[0m');
  console.log('\x1b[32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\x1b[0m\n');

  rl.prompt();

  rl.on('line', async (line) => {
    const message = line.trim();
    if (!message) { rl.prompt(); return; }

    const tTurn = startTimer();
    const turnNumber = (sessionTurnCount.get(SESSION_ID) ?? 0) + 1;
    sessionTurnCount.set(SESSION_ID, turnNumber);

    console.log(`\n[harness] Incoming turn | session=${SESSION_ID} | message="${message}"`);

    // Session + history
    await createOrTouchSession({ sessionId: SESSION_ID });
    const history = await loadConversationHistory(SESSION_ID);

    // Gate
    const route = await routeTurn(message, { sessionId: SESSION_ID });

    // Identity (no user in REPL — resolve with nulls)
    const identity = await resolveIdentity({ sessionId: SESSION_ID });

    // Episodic log
    const turnId = await logEpisode({
      sessionId: SESSION_ID,
      userId: null,
      turnNumber,
      rawMessage: message,
      routedSkill: route.skill,
      resolvedIntentOrSql: null,
    });

    await logTrace({
      sessionId: SESSION_ID,
      turnId,
      phase: 'gate',
      payload: { skill: route.skill, confidence: route.confidence, reason: route.reason },
      durationMs: tTurn(),
    });

    let answer;

    if (route.skill === 'talk_to_db') {
      const result = await runTalkToDb(message, { sessionId: SESSION_ID }, identity, turnId, history);
      answer = result.answer;
      await updateEpisodeAnswer(turnId, answer, result.sql);
    } else if (route.skill === 'chit_chat') {
      answer = 'Hi! How can I help you?';
      await updateEpisodeAnswer(turnId, answer, null);
    } else {
      answer = "I'm not sure how to help with that.";
      await updateEpisodeAnswer(turnId, answer, null);
    }

    console.log(`\n\x1b[33mAssistant:\x1b[0m ${answer}\n`);

    rl.prompt();
  });

  rl.on('close', () => {
    console.log('\n\x1b[90mREPL session ended.\x1b[0m\n');
    process.exit(0);
  });
}
