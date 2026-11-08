-- WORLD ECONOMY — ETAPA 11: documentos, passaportes, vistos, aeroportos e viagens
-- Migration aditiva: reutiliza profiles, citizen_documents, citizen_passports e histórico da Etapa 5.
begin;

alter table public.citizen_documents
  add column if not exists identification_code text,
  add column if not exists version_number integer not null default 1,
  add column if not exists previous_document_id uuid references public.citizen_documents(id),
  add column if not exists revoked_at timestamptz,
  add column if not exists revocation_reason text;

create unique index if not exists citizen_documents_identification_code_uidx
  on public.citizen_documents(identification_code) where identification_code is not null;

create table if not exists public.passport_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id),
  country_id uuid not null references public.countries(id),
  request_type text not null default 'new' check (request_type in ('new','renewal')),
  status text not null default 'pending' check (status in ('pending','in_review','approved','rejected','cancelled','issued')),
  reason text,
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  review_note text,
  issued_document_id uuid references public.citizen_documents(id),
  created_at timestamptz not null default now()
);
create unique index if not exists passport_one_open_request_uidx
  on public.passport_requests(profile_id) where status in ('pending','in_review','approved');

create table if not exists public.visa_types (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  code text not null,
  name text not null,
  purpose text not null check (purpose in ('tourism','work','business','residence','official_visit','transit')),
  duration_days integer not null default 30 check (duration_days between 1 and 3650),
  fee_amount numeric(18,2) not null default 0 check (fee_amount >= 0),
  currency_code text,
  requires_passport boolean not null default true,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(country_id,code)
);

create table if not exists public.visa_applications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id),
  destination_country_id uuid not null references public.countries(id),
  visa_type_id uuid not null references public.visa_types(id),
  purpose text not null,
  intended_entry date not null,
  intended_exit date not null,
  status text not null default 'pending' check (status in ('pending','in_review','approved','rejected','cancelled','expired')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  check (intended_exit >= intended_entry)
);

create table if not exists public.travel_authorizations (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id),
  destination_country_id uuid not null references public.countries(id),
  visa_application_id uuid references public.visa_applications(id),
  authorization_type text not null check (authorization_type in ('visa','entry_permit','special_permission','residence_permit')),
  valid_from date not null,
  valid_until date not null,
  status text not null default 'active' check (status in ('active','suspended','revoked','expired')),
  issued_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (valid_until >= valid_from)
);

create table if not exists public.airports (
  id uuid primary key default gen_random_uuid(),
  identifier text not null unique,
  name text not null,
  country_id uuid not null references public.countries(id),
  city_region text,
  coordinate_x integer not null,
  coordinate_y integer not null,
  coordinate_z integer not null,
  status text not null default 'pending' check (status in ('pending','active','suspended','closed')),
  manager_profile_id uuid references public.profiles(id),
  description text,
  created_by uuid not null references public.profiles(id),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists airports_country_status_idx on public.airports(country_id,status);

create table if not exists public.airport_routes (
  id uuid primary key default gen_random_uuid(),
  origin_airport_id uuid not null references public.airports(id),
  destination_airport_id uuid not null references public.airports(id),
  airline_name text,
  route_code text,
  status text not null default 'planned' check (status in ('planned','active','suspended','cancelled')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (origin_airport_id <> destination_airport_id),
  unique(origin_airport_id,destination_airport_id,route_code)
);

create table if not exists public.travel_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id),
  origin_country_id uuid not null references public.countries(id),
  destination_country_id uuid not null references public.countries(id),
  origin_airport_id uuid not null references public.airports(id),
  destination_airport_id uuid not null references public.airports(id),
  purpose text not null check (purpose in ('tourism','work','business','residence','official_visit','transit')),
  document_id uuid not null references public.citizen_documents(id),
  passport_id uuid references public.citizen_passports(id),
  visa_application_id uuid references public.visa_applications(id),
  status text not null default 'requested' check (status in ('requested','in_review','authorized','rejected','in_progress','completed','cancelled')),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references public.profiles(id),
  decision_note text,
  created_at timestamptz not null default now(),
  check (origin_country_id <> destination_country_id)
);
create index if not exists travel_requests_profile_created_idx on public.travel_requests(profile_id,created_at desc);

