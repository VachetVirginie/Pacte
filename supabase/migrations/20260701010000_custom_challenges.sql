-- Retire uniquement le challenge d'exemple s'il n'a encore aucune activité.
delete from public.challenges c
where c.title = '30 squats par jour'
  and not exists (select 1 from public.checkins ci where ci.challenge_id = c.id);

-- Une équipe est désormais créée vide : son premier challenge est choisi dans l'app.
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

  return v_team_id;
end;
$$;

create or replace function public.create_challenge(
  p_title text,
  p_description text default '',
  p_daily_target integer default 1,
  p_duration_days integer default 30,
  p_reward text default 'La gloire éternelle',
  p_reward_at integer default 80
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.team_members;
  v_challenge_id uuid;
begin
  select * into v_member
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc
  limit 1;

  if v_member.id is null then raise exception 'Crée ou rejoins une équipe avant de lancer un challenge'; end if;
  if nullif(trim(p_title), '') is null then raise exception 'Le nom du challenge est obligatoire'; end if;
  if p_daily_target < 1 then raise exception 'L''objectif quotidien doit être supérieur à zéro'; end if;
  if p_duration_days < 1 or p_duration_days > 365 then raise exception 'La durée doit être comprise entre 1 et 365 jours'; end if;

  insert into public.challenges (
    team_id, title, description, daily_target, reward, reward_at, starts_on, ends_on
  ) values (
    v_member.team_id,
    trim(p_title),
    coalesce(trim(p_description), ''),
    p_daily_target,
    coalesce(nullif(trim(p_reward), ''), 'La gloire éternelle'),
    greatest(1, least(100, p_reward_at)),
    current_date,
    current_date + p_duration_days - 1
  )
  returning id into v_challenge_id;

  return v_challenge_id;
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

  select id into v_member_id
  from public.team_members
  where team_id = v_team.id and user_id = auth.uid();

  select * into v_challenge
  from public.challenges
  where team_id = v_team.id
  order by created_at desc limit 1;

  if v_challenge.id is null then
    return jsonb_build_object(
      'mode', 'live',
      'challengeOnboarding', true,
      'teamName', v_team.name,
      'inviteCode', v_team.invite_code,
      'currentUserId', v_member_id
    );
  end if;

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
  into v_posts from (
    select * from public.posts where team_id = v_team.id order by created_at desc limit 50
  ) p;

  select case when count(*) = 0 then 0 else round(
    100.0 * count(*) filter (where exists (
      select 1 from public.checkins ci
      where ci.member_id = tm.id and ci.challenge_id = v_challenge.id and ci.checkin_day = current_date
    )) / count(*)
  )::int end
  into v_progress
  from public.team_members tm where tm.team_id = v_team.id;

  return jsonb_build_object(
    'mode', 'live',
    'currentUserId', v_member_id,
    'inviteCode', v_team.invite_code,
    'challenge', jsonb_build_object(
      'id', v_challenge.id,
      'team', v_team.name,
      'title', v_challenge.title,
      'description', v_challenge.description,
      'dailyTarget', v_challenge.daily_target,
      'durationDays', (v_challenge.ends_on - v_challenge.starts_on + 1),
      'reward', v_challenge.reward,
      'rewardAt', v_challenge.reward_at
    ),
    'members', v_members,
    'posts', v_posts,
    'progress', v_progress
  );
end;
$$;

grant execute on function public.create_challenge(text, text, integer, integer, text, integer) to authenticated;
