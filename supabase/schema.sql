-- Stride database setup. Paste all of this into Supabase: SQL Editor → New query → Run.

-- ---------- profiles: one row per Google account ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  is_admin boolean not null default false,
  state jsonb not null default '{}'::jsonb,   -- the student's progress
  xp integer not null default 0,
  wk text,                                     -- Monday of the current week (YYYY-MM-DD)
  wxp integer not null default 0,              -- XP earned this week
  updated_at timestamptz not null default now(),
  constraint nickname_format check (nickname is null or nickname ~ '^[A-Za-z0-9 _.-]{3,20}$')
);
create unique index if not exists profiles_nickname_unique on public.profiles (lower(nickname));
alter table public.profiles enable row level security;

drop policy if exists "read own profile" on public.profiles;
create policy "read own profile" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Students may change their nickname and progress, but never is_admin.
revoke all on public.profiles from anon;
revoke insert, update, delete on public.profiles from authenticated;
grant select on public.profiles to authenticated;
-- (added for study plans and reminders; safe to re-run)
alter table public.profiles add column if not exists tz text;
alter table public.profiles add column if not exists sched jsonb not null default '{}'::jsonb;  -- daily targets for the next 14 days
alter table public.profiles add column if not exists today jsonb not null default '{}'::jsonb;  -- progress today toward the target
alter table public.profiles add column if not exists category text;                           -- e.g. "100 Level"; leaderboards are per category
alter table public.profiles add column if not exists device text;                             -- the one device currently signed in to this account
alter table public.profiles add column if not exists device_at timestamptz;
grant update (nickname, state, xp, wk, wxp, tz, sched, today, category, device, device_at, updated_at) on public.profiles to authenticated;

-- Create a profile automatically when someone signs in with Google for the first time.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- ---------- leaderboard: nicknames and XP only ----------
create or replace view public.leaderboard as
  select id, nickname, xp, wk, wxp, category from public.profiles where nickname is not null;
revoke all on public.leaderboard from anon, authenticated;
grant select on public.leaderboard to authenticated;