create table if not exists public.border_rules (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id),
  requires_passport boolean not null default true,
  requires_visa boolean not null default false,
  requires_travel_authorization boolean not null default false,
  allow_entry boolean not null default true,
  allow_exit boolean not null default true,
  restricted_origin_countries uuid[] not null default '{}',
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  reason text not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists border_rules_country_effective_idx on public.border_rules(country_id,effective_from desc);

create table if not exists public.immigration_records (
  id uuid primary key default gen_random_uuid(),
  travel_request_id uuid references public.travel_requests(id),
  profile_id uuid not null references public.profiles(id),
  origin_country_id uuid not null references public.countries(id),
  destination_country_id uuid not null references public.countries(id),
  document_id uuid not null references public.citizen_documents(id),
  airport_id uuid references public.airports(id),
  result text not null check (result in ('approved','rejected')),
  reason text not null,
  officer_id uuid not null references public.profiles(id),
  occurred_at timestamptz not null default now()
);

create table if not exists public.emigration_records (
  id uuid primary key default gen_random_uuid(),
  travel_request_id uuid references public.travel_requests(id),
  profile_id uuid not null references public.profiles(id),
  origin_country_id uuid not null references public.countries(id),
  destination_country_id uuid not null references public.countries(id),
  document_id uuid not null references public.citizen_documents(id),
  airport_id uuid references public.airports(id),
  result text not null check (result in ('approved','rejected')),
  reason text not null,
  officer_id uuid not null references public.profiles(id),
  occurred_at timestamptz not null default now()
);

create table if not exists public.travel_fee_records (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id),
  country_id uuid not null references public.countries(id),
  related_type text not null check (related_type in ('passport','visa','airport_service','travel')),
  related_id uuid not null,
  amount numeric(18,2) not null check (amount >= 0),
  currency_code text not null,
  recipient_description text not null,
  status text not null default 'unpaid' check (status in ('unpaid','paid','waived','cancelled')),
  bank_transaction_id uuid,
  confirmed_by uuid references public.profiles(id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.document_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id),
  profile_id uuid references public.profiles(id),
  country_id uuid references public.countries(id),
  object_type text not null,
  object_id uuid not null,
  action text not null,
  reason text not null,
  previous_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);
create index if not exists document_audit_object_idx on public.document_audit_logs(object_type,object_id,created_at desc);
create index if not exists immigration_profile_idx on public.immigration_records(profile_id,occurred_at desc);
create index if not exists emigration_profile_idx on public.emigration_records(profile_id,occurred_at desc);

-- RLS: leitura pessoal; dados administrativos somente por RPCs verificadas.
do $rls$
declare t text;
begin
  foreach t in array array['passport_requests','visa_types','visa_applications','travel_authorizations','airports','airport_routes','travel_requests','border_rules','immigration_records','emigration_records','travel_fee_records','document_audit_logs']
  loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
  end loop;
end;
$rls$;

