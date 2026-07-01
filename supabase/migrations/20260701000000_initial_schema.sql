create extension if not exists pgcrypto;

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 60),
  invite_code text not null unique,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 40),
  initials text not null,
  color text not null default 'green',
  created_at timestamptz not null default now(),
  unique (team_id, user_id)
);

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  title text not null,
  description text not null default '',
  daily_target integer not null default 30 check (daily_target > 0),
  reward text not null default 'Café-croissants',
  reward_at integer not null default 80 check (reward_at between 1 and 100),
  starts_on date not null default current_date,
  ends_on date not null default (current_date + 30),
  created_at timestamptz not null default now()
);

create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  member_id uuid not null references public.team_members(id) on delete cascade,
  checkin_day date not null default current_date,
  mood text,
  created_at timestamptz not null default now(),
  unique (challenge_id, member_id, checkin_day)
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  author_id uuid not null references public.team_members(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);

create table public.reactions (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  member_id uuid not null references public.team_members(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 12),
  created_at timestamptz not null default now(),
  unique (post_id, member_id, emoji)
);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  url text not null default '/',
  created_at timestamptz not null default now()
);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.challenges enable row level security;
alter table public.checkins enable row level security;
alter table public.posts enable row level security;
alter table public.reactions enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.notifications enable row level security;

create or replace function public.is_team_member(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.team_members
    where team_id = p_team_id and user_id = auth.uid()
  );
$$;

create policy "members can read their teams" on public.teams
  for select to authenticated using (public.is_team_member(id));
create policy "members can read team members" on public.team_members
  for select to authenticated using (public.is_team_member(team_id));
create policy "members can read challenges" on public.challenges
  for select to authenticated using (public.is_team_member(team_id));
create policy "members can read checkins" on public.checkins
  for select to authenticated using (
    exists (
      select 1 from public.challenges c
      where c.id = challenge_id and public.is_team_member(c.team_id)
    )
  );
create policy "members can read posts" on public.posts
  for select to authenticated using (public.is_team_member(team_id));
create policy "members can read reactions" on public.reactions
  for select to authenticated using (
    exists (
      select 1 from public.posts p
      where p.id = post_id and public.is_team_member(p.team_id)
    )
  );
create policy "users manage own push subscriptions" on public.push_subscriptions
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users read own notifications" on public.notifications
  for select to authenticated using (user_id = auth.uid());

create or replace function public.make_initials(p_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(left(split_part(trim(p_name), ' ', 1), 1) ||
    case when position(' ' in trim(p_name)) > 0
      then left(reverse(split_part(reverse(trim(p_name)), ' ', 1)), 1)
      else ''
    end);
$$;

create or replace function public.create_team(p_team_name text, p_member_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_code text;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  v_code := upper(substr(md5(gen_random_uuid()::text), 1, 7));

  insert into public.teams (name, invite_code, owner_id)
  values (trim(p_team_name), v_code, auth.uid())
  returning id into v_team_id;

  insert into public.team_members (team_id, user_id, display_name, initials, color)
  values (v_team_id, auth.uid(), trim(p_member_name), public.make_initials(p_member_name), 'green');

  insert into public.challenges (team_id, title, description)
  values (v_team_id, '30 squats par jour', 'Un mois pour transformer nos pauses café en cuisses d''acier.');

  return v_team_id;
end;
$$;

create or replace function public.join_team(p_invite_code text, p_member_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_count integer;
  v_colors text[] := array['coral','blue','yellow','green','stone'];
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  select id into v_team_id from public.teams where invite_code = upper(trim(p_invite_code));
  if v_team_id is null then raise exception 'Code d''invitation inconnu'; end if;

  select count(*) into v_count from public.team_members where team_id = v_team_id;
  insert into public.team_members (team_id, user_id, display_name, initials, color)
  values (v_team_id, auth.uid(), trim(p_member_name), public.make_initials(p_member_name), v_colors[(v_count % 5) + 1])
  on conflict (team_id, user_id) do update set display_name = excluded.display_name;
  return v_team_id;
end;
$$;

create or replace function public.get_app_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team public.teams;
  v_challenge public.challenges;
  v_member_id uuid;
  v_members jsonb;
  v_posts jsonb;
  v_progress integer;
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;

  select t.* into v_team
  from public.teams t
  join public.team_members tm on tm.team_id = t.id
  where tm.user_id = auth.uid()
  order by tm.created_at desc limit 1;

  if v_team.id is null then return jsonb_build_object('onboarding', true); end if;

  select * into v_challenge from public.challenges
  where team_id = v_team.id order by created_at desc limit 1;
  select id into v_member_id from public.team_members
  where team_id = v_team.id and user_id = auth.uid();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tm.id, 'name', tm.display_name, 'initials', tm.initials, 'color', tm.color,
    'checkedIn', exists (
      select 1 from public.checkins ci
      where ci.member_id = tm.id and ci.challenge_id = v_challenge.id and ci.checkin_day = current_date
    )
  ) order by tm.created_at), '[]'::jsonb)
  into v_members from public.team_members tm where tm.team_id = v_team.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'authorId', p.author_id, 'body', p.body,
    'time', case
      when p.created_at > now() - interval '2 minutes' then 'à l''instant'
      when p.created_at > now() - interval '1 hour' then 'il y a ' || greatest(1, extract(minute from now() - p.created_at)::int) || ' min'
      else 'plus tôt'
    end,
    'reactions', coalesce((
      select jsonb_object_agg(r.emoji, r.total)
      from (select emoji, count(*)::int total from public.reactions where post_id = p.id group by emoji) r
    ), '{}'::jsonb)
  ) order by p.created_at desc), '[]'::jsonb)
  into v_posts from (select * from public.posts where team_id = v_team.id order by created_at desc limit 50) p;

  select case when count(*) = 0 then 0 else round(
    100.0 * count(*) filter (where exists (
      select 1 from public.checkins ci
      where ci.member_id = tm.id and ci.challenge_id = v_challenge.id and ci.checkin_day = current_date
    )) / count(*)
  )::int end into v_progress
  from public.team_members tm where tm.team_id = v_team.id;

  return jsonb_build_object(
    'mode', 'live',
    'currentUserId', v_member_id,
    'inviteCode', v_team.invite_code,
    'challenge', jsonb_build_object(
      'id', v_challenge.id, 'team', v_team.name, 'title', v_challenge.title,
      'description', v_challenge.description, 'dailyTarget', v_challenge.daily_target,
      'reward', v_challenge.reward, 'rewardAt', v_challenge.reward_at
    ),
    'members', v_members, 'posts', v_posts, 'progress', v_progress
  );
