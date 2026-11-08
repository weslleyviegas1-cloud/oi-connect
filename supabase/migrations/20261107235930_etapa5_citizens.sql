-- WORLD ECONOMY — ETAPA 5: cidadãos, perfis e identificação
-- Migration aditiva. Preserva profiles.player_number e todos os dados das etapas anteriores.
begin;

create table if not exists public.citizen_profiles (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  birth_date_sim date,
  residence_city text,
  bio text,
  public_profile_enabled boolean not null default true,
  show_player_number boolean not null default false,
  show_residence_city boolean not null default false,
  show_bio boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint citizen_profiles_city_length check (residence_city is null or length(residence_city) <= 100),
  constraint citizen_profiles_bio_length check (bio is null or length(bio) <= 500)
);

alter table public.profiles
  add column if not exists country_joined_at timestamptz;

update public.profiles
set country_joined_at = created_at
where country_id is not null and country_joined_at is null;

create table if not exists public.citizen_documents (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  country_id uuid references public.countries(id),
  document_type text not null,
  document_number text not null unique,
  status text not null default 'active',
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  issued_by uuid references public.profiles(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint citizen_documents_type_check check (document_type in ('national_identity','other')),
  constraint citizen_documents_status_check check (status in ('active','expired','cancelled','under_review'))
);

create table if not exists public.citizen_passports (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  country_id uuid references public.countries(id),
  passport_number text unique,
  status text not null default 'not_issued',
  issued_at timestamptz,
  expires_at timestamptz,
  issued_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint citizen_passports_status_check check (status in ('not_issued','active','expired','cancelled','under_review'))
);

create table if not exists public.nationality_change_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  from_country_id uuid references public.countries(id),
  to_country_id uuid not null references public.countries(id),
  status text not null default 'pending',
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  review_note text,
  constraint nationality_change_requests_status_check check (status in ('pending','approved','rejected','cancelled')),
  constraint nationality_change_requests_distinct_countries check (from_country_id is distinct from to_country_id)
);

create unique index if not exists nationality_change_one_pending_per_profile_uidx
  on public.nationality_change_requests(profile_id) where status='pending';
create index if not exists nationality_change_requests_status_requested_idx
  on public.nationality_change_requests(status,requested_at desc);
create index if not exists nationality_change_requests_country_idx
  on public.nationality_change_requests(to_country_id,status);

create table if not exists public.citizen_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  description text,
  country_id uuid references public.countries(id),
  actor_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists citizen_history_profile_created_idx
  on public.citizen_history(profile_id,created_at desc);

create table if not exists public.citizen_nickname_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  field_name text not null,
  old_value text,
  new_value text,
  changed_at timestamptz not null default now()
);
create index if not exists citizen_nickname_history_profile_changed_idx
  on public.citizen_nickname_history(profile_id,changed_at desc);

create table if not exists public.citizen_nationality_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  from_country_id uuid references public.countries(id),
  to_country_id uuid references public.countries(id),
  reason text,
  actor_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists citizen_nationality_history_profile_created_idx
  on public.citizen_nationality_history(profile_id,created_at desc);

create table if not exists public.citizen_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  description text not null,
  object_type text,
  object_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists citizen_notifications_recipient_created_idx
  on public.citizen_notifications(recipient_id,created_at desc);
create index if not exists citizen_notifications_unread_idx
  on public.citizen_notifications(recipient_id,is_read,created_at desc);

-- Todas as tabelas pessoais são protegidas por RLS. Escritas sensíveis passam pelas RPCs.
alter table public.citizen_profiles enable row level security;
alter table public.citizen_documents enable row level security;
alter table public.citizen_passports enable row level security;
alter table public.nationality_change_requests enable row level security;
alter table public.citizen_history enable row level security;
alter table public.citizen_nickname_history enable row level security;
alter table public.citizen_nationality_history enable row level security;
alter table public.citizen_notifications enable row level security;

drop policy if exists citizen_profiles_read_own on public.citizen_profiles;
create policy citizen_profiles_read_own on public.citizen_profiles
  for select to authenticated using (profile_id=auth.uid());
drop policy if exists citizen_documents_read_own on public.citizen_documents;
create policy citizen_documents_read_own on public.citizen_documents
  for select to authenticated using (profile_id=auth.uid());
