-- WORLD ECONOMY — ETAPA 4
-- Migração aditiva e idempotente. Preserva as estruturas e os dados das etapas anteriores.
-- Executar no SQL Editor do Supabase depois de revisar o diff desta migração.

create extension if not exists pgcrypto;

-- As quatro tabelas-base podem já existir no projeto (criadas durante a preparação da Etapa 4).
-- CREATE TABLE IF NOT EXISTS preserva essas estruturas e seus dados.
create table if not exists public.ministries (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  name text not null,
  description text,
  purpose text,
  category text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, country_id),
  unique (country_id, name)
);

create table if not exists public.government_departments (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  ministry_id uuid not null,
  name text not null,
  description text,
  purpose text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, ministry_id, country_id),
  unique (ministry_id, name),
  foreign key (ministry_id, country_id) references public.ministries(id, country_id)
);

create table if not exists public.government_members (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  profile_id uuid not null references public.profiles(id),
  ministry_id uuid,
  department_id uuid,
  position text not null,
  status text not null default 'active' check (status in ('active','inactive','exonerated')),
  appointed_by uuid references public.profiles(id),
  appointed_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, country_id),
  check (department_id is null or ministry_id is not null),
  foreign key (ministry_id, country_id) references public.ministries(id, country_id),
  foreign key (department_id, ministry_id, country_id)
    references public.government_departments(id, ministry_id, country_id)
);

create table if not exists public.government_appointments (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  action_type text not null check (action_type in ('appointment','exoneration')),
  candidate_profile_id uuid references public.profiles(id),
  member_id uuid,
  ministry_id uuid,
  department_id uuid,
  position text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  review_note text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  check (
    (action_type = 'appointment' and candidate_profile_id is not null and member_id is null and position is not null)
    or (action_type = 'exoneration' and candidate_profile_id is null and member_id is not null)
  ),
  check (department_id is null or ministry_id is not null),
  foreign key (ministry_id, country_id) references public.ministries(id, country_id),
  foreign key (department_id, ministry_id, country_id)
    references public.government_departments(id, ministry_id, country_id),
  foreign key (member_id, country_id) references public.government_members(id, country_id)
);

-- Permissões são separadas do perfil e do cargo global. Uma nomeação pendente nunca cria permissões.
create table if not exists public.government_member_permissions (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  member_id uuid not null,
  permission_key text not null,
  scope_type text not null default 'country' check (scope_type in ('country','ministry','department')),
  scope_id uuid,
  granted_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  foreign key (member_id, country_id) references public.government_members(id, country_id),
  check ((scope_type = 'country' and scope_id is null) or (scope_type <> 'country' and scope_id is not null))
);

create unique index if not exists government_member_permissions_country_uidx
  on public.government_member_permissions(member_id, permission_key)
  where scope_type = 'country';
create unique index if not exists government_member_permissions_scoped_uidx
  on public.government_member_permissions(member_id, permission_key, scope_type, scope_id)
  where scope_type <> 'country';