-- ---------- shared content (admins write, signed-in students read) ----------
create table if not exists public.subjects (
  id text primary key,
  title text not null,
  cat text not null,
  color text,
  units jsonb not null default '[]'::jsonb,
  mats jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.subjects add column if not exists exam_date date;           -- deadline set by an admin
alter table public.subjects add column if not exists session_min integer not null default 15;

create table if not exists public.materials (
  id text primary key,
  subject_id text not null references public.subjects(id) on delete cascade,
  name text,
  text text
);
create table if not exists public.lessons (
  id text primary key,                 -- <unit id>-L<level>
  subject_id text not null references public.subjects(id) on delete cascade,
  f jsonb not null
);
alter table public.lessons add column if not exists notes text;   -- optional extra notes for the level (Markdown with LaTeX)

-- images cut out of materials and past questions (files live in the "images" storage bucket)
create table if not exists public.images (
  id text primary key,
  subject_id text not null references public.subjects(id) on delete cascade,
  path text not null,            -- file path in the storage bucket
  src text,                      -- where it came from, e.g. "chem-notes.pdf · page 12"
  caption text,
  kind text not null default 'material',   -- 'material' or 'pq'
  v integer not null default 1,  -- bumps each time an admin replaces it
  created_at timestamptz not null default now()
);
-- past questions, kept exactly as imported
create table if not exists public.pq (
  id text primary key,
  subject_id text not null references public.subjects(id) on delete cascade,
  unit text,                     -- matching syllabus unit, if found
  year text,
  src text,                      -- file it came from
  q jsonb not null,              -- {p, o[], a, img, sol, steps, d, ai_answer, check, ai_sol, hidden}
  created_at timestamptz not null default now()
);
create index if not exists pq_subject on public.pq (subject_id);
alter table public.pq add column if not exists batch text;   -- one id per import, so a whole import can be deleted at once
create index if not exists pq_batch on public.pq (batch);
create index if not exists images_subject on public.images (subject_id);

-- study materials split into searchable parts (whole books work; each part remembers its PDF pages)
create table if not exists public.chunks (
  id bigint generated always as identity primary key,
  subject_id text not null references public.subjects(id) on delete cascade,
  mat_id text not null references public.materials(id) on delete cascade,
  seq integer not null,
  page_from integer,
  page_to integer,
  text text not null,
  tsv tsvector generated always as (to_tsvector('english', text)) stored
);
create index if not exists chunks_tsv on public.chunks using gin (tsv);
create index if not exists chunks_subject on public.chunks (subject_id);
create index if not exists chunks_mat on public.chunks (mat_id);

do $$
declare t text;
begin
  foreach t in array array['subjects','materials','lessons','images','pq','chunks'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "read content" on public.%I', t);
    execute format('create policy "read content" on public.%I for select to authenticated using (true)', t);
    execute format('drop policy if exists "admins write" on public.%I', t);
    execute format('create policy "admins write" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- ---------- lesson levels written for one student (when an admin hasn't prepared them) ----------
create table if not exists public.gen (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  f jsonb not null,
  primary key (user_id, key)
);
alter table public.gen enable row level security;
drop policy if exists "own generated lessons" on public.gen;
create policy "own generated lessons" on public.gen for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.gen from anon;

-- ---------- phone reminder subscriptions (one per device) ----------
create table if not exists public.push_subs (
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  sub jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, endpoint)
);
alter table public.push_subs enable row level security;
drop policy if exists "own push subscriptions" on public.push_subs;
create policy "own push subscriptions" on public.push_subs for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
revoke all on public.push_subs from anon;

-- ---------- facts and questions students flag as wrong or unclear ----------
-- One flag per student per item; flagging again changes the reason. Students see and change only their own flags;
-- admins see all of them and mark them fixed.
create table if not exists public.flags (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  subject_id text not null references public.subjects(id) on delete cascade,
  item text not null,          -- "L|<lesson id>|<fact>" for a fact or worked example, "L|<lesson id>|<fact>|<question>" for its question, "P|<past question id>"
  kind text not null,          -- 'fact', 'worked', 'question', 'theory'
  reason text not null,
  note text,
  snap text,                   -- the text the student saw, in case it is edited later
  status text not null default 'open',   -- 'open' or 'fixed'
  created_at timestamptz not null default now(),
  constraint flags_kind check (kind in ('fact','worked','question','theory')),
  constraint flags_status check (status in ('open','fixed')),
  constraint flags_len check (char_length(item) <= 200 and char_length(reason) <= 80 and char_length(coalesce(note,'')) <= 500 and char_length(coalesce(snap,'')) <= 1000)
);
create unique index if not exists flags_user_item on public.flags (user_id, item);
create index if not exists flags_subject on public.flags (subject_id, status);
alter table public.flags enable row level security;
drop policy if exists "own flags" on public.flags;
create policy "own flags" on public.flags for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and status = 'open');
drop policy if exists "admins manage flags" on public.flags;
create policy "admins manage flags" on public.flags for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
revoke all on public.flags from anon;
grant select, insert, update, delete on public.flags to authenticated;

-- ---------- server-only tables (no policies: only the server key can use them) ----------
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default current_date,
  n integer not null default 0,
  primary key (user_id, day)
);
create table if not exists public.admin_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  n integer not null default 0,
  since timestamptz not null default now()
);
create table if not exists public.push_log (
  user_id uuid not null references auth.users(id) on delete cascade,
  d text not null,          -- local date
  stage integer not null,   -- highest reminder stage sent that day
  primary key (user_id, d)
);
alter table public.push_log enable row level security;
revoke all on public.push_log from anon, authenticated;
alter table public.ai_usage enable row level security;
alter table public.admin_attempts enable row level security;
revoke all on public.ai_usage, public.admin_attempts from anon, authenticated;

create or replace function public.bump_ai_usage(p_user uuid) returns integer
language sql security definer set search_path = public as $$
  insert into public.ai_usage (user_id, day, n) values (p_user, current_date, 1)
  on conflict (user_id, day) do update set n = public.ai_usage.n + 1
  returning n
$$;
revoke execute on function public.bump_ai_usage(uuid) from public, anon, authenticated;

