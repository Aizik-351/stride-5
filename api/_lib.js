// Shared helpers for the API routes. Files starting with "_" are not exposed as routes by Vercel.
import { createClient } from '@supabase/supabase-js';

export const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// Returns the signed-in user and their profile, or sends a 401 and returns null.
export async function requireUser(req, res) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) { res.status(401).json({ code: 'auth' }); return null; }
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) { res.status(401).json({ code: 'auth' }); return null; }
  const { data: profile } = await admin.from('profiles').select('id,is_admin').eq('id', data.user.id).maybeSingle();
  return { user: data.user, profile: profile || { is_admin: false } };
}
