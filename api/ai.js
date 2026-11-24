// Calls the Claude API for lesson writing, syllabus reading and photo transcription.
// The API key stays on the server. Students get a daily limit; admins don't.
import { admin, requireUser } from './_lib.js';

const MODEL = process.env.ANTHROPIC_MODEL || 'claude-sonnet-5-5';
const STUDENT_DAILY_LIMIT = Number(process.env.STUDENT_DAILY_AI_LIMIT || 30);

// LaTeX commands that are easy to break inside JSON: "\frac" would silently turn into a form feed + "rac".
const LATEX = /(?<!\\)\\(frac|dfrac|tfrac|times|text|textrm|mathrm|mathbf|sqrt|ce|cdot|div|pm|mp|rightarrow|leftarrow|longrightarrow|xrightarrow|rightleftharpoons|leftrightarrow|to|Delta|delta|alpha|beta|gamma|theta|lambda|mu|pi|rho|sigma|omega|Omega|phi|approx|neq|leq|geq|le|ge|infty|log|ln|sin|cos|tan|circ|degree|quad|qquad|left|right|overline|vec|hat|ldots|cdots|dots|sum|int|propto|equiv|therefore|because|uparrow|downarrow|angle|triangle|parallel|perp|in|notin|cup|cap|subset|mathbb|operatorname|displaystyle|underline|boxed|prime|partial|nabla|epsilon|varepsilon|eta|kappa|tau|chi|psi|zeta|xi|nu)(?![a-zA-Z])/g;

// Doubles single backslashes that start LaTeX (\frac, \( ...) so the JSON parses as intended.
export function repairLatex(json) {
  return json
    .replace(LATEX, '\\\\$1')
    .replace(/(?<!\\)\\(?=[()\[\]{},;:! %$&#_^~|<>.'-])/g, '\\\\');
}

export function parseJson(text) {
  const t = String(text || '').replace(/```(?:json)?/gi, '');
  const a = t.indexOf('{'), b = t.lastIndexOf('}');
  if (a < 0 || b <= a) throw new Error('no json');
  const body = t.slice(a, b + 1);
  try { return JSON.parse(repairLatex(body)); } catch { return JSON.parse(body); }
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ code: 'method' });
  const who = await requireUser(req, res);
  if (!who) return;

  const { prompt, json, images } = req.body || {};
  if (typeof prompt !== 'string' || !prompt.trim() || prompt.length > 80000) return res.status(400).json({ code: 'bad' });
  const imgs = Array.isArray(images) ? images.slice(0, 4) : [];

  if (!who.profile.is_admin) {
    const { data: n, error } = await admin.rpc('bump_ai_usage', { p_user: who.user.id });
    if (error) return res.status(500).json({ code: 'db' });
    if (n > STUDENT_DAILY_LIMIT) return res.status(429).json({ code: 'limit' });
  }

  const content = [
    ...imgs
      .filter((i) => i && typeof i.data === 'string' && /^image\/(jpeg|png|webp|gif)$/.test(i.type))
      .map((i) => ({ type: 'image', source: { type: 'base64', media_type: i.type, data: i.data } })),
    { type: 'text', text: prompt + (json ? '\n\nRespond with the JSON only, no other text.' : '') },
  ];

  if (!process.env.ANTHROPIC_API_KEY) return res.status(500).json({ code: 'no_key' });

  let r;
  try {
    r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({ model: MODEL, max_tokens: 8000, messages: [{ role: 'user', content }] }),
    });
  } catch {
    return res.status(502).json({ code: 'busy' });
  }
  if (r.status === 429 || r.status === 529) return res.status(503).json({ code: 'busy' });
  if (!r.ok) {
    const body = await r.text().catch(() => '');
    console.error('Claude API error', r.status, body);
    let msg = '';
    try { msg = JSON.parse(body).error.message || ''; } catch {}
    const code = r.status === 401 || r.status === 403 ? 'key'
      : r.status === 404 ? 'model'
      : /credit balance/i.test(msg) ? 'credit'
      : 'ai';
    // Admins see the reason in the app; students just get a plain message.
    return res.status(502).json({ code, detail: who.profile.is_admin ? `Claude API ${r.status}: ${msg}`.slice(0, 300) : undefined });
  }
  const out = await r.json();
  const text = (out.content || []).filter((c) => c.type === 'text').map((c) => c.text).join('');
  if (!json) return res.status(200).json({ text });
  try {
    return res.status(200).json({ value: parseJson(text) });
  } catch {
    const cut = out.stop_reason === 'max_tokens';
    return res.status(502).json({ code: 'ai', detail: who.profile.is_admin ? (cut ? 'reply was cut off before it finished' : 'reply was not valid JSON') : undefined });
  }
}
