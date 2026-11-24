-- Runs the reminder check every 15 minutes. Do this AFTER deploying and adding the reminder keys in Vercel.
-- 1. Replace YOUR-APP.vercel.app with your Vercel address.
-- 2. Replace YOUR_CRON_SECRET with the CRON_SECRET value you added in Vercel.
-- 3. Paste into Supabase: SQL Editor → New query → Run.

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('stride-reminders') where exists (select 1 from cron.job where jobname = 'stride-reminders');

select cron.schedule(
  'stride-reminders',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := 'https://YOUR-APP.vercel.app/api/remind',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer YOUR_CRON_SECRET"}'::jsonb,
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);

-- To check it's running: select * from cron.job_run_details order by start_time desc limit 5;
-- To stop reminders:     select cron.unschedule('stride-reminders');