drop policy if exists passport_requests_read_scope on public.passport_requests;
create policy passport_requests_read_scope on public.passport_requests for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or public.has_government_permission(country_id,'documents.read',null,null));
drop policy if exists visa_types_read_active on public.visa_types;
create policy visa_types_read_active on public.visa_types for select to authenticated using(is_active or public.is_world_admin() or public.is_country_president(country_id));
drop policy if exists visa_applications_read_scope on public.visa_applications;
create policy visa_applications_read_scope on public.visa_applications for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(destination_country_id) or public.has_government_permission(destination_country_id,'immigration.review',null,null));
drop policy if exists travel_authorizations_read_scope on public.travel_authorizations;
create policy travel_authorizations_read_scope on public.travel_authorizations for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(destination_country_id));
drop policy if exists airports_read_scope on public.airports;
create policy airports_read_scope on public.airports for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id) or public.has_government_permission(country_id,'airport.manage',null,null));
drop policy if exists airport_routes_read_scope on public.airport_routes;
create policy airport_routes_read_scope on public.airport_routes for select to authenticated
using(exists(select 1 from public.airports a where a.id=origin_airport_id and a.status='active') or public.is_world_admin());
drop policy if exists travel_requests_read_scope on public.travel_requests;
create policy travel_requests_read_scope on public.travel_requests for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(origin_country_id) or public.is_country_president(destination_country_id) or public.has_government_permission(origin_country_id,'immigration.review',null,null) or public.has_government_permission(destination_country_id,'immigration.review',null,null));
drop policy if exists border_rules_read_scope on public.border_rules;
create policy border_rules_read_scope on public.border_rules for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.has_government_permission(country_id,'immigration.review',null,null));
drop policy if exists immigration_records_read_scope on public.immigration_records;
create policy immigration_records_read_scope on public.immigration_records for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(destination_country_id) or public.has_government_permission(destination_country_id,'immigration.review',null,null));
drop policy if exists emigration_records_read_scope on public.emigration_records;
create policy emigration_records_read_scope on public.emigration_records for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(origin_country_id) or public.has_government_permission(origin_country_id,'immigration.review',null,null));
drop policy if exists travel_fee_records_read_scope on public.travel_fee_records;
create policy travel_fee_records_read_scope on public.travel_fee_records for select to authenticated using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id));
drop policy if exists document_audit_read_scope on public.document_audit_logs;
create policy document_audit_read_scope on public.document_audit_logs for select to authenticated using(public.is_world_admin() or (country_id is not null and public.is_country_president(country_id)));

create or replace function public.request_passport(p_reason text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; rid uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into p from public.profiles where id=auth.uid() for update;
  if not found or p.role<>'citizen' or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' then raise exception 'Conta não elegível para solicitar passaporte.'; end if;
  if p.country_id is null then raise exception 'Defina sua nacionalidade antes de solicitar passaporte.'; end if;
  if exists(select 1 from public.passport_requests where profile_id=p.id and status in ('pending','in_review','approved')) then raise exception 'Já existe solicitação de passaporte em aberto.'; end if;
  insert into public.passport_requests(profile_id,country_id,request_type,reason) values(p.id,p.country_id,case when exists(select 1 from public.citizen_passports where profile_id=p.id and status in ('active','expired')) then 'renewal' else 'new' end,nullif(trim(p_reason),'')) returning id into rid;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason) values(auth.uid(),p.id,p.country_id,'passport_request',rid,'requested',coalesce(nullif(trim(p_reason),''),'Solicitação de passaporte.'));
  return rid;
end;$function$;