-- ---------- image storage: anyone can view, only admins can add, replace or remove ----------
insert into storage.buckets (id, name, public) values ('images', 'images', true) on conflict (id) do nothing;
drop policy if exists "admins add images" on storage.objects;
create policy "admins add images" on storage.objects for insert to authenticated with check (bucket_id = 'images' and public.is_admin());
drop policy if exists "admins change images" on storage.objects;
create policy "admins change images" on storage.objects for update to authenticated using (bucket_id = 'images' and public.is_admin());
drop policy if exists "admins remove images" on storage.objects;
create policy "admins remove images" on storage.objects for delete to authenticated using (bucket_id = 'images' and public.is_admin());
drop policy if exists "admins list images" on storage.objects;
create policy "admins list images" on storage.objects for select to authenticated using (bucket_id = 'images' and public.is_admin());

-- ---------- admin: students and activity (admins only; nicknames, never email addresses) ----------
-- Dropped first: Postgres can't change the columns of an existing function, so re-running would fail here.
drop function if exists public.admin_students();
create or replace function public.admin_students()
returns table (
  id uuid, nickname text, category text, xp integer, wxp integer, wk text,
  joined timestamptz, last_sign_in timestamptz, last_study text, streak integer, best integer,
  tdays integer, lessons integer, courses jsonb, quiz jsonb, tmet jsonb, reminders integer,
  sched jsonb, today jsonb, study jsonb
)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.is_admin() then
    raise exception 'Only admins can see student activity';
  end if;
  return query
  select p.id, p.nickname, p.category, p.xp, p.wxp, p.wk,
         u.created_at, u.last_sign_in_at,
         p.state->>'last',
         coalesce((p.state->>'streak')::numeric::int, 0),
         coalesce((p.state->>'best')::numeric::int, 0),
         coalesce((p.state->>'tdays')::numeric::int, 0),
         coalesce((p.state->>'n')::numeric::int, 0),
         coalesce(p.state->'plan'->'subs', '[]'::jsonb),
         coalesce(p.state->'quiz', '{}'::jsonb),
         coalesce(p.state->'tmet', '{}'::jsonb),
         (select count(*)::int from public.push_subs s where s.user_id = p.id),
         p.sched, p.today, p.state->'st'
  from public.profiles p
  join auth.users u on u.id = p.id;
end; $$;
revoke execute on function public.admin_students() from public, anon;
grant execute on function public.admin_students() to authenticated;

-- ---------- finds the passages in a course's materials that best match a topic ----------
-- Words are matched by their stem ("distil" also finds "distillation"). Each matching word scores by how rare it is
-- across the course's materials (so "electrolysis" counts for far more than "law"), words from the topic name count
-- double, and repeats count a little more. Runs with the caller's own permissions.
drop function if exists public.search_chunks(text, text, integer);
create or replace function public.search_chunks(p_subject text, p_query text, p_focus text default null, p_limit integer default 8)
returns table (id bigint, mat_id text, page_from integer, page_to integer, text text, rank double precision)
language sql stable security invoker set search_path = public as $$
  with terms as (
    select lexeme, max(w) as w from (
      select lexeme, 1.0 as w from unnest(to_tsvector('english', coalesce(p_query, '')))
      union all
      select lexeme, 2.0 from unnest(to_tsvector('english', coalesce(p_focus, '')))
    ) t group by lexeme
  ),
  total as (select count(*)::float as n from public.chunks where subject_id = p_subject),
  df as (
    select s.word, s.ndoc from ts_stat(format('select tsv from public.chunks where subject_id = %L', p_subject)) s
    where s.word in (select lexeme from terms)
  ),
  q as (select to_tsquery('simple', string_agg(quote_literal(lexeme), ' | ')) as tq from terms),
  cand as (
    select c.id, c.tsv from public.chunks c, q
    where c.subject_id = p_subject and q.tq is not null and c.tsv @@ q.tq
  ),
  scored as (
    select cand.id, sum(terms.w * ln((total.n + 1) / (df.ndoc + 0.5)) * (1 + ln(coalesce(array_length(u.positions, 1), 1)))) as score
    from cand
    cross join lateral unnest(cand.tsv) u
    join terms on terms.lexeme = u.lexeme
    join df on df.word = u.lexeme
    cross join total
    group by cand.id
  )
  select c.id, c.mat_id, c.page_from, c.page_to, c.text, scored.score
  from scored join public.chunks c on c.id = scored.id
  order by scored.score desc
  limit least(greatest(coalesce(p_limit, 8), 1), 20)
$$;
revoke execute on function public.search_chunks(text, text, text, integer) from public, anon;
grant execute on function public.search_chunks(text, text, text, integer) to authenticated;