create table if not exists public.government_decisions (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  title text not null,
  description text not null,
  category text not null default 'administrative',
  status text not null default 'draft'
    check (status in ('draft','pending_approval','approved','rejected','published','cancelled')),
  author_id uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  review_note text,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.national_legislation (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  reference_number text,
  title text not null,
  description text not null,
  category text not null default 'administrative',
  status text not null default 'draft'
    check (status in ('draft','under_review','approved','rejected','revoked')),
  author_id uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.government_announcements (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  title text not null,
  content text not null,
  category text not null default 'official',
  status text not null default 'draft' check (status in ('draft','published','archived')),
  author_id uuid not null references public.profiles(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.national_infrastructure (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  name text not null,
  category text not null,
  description text,
  location_name text,
  coord_x numeric,
  coord_y numeric,
  coord_z numeric,
  status text not null default 'active' check (status in ('active','inactive','planned')),
  responsible_member_id uuid,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (responsible_member_id, country_id)
    references public.government_members(id, country_id)
);

create table if not exists public.government_budgets (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  title text not null,
  fiscal_period text,
  budget_type text not null default 'planned'
    check (budget_type in ('planned','expense_plan','investment_plan')),
  planned_amount numeric(20,2) not null default 0 check (planned_amount >= 0),
  description text,
  status text not null default 'draft' check (status in ('draft','approved','archived')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.government_budget_allocations (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  budget_id uuid not null references public.government_budgets(id) on delete restrict,
  ministry_id uuid not null,
  planned_amount numeric(20,2) not null default 0 check (planned_amount >= 0),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (ministry_id, country_id) references public.ministries(id, country_id),
  unique (budget_id, ministry_id)
);

create table if not exists public.government_audit_logs (
  id bigint generated always as identity primary key,
  country_id uuid not null references public.countries(id),
  actor_id uuid references public.profiles(id),
  operation text not null,
  object_type text not null,
  object_id text,
  description text not null,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

-- Campos aditivos para instalações já criadas durante a preparação da etapa.
alter table public.government_departments
  add column if not exists responsible_member_id uuid;
alter table public.government_departments
  add column if not exists purpose text;
alter table public.government_departments
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname='government_departments_responsible_member_fk'
    and conrelid='public.government_departments'::regclass) then
    alter table public.government_departments
      add constraint government_departments_responsible_member_fk
      foreign key (responsible_member_id, country_id)
      references public.government_members(id, country_id);
  end if;
end $$;

-- Índices de consulta e integridade.
create index if not exists ministries_country_status_idx on public.ministries(country_id,status);
create index if not exists government_departments_country_ministry_idx on public.government_departments(country_id,ministry_id);
create index if not exists government_members_country_status_idx on public.government_members(country_id,status);
create index if not exists government_members_profile_status_idx on public.government_members(profile_id,status);
create index if not exists government_appointments_country_status_idx on public.government_appointments(country_id,status);
create index if not exists government_appointments_candidate_idx on public.government_appointments(candidate_profile_id);
create unique index if not exists government_appointments_one_pending_candidate_idx
  on public.government_appointments(country_id,candidate_profile_id)
  where action_type='appointment' and status='pending';
create index if not exists government_decisions_country_created_idx on public.government_decisions(country_id,created_at desc);
create index if not exists national_legislation_country_status_idx on public.national_legislation(country_id,status);
create index if not exists government_announcements_country_published_idx on public.government_announcements(country_id,published_at desc);
create index if not exists national_infrastructure_country_category_idx on public.national_infrastructure(country_id,category);
create index if not exists government_budgets_country_created_idx on public.government_budgets(country_id,created_at desc);
create index if not exists government_budget_allocations_budget_idx on public.government_budget_allocations(budget_id);
create index if not exists government_audit_logs_country_created_idx on public.government_audit_logs(country_id,created_at desc);

-- Funções de autorização executadas no backend.
create or replace function public.is_country_president(p_country_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'president'
      and p.country_id = p_country_id
      and coalesce(p.account_status,'active') = 'active'
      and p.registration_status = 'active'
  );
$$;

create or replace function public.has_government_permission(
  p_country_id uuid,
  p_permission_key text,
  p_ministry_id uuid default null,
  p_department_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.government_member_permissions gp
    join public.government_members gm on gm.id = gp.member_id
      and gm.country_id = gp.country_id and gm.status = 'active'
    where gp.country_id = p_country_id
      and gp.permission_key = p_permission_key
      and gm.profile_id = auth.uid()
      and (
        gp.scope_type = 'country'
        or (gp.scope_type = 'ministry' and gp.scope_id = p_ministry_id)
        or (gp.scope_type = 'department' and gp.scope_id = p_department_id)
      )
  );
$$;

create or replace function public.is_government_country_citizen(p_country_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.country_id = p_country_id
      and coalesce(p.account_status,'active') = 'active'
      and p.registration_status = 'active'
  );
$$;

-- Solicitação de nomeação: apenas o presidente do país pode indicar um cidadão do mesmo país.
create or replace function public.request_government_appointment(
  p_candidate_profile_id uuid,
  p_ministry_id uuid,
  p_department_id uuid,
  p_position text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_country_id uuid;
  v_candidate public.profiles%rowtype;
  v_id uuid;
begin
  select country_id into v_country_id from public.profiles where id=auth.uid();
  if v_country_id is null or not public.is_country_president(v_country_id) then
    raise exception 'Somente o presidente aprovado pode solicitar nomeações.';
  end if;
  select * into v_candidate from public.profiles
    where id=p_candidate_profile_id and country_id=v_country_id
      and role='citizen' and registration_status='active'
      and coalesce(account_status,'active')='active';
  if not found then raise exception 'O indicado precisa ser cidadão ativo do próprio país.'; end if;
  if p_ministry_id is not null and not exists (
    select 1 from public.ministries where id=p_ministry_id and country_id=v_country_id and status='active'
  ) then raise exception 'Ministério inválido para este país.'; end if;
  if p_department_id is not null and not exists (
    select 1 from public.government_departments
    where id=p_department_id and country_id=v_country_id and ministry_id=p_ministry_id and status='active'
  ) then raise exception 'Departamento inválido para este ministério.'; end if;
  if length(trim(coalesce(p_position,''))) < 2 then raise exception 'Informe o cargo pretendido.'; end if;
  insert into public.government_appointments(
    country_id,action_type,candidate_profile_id,ministry_id,department_id,position,requested_by
  ) values (v_country_id,'appointment',p_candidate_profile_id,p_ministry_id,p_department_id,trim(p_position),auth.uid())
  returning id into v_id;
  insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values (null,'government.appointment.requested','Nova nomeação governamental',
    'Há uma solicitação de nomeação aguardando análise do Super Admin.','government_appointment',v_id);
  return v_id;
end;
$$;

create or replace function public.request_government_exoneration(p_member_id uuid,p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_country_id uuid; v_id uuid;
begin
  select country_id into v_country_id from public.profiles where id=auth.uid();
  if v_country_id is null or not public.is_country_president(v_country_id) then
    raise exception 'Somente o presidente aprovado pode solicitar exonerações.';
  end if;
  if not exists (select 1 from public.government_members
    where id=p_member_id and country_id=v_country_id and status='active') then
    raise exception 'Integrante ativo não encontrado neste país.';
  end if;
  insert into public.government_appointments(
    country_id,action_type,member_id,requested_by,review_note
  ) values (v_country_id,'exoneration',p_member_id,auth.uid(),nullif(trim(p_note),'')) returning id into v_id;
  insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values (null,'government.exoneration.requested','Nova solicitação de exoneração',
    'Há uma solicitação de exoneração aguardando análise do Super Admin.','government_appointment',v_id);
  return v_id;
end;
$$;

-- Aprovação exclusiva do Super Admin. As permissões só nascem após a aprovação.
create or replace function public.review_government_appointment(
  p_appointment_id uuid,
  p_decision text,
  p_note text default null,
  p_permission_keys text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app public.government_appointments%rowtype;
  v_member_id uuid;
  v_profile public.profiles%rowtype;
  v_permissions text[];
  v_scope_type text;
  v_scope_id uuid;
  v_key text;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode revisar nomeações e exonerações.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;
  select * into v_app from public.government_appointments where id=p_appointment_id for update;
  if not found or v_app.status <> 'pending' then raise exception 'Solicitação inexistente ou já analisada.'; end if;

  if p_decision='approved' and v_app.action_type='appointment' then
    select * into v_profile from public.profiles
      where id=v_app.candidate_profile_id and country_id=v_app.country_id
        and role='citizen' and registration_status='active'
        and coalesce(account_status,'active')='active' for update;
    if not found then raise exception 'O indicado não é mais um cidadão ativo deste país.'; end if;
    if exists (select 1 from public.government_members
      where profile_id=v_app.candidate_profile_id and country_id=v_app.country_id and status='active') then
      raise exception 'Este cidadão já possui um cargo governamental ativo neste país.';
    end if;
    insert into public.government_members(
      country_id,profile_id,ministry_id,department_id,position,status,appointed_by
    ) values (
      v_app.country_id,v_app.candidate_profile_id,v_app.ministry_id,v_app.department_id,
      v_app.position,'active',auth.uid()
    ) returning id into v_member_id;

    v_scope_type := case when v_app.department_id is not null then 'department'
      when v_app.ministry_id is not null then 'ministry' else 'country' end;
    v_scope_id := case when v_scope_type='department' then v_app.department_id
      when v_scope_type='ministry' then v_app.ministry_id else null end;

    v_permissions := coalesce(p_permission_keys,
      case
        when lower(v_app.position) like '%ministro%' then array['ministry.read','department.read','department.manage','announcement.create','decision.create','legislation.create','budget.read','infrastructure.read']
        when lower(v_app.position) like '%vice%' then array['ministry.read','department.read','announcement.create','decision.create']
        else array['department.read','announcement.create']
      end
    );
    foreach v_key in array v_permissions loop
      if v_key not in ('ministry.read','department.read','department.manage','announcement.create',
        'decision.create','legislation.create','budget.read','infrastructure.read','infrastructure.manage') then
        raise exception 'Permissão não autorizada: %',v_key;
      end if;
      insert into public.government_member_permissions(
        country_id,member_id,permission_key,scope_type,scope_id,granted_by
      ) values (v_app.country_id,v_member_id,v_key,v_scope_type,v_scope_id,auth.uid())
      on conflict do nothing;
    end loop;
    insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values
      (v_app.candidate_profile_id,'government.appointment.approved','Nomeação aprovada',
       'Sua nomeação para o cargo de '||v_app.position||' foi aprovada.','government_member',v_member_id),
      (v_app.requested_by,'government.appointment.approved','Nomeação aprovada',
       'A nomeação solicitada foi aprovada pelo Super Admin.','government_member',v_member_id);
  elsif p_decision='approved' and v_app.action_type='exoneration' then
    update public.government_members set status='exonerated',ended_at=now(),updated_at=now()
      where id=v_app.member_id and country_id=v_app.country_id and status='active';
    if not found then raise exception 'Integrante ativo não encontrado.'; end if;
    delete from public.government_member_permissions where member_id=v_app.member_id;
    insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
    select gm.profile_id,'government.exoneration.approved','Exoneração aprovada',
      'Sua exoneração do cargo governamental foi aprovada.','government_member',gm.id
    from public.government_members gm where gm.id=v_app.member_id;
    insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values (v_app.requested_by,'government.exoneration.approved','Exoneração aprovada',
      'A solicitação de exoneração foi aprovada pelo Super Admin.','government_appointment',v_app.id);
  end if;

  update public.government_appointments set status=p_decision,reviewed_by=auth.uid(),
    review_note=nullif(trim(p_note),''),reviewed_at=now() where id=v_app.id;

  if p_decision='rejected' then
    insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values (v_app.requested_by,'government.appointment.rejected','Solicitação rejeitada',
      coalesce(nullif(trim(p_note),''),'A solicitação foi rejeitada pelo Super Admin.'),
      'government_appointment',v_app.id);
    if v_app.candidate_profile_id is not null then
      insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
      values (v_app.candidate_profile_id,'government.appointment.rejected','Nomeação não aprovada',
        coalesce(nullif(trim(p_note),''),'Sua nomeação não foi aprovada.'),
        'government_appointment',v_app.id);
    end if;
  end if;

  return jsonb_build_object('status',p_decision,'appointment_id',v_app.id,'member_id',v_member_id);
end;
$$;

-- Painel com dados reais do país do usuário; Super Admin pode informar um país.
create or replace function public.get_government_dashboard(p_country_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_country_id uuid;
  v_result jsonb;
begin
  select country_id into v_country_id from public.profiles where id=auth.uid();
  if public.is_world_admin() then
    v_country_id := coalesce(p_country_id,v_country_id);
  elsif p_country_id is not null and p_country_id is distinct from v_country_id then
    raise exception 'Acesso permitido somente ao próprio país.';
  end if;
  if v_country_id is null then raise exception 'Sua conta ainda não está vinculada a um país.'; end if;

  select jsonb_build_object(
    'country', (select to_jsonb(c) from public.countries c where c.id=v_country_id),
    'president', (select jsonb_build_object('id',p.id,'username',p.username,'player_number',p.player_number)
      from public.profiles p where p.country_id=v_country_id and p.role='president'
        and coalesce(p.account_status,'active')='active' limit 1),
    'citizens_count', (select count(*) from public.profiles p where p.country_id=v_country_id
      and p.role='citizen' and p.registration_status='active' and coalesce(p.account_status,'active')='active'),
    'ministries_count', (select count(*) from public.ministries m where m.country_id=v_country_id and m.status='active'),
    'ministers_count', (select count(*) from public.government_members gm where gm.country_id=v_country_id and gm.status='active'),
    'departments_count', (select count(*) from public.government_departments d where d.country_id=v_country_id and d.status='active'),
    'announcements', coalesce((select jsonb_agg(to_jsonb(a) order by a.published_at desc)
      from (select * from public.government_announcements where country_id=v_country_id and status='published'
        order by published_at desc nulls last limit 5) a),'[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(to_jsonb(d) order by d.updated_at desc)
      from (select * from public.government_decisions where country_id=v_country_id and status='published'
        order by updated_at desc limit 5) d),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

-- Auditoria automática: registra operações feitas nas tabelas governamentais.
create or replace function public.log_government_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_row jsonb;
  v_country_id uuid;
  v_id text;
  v_operation text;
begin
  if tg_op='DELETE' then v_old:=to_jsonb(old); v_row:=v_old; v_operation:='deleted';
  elsif tg_op='UPDATE' then v_old:=to_jsonb(old); v_new:=to_jsonb(new); v_row:=v_new; v_operation:='updated';
  else v_new:=to_jsonb(new); v_row:=v_new; v_operation:='created'; end if;
  v_country_id := nullif(v_row->>'country_id','')::uuid;
  v_id := v_row->>'id';
  if v_country_id is not null then
    insert into public.government_audit_logs(
      country_id,actor_id,operation,object_type,object_id,description,old_values,new_values
    ) values (
      v_country_id,auth.uid(),tg_table_name||'.'||v_operation,tg_table_name,v_id,
      initcap(replace(tg_table_name,'_',' '))||' '||v_operation,v_old,v_new
    );
  end if;
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

-- RLS: leitura pública somente do conteúdo publicado do país; alterações sempre por autoridade do país/permissão.
alter table public.ministries enable row level security;
alter table public.government_departments enable row level security;
alter table public.government_members enable row level security;
alter table public.government_appointments enable row level security;
alter table public.government_member_permissions enable row level security;
alter table public.government_decisions enable row level security;
alter table public.national_legislation enable row level security;
alter table public.government_announcements enable row level security;
alter table public.national_infrastructure enable row level security;
alter table public.government_budgets enable row level security;
alter table public.government_budget_allocations enable row level security;
alter table public.government_audit_logs enable row level security;

revoke all on public.ministries, public.government_departments, public.government_members,
  public.government_appointments, public.government_member_permissions, public.government_decisions,
  public.national_legislation, public.government_announcements, public.national_infrastructure,
  public.government_budgets, public.government_budget_allocations, public.government_audit_logs
from public, anon, authenticated;

grant select, insert, update, delete on public.ministries, public.government_departments,
  public.government_decisions, public.national_legislation, public.government_announcements,
  public.national_infrastructure, public.government_budgets, public.government_budget_allocations
to authenticated;
grant select on public.government_members, public.government_appointments,
  public.government_member_permissions, public.government_audit_logs to authenticated;
grant usage, select on sequence public.government_audit_logs_id_seq to authenticated;

-- Remove somente políticas desta etapa, para permitir reexecução idempotente.
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies
    where schemaname='public' and tablename in (
      'ministries','government_departments','government_members','government_appointments',
      'government_member_permissions','government_decisions','national_legislation',
      'government_announcements','national_infrastructure','government_budgets',
      'government_budget_allocations','government_audit_logs'
    )
  loop
    execute format('drop policy if exists %I on %I.%I',r.policyname,r.schemaname,r.tablename);
  end loop;
end $$;

create policy ministries_read_country on public.ministries for select to authenticated
  using (public.is_world_admin() or public.is_government_country_citizen(country_id)
    or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'ministry.read',id,null));
create policy ministries_insert_authorized on public.ministries for insert to authenticated
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'ministry.manage',id,null));
create policy ministries_update_authorized on public.ministries for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'ministry.manage',id,null))
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'ministry.manage',id,null));
create policy ministries_delete_authorized on public.ministries for delete to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id));

create policy departments_read_country on public.government_departments for select to authenticated
  using (public.is_world_admin() or public.is_government_country_citizen(country_id)
    or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'department.read',ministry_id,id));
create policy departments_insert_authorized on public.government_departments for insert to authenticated
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'department.manage',ministry_id,id));
create policy departments_update_authorized on public.government_departments for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'department.manage',ministry_id,id))
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'department.manage',ministry_id,id));
create policy departments_delete_authorized on public.government_departments for delete to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id));

