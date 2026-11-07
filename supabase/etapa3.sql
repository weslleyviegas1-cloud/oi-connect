-- WORLD ECONOMY — ETAPA 3
-- Migração aditiva. Executar uma única vez no SQL Editor do Supabase.
-- Preserva profiles, countries, president_applications, autenticação e IDs existentes.

create extension if not exists pgcrypto;

alter table public.countries
  add column if not exists short_name text,
  add column if not exists identifier text,
  add column if not exists description text,
  add column if not exists capital text,
  add column if not exists continent text,
  add column if not exists currency_name text,
  add column if not exists currency_code text,
  add column if not exists citizens_available boolean not null default true,
  add column if not exists coord_x numeric,
  add column if not exists coord_y numeric,
  add column if not exists coord_z numeric,
  add column if not exists spawn_x numeric,
  add column if not exists spawn_y numeric,
  add column if not exists spawn_z numeric,
  add column if not exists spawn_name text,
  add column if not exists spawn_description text,
  add column if not exists updated_at timestamptz not null default now();

update public.countries
set identifier = lower(regexp_replace(unaccent_name, '[^a-z0-9]+', '-', 'g'))
where identifier is null;

-- Gera identificadores sem depender de extensões adicionais para nomes novos.
create unique index if not exists countries_identifier_uidx
  on public.countries(identifier) where identifier is not null;

alter table public.profiles
  add column if not exists minecraft_username text,
  add column if not exists account_status text not null default 'active',
  add column if not exists suspended_at timestamptz,
  add column if not exists suspension_note text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_account_status_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_account_status_check
      check (account_status in ('active','suspended'));
  end if;
end $$;

create table if not exists public.world_spawn (
  id boolean primary key default true check (id = true),
  name text not null default 'Nascimento global',
  description text,
  coord_x numeric not null default 0,
  coord_y numeric not null default 70,
  coord_z numeric not null default 0,
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

create table if not exists public.platform_settings (
  id boolean primary key default true check (id = true),
  platform_name text not null default 'WORLD ECONOMY',
  logo_url text,
  visual_identity jsonb not null default '{}'::jsonb,
  app_status text not null default 'online' check (app_status in ('online','maintenance','paused')),
  signup_open boolean not null default true,
  login_enabled boolean not null default true,
  global_notice text,
  maintenance_at timestamptz,
  notifications_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);

insert into public.world_spawn(id) values (true) on conflict (id) do nothing;
insert into public.platform_settings(id) values (true) on conflict (id) do nothing;

create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  description text not null,
  object_type text,
  object_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists admin_notifications_recipient_created_idx
  on public.admin_notifications(recipient_id, created_at desc);
create index if not exists admin_notifications_unread_idx
  on public.admin_notifications(is_read, created_at desc);

create table if not exists public.admin_audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  operation text not null,
  object_type text not null,
  object_id text,
  description text not null,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_logs_created_idx
  on public.admin_audit_logs(created_at desc);

alter table public.world_spawn enable row level security;
alter table public.platform_settings enable row level security;
alter table public.admin_notifications enable row level security;
alter table public.admin_audit_logs enable row level security;

drop policy if exists "World spawn visível" on public.world_spawn;
create policy "World spawn visível" on public.world_spawn
  for select to anon, authenticated using (is_active or public.is_world_admin());

drop policy if exists "Configurações públicas de plataforma" on public.platform_settings;
create policy "Configurações públicas de plataforma" on public.platform_settings
  for select to anon, authenticated using (true);

drop policy if exists "Notificações do dono ou admin" on public.admin_notifications;
create policy "Notificações do dono ou admin" on public.admin_notifications
  for select to authenticated using (recipient_id = auth.uid() or public.is_world_admin());

drop policy if exists "Auditoria somente admin" on public.admin_audit_logs;
create policy "Auditoria somente admin" on public.admin_audit_logs
  for select to authenticated using (public.is_world_admin());

revoke all on public.world_spawn from public, anon, authenticated;
revoke all on public.platform_settings from public, anon, authenticated;
revoke all on public.admin_notifications from public, anon, authenticated;
revoke all on public.admin_audit_logs from public, anon, authenticated;
grant select on public.world_spawn, public.platform_settings to anon, authenticated;
grant select on public.admin_notifications, public.admin_audit_logs to authenticated;

-- Upload público para leitura; escrita e exclusão somente pelo Super Admin.
insert into storage.buckets(id,name,public)
values ('country-flags','country-flags',true)
on conflict (id) do update set public = true;

drop policy if exists "Bandeiras públicas" on storage.objects;
create policy "Bandeiras públicas" on storage.objects
  for select using (bucket_id = 'country-flags');

drop policy if exists "Admin envia bandeiras" on storage.objects;
create policy "Admin envia bandeiras" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'country-flags' and public.is_world_admin());

