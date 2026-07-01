create table public.bonus_definitions (
  code text primary key,
  title text not null,
  description text not null,
  emoji text not null,
  effect_mode text not null check (effect_mode in ('multiply', 'add')),
  effect_value numeric not null,
  created_at timestamptz not null default now()
);

insert into public.bonus_definitions (code, title, description, emoji, effect_mode, effect_value)
values
  ('double_target', 'Double dose', 'Double l’objectif du jour d’un collègue. Oui, c’est personnel.', '⚡', 'multiply', 2),
  ('half_target', 'Coup de pouce', 'Divise par deux l’objectif du jour d’un collègue.', '🪽', 'multiply', 0.5),
  ('plus_five', 'Cinq de plus', 'Ajoute 5 répétitions à l’objectif du jour.', '🌶️', 'add', 5),
  ('plus_ten', 'Cadeau empoisonné', 'Ajoute 10 répétitions à l’objectif du jour.', '🎁', 'add', 10)
on conflict (code) do update set
  title = excluded.title,
  description = excluded.description,
  emoji = excluded.emoji,
  effect_mode = excluded.effect_mode,
  effect_value = excluded.effect_value;

create table public.bonus_cards (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  owner_member_id uuid not null references public.team_members(id) on delete cascade,
  target_member_id uuid references public.team_members(id) on delete cascade,
  definition_code text not null references public.bonus_definitions(code),
  status text not null default 'available' check (status in ('available', 'assigned')),
  earned_on date not null default current_date,
  assigned_at timestamptz,
  seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (challenge_id, earned_on)
);

alter table public.bonus_definitions enable row level security;
alter table public.bonus_cards enable row level security;

create policy "authenticated users read bonus definitions" on public.bonus_definitions
  for select to authenticated using (true);
create policy "members read team bonus cards" on public.bonus_cards
  for select to authenticated using (public.is_team_member(team_id));

create or replace function public.get_bonus_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.team_members;
  v_owned jsonb;
  v_received jsonb;
  v_effects jsonb;
begin
  select * into v_member
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc limit 1;

  if v_member.id is null then
    return jsonb_build_object('ownedCards', '[]'::jsonb, 'receivedCards', '[]'::jsonb, 'effects', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bc.id,
    'mode', 'owned',
    'challengeId', bc.challenge_id,
    'title', bd.title,
    'description', bd.description,
    'emoji', bd.emoji,
    'effectMode', bd.effect_mode,
    'effectValue', bd.effect_value
  ) order by bc.created_at), '[]'::jsonb)
  into v_owned
  from public.bonus_cards bc
  join public.bonus_definitions bd on bd.code = bc.definition_code
  where bc.owner_member_id = v_member.id
    and bc.status = 'available'
    and bc.earned_on = current_date;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', bc.id,
    'mode', 'received',
    'challengeId', bc.challenge_id,
    'title', bd.title,
    'description', bd.description,
    'emoji', bd.emoji,
    'effectMode', bd.effect_mode,
    'effectValue', bd.effect_value,
    'senderName', owner.display_name
  ) order by bc.assigned_at), '[]'::jsonb)
  into v_received
  from public.bonus_cards bc
  join public.bonus_definitions bd on bd.code = bc.definition_code
  join public.team_members owner on owner.id = bc.owner_member_id
  where bc.target_member_id = v_member.id
    and bc.status = 'assigned'
    and bc.seen_at is null
    and bc.earned_on = current_date;

  select coalesce(jsonb_agg(jsonb_build_object(
    'challengeId', bc.challenge_id,
    'effectMode', bd.effect_mode,
    'effectValue', bd.effect_value,
    'title', bd.title,
    'emoji', bd.emoji
  )), '[]'::jsonb)
  into v_effects
  from public.bonus_cards bc
  join public.bonus_definitions bd on bd.code = bc.definition_code
  where bc.target_member_id = v_member.id
    and bc.status = 'assigned'
    and bc.earned_on = current_date;

  return jsonb_build_object(
    'ownedCards', v_owned,
    'receivedCards', v_received,
    'effects', v_effects
  );
end;
$$;

