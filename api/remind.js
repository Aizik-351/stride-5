// Sends escalating daily reminders. Supabase calls this every 15 minutes (see supabase/reminders.sql).
// For each student with reminders on, it checks today's target in their own time zone:
//   stage 1 (regular)      from their study time, or 4 pm if they didn't set one
//   stage 2 (serious)      from 7 pm (or 90 min after stage 1 if that's later)
//   stage 3 (most serious) from 9:30 pm (or 1 hour after stage 2), up to 11:30 pm
// Each stage is sent at most once a day, and nothing is sent once the target is met.
import webpush from 'web-push';
import { admin } from './_lib.js';

const hm = (s) => { const [h, m] = String(s).split(':').map(Number); return (h || 0) * 60 + (m || 0); };

function localNow(tz) {
  const fmt = (zone) => Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date()).map((p) => [p.type, p.value]));
  let p;
  try { p = fmt(tz || 'UTC'); } catch { p = fmt('UTC'); }
  return { d: `${p.year}-${p.month}-${p.day}`, m: Number(p.hour) * 60 + Number(p.minute) };
}

const ses = (n) => `${n} session${n === 1 ? '' : 's'}`;
function message(stage, pct, left, target, mins) {
  if (stage === 1) return pct > 0
    ? { title: 'Keep going', body: `You're ${pct}% through today's study target. ${ses(left)} to go.` }
    : { title: 'Time to study', body: `Today's target is ${ses(target)}${mins ? `, about ${mins} minutes` : ''}. Start your first one now.` };
  if (stage === 2) return { title: `Only ${pct}% of today's target done`, body: `The evening is here and you still have ${ses(left)} to do to stay on track for your exam.` };
  return { title: `Last call: ${pct}% of today's target`, body: "The day is almost over. Even one session now keeps you closer to your goal." };
}

export default async function handler(req, res) {
  if (!process.env.CRON_SECRET || req.headers.authorization !== `Bearer ${process.env.CRON_SECRET}`) {
    return res.status(401).json({ code: 'auth' });
  }
  if (!process.env.VAPID_PUBLIC_KEY || !process.env.VAPID_PRIVATE_KEY) return res.status(500).json({ code: 'not_configured' });
  webpush.setVapidDetails(process.env.VAPID_SUBJECT || 'mailto:admin@example.com', process.env.VAPID_PUBLIC_KEY, process.env.VAPID_PRIVATE_KEY);

  const { data: subs, error } = await admin.from('push_subs').select('user_id,endpoint,sub');
  if (error) return res.status(500).json({ code: 'db' });
  const byUser = new Map();
  for (const s of subs || []) (byUser.get(s.user_id) || byUser.set(s.user_id, []).get(s.user_id)).push(s);
  const ids = [...byUser.keys()];
  if (!ids.length) return res.status(200).json({ sent: 0 });

  const profiles = [], logs = [];
  for (let i = 0; i < ids.length; i += 200) {
    const chunk = ids.slice(i, i + 200);
    const [p, l] = await Promise.all([
      admin.from('profiles').select('id,tz,sched,today').in('id', chunk),
      admin.from('push_log').select('user_id,d,stage').in('user_id', chunk),
    ]);
    profiles.push(...(p.data || [])); logs.push(...(l.data || []));
  }
  const logMap = new Map(logs.map((l) => [l.user_id + '|' + l.d, l.stage]));

  let sent = 0;
  for (const p of profiles) {
    const now = localNow(p.tz);
    const entry = p.sched && p.sched[now.d];
    if (!entry || !entry.m) continue;                         // not a study day, or nothing due
    // Targets and progress are in sessions of content.
    const done = p.today && p.today.d === now.d ? Number(p.today.done ?? 0) || 0 : 0;
    if (done >= entry.m) continue;                            // target met: stay quiet
    const s1 = entry.t ? hm(entry.t) : 16 * 60;
    const s2 = Math.max(19 * 60, s1 + 90);
    const s3 = Math.min(23 * 60 + 30, Math.max(21 * 60 + 30, s2 + 60));
    const stage = now.m >= s3 ? 3 : now.m >= s2 ? 2 : now.m >= s1 ? 1 : 0;
    if (!stage || (logMap.get(p.id + '|' + now.d) || 0) >= stage) continue;

    const pct = Math.floor((100 * done) / entry.m);
    const payload = JSON.stringify({ ...message(stage, pct, Math.max(1, Math.ceil(entry.m - done - 1e-6)), entry.m, entry.mins), stage, tag: 'stride-daily' });
    let delivered = false;
    for (const s of byUser.get(p.id) || []) {
      try { await webpush.sendNotification(s.sub, payload, { TTL: 3600 }); delivered = true; sent++; }
      catch (err) {
        if (err.statusCode === 404 || err.statusCode === 410) {
          await admin.from('push_subs').delete().eq('user_id', p.id).eq('endpoint', s.endpoint);
        }
      }
    }
    if (delivered) await admin.from('push_log').upsert({ user_id: p.id, d: now.d, stage });
  }
  return res.status(200).json({ sent });
}