create or replace function public.review_passport_request(p_request_id uuid,p_decision text,p_reason text,p_validity_days integer default 1825)
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare r public.passport_requests%rowtype; p public.profiles%rowtype; pass_no text; doc_id uuid; old jsonb;
begin
  if auth.uid() is null or (p_decision not in ('approve','reject')) then raise exception 'Decisão inválida.'; end if;
  select * into r from public.passport_requests where id=p_request_id and status in ('pending','in_review') for update;
  if not found then raise exception 'Solicitação não encontrada ou já processada.'; end if;
  if not (public.is_world_admin() or public.is_country_president(r.country_id) or public.has_government_permission(r.country_id,'documents.manage',null,null)) then raise exception 'Sem permissão para emitir documentos deste país.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Informe a justificativa da decisão.'; end if;
  select * into p from public.profiles where id=r.profile_id for update;
  if p_decision='reject' then
    update public.passport_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid(),review_note=trim(p_reason) where id=r.id;
    insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values) values(auth.uid(),r.profile_id,r.country_id,'passport_request',r.id,'rejected',trim(p_reason),jsonb_build_object('status',r.status),jsonb_build_object('status','rejected'));
    return jsonb_build_object('status','rejected','request_id',r.id);
  end if;
  if p_validity_days not between 30 and 3650 then raise exception 'Validade deve ficar entre 30 e 3650 dias.'; end if;
  if p.country_id is distinct from r.country_id then raise exception 'A nacionalidade do cidadão mudou; solicitação precisa ser refeita.'; end if;
  pass_no := 'WE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  insert into public.citizen_passports(profile_id,country_id,passport_number,status,issued_at,expires_at,issued_by)
  values(p.id,r.country_id,pass_no,'active',now(),now()+make_interval(days=>p_validity_days),auth.uid())
  on conflict(profile_id) do update set country_id=excluded.country_id,passport_number=excluded.passport_number,status='active',issued_at=now(),expires_at=excluded.expires_at,issued_by=auth.uid(),updated_at=now();
  insert into public.citizen_documents(profile_id,country_id,document_type,document_number,status,issued_by,expires_at,identification_code,metadata)
  values(p.id,r.country_id,'other',pass_no,'active',auth.uid(),now()+make_interval(days=>p_validity_days),'PASS-'||pass_no,jsonb_build_object('kind','passport','permanent_id',p.player_number,'holder',p.username,'fictional',true))
  returning id into doc_id;
  update public.passport_requests set status='issued',reviewed_at=now(),reviewed_by=auth.uid(),review_note=trim(p_reason),issued_document_id=doc_id where id=r.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,new_values) values(auth.uid(),p.id,r.country_id,'passport',doc_id,'issued',trim(p_reason),jsonb_build_object('passport_number',pass_no,'expires_at',now()+make_interval(days=>p_validity_days)));
  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id) values(p.id,'passport_issued','Passaporte emitido','Passaporte fictício emitido dentro do WORLD ECONOMY.',r.country_id,auth.uid());
  return jsonb_build_object('status','issued','passport_number',pass_no,'document_id',doc_id);
end;$function$;

create or replace function public.submit_visa_application(p_visa_type_id uuid,p_entry date,p_exit date,p_purpose text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v public.visa_types%rowtype; rid uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into v from public.visa_types where id=p_visa_type_id and is_active;
  if not found then raise exception 'Tipo de visto indisponível.'; end if;
  if p_exit<p_entry or p_entry<current_date then raise exception 'Período de viagem inválido.'; end if;
  if not exists(select 1 from public.citizen_passports cp where cp.profile_id=auth.uid() and cp.status='active' and cp.expires_at::date>=p_exit) then raise exception 'É necessário passaporte válido até o fim da viagem.'; end if;
  insert into public.visa_applications(profile_id,destination_country_id,visa_type_id,purpose,intended_entry,intended_exit)
  values(auth.uid(),v.country_id,p_visa_type_id,coalesce(nullif(trim(p_purpose),''),v.purpose),p_entry,p_exit) returning id into rid;
  return rid;
end;$function$;

create or replace function public.review_visa_application(p_application_id uuid,p_decision text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare v public.visa_applications%rowtype; auth_id uuid;
begin
  if auth.uid() is null or p_decision not in ('approve','reject') then raise exception 'Decisão inválida.'; end if;
  select * into v from public.visa_applications where id=p_application_id and status in ('pending','in_review') for update;
  if not found then raise exception 'Solicitação não encontrada.'; end if;
  if not (public.is_world_admin() or public.is_country_president(v.destination_country_id) or public.has_government_permission(v.destination_country_id,'immigration.review',null,null)) then raise exception 'Sem permissão para analisar vistos deste país.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Justificativa obrigatória.'; end if;
  if p_decision='approve' then
    insert into public.travel_authorizations(profile_id,destination_country_id,visa_application_id,authorization_type,valid_from,valid_until,issued_by)
    values(v.profile_id,v.destination_country_id,v.id,'visa',v.intended_entry,v.intended_exit,auth.uid()) returning id into auth_id;
    update public.visa_applications set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_reason) where id=v.id;
  else
    update public.visa_applications set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_reason) where id=v.id;
  end if;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values)
  values(auth.uid(),v.profile_id,v.destination_country_id,'visa_application',v.id,p_decision,trim(p_reason),jsonb_build_object('status',v.status),jsonb_build_object('status',case when p_decision='approve' then 'approved' else 'rejected' end));
  return jsonb_build_object('status',case when p_decision='approve' then 'approved' else 'rejected' end,'authorization_id',auth_id);
