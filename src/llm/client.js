import { GoogleGenAI } from '@google/genai';
import OpenAI from 'openai';

const PRIMARY_MODEL = 'gemini-flash-lite-latest';
const FALLBACK_MODEL = 'llama-3.1-70b-versatile'; // Groq

let genai = null;
let groq = null;

function getGenAI() {
  if (!genai) genai = new GoogleGenAI({ apiKey: process.env.LLM_PRIMARY_KEY });
  return genai;
}

function getGroq() {
  if (!groq) {
    groq = new OpenAI({
      apiKey: process.env.LLM_FALLBACK_KEY,
      baseURL: 'https://api.groq.com/openai/v1',
    });
  }
  return groq;
}

/**
 * Unified LLM call. All skill code calls this — never a provider SDK directly.
 *
 * @param {string} systemPrompt
 * @param {string} userPrompt
 * @param {{ temperature?: number, maxTokens?: number, useFallback?: boolean }} options
 * @returns {Promise<{ text: string, usage: { inputTokens: number, outputTokens: number }, provider: string }>}
 */
export async function llmCall(systemPrompt, userPrompt, options = {}) {
  const { temperature = 0.1, maxTokens = 4096, useFallback = false } = options;

  if (!useFallback && process.env.LLM_PRIMARY_KEY) {
    try {
      return await callGemini(systemPrompt, userPrompt, { temperature, maxTokens });
    } catch (err) {
      console.warn('[llmClient] Gemini failed, trying fallback:', err.message);
      if (process.env.LLM_FALLBACK_KEY) {
        return await callGroq(systemPrompt, userPrompt, { temperature, maxTokens });
      }
      throw err;
    }
  }

  return await callGroq(systemPrompt, userPrompt, { temperature, maxTokens });
}

async function callGemini(systemPrompt, userPrompt, { temperature, maxTokens }) {
  const client = getGenAI();
  const response = await client.models.generateContent({
    model: PRIMARY_MODEL,
    contents: userPrompt,
    config: {
      systemInstruction: systemPrompt,
      temperature,
      maxOutputTokens: maxTokens,
    },
  });

  const text = response.text;
  const usage = response.usageMetadata ?? {};

  return {
    text,
    usage: {
      inputTokens: usage.promptTokenCount ?? 0,
      outputTokens: usage.candidatesTokenCount ?? 0,
    },
    provider: 'gemini',
    model: PRIMARY_MODEL,
  };
}

async function callGroq(systemPrompt, userPrompt, { temperature, maxTokens }) {
  const client = getGroq();
  const completion = await client.chat.completions.create({
    model: FALLBACK_MODEL,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt },
    ],
    temperature,
    max_tokens: maxTokens,
  });

  const choice = completion.choices[0];
  const usage = completion.usage ?? {};

  return {
    text: choice.message.content,
    usage: {
      inputTokens: usage.prompt_tokens ?? 0,
      outputTokens: usage.completion_tokens ?? 0,
    },
    provider: 'groq',
    model: FALLBACK_MODEL,
  };
}
