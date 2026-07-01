alter table public.challenges
  add column if not exists target_mode text not null default 'fixed'
    check (target_mode in ('fixed', 'linear')),
  add column if not exists start_target integer,
  add column if not exists daily_increment integer not null default 0;

update public.challenges
set start_target = daily_target
where start_target is null;

alter table public.challenges
  alter column start_target set not null,
  add constraint challenges_start_target_positive check (start_target > 0),
  add constraint challenges_daily_increment_range check (daily_increment between 0 and 10000);

create or replace function public.create_challenge_v2(
  p_title text,
  p_description text default '',
  p_target_mode text default 'fixed',
  p_start_target integer default 1,
  p_daily_increment integer default 0,
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
  v_increment integer;
begin
  select * into v_member
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc
  limit 1;

  if v_member.id is null then raise exception 'Crée ou rejoins une équipe avant de lancer un challenge'; end if;
  if nullif(trim(p_title), '') is null then raise exception 'Le nom du challenge est obligatoire'; end if;
  if p_target_mode not in ('fixed', 'linear') then raise exception 'Type de progression inconnu'; end if;
  if p_start_target < 1 then raise exception 'L''objectif de départ doit être supérieur à zéro'; end if;
  if p_daily_increment < 0 then raise exception 'La progression quotidienne ne peut pas être négative'; end if;
  if p_duration_days < 1 or p_duration_days > 365 then raise exception 'La durée doit être comprise entre 1 et 365 jours'; end if;

  v_increment := case when p_target_mode = 'linear' then p_daily_increment else 0 end;

  insert into public.challenges (
    team_id, title, description, daily_target, target_mode, start_target,
    daily_increment, reward, reward_at, starts_on, ends_on
  ) values (
    v_member.team_id,
    trim(p_title),
    coalesce(trim(p_description), ''),
    p_start_target,
    p_target_mode,
    p_start_target,
    v_increment,
    coalesce(nullif(trim(p_reward), ''), 'La gloire éternelle'),
    greatest(1, least(100, p_reward_at)),
    current_date,
    current_date + p_duration_days - 1
  )
  returning id into v_challenge_id;

  return v_challenge_id;
end;
$$;

create or replace function public.check_in_challenge(
  p_challenge_id uuid,
  p_note text default null,
  p_mood text default '🔥'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.team_members;
  v_challenge public.challenges;
begin
  select * into v_member
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc
  limit 1;

  select * into v_challenge
  from public.challenges
  where id = p_challenge_id and team_id = v_member.team_id;

  if v_member.id is null or v_challenge.id is null then raise exception 'Challenge inaccessible'; end if;
  if current_date < v_challenge.starts_on or current_date > v_challenge.ends_on then raise exception 'Ce challenge n''est pas actif aujourd''hui'; end if;

  insert into public.checkins (challenge_id, member_id, mood)
  values (v_challenge.id, v_member.id, p_mood)
  on conflict (challenge_id, member_id, checkin_day) do nothing;

  if nullif(trim(p_note), '') is not null then
    insert into public.posts (team_id, author_id, body)
    values (v_member.team_id, v_member.id, trim(p_note));
  end if;
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
  v_challenges jsonb;
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
  where team_id = v_team.id and ends_on >= current_date
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
    'id', tm.id,
    'name', tm.display_name,
    'initials', tm.initials,
    'color', tm.color,
    'checkedIn', exists (
      select 1 from public.checkins ci
      where ci.member_id = tm.id
        and ci.challenge_id = v_challenge.id
        and ci.checkin_day = current_date
    )
  ) order by tm.created_at), '[]'::jsonb)
  into v_members
  from public.team_members tm
  where tm.team_id = v_team.id;

  select coalesce(jsonb_agg(challenge_json order by created_at desc), '[]'::jsonb)
  into v_challenges
  from (
    select
      c.created_at,
      jsonb_build_object(
        'id', c.id,
        'team', v_team.name,
        'title', c.title,
        'description', c.description,
        'targetMode', c.target_mode,
        'startTarget', c.start_target,
        'dailyIncrement', c.daily_increment,
        'todayTarget', greatest(1, c.start_target + (
          case when c.target_mode = 'linear'
            then greatest(0, current_date - c.starts_on) * c.daily_increment
            else 0
          end
        )),
        'dailyTarget', greatest(1, c.start_target + (
          case when c.target_mode = 'linear'
            then greatest(0, current_date - c.starts_on) * c.daily_increment
            else 0
          end
        )),
        'dayNumber', greatest(1, current_date - c.starts_on + 1),
        'durationDays', c.ends_on - c.starts_on + 1,
        'reward', c.reward,
        'rewardAt', c.reward_at,
        'checkedIn', exists (
          select 1 from public.checkins ci
          where ci.challenge_id = c.id
            and ci.member_id = v_member_id
            and ci.checkin_day = current_date
        ),
        'doneCount', (
          select count(*)::int from public.checkins ci
          join public.team_members tm2 on tm2.id = ci.member_id
          where ci.challenge_id = c.id
            and ci.checkin_day = current_date
            and tm2.team_id = v_team.id
        ),
        'progress', (
          select case when count(*) = 0 then 0 else round(
            100.0 * count(*) filter (where exists (
              select 1 from public.checkins ci
              where ci.member_id = tm3.id
                and ci.challenge_id = c.id
                and ci.checkin_day = current_date
            )) / count(*)
          )::int end
          from public.team_members tm3 where tm3.team_id = v_team.id
        ),
        'checkedMemberIds', coalesce((
          select jsonb_agg(ci.member_id)
          from public.checkins ci
          join public.team_members tm4 on tm4.id = ci.member_id
          where ci.challenge_id = c.id
            and ci.checkin_day = current_date
            and tm4.team_id = v_team.id
        ), '[]'::jsonb)
      ) as challenge_json
    from public.challenges c
    where c.team_id = v_team.id
      and c.starts_on <= current_date
      and c.ends_on >= current_date
  ) active_challenges;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'authorId', p.author_id,
    'body', p.body,
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
  into v_posts
  from (select * from public.posts where team_id = v_team.id order by created_at desc limit 50) p;

  return jsonb_build_object(
    'mode', 'live',
    'currentUserId', v_member_id,
    'inviteCode', v_team.invite_code,
    'challenge', v_challenges->0,
    'challenges', v_challenges,
    'members', v_members,
    'posts', v_posts,
    'progress', coalesce((v_challenges->0->>'progress')::int, 0)
  );
end;
$$;

grant execute on function public.create_challenge_v2(text, text, text, integer, integer, integer, text, integer) to authenticated;
grant execute on function public.check_in_challenge(uuid, text, text) to authenticated;