create policy government_members_read on public.government_members for select to authenticated
  using (public.is_world_admin() or public.is_government_country_citizen(country_id)
    or public.is_country_president(country_id) or profile_id=auth.uid());
create policy government_members_admin_write on public.government_members for all to authenticated
  using (public.is_world_admin()) with check (public.is_world_admin());

create policy appointments_read_involved on public.government_appointments for select to authenticated
  using (public.is_world_admin() or requested_by=auth.uid() or candidate_profile_id=auth.uid()
    or public.is_country_president(country_id));
create policy appointments_admin_write on public.government_appointments for all to authenticated
  using (public.is_world_admin()) with check (public.is_world_admin());

create policy member_permissions_read_scoped on public.government_member_permissions for select to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or exists (select 1 from public.government_members gm where gm.id=member_id and gm.profile_id=auth.uid()));
create policy member_permissions_admin_write on public.government_member_permissions for all to authenticated
  using (public.is_world_admin()) with check (public.is_world_admin());

create policy decisions_read_public on public.government_decisions for select to authenticated
  using ((status='published' and public.is_government_country_citizen(country_id))
    or public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'decision.create',null,null));
create policy decisions_insert_authorized on public.government_decisions for insert to authenticated
  with check ((public.is_country_president(country_id) or public.has_government_permission(country_id,'decision.create',null,null))
    and author_id=auth.uid());