end;$function$;

create or replace function public.create_world_airport(p_identifier text,p_name text,p_country_id uuid,p_city text,p_x integer,p_y integer,p_z integer,p_description text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare aid uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_government_permission(p_country_id,'airport.manage',null,null)) then raise exception 'Sem permissão para cadastrar aeroporto neste país.'; end if;
  if length(trim(p_identifier))<3 or length(trim(p_identifier))>12 or trim(p_name)='' then raise exception 'Identificador ou nome inválido.'; end if;
  insert into public.airports(identifier,name,country_id,city_region,coordinate_x,coordinate_y,coordinate_z,description,created_by,status)
  values(upper(trim(p_identifier)),trim(p_name),p_country_id,nullif(trim(p_city),''),p_x,p_y,p_z,nullif(trim(p_description),''),auth.uid(),case when public.is_world_admin() then 'active' else 'pending' end)
  returning id into aid;
  insert into public.document_audit_logs(actor_id,country_id,object_type,object_id,action,reason,new_values) values(auth.uid(),p_country_id,'airport',aid,'created','Cadastro de aeroporto.',jsonb_build_object('status',case when public.is_world_admin() then 'active' else 'pending' end));
  return aid;
end;$function$;

create or replace function public.admin_set_airport_status(p_airport_id uuid,p_status text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare a public.airports%rowtype;
begin
  select * into a from public.airports where id=p_airport_id for update;
  if not found then raise exception 'Aeroporto não encontrado.'; end if;
  if not (public.is_world_admin() or public.is_country_president(a.country_id) or public.has_government_permission(a.country_id,'airport.manage',null,null)) then raise exception 'Sem permissão.'; end if;
  if p_status not in ('active','suspended','closed') or nullif(trim(p_reason),'') is null then raise exception 'Situação ou justificativa inválida.'; end if;
  update public.airports set status=p_status,approved_by=case when p_status='active' then auth.uid() else approved_by end,approved_at=case when p_status='active' then now() else approved_at end,updated_at=now() where id=a.id;
  insert into public.document_audit_logs(actor_id,country_id,object_type,object_id,action,reason,previous_values,new_values) values(auth.uid(),a.country_id,'airport',a.id,'status_changed',trim(p_reason),jsonb_build_object('status',a.status),jsonb_build_object('status',p_status));
end;$function$;

create or replace function public.submit_world_travel_request(p_origin_airport uuid,p_destination_airport uuid,p_document_id uuid,p_purpose text,p_entry date,p_exit date)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; o public.airports%rowtype; d public.airports%rowtype; doc public.citizen_documents%rowtype; rid uuid; br public.border_rules%rowtype;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into p from public.profiles where id=auth.uid();
  select * into o from public.airports where id=p_origin_airport and status='active';
  select * into d from public.airports where id=p_destination_airport and status='active';
  select * into doc from public.citizen_documents where id=p_document_id and profile_id=auth.uid() and status='active' and (expires_at is null or expires_at>now());
  if o.id is null or d.id is null or doc.id is null then raise exception 'Aeroportos ativos e documento válido são obrigatórios.'; end if;
  if o.country_id=d.country_id or o.country_id is distinct from p.country_id then raise exception 'Origem/destino ou nacionalidade incompatível.'; end if;
  if p_entry<current_date or p_exit<p_entry then raise exception 'Datas inválidas.'; end if;
  select * into br from public.border_rules where country_id=d.country_id and effective_from<=now() and (effective_until is null or effective_until>now()) order by effective_from desc limit 1;
  if found then
    if not br.allow_entry or o.country_id=any(br.restricted_origin_countries) then raise exception 'As regras atuais de fronteira não permitem esta entrada.'; end if;
    if br.requires_passport and not exists(select 1 from public.citizen_passports cp where cp.profile_id=p.id and cp.status='active' and cp.expires_at::date>=p_exit) then raise exception 'Passaporte válido obrigatório.'; end if;
    if br.requires_visa and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=p.id and ta.destination_country_id=d.country_id and ta.status='active' and ta.valid_from<=p_entry and ta.valid_until>=p_exit) then raise exception 'Visto/autorização válido obrigatório.'; end if;
    if br.requires_travel_authorization and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=p.id and ta.destination_country_id=d.country_id and ta.status='active' and ta.valid_from<=p_entry and ta.valid_until>=p_exit) then raise exception 'Autorização especial obrigatória.'; end if;
  end if;
  insert into public.travel_requests(profile_id,origin_country_id,destination_country_id,origin_airport_id,destination_airport_id,purpose,document_id,passport_id,status)
  values(p.id,o.country_id,d.country_id,o.id,d.id,p_purpose,doc.id,(select id from public.citizen_passports where profile_id=p.id and status='active'),'requested') returning id into rid;
  return rid;
