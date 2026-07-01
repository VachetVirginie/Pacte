-- Une session anonyme peut être perdue (navigation privée, données du site
-- effacées, changement d'appareil). Le code d'équipe + le même pseudo
-- rattache désormais la nouvelle session au membre existant.
create or replace function public.join_team(p_invite_code text, p_member_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_id uuid;
  v_member public.team_members;
  v_current_member_id uuid;
  v_count integer;
  v_colors text[] := array['coral','blue','yellow','green','stone'];
  v_name text := trim(p_member_name);
begin
  if auth.uid() is null then raise exception 'Authentification requise'; end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then
    raise exception 'Le pseudo doit contenir entre 1 et 40 caractères';
  end if;

  select id into v_team_id
  from public.teams
  where invite_code = upper(trim(p_invite_code));

  if v_team_id is null then raise exception 'Code d''invitation inconnu'; end if;

  select id into v_current_member_id
  from public.team_members
  where team_id = v_team_id and user_id = auth.uid();

  if v_current_member_id is not null then
    update public.team_members
    set display_name = v_name,
        initials = public.make_initials(v_name)
    where id = v_current_member_id;
    return v_team_id;
  end if;

  select * into v_member
  from public.team_members
  where team_id = v_team_id
    and lower(trim(display_name)) = lower(v_name)
  order by created_at desc
  limit 1
  for update;

  if v_member.id is not null then
    update public.team_members
    set user_id = auth.uid(),
        display_name = v_name,
        initials = public.make_initials(v_name)
    where id = v_member.id;

    update public.teams
    set owner_id = auth.uid()
    where id = v_team_id and owner_id = v_member.user_id;

    return v_team_id;
  end if;

  select count(*) into v_count
  from public.team_members
  where team_id = v_team_id;

  insert into public.team_members (team_id, user_id, display_name, initials, color)
  values (
    v_team_id,
    auth.uid(),
    v_name,
    public.make_initials(v_name),
    v_colors[(v_count % 5) + 1]
  );

  return v_team_id;
end;
$$;

grant execute on function public.join_team(text, text) to authenticated;