create policy decisions_update_authorized on public.government_decisions for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'decision.create',null,null))
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'decision.create',null,null));

create policy legislation_read_public on public.national_legislation for select to authenticated
  using ((status in ('approved','revoked') and public.is_government_country_citizen(country_id))
    or public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'legislation.create',null,null));
create policy legislation_insert_authorized on public.national_legislation for insert to authenticated
  with check ((public.is_country_president(country_id) or public.has_government_permission(country_id,'legislation.create',null,null))
    and author_id=auth.uid());
create policy legislation_update_authorized on public.national_legislation for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'legislation.create',null,null))
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'legislation.create',null,null));

create policy announcements_read_public on public.government_announcements for select to authenticated
  using ((status='published' and public.is_government_country_citizen(country_id))
    or public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'announcement.create',null,null));
create policy announcements_insert_authorized on public.government_announcements for insert to authenticated
  with check ((public.is_country_president(country_id) or public.has_government_permission(country_id,'announcement.create',null,null))
    and author_id=auth.uid());
create policy announcements_update_authorized on public.government_announcements for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'announcement.create',null,null))
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'announcement.create',null,null));

create policy infrastructure_read_public on public.national_infrastructure for select to authenticated
  using ((status='active' and public.is_government_country_citizen(country_id))
    or public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'infrastructure.read',null,null));