drop policy if exists citizen_passports_read_own on public.citizen_passports;
create policy citizen_passports_read_own on public.citizen_passports
  for select to authenticated using (profile_id=auth.uid());
drop policy if exists nationality_requests_read_own on public.nationality_change_requests;
create policy nationality_requests_read_own on public.nationality_change_requests
  for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());
drop policy if exists citizen_history_read_own on public.citizen_history;
create policy citizen_history_read_own on public.citizen_history
  for select to authenticated using (profile_id=auth.uid());
drop policy if exists citizen_nickname_history_read_own on public.citizen_nickname_history;
create policy citizen_nickname_history_read_own on public.citizen_nickname_history
  for select to authenticated using (profile_id=auth.uid());
drop policy if exists citizen_nationality_history_read_own on public.citizen_nationality_history;
create policy citizen_nationality_history_read_own on public.citizen_nationality_history
  for select to authenticated using (profile_id=auth.uid());
drop policy if exists citizen_notifications_read_own on public.citizen_notifications;
create policy citizen_notifications_read_own on public.citizen_notifications
  for select to authenticated using (recipient_id=auth.uid());
drop policy if exists citizen_notifications_update_own on public.citizen_notifications;
create policy citizen_notifications_update_own on public.citizen_notifications
  for update to authenticated using (recipient_id=auth.uid())
  with check (recipient_id=auth.uid());

revoke all on public.citizen_profiles, public.citizen_documents, public.citizen_passports,
  public.nationality_change_requests, public.citizen_history, public.citizen_nickname_history,
  public.citizen_nationality_history, public.citizen_notifications from public, anon, authenticated;
grant select on public.citizen_profiles, public.citizen_documents, public.citizen_passports,
  public.nationality_change_requests, public.citizen_history, public.citizen_nickname_history,
  public.citizen_nationality_history, public.citizen_notifications to authenticated;
grant update(is_read) on public.citizen_notifications to authenticated;