drop policy if exists "Admin altera bandeiras" on storage.objects;
create policy "Admin altera bandeiras" on storage.objects
  for update to authenticated
  using (bucket_id = 'country-flags' and public.is_world_admin())
  with check (bucket_id = 'country-flags' and public.is_world_admin());

drop policy if exists "Admin remove bandeiras" on storage.objects;
create policy "Admin remove bandeiras" on storage.objects
  for delete to authenticated
  using (bucket_id = 'country-flags' and public.is_world_admin());

create or replace function public.admin_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare v_result jsonb;
begin
  if not public.is_world_admin() then
    raise exception 'Apenas o Super Admin pode consultar os indicadores administrativos.';
  end if;
  select jsonb_build_object(
    'countries_total', (select count(*) from public.countries),
    'countries_active', (select count(*) from public.countries where is_active),
    'countries_suspended', (select count(*) from public.countries where not is_active),
    'presidencies_available', (
      select count(*) from public.countries c
      where c.is_active and c.president_available
        and not exists (select 1 from public.profiles p where p.country_id=c.id and p.role='president')
    ),
    'citizens_total', (select count(*) from public.profiles where role='citizen'),
    'presidents_total', (select count(*) from public.profiles where role='president'),
    'applications_pending', (select count(*) from public.president_applications where status='pending'),
    'users_total', (select count(*) from auth.users)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.admin_list_players(p_search text default null)
returns table (
  id uuid,
  username text,
  minecraft_username text,
  player_number bigint,
  role text,
  registration_status text,
  account_status text,
  country_id uuid,
  country_name text,
  country_flag text,
  avatar_url text,
  email text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_world_admin() then
    raise exception 'Apenas o Super Admin pode consultar jogadores.';
  end if;
  return query
  select p.id, p.username, p.minecraft_username, p.player_number, p.role,
         p.registration_status, p.account_status, p.country_id,
         c.name, c.flag, p.avatar_url, u.email::text, p.created_at
  from public.profiles p
  join auth.users u on u.id=p.id
  left join public.countries c on c.id=p.country_id
  where coalesce(p_search,'') = ''
     or p.username ilike '%' || p_search || '%'
     or coalesce(p.minecraft_username,'') ilike '%' || p_search || '%'
     or p.player_number::text = p_search
  order by p.created_at desc;
end;
$$;

create or replace function public.admin_upsert_country(
  p_id uuid,
  p_name text,
  p_short_name text,
  p_identifier text,
  p_flag text,
  p_description text,
  p_capital text,
  p_continent text,
  p_currency_name text,
  p_currency_code text,
  p_coord_x numeric,
  p_coord_y numeric,
  p_coord_z numeric,
  p_spawn_x numeric,
  p_spawn_y numeric,
  p_spawn_z numeric,
  p_spawn_name text,
  p_spawn_description text,
  p_is_active boolean,
  p_citizens_available boolean,
  p_president_available boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_old jsonb;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode gerenciar países.'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'Informe o nome oficial do país.'; end if;
  if length(trim(coalesce(p_identifier,''))) < 2 then raise exception 'Informe o identificador exclusivo.'; end if;
  if p_is_active = false and p_president_available then
    raise exception 'Um país suspenso não pode aceitar solicitações presidenciais.';
  end if;
  if p_id is not null then
    select to_jsonb(c) into v_old from public.countries c where c.id=p_id for update;
    if not found then raise exception 'País não encontrado.'; end if;
    update public.countries set
      name=trim(p_name), short_name=nullif(trim(p_short_name),''), identifier=lower(trim(p_identifier)),
      flag=nullif(trim(p_flag),''), description=nullif(trim(p_description),''), capital=nullif(trim(p_capital),''),
      continent=nullif(trim(p_continent),''), currency_name=nullif(trim(p_currency_name,''),
      currency_code=nullif(upper(trim(p_currency_code)),''), coord_x=p_coord_x, coord_y=p_coord_y, coord_z=p_coord_z,
      spawn_x=p_spawn_x, spawn_y=p_spawn_y, spawn_z=p_spawn_z, spawn_name=nullif(trim(p_spawn_name),''),
      spawn_description=nullif(trim(p_spawn_description),''), is_active=p_is_active,
      citizens_available=p_citizens_available, president_available=p_president_available, updated_at=now()
    where id=p_id returning id into v_id;
  else
    insert into public.countries(
      name,short_name,identifier,flag,description,capital,continent,currency_name,currency_code,
      coord_x,coord_y,coord_z,spawn_x,spawn_y,spawn_z,spawn_name,spawn_description,
      is_active,citizens_available,president_available
    ) values (
      trim(p_name),nullif(trim(p_short_name),''),lower(trim(p_identifier)),nullif(trim(p_flag),''),
      nullif(trim(p_description),''),nullif(trim(p_capital),''),nullif(trim(p_continent),''),
      nullif(trim(p_currency_name),''),nullif(upper(trim(p_currency_code)),''),p_coord_x,p_coord_y,p_coord_z,
      p_spawn_x,p_spawn_y,p_spawn_z,nullif(trim(p_spawn_name),''),nullif(trim(p_spawn_description),''),
      p_is_active,p_citizens_available,p_president_available
    ) returning id into v_id;
  end if;
  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
  values(auth.uid(),case when p_id is null then 'country.created' else 'country.updated' end,
    'country',v_id::text,case when p_id is null then 'País cadastrado: '||trim(p_name) else 'País atualizado: '||trim(p_name) end,
    v_old,(select to_jsonb(c) from public.countries c where c.id=v_id));
  return v_id;
end;
$$;

create or replace function public.admin_save_world_spawn(
  p_name text, p_description text, p_x numeric, p_y numeric, p_z numeric, p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_old jsonb;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode alterar o nascimento global.'; end if;
  select to_jsonb(s) into v_old from public.world_spawn s where id=true for update;
  insert into public.world_spawn(id,name,description,coord_x,coord_y,coord_z,is_active,updated_at,updated_by)
  values(true,trim(p_name),nullif(trim(p_description),''),p_x,p_y,p_z,p_is_active,now(),auth.uid())
  on conflict(id) do update set name=excluded.name,description=excluded.description,
    coord_x=excluded.coord_x,coord_y=excluded.coord_y,coord_z=excluded.coord_z,
    is_active=excluded.is_active,updated_at=now(),updated_by=auth.uid();
  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
  values(auth.uid(),'spawn.global.updated','world_spawn','global','Coordenadas globais atualizadas',v_old,
    (select to_jsonb(s) from public.world_spawn s where id=true));
end;
$$;

create or replace function public.admin_save_platform_settings(
  p_platform_name text, p_logo_url text, p_app_status text, p_signup_open boolean,
  p_login_enabled boolean, p_global_notice text, p_maintenance_at timestamptz,
  p_notifications_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_old jsonb;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode alterar configurações globais.'; end if;
  if p_app_status not in ('online','maintenance','paused') then raise exception 'Status geral inválido.'; end if;
  select to_jsonb(s) into v_old from public.platform_settings s where id=true for update;
  update public.platform_settings set platform_name=trim(p_platform_name),logo_url=nullif(trim(p_logo_url),''),
    app_status=p_app_status,signup_open=p_signup_open,login_enabled=p_login_enabled,
    global_notice=nullif(trim(p_global_notice),''),maintenance_at=p_maintenance_at,
    notifications_enabled=p_notifications_enabled,updated_at=now(),updated_by=auth.uid()
  where id=true;
  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
  values(auth.uid(),'settings.updated','platform_settings','global','Configurações gerais alteradas',v_old,
    (select to_jsonb(s) from public.platform_settings s where id=true));
end;
$$;

create or replace function public.admin_set_player_status(
  p_player_id uuid, p_status text, p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_old jsonb; v_player public.profiles%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode alterar contas.'; end if;
  if p_status not in ('active','suspended') then raise exception 'Status de conta inválido.'; end if;
  if p_player_id=auth.uid() and p_status='suspended' then raise exception 'A conta do Super Admin principal não pode ser suspensa por este painel.'; end if;
  select * into v_player from public.profiles where id=p_player_id for update;
  if not found then raise exception 'Jogador não encontrado.'; end if;
  v_old:=to_jsonb(v_player);
  update public.profiles set account_status=p_status,
    suspended_at=case when p_status='suspended' then now() else null end,
    suspension_note=case when p_status='suspended' then nullif(trim(p_note),'') else null end
  where id=p_player_id;
  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
  values(auth.uid(),case when p_status='suspended' then 'player.suspended' else 'player.reactivated' end,
    'player',p_player_id::text,case when p_status='suspended' then 'Conta suspensa: '||v_player.username else 'Conta reativada: '||v_player.username end,
    v_old,(select to_jsonb(p) from public.profiles p where p.id=p_player_id));
  insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values(p_player_id,'account.status','Status da conta atualizado',
    case when p_status='suspended' then 'Sua conta foi suspensa pelo Super Admin.' else 'Sua conta foi reativada.' end,
    'player',p_player_id);
end;
$$;

create or replace function public.admin_mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode alterar notificações administrativas.'; end if;
  update public.admin_notifications set is_read=true
  where id=p_notification_id and recipient_id is null;
end;
$$;

-- Auditoria e notificações automáticas para novos pedidos e revisões presidenciais.
create or replace function public.handle_president_application_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_country public.countries%rowtype; v_player public.profiles%rowtype;
begin
  select * into v_country from public.countries where id=new.country_id;
  select * into v_player from public.profiles where id=new.player_id;
  if tg_op='INSERT' then
    insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values(null,'presidency.requested','Nova solicitação presidencial',
      v_player.username||' solicitou a presidência de '||v_country.name||'.',
      'president_application',new.id);
    insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,new_values)
    values(new.player_id,'presidency.requested','president_application',new.id::text,
      'Solicitação presidencial enviada para '||v_country.name,to_jsonb(new));
  elsif tg_op='UPDATE' and old.status is distinct from new.status then
    insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values(new.player_id,'presidency.reviewed',
      case when new.status='approved' then 'Solicitação presidencial aprovada' else 'Solicitação presidencial recusada' end,
      case when new.status='approved' then 'Sua solicitação para '||v_country.name||' foi aprovada.' else 'Sua solicitação para '||v_country.name||' foi recusada.' end,
      'president_application',new.id);
    insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
    values(auth.uid(),'presidency.'||new.status,'president_application',new.id::text,
      'Solicitação presidencial '||new.status||' para '||v_country.name,to_jsonb(old),to_jsonb(new));
  end if;
  return new;
end;
$$;

drop trigger if exists president_application_events on public.president_applications;
create trigger president_application_events
after insert or update of status on public.president_applications
for each row execute function public.handle_president_application_events();

-- Mantém o cadastro da Etapa 2, acrescentando o bloqueio para países fechados a cidadãos.
create or replace function public.register_player(p_type text, p_country_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_country public.countries%rowtype;
  v_profile public.profiles%rowtype;
  v_application_id uuid;
begin
  if v_uid is null then raise exception 'É necessário entrar na conta.'; end if;
  if p_type is null or p_type not in ('citizen','president') then raise exception 'Tipo de jogador inválido.'; end if;
  select * into v_profile from public.profiles where id=v_uid for update;
  if not found then raise exception 'Perfil do jogador não encontrado.'; end if;
  if v_profile.role='super_admin' then return jsonb_build_object('status','active','role','super_admin'); end if;
  if coalesce(v_profile.account_status,'active') <> 'active' then raise exception 'Esta conta está suspensa.'; end if;
  if v_profile.country_id is not null or v_profile.registration_status <> 'active' then
    raise exception 'Esta conta já possui uma escolha de país ou solicitação registrada.';
  end if;
  select * into v_country from public.countries
    where id=p_country_id and is_active=true for update;
  if not found then raise exception 'País indisponível. Atualize a lista e tente novamente.'; end if;
  if p_type='citizen' then
    if not v_country.citizens_available then raise exception 'Este país não está aceitando novos cidadãos.'; end if;
    update public.profiles set country_id=v_country.id,role='citizen',registration_status='active' where id=v_uid;
    return jsonb_build_object('status','active','role','citizen','country_id',v_country.id);
  end if;
  if not v_country.president_available then raise exception 'Este país não está aceitando solicitações de presidência.'; end if;
  if exists(select 1 from public.profiles where country_id=v_country.id and role='president') then
    raise exception 'Este país já possui um presidente.';
  end if;
  insert into public.president_applications(player_id,country_id) values(v_uid,v_country.id)
  returning id into v_application_id;
  update public.profiles set registration_status='pending_presidency' where id=v_uid;
  return jsonb_build_object('status','pending','application_id',v_application_id,'country_id',v_country.id);
end;
$$;

-- Função de revisão já existente; trigger acima gera aviso ao jogador e registro de auditoria.
revoke all on function public.admin_dashboard_stats() from public, anon;
revoke all on function public.admin_list_players(text) from public, anon;
revoke all on function public.admin_upsert_country(uuid,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text,text,boolean,boolean,boolean) from public, anon;
revoke all on function public.admin_save_world_spawn(text,text,numeric,numeric,numeric,boolean) from public, anon;
revoke all on function public.admin_save_platform_settings(text,text,text,boolean,boolean,text,timestamptz,boolean) from public, anon;
revoke all on function public.admin_set_player_status(uuid,text,text) from public, anon;
revoke all on function public.admin_mark_notification_read(uuid) from public, anon;
revoke all on function public.register_player(text,uuid) from public, anon;

grant execute on function public.admin_dashboard_stats() to authenticated;
grant execute on function public.admin_list_players(text) to authenticated;
grant execute on function public.admin_upsert_country(uuid,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,numeric,numeric,text,text,boolean,boolean,boolean) to authenticated;
grant execute on function public.admin_save_world_spawn(text,text,numeric,numeric,numeric,boolean) to authenticated;
grant execute on function public.admin_save_platform_settings(text,text,text,boolean,boolean,text,timestamptz,boolean) to authenticated;
grant execute on function public.admin_set_player_status(uuid,text,text) to authenticated;
grant execute on function public.admin_mark_notification_read(uuid) to authenticated;
grant execute on function public.register_player(text,uuid) to authenticated;