end;$function$;

create or replace function public.decide_world_travel(p_request_id uuid,p_decision text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.travel_requests%rowtype;
begin
  select * into r from public.travel_requests where id=p_request_id and status in ('requested','in_review') for update;
  if not found then raise exception 'Viagem não encontrada ou já decidida.'; end if;
  if not (public.is_world_admin() or public.is_country_president(r.destination_country_id) or public.has_government_permission(r.destination_country_id,'immigration.review',null,null)) then raise exception 'Sem permissão para decidir entrada no país.'; end if;
  if p_decision not in ('authorized','rejected') or nullif(trim(p_reason),'') is null then raise exception 'Decisão e justificativa obrigatórias.'; end if;
  if p_decision='authorized' then
    if not exists(select 1 from public.citizen_documents cd where cd.id=r.document_id and cd.profile_id=r.profile_id and cd.status='active' and (cd.expires_at is null or cd.expires_at>now())) then raise exception 'Documento utilizado está inválido.'; end if;
    if exists(select 1 from public.border_rules br where br.country_id=r.destination_country_id and br.effective_from<=now() and (br.effective_until is null or br.effective_until>now()) and (not br.allow_entry or r.origin_country_id=any(br.restricted_origin_countries))) then raise exception 'Regra de fronteira impede a entrada.'; end if;
  end if;
  update public.travel_requests set status=p_decision,decided_at=now(),decided_by=auth.uid(),decision_note=trim(p_reason) where id=r.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values) values(auth.uid(),r.profile_id,r.destination_country_id,'travel_request',r.id,p_decision,trim(p_reason),jsonb_build_object('status',r.status),jsonb_build_object('status',p_decision));
end;$function$;