create policy infrastructure_insert_authorized on public.national_infrastructure for insert to authenticated
  with check ((public.is_country_president(country_id) or public.has_government_permission(country_id,'infrastructure.manage',null,null))
    and created_by=auth.uid());
create policy infrastructure_update_authorized on public.national_infrastructure for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'infrastructure.manage',null,null))
  with check (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'infrastructure.manage',null,null));

create policy budgets_read_authorized on public.government_budgets for select to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'budget.read',null,null));
create policy budgets_insert_authorized on public.government_budgets for insert to authenticated
  with check ((public.is_country_president(country_id) or public.has_government_permission(country_id,'budget.read',null,null))
    and created_by=auth.uid());
create policy budgets_update_authorized on public.government_budgets for update to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id))
  with check (public.is_world_admin() or public.is_country_president(country_id));

create policy allocations_read_authorized on public.government_budget_allocations for select to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id)
    or public.has_government_permission(country_id,'budget.read',ministry_id,null));
create policy allocations_insert_authorized on public.government_budget_allocations for insert to authenticated
  with check (public.is_country_president(country_id) or public.is_world_admin());
create policy allocations_update_authorized on public.government_budget_allocations for update to authenticated
  using (public.is_country_president(country_id) or public.is_world_admin())
  with check (public.is_country_president(country_id) or public.is_world_admin());