end;
$$;

create or replace function public.check_in(p_note text default null, p_mood text default '🔥')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.team_members;
  v_challenge_id uuid;
begin
  select * into v_member from public.team_members where user_id = auth.uid() order by created_at desc limit 1;
  if v_member.id is null then raise exception 'Aucune équipe'; end if;
  select id into v_challenge_id from public.challenges where team_id = v_member.team_id order by created_at desc limit 1;

  insert into public.checkins (challenge_id, member_id, mood)
  values (v_challenge_id, v_member.id, p_mood)
  on conflict (challenge_id, member_id, checkin_day) do nothing;

  if nullif(trim(p_note), '') is not null then
    insert into public.posts (team_id, author_id, body)
    values (v_member.team_id, v_member.id, trim(p_note));
  end if;
end;
$$;

create or replace function public.add_post(p_body text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_member public.team_members; v_id uuid;
begin
  select * into v_member from public.team_members where user_id = auth.uid() order by created_at desc limit 1;
  insert into public.posts (team_id, author_id, body)
  values (v_member.team_id, v_member.id, trim(p_body)) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.add_reaction(p_post_id uuid, p_emoji text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_member_id uuid;
begin
  select tm.id into v_member_id
  from public.team_members tm join public.posts p on p.team_id = tm.team_id
  where tm.user_id = auth.uid() and p.id = p_post_id;
  if v_member_id is null then raise exception 'Message inaccessible'; end if;
  insert into public.reactions (post_id, member_id, emoji)
  values (p_post_id, v_member_id, p_emoji)
  on conflict (post_id, member_id, emoji) do nothing;
end;
$$;

create or replace function public.save_push_subscription(p_subscription jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.push_subscriptions (user_id, endpoint, subscription)
  values (auth.uid(), p_subscription->>'endpoint', p_subscription)
  on conflict (endpoint) do update set
    user_id = auth.uid(), subscription = excluded.subscription, updated_at = now();
$$;

create or replace function public.send_nudge(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_sender public.team_members; v_target public.team_members;
begin
  select * into v_sender from public.team_members where user_id = auth.uid() order by created_at desc limit 1;
  select * into v_target from public.team_members where id = p_member_id and team_id = v_sender.team_id;
  if v_target.id is null then raise exception 'Collègue introuvable'; end if;
  insert into public.notifications (user_id, title, body)
  values (v_target.user_id, 'Petit coup de coude 👀', v_sender.display_name || ' t''attend pour le défi du jour.');
end;
$$;

grant execute on function public.get_app_state() to authenticated;
grant execute on function public.create_team(text, text) to authenticated;
grant execute on function public.join_team(text, text) to authenticated;
grant execute on function public.check_in(text, text) to authenticated;
grant execute on function public.add_post(text) to authenticated;
grant execute on function public.add_reaction(uuid, text) to authenticated;
grant execute on function public.save_push_subscription(jsonb) to authenticated;
grant execute on function public.send_nudge(uuid) to authenticated;

alter publication supabase_realtime add table public.team_members;
alter publication supabase_realtime add table public.checkins;
alter publication supabase_realtime add table public.posts;
alter publication supabase_realtime add table public.reactions;