create or replace function public.record_world_border_crossing(p_travel_request_id uuid,p_result text,p_reason text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare r public.travel_requests%rowtype; iid uuid;
begin
  select * into r from public.travel_requests where id=p_travel_request_id and status='authorized' for update;
  if not found then raise exception 'Viagem autorizada não encontrada.'; end if;
  if not (public.is_world_admin() or public.is_country_president(r.destination_country_id) or public.has_government_permission(r.destination_country_id,'immigration.review',null,null) or public.has_government_permission(r.origin_country_id,'immigration.review',null,null)) then raise exception 'Sem permissão para controle de fronteira.'; end if;
  if p_result not in ('approved','rejected') or nullif(trim(p_reason),'') is null then raise exception 'Resultado e justificativa obrigatórios.'; end if;
  insert into public.immigration_records(travel_request_id,profile_id,origin_country_id,destination_country_id,document_id,airport_id,result,reason,officer_id)
  values(r.id,r.profile_id,r.origin_country_id,r.destination_country_id,r.document_id,r.destination_airport_id,p_result,trim(p_reason),auth.uid()) returning id into iid;
  insert into public.emigration_records(travel_request_id,profile_id,origin_country_id,destination_country_id,document_id,airport_id,result,reason,officer_id)
  values(r.id,r.profile_id,r.origin_country_id,r.destination_country_id,r.document_id,r.origin_airport_id,p_result,trim(p_reason),auth.uid());
  update public.travel_requests set status=case when p_result='approved' then 'completed' else 'rejected' end where id=r.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason) values(auth.uid(),r.profile_id,r.destination_country_id,'border_crossing',iid,p_result,trim(p_reason));
  return iid;
end;$function$;

create or replace function public.create_border_rule(p_country_id uuid,p_requires_passport boolean,p_requires_visa boolean,p_requires_authorization boolean,p_allow_entry boolean,p_allow_exit boolean,p_reason text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare rid uuid;
begin
  if not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_government_permission(p_country_id,'immigration.rules',null,null)) then raise exception 'Sem permissão para alterar regras deste país.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Justificativa obrigatória.'; end if;
  update public.border_rules set effective_until=now() where country_id=p_country_id and effective_until is null;
  insert into public.border_rules(country_id,requires_passport,requires_visa,requires_travel_authorization,allow_entry,allow_exit,reason,created_by)
  values(p_country_id,p_requires_passport,p_requires_visa,p_requires_authorization,p_allow_entry,p_allow_exit,trim(p_reason),auth.uid()) returning id into rid;
  insert into public.document_audit_logs(actor_id,country_id,object_type,object_id,action,reason) values(auth.uid(),p_country_id,'border_rule',rid,'created',trim(p_reason));
  return rid;
end;$function$;

create or replace function public.admin_create_visa_type(p_country_id uuid,p_code text,p_name text,p_purpose text,p_duration_days integer,p_fee numeric,p_currency text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare rid uuid;
begin
  if not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_government_permission(p_country_id,'immigration.rules',null,null)) then raise exception 'Sem permissão para configurar vistos.'; end if;
  if p_purpose not in ('tourism','work','business','residence','official_visit','transit') or p_duration_days not between 1 and 3650 or p_fee<0 then raise exception 'Parâmetros inválidos.'; end if;
  insert into public.visa_types(country_id,code,name,purpose,duration_days,fee_amount,currency_code,created_by)
  values(p_country_id,upper(trim(p_code)),trim(p_name),p_purpose,p_duration_days,p_fee,nullif(upper(trim(p_currency)),''))
  returning id into rid;
  return rid;
end;$function$;

do $grants$
declare f text;
begin
 foreach f in array array[
 'request_passport(text)','review_passport_request(uuid,text,text,integer)',
 'submit_visa_application(uuid,date,date,text)','review_visa_application(uuid,text,text)',
 'create_world_airport(text,text,uuid,text,integer,integer,integer,text)','admin_set_airport_status(uuid,text,text)',
 'submit_world_travel_request(uuid,uuid,uuid,text,date,date)','decide_world_travel(uuid,text,text)',
 'record_world_border_crossing(uuid,text,text)','create_border_rule(uuid,boolean,boolean,boolean,boolean,boolean,text)',
 'admin_create_visa_type(uuid,text,text,text,integer,numeric,text)'
 ] loop
  execute format('revoke all on function public.%s from public,anon',f);
  execute format('grant execute on function public.%s to authenticated',f);
 end loop;
end;$grants$;

commit;