create policy government_audit_read_country on public.government_audit_logs for select to authenticated
  using (public.is_world_admin() or public.is_country_president(country_id));

-- Auditoria automática para todas as tabelas governamentais mutáveis.
drop trigger if exists ministries_audit on public.ministries;
create trigger ministries_audit after insert or update or delete on public.ministries
  for each row execute function public.log_government_change();
drop trigger if exists government_departments_audit on public.government_departments;
create trigger government_departments_audit after insert or update or delete on public.government_departments
  for each row execute function public.log_government_change();
drop trigger if exists government_members_audit on public.government_members;
create trigger government_members_audit after insert or update or delete on public.government_members
  for each row execute function public.log_government_change();
drop trigger if exists government_appointments_audit on public.government_appointments;
create trigger government_appointments_audit after insert or update or delete on public.government_appointments
  for each row execute function public.log_government_change();
drop trigger if exists government_member_permissions_audit on public.government_member_permissions;
create trigger government_member_permissions_audit after insert or update or delete on public.government_member_permissions
  for each row execute function public.log_government_change();
drop trigger if exists government_decisions_audit on public.government_decisions;
create trigger government_decisions_audit after insert or update or delete on public.government_decisions
  for each row execute function public.log_government_change();
drop trigger if exists national_legislation_audit on public.national_legislation;
create trigger national_legislation_audit after insert or update or delete on public.national_legislation
  for each row execute function public.log_government_change();