create or replace function public.get_my_citizen_profile()
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare v_profile public.profiles%rowtype; v_extra public.citizen_profiles%rowtype; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  select * into v_profile from public.profiles where id=auth.uid();
  if not found then raise exception 'Perfil do cidadão não encontrado.'; end if;
  insert into public.citizen_profiles(profile_id) values(auth.uid()) on conflict(profile_id) do nothing;
  select * into v_extra from public.citizen_profiles where profile_id=auth.uid();
  select jsonb_build_object(
    'id',v_profile.id,'username',v_profile.username,'avatar_url',v_profile.avatar_url,
    'created_at',v_profile.created_at,'player_number',v_profile.player_number,
    'role',v_profile.role,'country_id',v_profile.country_id,
    'registration_status',v_profile.registration_status,'minecraft_username',v_profile.minecraft_username,
    'account_status',v_profile.account_status,'citizen_status',
      case when v_profile.account_status='suspended' then 'suspended' else 'active' end,
    'country_joined_at',v_profile.country_joined_at,
    'country_name',(select c.name from public.countries c where c.id=v_profile.country_id),
    'country_flag',(select c.flag from public.countries c where c.id=v_profile.country_id),
    'country_capital',(select c.capital from public.countries c where c.id=v_profile.country_id),
    'country_continent',(select c.continent from public.countries c where c.id=v_profile.country_id),
    'birth_date_sim',v_extra.birth_date_sim,'residence_city',v_extra.residence_city,'bio',v_extra.bio,
    'public_profile_enabled',v_extra.public_profile_enabled,
    'show_player_number',v_extra.show_player_number,
    'show_residence_city',v_extra.show_residence_city,'show_bio',v_extra.show_bio
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.update_my_citizen_profile(
  p_birth_date_sim date,
  p_residence_city text,
  p_bio text,
  p_public_profile_enabled boolean,
  p_show_player_number boolean,
  p_show_residence_city boolean,
  p_show_bio boolean
)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  if length(coalesce(p_residence_city,''))>100 or length(coalesce(p_bio,''))>500 then
    raise exception 'A cidade deve ter até 100 caracteres e a descrição até 500.';
  end if;
  insert into public.citizen_profiles(
    profile_id,birth_date_sim,residence_city,bio,public_profile_enabled,
    show_player_number,show_residence_city,show_bio,updated_at
  ) values (
    auth.uid(),p_birth_date_sim,nullif(trim(p_residence_city),''),nullif(trim(p_bio),''),
    coalesce(p_public_profile_enabled,true),coalesce(p_show_player_number,false),
    coalesce(p_show_residence_city,false),coalesce(p_show_bio,false),now()
  )
  on conflict(profile_id) do update set
    birth_date_sim=excluded.birth_date_sim,residence_city=excluded.residence_city,bio=excluded.bio,
    public_profile_enabled=excluded.public_profile_enabled,show_player_number=excluded.show_player_number,
    show_residence_city=excluded.show_residence_city,show_bio=excluded.show_bio,updated_at=now();
  return public.get_my_citizen_profile();
end;
$$;

create or replace function public.update_my_minecraft_nickname(p_nickname text)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare v_old text; v_new text:=nullif(trim(p_nickname),'');
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  if v_new is null or length(v_new)<3 or length(v_new)>32 then
    raise exception 'O nickname deve ter entre 3 e 32 caracteres.';
  end if;
  select minecraft_username into v_old from public.profiles where id=auth.uid() for update;
  if not found then raise exception 'Perfil não encontrado.'; end if;
  if v_old is distinct from v_new then
    update public.profiles set minecraft_username=v_new where id=auth.uid();
    insert into public.citizen_nickname_history(profile_id,field_name,old_value,new_value)
      values(auth.uid(),'minecraft_username',v_old,v_new);
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
      select auth.uid(),'nickname_changed','Nickname atualizado',
        'O nickname do Minecraft foi atualizado.',country_id,auth.uid()
      from public.profiles where id=auth.uid();
  end if;
  return jsonb_build_object('status','updated','minecraft_username',v_new);
end;
$$;

create or replace function public.request_nationality_change(p_country_id uuid)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare v_profile public.profiles%rowtype; v_country public.countries%rowtype; v_request uuid;
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  select * into v_profile from public.profiles where id=auth.uid() for update;
  if not found then raise exception 'Perfil não encontrado.'; end if;
  if v_profile.role<>'citizen' or v_profile.registration_status<>'active'
    or coalesce(v_profile.account_status,'active')<>'active' then
    raise exception 'Somente cidadãos com conta ativa podem solicitar mudança de nacionalidade.';
  end if;
  if exists(select 1 from public.government_members gm where gm.profile_id=auth.uid() and gm.status='active') then
    raise exception 'Encerre seu vínculo governamental ativo antes de solicitar mudança de nacionalidade.';
  end if;
  select * into v_country from public.countries
    where id=p_country_id and is_active=true and citizens_available=true;
  if not found then raise exception 'O país selecionado não está aceitando novos cidadãos.'; end if;
  if v_profile.country_id is not distinct from p_country_id then
    raise exception 'Você já possui nacionalidade deste país.';
  end if;
  if exists(select 1 from public.nationality_change_requests where profile_id=auth.uid() and status='pending') then
    raise exception 'Você já possui uma solicitação pendente.';
  end if;
  insert into public.nationality_change_requests(profile_id,from_country_id,to_country_id)
    values(auth.uid(),v_profile.country_id,p_country_id) returning id into v_request;
  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
    values(auth.uid(),'nationality_requested','Mudança de nacionalidade solicitada',
      'Solicitação enviada para análise do Super Admin.',v_profile.country_id,auth.uid());
  insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
    select id,'nationality_request','Nova solicitação de nacionalidade',
      'Uma solicitação de mudança de nacionalidade aguarda análise.','nationality_change_request',v_request
    from public.profiles where role='super_admin';
  return jsonb_build_object('status','pending','request_id',v_request,'to_country_id',p_country_id);
end;
$$;

create or replace function public.get_public_citizen_profile(p_profile_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path=public,auth
as $$
declare v_profile public.profiles%rowtype; v_extra public.citizen_profiles%rowtype;
begin
  if p_profile_id is null then raise exception 'Perfil inválido.'; end if;
  select * into v_profile from public.profiles where id=p_profile_id;
  if not found then return null; end if;
  select * into v_extra from public.citizen_profiles where profile_id=p_profile_id;
  if not coalesce(v_extra.public_profile_enabled,true) then
    if auth.uid() is distinct from p_profile_id and not public.is_world_admin() then
      raise exception 'Este cidadão desativou seu perfil público.';
    end if;
  end if;
  return jsonb_build_object(
    'username',v_profile.username,'minecraft_username',v_profile.minecraft_username,
    'country_name',(select c.name from public.countries c where c.id=v_profile.country_id),
    'country_flag',(select c.flag from public.countries c where c.id=v_profile.country_id),
    'player_number',case when coalesce(v_extra.show_player_number,false) then v_profile.player_number else null end,
    'residence_city',case when coalesce(v_extra.show_residence_city,false) then v_extra.residence_city else null end,
    'bio',case when coalesce(v_extra.show_bio,false) then v_extra.bio else null end
  );
end;
$$;

create or replace function public.get_country_citizens(p_country_id uuid,p_search text default null)
returns table(
  profile_id uuid,username text,minecraft_username text,player_number bigint,
  avatar_url text,role text,joined_at timestamptz,citizen_status text
)
language plpgsql stable security definer
set search_path=public,auth
as $$
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  if not (public.is_world_admin() or public.is_country_president(p_country_id)
    or public.has_government_permission(p_country_id,'citizen.read',null,null)) then
    raise exception 'Você não possui permissão para consultar cidadãos deste país.';
  end if;
  return query
    select p.id,p.username,p.minecraft_username,p.player_number,p.avatar_url,p.role,
      coalesce(p.country_joined_at,p.created_at),
      case when p.account_status='suspended' then 'suspended' else 'active' end
    from public.profiles p
    where p.country_id=p_country_id and p.registration_status='active'
      and coalesce(p.account_status,'active')='active'
      and p.role in ('citizen','president')
      and (nullif(trim(p_search),'') is null
        or p.username ilike '%'||trim(p_search)||'%'
        or coalesce(p.minecraft_username,'') ilike '%'||trim(p_search)||'%'
        or p.player_number::text ilike '%'||trim(p_search)||'%')
    order by p.player_number;
end;
$$;

create or replace function public.admin_list_nationality_change_requests()
returns table(
  id uuid,profile_id uuid,from_country_id uuid,to_country_id uuid,status text,
  requested_at timestamptz,reviewed_at timestamptz,review_note text,
  username text,player_number bigint,minecraft_username text,
  from_country_name text,from_country_flag text,to_country_name text,to_country_flag text
)
language plpgsql stable security definer
set search_path=public,auth
as $$
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode consultar solicitações de nacionalidade.'; end if;
  return query
    select r.id,r.profile_id,r.from_country_id,r.to_country_id,r.status,r.requested_at,
      r.reviewed_at,r.review_note,p.username,p.player_number,p.minecraft_username,
      fc.name,fc.flag,tc.name,tc.flag
    from public.nationality_change_requests r
    join public.profiles p on p.id=r.profile_id
    left join public.countries fc on fc.id=r.from_country_id
    join public.countries tc on tc.id=r.to_country_id
    order by case when r.status='pending' then 0 else 1 end,r.requested_at desc;
end;
$$;

create or replace function public.admin_review_nationality_change(
  p_request_id uuid,p_decision text,p_note text default null
)
returns jsonb
language plpgsql security definer
set search_path=public,auth
as $$
declare v_request public.nationality_change_requests%rowtype;
  v_profile public.profiles%rowtype; v_country public.countries%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode revisar mudanças de nacionalidade.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;
  select * into v_request from public.nationality_change_requests
    where id=p_request_id and status='pending' for update;
  if not found then raise exception 'Solicitação não encontrada ou já revisada.'; end if;
  select * into v_profile from public.profiles where id=v_request.profile_id for update;
  if not found then raise exception 'Cidadão não encontrado.'; end if;
  select * into v_country from public.countries where id=v_request.to_country_id for update;
  if p_decision='approved' then
    if not v_country.is_active or not v_country.citizens_available then
      raise exception 'O país de destino não está mais aceitando cidadãos.';
    end if;
    if v_profile.country_id is distinct from v_request.from_country_id then
      raise exception 'A nacionalidade atual mudou desde a solicitação. Atualize e revise novamente.';
    end if;
    if v_profile.role<>'citizen' or v_profile.registration_status<>'active'
      or coalesce(v_profile.account_status,'active')<>'active' then
      raise exception 'A conta não está elegível para mudança de nacionalidade.';
    end if;
    if exists(select 1 from public.government_members gm where gm.profile_id=v_profile.id and gm.status='active')
      or v_profile.role='president' then
      raise exception 'O cidadão possui vínculo governamental ativo e não pode mudar de país.';
    end if;
    update public.profiles set country_id=v_country.id,country_joined_at=now()
      where id=v_profile.id;
    insert into public.citizen_nationality_history(profile_id,from_country_id,to_country_id,reason,actor_id)
      values(v_profile.id,v_request.from_country_id,v_request.to_country_id,
        coalesce(nullif(trim(p_note),''),'Mudança aprovada pelo Super Admin.'),auth.uid());
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
      values(v_profile.id,'nationality_changed','Nacionalidade alterada',
        'Sua mudança de nacionalidade foi aprovada pelo Super Admin.',v_country.id,auth.uid());
  else
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
      values(v_profile.id,'nationality_rejected','Solicitação de nacionalidade rejeitada',
        coalesce(nullif(trim(p_note),''),'A solicitação foi rejeitada pelo Super Admin.'),
        v_profile.country_id,auth.uid());
  end if;
  update public.nationality_change_requests
    set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),
      review_note=nullif(trim(p_note),'')
    where id=v_request.id;
  insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values(v_profile.id,'nationality_'||p_decision,
      case when p_decision='approved' then 'Mudança de nacionalidade aprovada' else 'Mudança de nacionalidade rejeitada' end,
      coalesce(nullif(trim(p_note),''),case when p_decision='approved'
        then 'Sua nacionalidade foi atualizada.' else 'Sua solicitação não foi aprovada.' end),
      'nationality_change_request',v_request.id);
  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
    values(auth.uid(),'review','nationality_change_request',v_request.id::text,
      'Revisão de solicitação de nacionalidade.',
      jsonb_build_object('status','pending','country_id',v_request.from_country_id),
      jsonb_build_object('status',p_decision,'country_id',case when p_decision='approved' then v_country.id else v_profile.country_id end));
  return jsonb_build_object('status',p_decision,'request_id',v_request.id);
end;
$$;

-- As RPCs executam com privilégios controlados e validam auth.uid() e o escopo no servidor.
revoke all on function public.get_my_citizen_profile() from public,anon;
revoke all on function public.update_my_citizen_profile(date,text,text,boolean,boolean,boolean,boolean) from public,anon;
revoke all on function public.update_my_minecraft_nickname(text) from public,anon;
revoke all on function public.request_nationality_change(uuid) from public,anon;
revoke all on function public.get_public_citizen_profile(uuid) from public,anon;
revoke all on function public.get_country_citizens(uuid,text) from public,anon;
revoke all on function public.admin_list_nationality_change_requests() from public,anon;
revoke all on function public.admin_review_nationality_change(uuid,text,text) from public,anon;
grant execute on function public.get_my_citizen_profile() to authenticated;
grant execute on function public.update_my_citizen_profile(date,text,text,boolean,boolean,boolean,boolean) to authenticated;
grant execute on function public.update_my_minecraft_nickname(text) to authenticated;
grant execute on function public.request_nationality_change(uuid) to authenticated;
grant execute on function public.get_public_citizen_profile(uuid) to authenticated;
grant execute on function public.get_country_citizens(uuid,text) to authenticated;
grant execute on function public.admin_list_nationality_change_requests() to authenticated;
grant execute on function public.admin_review_nationality_change(uuid,text,text) to authenticated;


-- Mantém a data de ingresso no país coerente com qualquer alteração autorizada de country_id.
create or replace function public.track_citizen_country_joined_at()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.country_id is distinct from old.country_id then
    new.country_joined_at := case when new.country_id is null then null else now() end;
  elsif new.country_id is not null and new.country_joined_at is null then
    new.country_joined_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_track_country_joined_at on public.profiles;
create trigger profiles_track_country_joined_at
before update of country_id on public.profiles
for each row execute function public.track_citizen_country_joined_at();

revoke all on function public.track_citizen_country_joined_at() from public,anon,authenticated;

commit;
