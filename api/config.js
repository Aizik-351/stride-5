// Public settings the browser needs to talk to Supabase. The anon key is meant to be public;
// Row Level Security in supabase/schema.sql is what protects the data.
export default function handler(req, res) {
  res.setHeader('Cache-Control', 'public, max-age=300');
  res.status(200).json({
    url: process.env.SUPABASE_URL, anon: process.env.SUPABASE_ANON_KEY, vapid: process.env.VAPID_PUBLIC_KEY || null,
    // Google OAuth Web client ID (public). When set, sign-in uses Google's own button, so Google shows this site's address.
    google: process.env.GOOGLE_CLIENT_ID || null,
    // AI features are on only when a Claude API key is set. Without one, content is imported instead.
    ai: !!process.env.ANTHROPIC_API_KEY });
}
