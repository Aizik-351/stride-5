// Unlocks admin for the signed-in Google account when the correct passcode is entered.
// The passcode lives only in the ADMIN_PASSCODE environment variable on Vercel.
import crypto from 'node:crypto';
import { admin, requireUser } from './_lib.js';

const MAX_TRIES = 5;          // wrong attempts allowed…
const WINDOW_MS = 60 * 60e3;  // …per hour, per account

const hash = (s) => crypto.createHash('sha256').update(String(s)).digest();

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ code: 'method' });
  const who = await requireUser(req, res);
  if (!who) return;
  const expected = process.env.ADMIN_PASSCODE;
  if (!expected || expected.length < 8) return res.status(500).json({ code: 'not_configured' });

  const uid = who.user.id;
  const { data: att } = await admin.from('admin_attempts').select('n,since').eq('user_id', uid).maybeSingle();
  const fresh = !att || Date.now() - new Date(att.since).getTime() > WINDOW_MS;
  if (!fresh && att.n >= MAX_TRIES) return res.status(429).json({ code: 'locked' });

  const ok = crypto.timingSafeEqual(hash(req.body && req.body.code), hash(expected));
  if (!ok) {
    await admin.from('admin_attempts').upsert({
      user_id: uid,
      n: fresh ? 1 : att.n + 1,
      since: fresh ? new Date().toISOString() : att.since,
    });
    return res.status(403).json({ code: 'wrong' });
  }

  await admin.from('admin_attempts').delete().eq('user_id', uid);
  const { error } = await admin.from('profiles').update({ is_admin: true }).eq('id', uid);
  if (error) return res.status(500).json({ code: 'db' });
  return res.status(200).json({ ok: true });
}