create or replace function public.assign_bonus_card(p_bonus_id uuid, p_target_member_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner public.team_members;
  v_card public.bonus_cards;
  v_target public.team_members;
  v_definition public.bonus_definitions;
begin
  select * into v_owner
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc limit 1;

  select * into v_card
  from public.bonus_cards
  where id = p_bonus_id
    and owner_member_id = v_owner.id
    and status = 'available'
  for update;

  if v_card.id is null then raise exception 'Cette carte n''est plus disponible'; end if;

  if p_target_member_id is null then
    select * into v_target
    from public.team_members
    where team_id = v_card.team_id
      and id <> v_owner.id
    order by random()
    limit 1;
  else
    select * into v_target
    from public.team_members
    where id = p_target_member_id
      and team_id = v_card.team_id;
  end if;

  if v_target.id is null then v_target := v_owner; end if;

  update public.bonus_cards
  set target_member_id = v_target.id,
      status = 'assigned',
      assigned_at = now()
  where id = v_card.id;

  select * into v_definition
  from public.bonus_definitions
  where code = v_card.definition_code;

  insert into public.posts (team_id, author_id, body)
  values (
    v_card.team_id,
    v_owner.id,
    v_definition.emoji || ' ' || v_owner.display_name || ' joue « ' ||
    v_definition.title || ' » sur ' || v_target.display_name || ' !'
  );

  insert into public.notifications (user_id, title, body)
  values (
    v_target.user_id,
    'BAM ! Une carte pour toi ' || v_definition.emoji,
    v_owner.display_name || ' vient de te jouer « ' || v_definition.title || ' ».'
  );

  return v_target.id;
end;
$$;

create or replace function public.acknowledge_bonus_card(p_bonus_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.bonus_cards bc
  set seen_at = now()
  from public.team_members tm
  where bc.id = p_bonus_id
    and bc.target_member_id = tm.id
    and tm.user_id = auth.uid();
$$;

create or replace function public.toggle_reaction(p_post_id uuid, p_emoji text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member_id uuid;
begin
  select tm.id into v_member_id
  from public.team_members tm
  join public.posts p on p.team_id = tm.team_id
  where tm.user_id = auth.uid() and p.id = p_post_id;

  if v_member_id is null then raise exception 'Message inaccessible'; end if;

  if exists (
    select 1 from public.reactions
    where post_id = p_post_id and member_id = v_member_id and emoji = p_emoji
  ) then
    delete from public.reactions
    where post_id = p_post_id and member_id = v_member_id and emoji = p_emoji;
  else
    insert into public.reactions (post_id, member_id, emoji)
    values (p_post_id, v_member_id, p_emoji);
  end if;
end;
$$;

create or replace function public.get_wall_posts()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_posts jsonb;
begin
  select team_id into v_team_id
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc limit 1;

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
      select jsonb_object_agg(counts.emoji, counts.total)
      from (
        select r.emoji, count(*)::int total
        from public.reactions r
        where r.post_id = p.id
        group by r.emoji
      ) counts
    ), '{}'::jsonb),
    'reactionPeople', coalesce((
      select jsonb_object_agg(people.emoji, people.names)
      from (
        select r.emoji, jsonb_agg(tm.display_name order by tm.display_name) names
        from public.reactions r
        join public.team_members tm on tm.id = r.member_id
        where r.post_id = p.id
        group by r.emoji
      ) people
    ), '{}'::jsonb)
  ) order by p.created_at desc), '[]'::jsonb)
  into v_posts
  from (
    select * from public.posts
    where team_id = v_team_id
    order by created_at desc
    limit 50
  ) p;

  return v_posts;
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
  v_checkin_id uuid;
  v_definition_code text;
  v_bonus_id uuid;
begin
  select * into v_member
  from public.team_members
  where user_id = auth.uid()
  order by created_at desc limit 1;

  select * into v_challenge
  from public.challenges
  where id = p_challenge_id and team_id = v_member.team_id;

  if v_member.id is null or v_challenge.id is null then raise exception 'Challenge inaccessible'; end if;
  if current_date < v_challenge.starts_on or current_date > v_challenge.ends_on then raise exception 'Ce challenge n''est pas actif aujourd''hui'; end if;

  insert into public.checkins (challenge_id, member_id, mood)
  values (v_challenge.id, v_member.id, p_mood)
  on conflict (challenge_id, member_id, checkin_day) do nothing
  returning id into v_checkin_id;

  if v_checkin_id is not null then
    if (
      select count(*) from public.checkins
      where challenge_id = v_challenge.id and checkin_day = current_date
    ) = 1 and not exists (
      select 1 from public.bonus_cards
      where challenge_id = v_challenge.id and earned_on = current_date
    ) then
      select code into v_definition_code
      from public.bonus_definitions
      order by random()
      limit 1;

      insert into public.bonus_cards (
        team_id, challenge_id, owner_member_id, definition_code
      ) values (
        v_member.team_id, v_challenge.id, v_member.id, v_definition_code
      )
      returning id into v_bonus_id;

      insert into public.posts (team_id, author_id, body)
      select
        v_member.team_id,
        v_member.id,
        bd.emoji || ' ' || v_member.display_name ||
        ' est la première personne à valider et gagne la carte « ' || bd.title || ' » !'
      from public.bonus_definitions bd
      where bd.code = v_definition_code;
    end if;
  end if;

  if nullif(trim(p_note), '') is not null then
    insert into public.posts (team_id, author_id, body)
    values (v_member.team_id, v_member.id, trim(p_note));
  end if;
end;
$$;

grant execute on function public.get_bonus_state() to authenticated;
grant execute on function public.assign_bonus_card(uuid, uuid) to authenticated;
grant execute on function public.acknowledge_bonus_card(uuid) to authenticated;
grant execute on function public.toggle_reaction(uuid, text) to authenticated;
grant execute on function public.get_wall_posts() to authenticated;

alter publication supabase_realtime add table public.bonus_cards;