drop trigger if exists government_announcements_audit on public.government_announcements;
create trigger government_announcements_audit after insert or update or delete on public.government_announcements
  for each row execute function public.log_government_change();
drop trigger if exists national_infrastructure_audit on public.national_infrastructure;
create trigger national_infrastructure_audit after insert or update or delete on public.national_infrastructure
  for each row execute function public.log_government_change();
drop trigger if exists government_budgets_audit on public.government_budgets;
create trigger government_budgets_audit after insert or update or delete on public.government_budgets
  for each row execute function public.log_government_change();
drop trigger if exists government_budget_allocations_audit on public.government_budget_allocations;
create trigger government_budget_allocations_audit after insert or update or delete on public.government_budget_allocations
  for each row execute function public.log_government_change();

grant execute on function public.is_country_president(uuid) to authenticated;
grant execute on function public.has_government_permission(uuid,text,uuid,uuid) to authenticated;
grant execute on function public.is_government_country_citizen(uuid) to authenticated;
grant execute on function public.request_government_appointment(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.request_government_exoneration(uuid,text) to authenticated;
grant execute on function public.review_government_appointment(uuid,text,text,text[]) to authenticated;
grant execute on function public.get_government_dashboard(uuid) to authenticated;

-- O dashboard não recebe país arbitrário de cidadão ou presidente: o RPC valida o vínculo no backend.
