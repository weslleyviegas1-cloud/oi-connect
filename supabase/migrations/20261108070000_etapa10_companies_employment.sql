-- WORLD ECONOMY — ETAPA 10: empresas, mercado de trabalho e folha salarial
-- Migration aditiva. Não apaga nem reescreve dados das etapas anteriores.
begin;

create extension if not exists pgcrypto;

create table if not exists public.companies (
 id uuid primary key default gen_random_uuid(),
 company_identifier text not null unique,
 legal_name text not null check(length(trim(legal_name)) between 2 and 180),
 trade_name text,
 logo_url text,
 country_id uuid not null references public.countries(id) on delete restrict,
 city text,
 region text,
 sector text not null check(sector in ('commerce','construction','agriculture','livestock','mining','industry','transport','technology','services','food','health','education','energy','tourism','other')),
 company_type text not null check(company_type in ('private','public','state_owned','partnership')),
 size_class text not null default 'small_business' check(size_class in ('small_business','large_enterprise')),
 description text,
 founded_at date not null default current_date,
 declared_capital numeric(30,6) not null default 0 check(declared_capital>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 created_by uuid not null references public.profiles(id) on delete restrict,
 approved_by uuid references public.profiles(id) on delete restrict,
 approved_at timestamptz,
 government_entity_id uuid,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(company_type not in ('public','state_owned') or government_entity_id is not null)
);
create index if not exists companies_country_status_idx on public.companies(country_id,status);
create index if not exists companies_sector_idx on public.companies(country_id,sector,status);

create table if not exists public.company_owners (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 profile_id uuid not null references public.profiles(id) on delete restrict,
 ownership_percent numeric(7,4) not null default 100 check(ownership_percent>0 and ownership_percent<=100),
 owner_role text not null default 'owner' check(owner_role in ('owner','shareholder','founder')),
 status text not null default 'active' check(status in ('active','removed')),
 appointed_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(company_id,profile_id)
);
create index if not exists company_owners_profile_idx on public.company_owners(profile_id,status);

create table if not exists public.company_departments (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 name text not null check(length(trim(name)) between 2 and 100),
 description text,
 manager_profile_id uuid references public.profiles(id) on delete set null,
 status text not null default 'active' check(status in ('active','inactive')),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(company_id,name)
);

create table if not exists public.company_members (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 profile_id uuid not null references public.profiles(id) on delete restrict,
 member_role text not null check(member_role in ('owner','director','manager','hr','finance','employee')),
 permissions text[] not null default '{}',
 department_id uuid references public.company_departments(id) on delete set null,
 status text not null default 'active' check(status in ('active','suspended','removed')),
 appointed_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(company_id,profile_id)
);
create index if not exists company_members_profile_idx on public.company_members(profile_id,status);

create table if not exists public.job_positions (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 title text not null check(length(trim(title)) between 2 and 120),
 description text,
 department_id uuid references public.company_departments(id) on delete set null,
 is_custom boolean not null default true,
 status text not null default 'active' check(status in ('active','inactive')),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(company_id,title)
);

create table if not exists public.job_openings (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 position_id uuid not null references public.job_positions(id) on delete restrict,
 title text not null,
 description text not null,
 requirements text,
 salary_amount numeric(30,6) not null check(salary_amount>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 employment_type text not null default 'monthly' check(employment_type in ('monthly','hourly','daily','project')),
 openings_count integer not null default 1 check(openings_count between 1 and 10000),
 country_id uuid not null references public.countries(id) on delete restrict,
 city text,
 region text,
 published_at timestamptz not null default now(),
 application_deadline timestamptz,
 status text not null default 'open' check(status in ('open','paused','filled','closed')),
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 check(application_deadline is null or application_deadline>published_at)
);
create index if not exists job_openings_public_idx on public.job_openings(country_id,status,published_at desc);

create table if not exists public.job_applications (
 id uuid primary key default gen_random_uuid(),
 opening_id uuid not null references public.job_openings(id) on delete restrict,
 applicant_profile_id uuid not null references public.profiles(id) on delete restrict,
 cover_letter text,
 status text not null default 'submitted' check(status in ('submitted','reviewing','accepted','rejected','withdrawn')),
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz,
 review_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(opening_id,applicant_profile_id)
);
create index if not exists job_applications_applicant_idx on public.job_applications(applicant_profile_id,created_at desc);

create table if not exists public.employment_contracts (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 employee_profile_id uuid not null references public.profiles(id) on delete restrict,
 position_id uuid references public.job_positions(id) on delete restrict,
 department_id uuid references public.company_departments(id) on delete set null,
 application_id uuid references public.job_applications(id) on delete restrict,
 job_title text not null,
 salary_amount numeric(30,6) not null check(salary_amount>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 pay_frequency text not null default 'monthly' check(pay_frequency in ('monthly','weekly','daily','hourly','project')),
 employment_type text not null default 'permanent' check(employment_type in ('permanent','fixed_term','temporary','part_time','contractor')),
 working_hours numeric(8,2),
 conditions text,
 starts_at date not null default current_date,
 ends_at date,
 status text not null default 'pending_employee' check(status in ('pending_employee','pending_company','active','rejected','terminated','expired')),
 company_accepted_at timestamptz,
 employee_accepted_at timestamptz,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(ends_at is null or ends_at>=starts_at)
);
create unique index if not exists employment_one_active_company_employee_uidx on public.employment_contracts(company_id,employee_profile_id) where status in ('pending_employee','pending_company','active');
create index if not exists employment_employee_idx on public.employment_contracts(employee_profile_id,status,starts_at desc);
create index if not exists employment_company_idx on public.employment_contracts(company_id,status);

create table if not exists public.employment_history (
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.employment_contracts(id) on delete restrict,
 company_id uuid not null references public.companies(id) on delete restrict,
 employee_profile_id uuid not null references public.profiles(id) on delete restrict,
 event_type text not null check(event_type in ('offered','accepted','rejected','salary_changed','role_changed','department_changed','renewed','terminated','resigned','expired')),
 previous_data jsonb,
 new_data jsonb,
 actor_id uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
create index if not exists employment_history_employee_idx on public.employment_history(employee_profile_id,created_at desc);

create table if not exists public.employment_contract_revisions (
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.employment_contracts(id) on delete restrict,
 previous_data jsonb not null,
 new_data jsonb not null,
 revised_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);

create table if not exists public.payroll_records (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 contract_id uuid not null references public.employment_contracts(id) on delete restrict,
 employee_profile_id uuid not null references public.profiles(id) on delete restrict,
 reference_period text not null,
 gross_amount numeric(30,6) not null check(gross_amount>=0),
 deductions_amount numeric(30,6) not null default 0 check(deductions_amount>=0),
 net_amount numeric(30,6) generated always as (gross_amount-deductions_amount) stored,
 currency_id uuid not null references public.currencies(id) on delete restrict,
 tax_calculation_status text not null default 'not_configured' check(tax_calculation_status in ('not_configured','reviewed','exempt','pending')),
 status text not null default 'draft' check(status in ('draft','approved','paid','cancelled')),
 created_by uuid not null references public.profiles(id),
 approved_by uuid references public.profiles(id),
 approved_at timestamptz,
 paid_at timestamptz,
 created_at timestamptz not null default now(),
 unique(contract_id,reference_period),
 check(deductions_amount<=gross_amount)
);
create index if not exists payroll_company_period_idx on public.payroll_records(company_id,reference_period,status);
create index if not exists payroll_employee_idx on public.payroll_records(employee_profile_id,created_at desc);

create table if not exists public.salary_payments (
 id uuid primary key default gen_random_uuid(),
 payroll_id uuid not null unique references public.payroll_records(id) on delete restrict,
 company_id uuid not null references public.companies(id) on delete restrict,
 employee_profile_id uuid not null references public.profiles(id) on delete restrict,
 from_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 to_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 amount numeric(30,6) not null check(amount>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 idempotency_key text not null unique,
 paid_by uuid not null references public.profiles(id),
 paid_at timestamptz not null default now()
);

create table if not exists public.company_financial_records (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 record_type text not null check(record_type in ('revenue','expense')),
 category text not null,
 description text not null,
 amount numeric(30,6) not null check(amount>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 record_status text not null check(record_status in ('planned','paid','received','cancelled')),
 reference_type text,
 reference_id uuid,
 responsible_profile_id uuid not null references public.profiles(id),
 attachment_url text,
 created_at timestamptz not null default now()
);
create index if not exists company_financial_records_idx on public.company_financial_records(company_id,created_at desc);

create table if not exists public.company_tax_records (
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id) on delete restrict,
 tax_rule_id uuid references public.tax_rules(id) on delete restrict,
 tax_obligation_id uuid references public.tax_obligations(id) on delete restrict,
 description text not null,
 reference_period text not null,
 tax_base numeric(30,6) not null default 0 check(tax_base>=0),
 applied_rate numeric(9,4) check(applied_rate is null or applied_rate between 0 and 100),
 amount_due numeric(30,6) not null check(amount_due>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 status text not null default 'pending_review' check(status in ('pending_review','validated','paid','cancelled')),
 validated_by uuid references public.profiles(id),
 validated_at timestamptz,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create index if not exists company_tax_records_idx on public.company_tax_records(company_id,status,created_at desc);

create table if not exists public.company_audit_logs (
 id uuid primary key default gen_random_uuid(),
 company_id uuid references public.companies(id) on delete restrict,
 actor_id uuid references public.profiles(id),
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists company_audit_logs_idx on public.company_audit_logs(company_id,created_at desc);

-- Titularidade empresarial em contas da Etapa 9: mantém contas pessoais intactas.
alter table public.bank_accounts alter column owner_profile_id drop not null;
alter table public.bank_accounts add column if not exists owner_company_id uuid references public.companies(id) on delete restrict;
alter table public.bank_accounts drop constraint if exists bank_accounts_exactly_one_owner_check;
alter table public.bank_accounts add constraint bank_accounts_exactly_one_owner_check
 check ((owner_profile_id is not null)::integer + (owner_company_id is not null)::integer = 1);
create unique index if not exists bank_accounts_company_bank_currency_uidx
 on public.bank_accounts(owner_company_id,bank_id,currency_id) where owner_company_id is not null;
create index if not exists bank_accounts_company_idx on public.bank_accounts(owner_company_id,status);

create or replace function public.is_company_member(p_company_id uuid,p_permission text default null)
returns boolean language sql stable security definer set search_path=public,auth as $function$
 select auth.uid() is not null and exists(
  select 1 from public.company_members m join public.profiles p on p.id=m.profile_id
  where m.company_id=p_company_id and m.profile_id=auth.uid() and m.status='active'
   and coalesce(p.account_status,'active')='active' and p.registration_status='active'
   and (p_permission is null or p_permission=any(m.permissions) or m.member_role in ('owner','director') or 'company.manage'=any(m.permissions))
 );
$function$;

create or replace function public.company_audit(p_company_id uuid,p_action text,p_type text,p_id uuid,p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path=public,auth as $function$
 insert into public.company_audit_logs(company_id,actor_id,action,entity_type,entity_id,details)
 values(p_company_id,auth.uid(),p_action,p_type,p_id,coalesce(p_details,'{}'::jsonb));
$function$;

alter table public.companies enable row level security;
alter table public.company_owners enable row level security;
alter table public.company_departments enable row level security;
alter table public.company_members enable row level security;
alter table public.job_positions enable row level security;
alter table public.job_openings enable row level security;
alter table public.job_applications enable row level security;
alter table public.employment_contracts enable row level security;
alter table public.employment_history enable row level security;
alter table public.employment_contract_revisions enable row level security;
alter table public.payroll_records enable row level security;
alter table public.salary_payments enable row level security;
alter table public.company_financial_records enable row level security;
alter table public.company_tax_records enable row level security;
alter table public.company_audit_logs enable row level security;

drop policy if exists companies_read on public.companies;
create policy companies_read on public.companies for select to authenticated
using(status='active' or public.is_world_admin() or created_by=auth.uid() or public.is_company_member(id)
 or public.is_country_president(country_id));
drop policy if exists company_owners_read on public.company_owners;
create policy company_owners_read on public.company_owners for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(company_id) or exists(select 1 from public.companies c where c.id=company_id and public.is_country_president(c.country_id)));
drop policy if exists company_departments_read on public.company_departments;
create policy company_departments_read on public.company_departments for select to authenticated using(public.is_world_admin() or public.is_company_member(company_id) or exists(select 1 from public.companies c where c.id=company_id and c.status='active'));
drop policy if exists company_members_read on public.company_members;
create policy company_members_read on public.company_members for select to authenticated using(profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(company_id,'staff.read'));
drop policy if exists job_positions_read on public.job_positions;
create policy job_positions_read on public.job_positions for select to authenticated using(public.is_world_admin() or public.is_company_member(company_id) or exists(select 1 from public.companies c where c.id=company_id and c.status='active'));
drop policy if exists job_openings_read on public.job_openings;
create policy job_openings_read on public.job_openings for select to authenticated using(status='open' or public.is_world_admin() or public.is_company_member(company_id));
drop policy if exists job_applications_read on public.job_applications;
create policy job_applications_read on public.job_applications for select to authenticated using(applicant_profile_id=auth.uid() or public.is_world_admin() or public.is_company_member((select company_id from public.job_openings where id=opening_id),'hr.read'));
drop policy if exists employment_contracts_read on public.employment_contracts;
create policy employment_contracts_read on public.employment_contracts for select to authenticated using(employee_profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(company_id,'contracts.read'));
drop policy if exists employment_history_read on public.employment_history;
create policy employment_history_read on public.employment_history for select to authenticated using(employee_profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(company_id,'contracts.read'));
drop policy if exists employment_contract_revisions_read on public.employment_contract_revisions;
create policy employment_contract_revisions_read on public.employment_contract_revisions for select to authenticated using(exists(select 1 from public.employment_contracts c where c.id=contract_id and (c.employee_profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(c.company_id,'contracts.read'))));
drop policy if exists payroll_records_read on public.payroll_records;
create policy payroll_records_read on public.payroll_records for select to authenticated using(employee_profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(company_id,'payroll.read'));
drop policy if exists salary_payments_read on public.salary_payments;
create policy salary_payments_read on public.salary_payments for select to authenticated using(employee_profile_id=auth.uid() or public.is_world_admin() or public.is_company_member(company_id,'payroll.read'));
drop policy if exists company_financial_records_read on public.company_financial_records;
create policy company_financial_records_read on public.company_financial_records for select to authenticated using(public.is_world_admin() or public.is_company_member(company_id,'finance.read'));
drop policy if exists company_tax_records_read on public.company_tax_records;
create policy company_tax_records_read on public.company_tax_records for select to authenticated using(public.is_world_admin() or public.is_company_member(company_id,'tax.read') or exists(select 1 from public.companies c where c.id=company_id and public.is_country_president(c.country_id)));

revoke all on public.companies,public.company_owners,public.company_departments,public.company_members,public.job_positions,public.job_openings,
 public.job_applications,public.employment_contracts,public.employment_history,public.employment_contract_revisions,
 public.payroll_records,public.salary_payments,public.company_financial_records,public.company_tax_records,public.company_audit_logs from public,anon,authenticated;
grant select on public.companies,public.company_owners,public.company_departments,public.company_members,public.job_positions,public.job_openings,
 public.job_applications,public.employment_contracts,public.employment_history,public.employment_contract_revisions,
 public.payroll_records,public.salary_payments,public.company_financial_records,public.company_tax_records to authenticated;
grant select on public.company_audit_logs to authenticated;

drop policy if exists bank_accounts_company_read on public.bank_accounts;
create policy bank_accounts_company_read on public.bank_accounts for select to authenticated
using(owner_company_id is not null and (public.is_world_admin() or public.is_company_member(owner_company_id,'finance.read') or public.is_company_member(owner_company_id,'payroll.read')));
drop policy if exists bank_transactions_company_read on public.bank_transactions;
create policy bank_transactions_company_read on public.bank_transactions for select to authenticated
using(exists(select 1 from public.bank_accounts a where a.id=account_id and a.owner_company_id is not null and (public.is_world_admin() or public.is_company_member(a.owner_company_id,'finance.read') or public.is_company_member(a.owner_company_id,'payroll.read'))));

create or replace function public.request_company_registration(
 p_legal_name text,p_trade_name text,p_country_id uuid,p_city text,p_region text,p_sector text,p_company_type text,p_size_class text,
 p_description text,p_declared_capital numeric,p_currency_id uuid,p_government_entity_id uuid default null,p_logo_url text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; v_id uuid; v_identifier text; v_code text;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into p from public.profiles where id=auth.uid() for update;
 if not found or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' or p.country_id is distinct from p_country_id then raise exception 'Somente cidadão ativo do país de registro pode solicitar empresa.'; end if;
 if length(trim(coalesce(p_legal_name,'')))<2 or p_sector not in ('commerce','construction','agriculture','livestock','mining','industry','transport','technology','services','food','health','education','energy','tourism','other') or p_company_type not in ('private','public','state_owned','partnership') or p_size_class not in ('small_business','large_enterprise') or p_declared_capital is null or p_declared_capital<0 or p_declared_capital<>round(p_declared_capital,6) then raise exception 'Dados cadastrais inválidos.'; end if;
 if p_company_type in ('public','state_owned') and (p_government_entity_id is null or not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_economy_permission(p_country_id,'economy.manage'))) then raise exception 'Empresas públicas ou estatais exigem vínculo a ministério e autorização governamental.'; end if;
 if p_company_type in ('public','state_owned') and not exists(select 1 from public.ministries m where m.id=p_government_entity_id and m.country_id=p_country_id and m.status='active') then raise exception 'O ministério informado não pertence ao país de registro ou está inativo.'; end if;
 if not exists(select 1 from public.countries c join public.currencies cu on cu.internal_code=c.currency_code where c.id=p_country_id and c.is_active and cu.id=p_currency_id and cu.status='active') then raise exception 'A moeda deve corresponder à moeda nacional ativa do país.'; end if;
 v_code:='WE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.companies(company_identifier,legal_name,trade_name,country_id,city,region,sector,company_type,size_class,description,declared_capital,currency_id,government_entity_id,logo_url,created_by)
 values(v_code,trim(p_legal_name),nullif(trim(p_trade_name),''),p_country_id,nullif(trim(p_city),''),nullif(trim(p_region),''),p_sector,p_company_type,p_size_class,nullif(trim(p_description),''),p_declared_capital,p_currency_id,p_government_entity_id,nullif(trim(p_logo_url),''),auth.uid()) returning id into v_id;
 insert into public.company_owners(company_id,profile_id,ownership_percent,owner_role,appointed_by) values(v_id,auth.uid(),100,'founder',auth.uid());
 insert into public.company_members(company_id,profile_id,member_role,permissions,appointed_by)
 values(v_id,auth.uid(),'owner',array['company.manage','staff.read','hr.read','contracts.read','payroll.read','finance.read','tax.read','department.manage','jobs.manage'],auth.uid());
 perform public.company_audit(v_id,'company_requested','company',v_id,jsonb_build_object('identifier',v_code,'status','pending'));
 return v_id;
end;
$function$;

create or replace function public.admin_review_company(p_company_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare c public.companies%rowtype;
begin
 if not public.is_world_admin() or p_status not in ('active','suspended','closed') then raise exception 'Operação não autorizada ou situação inválida.'; end if;
 select * into c from public.companies where id=p_company_id for update;
 if not found then raise exception 'Empresa não encontrada.'; end if;
 update public.companies set status=p_status,approved_by=case when p_status='active' then auth.uid() else approved_by end,approved_at=case when p_status='active' then now() else approved_at end,updated_at=now() where id=c.id;
 perform public.company_audit(c.id,'company_status_changed','company',c.id,jsonb_build_object('from',c.status,'to',p_status,'note',p_note));
end;
$function$;

create or replace function public.company_upsert_department(p_company_id uuid,p_department_id uuid,p_name text,p_description text,p_manager uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_company_member(p_company_id,'department.manage') then raise exception 'Sem permissão para administrar departamentos.'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Nome de departamento inválido.'; end if;
 if p_department_id is null then insert into public.company_departments(company_id,name,description,manager_profile_id,created_by) values(p_company_id,trim(p_name),nullif(trim(p_description),''),p_manager,auth.uid()) returning id into v_id;
 else update public.company_departments set name=trim(p_name),description=nullif(trim(p_description),''),manager_profile_id=p_manager where id=p_department_id and company_id=p_company_id returning id into v_id; if v_id is null then raise exception 'Departamento não encontrado.'; end if; end if;
 perform public.company_audit(p_company_id,'department_saved','department',v_id,jsonb_build_object('name',p_name,'manager',p_manager)); return v_id;
end;
$function$;

create or replace function public.company_upsert_position(p_company_id uuid,p_position_id uuid,p_title text,p_description text,p_department_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_company_member(p_company_id,'jobs.manage') then raise exception 'Sem permissão para administrar cargos.'; end if;
 if length(trim(coalesce(p_title,'')))<2 then raise exception 'Cargo inválido.'; end if;
 if p_position_id is null then insert into public.job_positions(company_id,title,description,department_id,created_by) values(p_company_id,trim(p_title),nullif(trim(p_description),''),p_department_id,auth.uid()) returning id into v_id;
 else update public.job_positions set title=trim(p_title),description=nullif(trim(p_description),''),department_id=p_department_id where id=p_position_id and company_id=p_company_id returning id into v_id; if v_id is null then raise exception 'Cargo não encontrado.'; end if; end if;
 perform public.company_audit(p_company_id,'position_saved','job_position',v_id,jsonb_build_object('title',p_title)); return v_id;
end;
$function$;

create or replace function public.company_manage_member(p_company_id uuid,p_profile_id uuid,p_role text,p_permissions text[],p_status text default 'active')
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_company_member(p_company_id,'company.manage') then raise exception 'Sem permissão para administrar membros.'; end if;
 if p_role not in ('director','manager','hr','finance','employee') or p_status not in ('active','suspended','removed') or not exists(select 1 from public.profiles where id=p_profile_id and registration_status='active' and coalesce(account_status,'active')='active') then raise exception 'Membro ou função inválidos.'; end if;
 insert into public.company_members(company_id,profile_id,member_role,permissions,status,appointed_by) values(p_company_id,p_profile_id,p_role,coalesce(p_permissions,'{}'),p_status,auth.uid())
 on conflict(company_id,profile_id) do update set member_role=excluded.member_role,permissions=excluded.permissions,status=excluded.status returning id into v_id;
 perform public.company_audit(p_company_id,'member_updated','company_member',v_id,jsonb_build_object('profile_id',p_profile_id,'role',p_role,'status',p_status)); return v_id;
end;
$function$;

create or replace function public.company_open_job(p_company_id uuid,p_position_id uuid,p_title text,p_description text,p_requirements text,p_salary numeric,p_currency_id uuid,p_employment_type text,p_openings integer,p_city text,p_region text,p_deadline timestamptz default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.companies%rowtype; v_id uuid;
begin
 if not public.is_company_member(p_company_id,'jobs.manage') then raise exception 'Sem permissão para publicar vagas.'; end if;
 select * into c from public.companies where id=p_company_id and status='active'; if not found then raise exception 'Empresa não está ativa.'; end if;
 if not exists(select 1 from public.job_positions where id=p_position_id and company_id=p_company_id and status='active') or p_salary is null or p_salary<0 or p_salary<>round(p_salary,6) or p_openings not between 1 and 10000 or p_employment_type not in ('monthly','hourly','daily','project') or (p_deadline is not null and p_deadline<=now()) then raise exception 'Dados da vaga inválidos.'; end if;
 if not exists(select 1 from public.currencies where id=p_currency_id and status='active') then raise exception 'Moeda inválida.'; end if;
 insert into public.job_openings(company_id,position_id,title,description,requirements,salary_amount,currency_id,employment_type,openings_count,country_id,city,region,application_deadline,created_by)
 values(p_company_id,p_position_id,trim(p_title),trim(p_description),nullif(trim(p_requirements),''),p_salary,p_currency_id,p_employment_type,p_openings,c.country_id,nullif(trim(p_city),''),nullif(trim(p_region),''),p_deadline,auth.uid()) returning id into v_id;
 perform public.company_audit(p_company_id,'job_published','job_opening',v_id,jsonb_build_object('title',p_title,'openings',p_openings)); return v_id;
end;
$function$;

create or replace function public.citizen_apply_job(p_opening_id uuid,p_cover_letter text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare o public.job_openings%rowtype; p public.profiles%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into p from public.profiles where id=auth.uid(); if not found or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' then raise exception 'Somente cidadão ativo pode candidatar-se.'; end if;
 select * into o from public.job_openings where id=p_opening_id and status='open' and (application_deadline is null or application_deadline>now()); if not found then raise exception 'Vaga encerrada ou prazo expirado.'; end if;
 if p.country_id is distinct from o.country_id then raise exception 'A candidatura deve respeitar o país da vaga.'; end if;
 insert into public.job_applications(opening_id,applicant_profile_id,cover_letter) values(o.id,auth.uid(),nullif(trim(p_cover_letter),'')) returning id into v_id;
 perform public.company_audit(o.company_id,'application_submitted','job_application',v_id,jsonb_build_object('applicant',auth.uid())); return v_id;
exception when unique_violation then raise exception 'Você já se candidatou a esta vaga.';
end;
$function$;

create or replace function public.company_review_application(p_application_id uuid,p_decision text,p_note text,p_salary numeric default null,p_job_title text default null,p_starts_at date default current_date)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.job_applications%rowtype; o public.job_openings%rowtype; v_contract uuid;
begin
 select * into a from public.job_applications where id=p_application_id for update; if not found then raise exception 'Candidatura não encontrada.'; end if;
 select * into o from public.job_openings where id=a.opening_id;
 if not public.is_company_member(o.company_id,'hr.manage') then raise exception 'Sem permissão para revisar candidaturas.'; end if;
 if a.status not in ('submitted','reviewing') or p_decision not in ('reviewing','accepted','rejected') then raise exception 'Candidatura já revisada ou decisão inválida.'; end if;
 update public.job_applications set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),''),updated_at=now() where id=a.id;
 if p_decision='accepted' then
  insert into public.employment_contracts(company_id,employee_profile_id,position_id,department_id,application_id,job_title,salary_amount,currency_id,pay_frequency,employment_type,starts_at,status,company_accepted_at,created_by)
  values(o.company_id,a.applicant_profile_id,o.position_id,(select department_id from public.job_positions where id=o.position_id),a.id,coalesce(nullif(trim(p_job_title),''),o.title),coalesce(p_salary,o.salary_amount),o.currency_id,
   case o.employment_type when 'monthly' then 'monthly' when 'hourly' then 'hourly' when 'daily' then 'daily' else 'project' end,
   'permanent',p_starts_at,'pending_employee',now(),auth.uid()) returning id into v_contract;
  insert into public.employment_history(contract_id,company_id,employee_profile_id,event_type,new_data,actor_id)
  values(v_contract,o.company_id,a.applicant_profile_id,'offered',jsonb_build_object('salary',coalesce(p_salary,o.salary_amount),'currency_id',o.currency_id,'job_title',coalesce(p_job_title,o.title)),auth.uid());
 end if;
 perform public.company_audit(o.company_id,'application_reviewed','job_application',a.id,jsonb_build_object('decision',p_decision,'contract_id',v_contract)); return v_contract;
end;
$function$;

create or replace function public.respond_employment_offer(p_contract_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare c public.employment_contracts%rowtype;
begin
 select * into c from public.employment_contracts where id=p_contract_id and employee_profile_id=auth.uid() for update;
 if not found or c.status<>'pending_employee' then raise exception 'Oferta inexistente ou não está aguardando sua resposta.'; end if;
 if p_accept then
  update public.employment_contracts set status='active',employee_accepted_at=now(),updated_at=now() where id=c.id;
  insert into public.employment_history(contract_id,company_id,employee_profile_id,event_type,new_data,actor_id)
  values(c.id,c.company_id,c.employee_profile_id,'accepted',to_jsonb(c),auth.uid());
  insert into public.company_members(company_id,profile_id,member_role,permissions,appointed_by)
  values(c.company_id,c.employee_profile_id,'employee',array['contracts.read'],auth.uid()) on conflict(company_id,profile_id) do nothing;
 else
  update public.employment_contracts set status='rejected',updated_at=now() where id=c.id;
  insert into public.employment_history(contract_id,company_id,employee_profile_id,event_type,previous_data,actor_id)
  values(c.id,c.company_id,c.employee_profile_id,'rejected',to_jsonb(c),auth.uid());
 end if;
 perform public.company_audit(c.company_id,case when p_accept then 'employment_accepted' else 'employment_rejected' end,'employment_contract',c.id,'{}'::jsonb);
end;
$function$;

create or replace function public.company_terminate_employment(p_contract_id uuid,p_reason text,p_resignation boolean default false)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare c public.employment_contracts%rowtype;
begin
 select * into c from public.employment_contracts where id=p_contract_id for update; if not found or c.status<>'active' then raise exception 'Vínculo ativo não encontrado.'; end if;
 if p_resignation then if c.employee_profile_id<>auth.uid() then raise exception 'Somente o funcionário pode pedir demissão.'; end if;
 else if not public.is_company_member(c.company_id,'hr.manage') then raise exception 'Sem permissão para encerrar vínculo.'; end if; end if;
 update public.employment_contracts set status='terminated',ends_at=coalesce(ends_at,current_date),updated_at=now() where id=c.id;
 update public.company_members set status='removed' where company_id=c.company_id and profile_id=c.employee_profile_id and member_role='employee';
 insert into public.employment_history(contract_id,company_id,employee_profile_id,event_type,previous_data,new_data,actor_id)
 values(c.id,c.company_id,c.employee_profile_id,case when p_resignation then 'resigned' else 'terminated' end,to_jsonb(c),jsonb_build_object('reason',p_reason),auth.uid());
 perform public.company_audit(c.company_id,'employment_terminated','employment_contract',c.id,jsonb_build_object('reason',p_reason,'resignation',p_resignation));
end;
$function$;

create or replace function public.company_create_payroll(p_company_id uuid,p_contract_id uuid,p_period text,p_gross numeric,p_deductions numeric,p_tax_status text default 'not_configured')
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.employment_contracts%rowtype; v_id uuid;
begin
 if not public.is_company_member(p_company_id,'payroll.manage') then raise exception 'Sem permissão para preparar folha salarial.'; end if;
 select * into c from public.employment_contracts where id=p_contract_id and company_id=p_company_id and status='active';
 if not found or p_gross is null or p_gross<0 or p_gross<>round(p_gross,6) or p_deductions is null or p_deductions<0 or p_deductions>p_gross or p_deductions<>round(p_deductions,6) or length(trim(coalesce(p_period,'')))<4 or p_tax_status not in ('not_configured','reviewed','exempt','pending') then raise exception 'Dados de folha inválidos.'; end if;
 if p_gross<>c.salary_amount then raise exception 'O valor bruto deve corresponder ao salário vigente no contrato. Atualize o contrato formalmente antes de gerar a folha.'; end if;
 insert into public.payroll_records(company_id,contract_id,employee_profile_id,reference_period,gross_amount,deductions_amount,currency_id,tax_calculation_status,created_by)
 values(p_company_id,c.id,c.employee_profile_id,trim(p_period),p_gross,p_deductions,c.currency_id,p_tax_status,auth.uid()) returning id into v_id;
 perform public.company_audit(p_company_id,'payroll_created','payroll',v_id,jsonb_build_object('period',p_period,'gross',p_gross,'deductions',p_deductions)); return v_id;
end;
$function$;

create or replace function public.company_approve_payroll(p_payroll_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare p public.payroll_records%rowtype;
begin
 select * into p from public.payroll_records where id=p_payroll_id for update; if not found or p.status<>'draft' then raise exception 'Folha não está em rascunho.'; end if;
 if not public.is_company_member(p.company_id,'payroll.manage') then raise exception 'Sem permissão para aprovar folha.'; end if;
 if p.tax_calculation_status not in ('reviewed','exempt') then raise exception 'Revise a tributação aplicável ou registre formalmente a isenção antes de aprovar.'; end if;
 update public.payroll_records set status='approved',approved_by=auth.uid(),approved_at=now() where id=p.id;
 perform public.company_audit(p.company_id,'payroll_approved','payroll',p.id,'{}'::jsonb);
end;
$function$;


alter table public.companies drop constraint if exists companies_government_entity_fk;
alter table public.companies add constraint companies_government_entity_fk foreign key(government_entity_id) references public.ministries(id) on delete restrict;

create table if not exists public.employment_payout_accounts (
 contract_id uuid primary key references public.employment_contracts(id) on delete restrict,
 employee_profile_id uuid not null references public.profiles(id) on delete restrict,
 account_id uuid not null references public.bank_accounts(id) on delete restrict,
 authorized_at timestamptz not null default now(),
 unique(contract_id,account_id)
);
alter table public.employment_payout_accounts enable row level security;
drop policy if exists employment_payout_accounts_read on public.employment_payout_accounts;
create policy employment_payout_accounts_read on public.employment_payout_accounts for select to authenticated
using(employee_profile_id=auth.uid() or public.is_world_admin() or exists(select 1 from public.employment_contracts c where c.id=contract_id and public.is_company_member(c.company_id,'payroll.manage')));
revoke all on public.employment_payout_accounts from public,anon,authenticated;
grant select on public.employment_payout_accounts to authenticated;

create or replace function public.set_my_employment_payout_account(p_contract_id uuid,p_account_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare c public.employment_contracts%rowtype; a public.bank_accounts%rowtype;
begin
 select * into c from public.employment_contracts where id=p_contract_id and employee_profile_id=auth.uid() and status='active';
 if not found then raise exception 'Vínculo ativo não encontrado.'; end if;
 select * into a from public.bank_accounts where id=p_account_id and owner_profile_id=auth.uid() and status='active';
 if not found or a.currency_id<>c.currency_id or a.country_id<>(select country_id from public.companies where id=c.company_id) then raise exception 'A conta precisa pertencer ao funcionário, estar ativa e usar a moeda nacional do contrato.'; end if;
 insert into public.employment_payout_accounts(contract_id,employee_profile_id,account_id)
 values(c.id,auth.uid(),a.id)
 on conflict(contract_id) do update set account_id=excluded.account_id,authorized_at=now();
 perform public.company_audit(c.company_id,'salary_account_authorized','employment_payout_account',c.id,jsonb_build_object('account_id',a.id));
end;
$function$;
revoke all on function public.set_my_employment_payout_account(uuid,uuid) from public,anon;
grant execute on function public.set_my_employment_payout_account(uuid,uuid) to authenticated;

create or replace function public.company_pay_salary(p_payroll_id uuid,p_from_account uuid,p_employee_account uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.payroll_records%rowtype; src public.bank_accounts%rowtype; dst public.bank_accounts%rowtype; b public.commercial_banks%rowtype; v_id uuid; v_source_after numeric; v_dest_after numeric; v_existing public.salary_payments%rowtype;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Autenticação ou chave idempotente inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 select * into v_existing from public.salary_payments where idempotency_key=p_idempotency_key;
 if found then if v_existing.payroll_id=p_payroll_id and v_existing.from_account_id=p_from_account and v_existing.to_account_id=p_employee_account then return v_existing.id; end if; raise exception 'Chave idempotente reutilizada com outros dados.'; end if;
 select * into p from public.payroll_records where id=p_payroll_id for update;
 if not found or p.status<>'approved' then raise exception 'Folha não está aprovada.'; end if;
 if not public.is_company_member(p.company_id,'payroll.manage') then raise exception 'Sem permissão para pagar salários.'; end if;
 select * into src from public.bank_accounts where id=p_from_account for update;
 select * into dst from public.bank_accounts where id=p_employee_account for update;
 if src.id is null or src.owner_company_id<>p.company_id or src.status<>'active' then raise exception 'Conta empresarial de origem inválida ou inativa.'; end if;
 if dst.id is null or dst.owner_profile_id<>p.employee_profile_id or dst.status<>'active' then raise exception 'Conta de destino não pertence ao funcionário ou está inativa.'; end if;
 if not exists(select 1 from public.employment_payout_accounts pa where pa.contract_id=p.contract_id and pa.employee_profile_id=p.employee_profile_id and pa.account_id=dst.id) then raise exception 'O funcionário ainda não autorizou esta conta para receber salário.'; end if;
 if not exists(select 1 from public.commercial_banks bx where bx.id=dst.bank_id and bx.status='active') then raise exception 'Banco da conta do funcionário indisponível.'; end if;
 if src.currency_id<>p.currency_id or dst.currency_id<>p.currency_id then raise exception 'Moeda das contas deve ser igual à moeda da folha.'; end if;
 select * into b from public.commercial_banks where id=src.bank_id and status='active'; if not found then raise exception 'Banco de origem indisponível.'; end if;
 if src.balance<p.net_amount then raise exception 'Saldo empresarial insuficiente. Folha não paga.'; end if;
 if p.net_amount<=0 then raise exception 'Valor líquido deve ser maior que zero.'; end if;
 update public.bank_accounts set balance=balance-p.net_amount where id=src.id returning balance into v_source_after;
 update public.bank_accounts set balance=balance+p.net_amount where id=dst.id returning balance into v_dest_after;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(src.id,'transfer_out',p.net_amount,p.currency_id,v_source_after,'Pagamento de salário — folha '||p.reference_period,p.id,p_idempotency_key||':out',auth.uid());
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(dst.id,'transfer_in',p.net_amount,p.currency_id,v_dest_after,'Salário recebido — '||p.reference_period,p.id,p_idempotency_key||':in',auth.uid());
 insert into public.bank_transfers(from_account_id,to_account_id,amount_sent,from_currency_id,amount_received,to_currency_id,exchange_rate,fee_amount,status,description,idempotency_key,initiated_by)
 values(src.id,dst.id,p.net_amount,p.currency_id,p.net_amount,p.currency_id,1,0,'completed','Pagamento salarial',p_idempotency_key,auth.uid());
 insert into public.salary_payments(payroll_id,company_id,employee_profile_id,from_account_id,to_account_id,amount,currency_id,idempotency_key,paid_by)
 values(p.id,p.company_id,p.employee_profile_id,src.id,dst.id,p.net_amount,p.currency_id,p_idempotency_key,auth.uid()) returning id into v_id;
 update public.payroll_records set status='paid',paid_at=now() where id=p.id;
 insert into public.company_financial_records(company_id,record_type,category,description,amount,currency_id,record_status,reference_type,reference_id,responsible_profile_id)
 values(p.company_id,'expense','payroll','Pagamento de salário — '||p.reference_period,p.net_amount,p.currency_id,'paid','salary_payment',v_id,auth.uid());
 perform public.company_audit(p.company_id,'salary_paid','salary_payment',v_id,jsonb_build_object('amount',p.net_amount,'currency_id',p.currency_id,'payroll_id',p.id));
 return v_id;
end;
$function$;

create or replace function public.company_record_financial_event(p_company_id uuid,p_type text,p_category text,p_description text,p_amount numeric,p_currency_id uuid,p_status text,p_reference_type text default null,p_reference_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_company_member(p_company_id,'finance.manage') then raise exception 'Sem permissão para registrar receitas ou despesas.'; end if;
 if p_type not in ('revenue','expense') or p_status not in ('planned','paid','received','cancelled') or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,6) or length(trim(coalesce(p_description,'')))<3 or not exists(select 1 from public.currencies where id=p_currency_id and status='active') then raise exception 'Registro financeiro inválido.'; end if;
 insert into public.company_financial_records(company_id,record_type,category,description,amount,currency_id,record_status,reference_type,reference_id,responsible_profile_id)
 values(p_company_id,p_type,trim(p_category),trim(p_description),p_amount,p_currency_id,p_status,p_reference_type,p_reference_id,auth.uid()) returning id into v_id;
 perform public.company_audit(p_company_id,'financial_record_created','financial_record',v_id,jsonb_build_object('type',p_type,'amount',p_amount,'status',p_status)); return v_id;
end;
$function$;

create or replace function public.company_create_tax_record(p_company_id uuid,p_tax_rule_id uuid,p_description text,p_period text,p_base numeric,p_amount numeric)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.companies%rowtype; t public.tax_rules%rowtype; v_id uuid; v_rate numeric;
begin
 if not public.is_company_member(p_company_id,'tax.manage') then raise exception 'Sem permissão para registrar tributos empresariais.'; end if;
 select * into c from public.companies where id=p_company_id;
 select * into t from public.tax_rules where id=p_tax_rule_id and country_id=c.country_id and status='active' and current_date between effective_from and coalesce(effective_until,'infinity'::date);
 if not found then raise exception 'Regra tributária não está ativa para este país e período.'; end if;
 if p_base is null or p_base<0 or p_amount is null or p_amount<0 or p_base<>round(p_base,6) or p_amount<>round(p_amount,6) then raise exception 'Base ou tributo inválido.'; end if;
 if t.calculation_base<>'declared_value' then raise exception 'A base de cálculo desta regra ainda não está automatizada; não será estimado um tributo.'; end if;
 v_rate:=t.rate;
 if p_amount<>round(p_base*v_rate/100,2) then raise exception 'Valor tributário diverge da alíquota ativa (%). Valor esperado: %.',v_rate,round(p_base*v_rate/100,2); end if;
 insert into public.company_tax_records(company_id,tax_rule_id,description,reference_period,tax_base,applied_rate,amount_due,currency_id,status,created_by)
 values(c.id,t.id,trim(p_description),trim(p_period),p_base,v_rate,p_amount,c.currency_id,'pending_review',auth.uid()) returning id into v_id;
 perform public.company_audit(c.id,'tax_record_created','company_tax_record',v_id,jsonb_build_object('tax_rule',t.identifier,'rate',v_rate,'amount',p_amount)); return v_id;
end;
$function$;

create or replace function public.admin_validate_company_tax(p_tax_record_id uuid,p_tax_obligation_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.company_tax_records%rowtype; o public.tax_obligations%rowtype;
begin
 if not public.is_world_admin() then raise exception 'Somente Super Admin valida obrigações tributárias empresariais.'; end if;
 select * into r from public.company_tax_records where id=p_tax_record_id for update;
 if not found or r.status<>'pending_review' then raise exception 'Registro tributário indisponível.'; end if;
 select * into o from public.tax_obligations where id=p_tax_obligation_id and country_id=(select country_id from public.companies where id=r.company_id);
 if not found or o.amount_due<>r.amount_due or o.currency_code_snapshot<>(select internal_code from public.currencies where id=r.currency_id) then raise exception 'Obrigação fiscal não corresponde ao valor, país ou moeda do registro.'; end if;
 update public.company_tax_records set tax_obligation_id=o.id,status='validated',validated_by=auth.uid(),validated_at=now() where id=r.id;
 perform public.company_audit(r.company_id,'tax_record_validated','company_tax_record',r.id,jsonb_build_object('tax_obligation_id',o.id));
end;
$function$;

create or replace function public.open_company_bank_account(p_company_id uuid,p_bank_id uuid,p_currency_id uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.companies%rowtype; b public.commercial_banks%rowtype; v_id uuid; v_number text;
begin
 if not public.is_company_member(p_company_id,'finance.manage') then raise exception 'Sem permissão para solicitar conta empresarial.'; end if;
 select * into c from public.companies where id=p_company_id and status='active'; if not found then raise exception 'Empresa não está ativa.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id and country_id=c.country_id and status='active'; if not found then raise exception 'Banco ativo do país da empresa não encontrado.'; end if;
 if not exists(select 1 from public.currencies where id=p_currency_id and status='active' and internal_code=(select currency_code from public.countries where id=c.country_id)) then raise exception 'Conta empresarial deve usar a moeda nacional vigente.'; end if;
 if exists(select 1 from public.bank_accounts where owner_company_id=c.id and bank_id=b.id and currency_id=p_currency_id and status<>'closed') then raise exception 'A empresa já possui conta aberta neste banco e moeda.'; end if;
 v_number:=lpad((floor(random()*89999999)+10000000)::bigint::text,8,'0');
 insert into public.bank_accounts(bank_id,owner_company_id,country_id,currency_id,account_number,account_type,status,balance)
 values(b.id,c.id,c.country_id,p_currency_id,v_number,'business','active',0) returning id into v_id;
 perform public.company_audit(c.id,'company_bank_account_opened','bank_account',v_id,jsonb_build_object('bank_id',b.id,'currency_id',p_currency_id));
 return v_id;
end;
$function$;

-- Abertura de conta empresarial é a única RPC autorizada a criar conta com titularidade de empresa.
revoke all on public.bank_accounts from public,anon,authenticated;
grant select on public.bank_accounts to authenticated;

do $$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
   'request_company_registration','admin_review_company','company_upsert_department','company_upsert_position','company_manage_member',
   'company_open_job','citizen_apply_job','company_review_application','respond_employment_offer','company_terminate_employment',
   'company_create_payroll','company_approve_payroll','company_pay_salary','company_record_financial_event',
   'company_create_tax_record','admin_validate_company_tax','open_company_bank_account','set_my_employment_payout_account','company_manage_owner','company_amend_employment_contract','company_pay_payroll_batch'
  )
 loop execute format('revoke all on function %s from public,anon',f.signature); execute format('grant execute on function %s to authenticated',f.signature); end loop;
end $$;


-- Obrigações fiscais podem identificar empresa sem reutilizar identidade pessoal do cidadão.
alter table public.tax_obligations add column if not exists taxpayer_company_id uuid references public.companies(id) on delete restrict;
create index if not exists tax_obligations_company_idx on public.tax_obligations(taxpayer_company_id,status);

create or replace function public.admin_validate_company_tax(p_tax_record_id uuid,p_tax_obligation_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.company_tax_records%rowtype; o public.tax_obligations%rowtype; c public.companies%rowtype;
begin
 if not public.is_world_admin() then raise exception 'Somente Super Admin valida obrigações tributárias empresariais.'; end if;
 select * into r from public.company_tax_records where id=p_tax_record_id for update;
 if not found or r.status<>'pending_review' then raise exception 'Registro tributário indisponível.'; end if;
 select * into c from public.companies where id=r.company_id;
 select * into o from public.tax_obligations where id=p_tax_obligation_id and country_id=c.country_id;
 if not found or o.taxpayer_company_id is distinct from c.id or o.amount_due<>r.amount_due or o.tax_rule_id is distinct from r.tax_rule_id or o.currency_code_snapshot<>(select internal_code from public.currencies where id=r.currency_id) then
  raise exception 'Obrigação fiscal não identifica esta empresa ou diverge em valor, regra, país ou moeda.';
 end if;
 update public.company_tax_records set tax_obligation_id=o.id,status='validated',validated_by=auth.uid(),validated_at=now() where id=r.id;
 perform public.company_audit(r.company_id,'tax_record_validated','company_tax_record',r.id,jsonb_build_object('tax_obligation_id',o.id));
end;
$function$;

create or replace function public.company_pay_tax_obligation(p_company_id uuid,p_tax_record_id uuid,p_account_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare r public.company_tax_records%rowtype; o public.tax_obligations%rowtype; a public.bank_accounts%rowtype; t public.national_treasuries%rowtype;
 v_paid numeric; v_remaining numeric; v_code text; v_tx uuid; v_collection uuid; v_after numeric; v_existing public.bank_transactions%rowtype;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Autenticação ou chave idempotente inválida.'; end if;
 if not public.is_company_member(p_company_id,'tax.manage') then raise exception 'Sem permissão para quitar tributos empresariais.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 select * into v_existing from public.bank_transactions where idempotency_key=p_idempotency_key;
 if found then if v_existing.transaction_type='tax_payment' and v_existing.actor_id=auth.uid() and exists(select 1 from public.tax_collections tc where tc.id=v_existing.reference_id and tc.obligation_id=(select tax_obligation_id from public.company_tax_records where id=p_tax_record_id) and tc.amount=v_existing.amount) then return v_existing.id; end if; raise exception 'Chave idempotente já utilizada com outros dados.'; end if;
 select * into r from public.company_tax_records where id=p_tax_record_id and company_id=p_company_id for update;
 if not found or r.status<>'validated' or r.tax_obligation_id is null then raise exception 'Registro fiscal não validado ou sem obrigação vinculada.'; end if;
 select * into o from public.tax_obligations where id=r.tax_obligation_id and taxpayer_company_id=p_company_id for update;
 if not found or o.status not in ('open','partially_paid','overdue','pending_confirmation') then raise exception 'Obrigação tributária da empresa indisponível.'; end if;
 select * into a from public.bank_accounts where id=p_account_id and owner_company_id=p_company_id for update;
 if not found or a.status<>'active' or a.country_id<>o.country_id or a.currency_id<>r.currency_id then raise exception 'Conta bancária empresarial inválida para esta obrigação.'; end if;
 select internal_code into v_code from public.currencies where id=a.currency_id and status='active';
 if v_code is null or v_code<>o.currency_code_snapshot then raise exception 'Moeda da conta diverge da obrigação tributária.'; end if;
 if not exists(select 1 from public.commercial_banks b where b.id=a.bank_id and b.status='active') then raise exception 'Banco indisponível.'; end if;
 select * into t from public.national_treasuries where country_id=o.country_id for update;
 if not found or t.operations_suspended or t.currency_code is distinct from v_code then raise exception 'Tesouro Nacional indisponível ou com moeda divergente.'; end if;
 if (t.opening_balance>0 and t.opening_balance_currency_code_snapshot<>v_code) or exists(select 1 from public.treasury_ledger_entries e where e.country_id=o.country_id and e.currency_code_snapshot<>v_code) then raise exception 'Tesouro requer conciliação monetária.'; end if;
 select coalesce(sum(amount),0) into v_paid from public.tax_collections where obligation_id=o.id;
 v_remaining:=o.amount_due-v_paid;
 if v_remaining<=0 or r.amount_due>v_remaining then raise exception 'O valor fiscal registrado excede o saldo devido da obrigação.'; end if;
 if a.balance<r.amount_due then raise exception 'Saldo empresarial insuficiente. Tributo não pago.'; end if;
 update public.bank_accounts set balance=balance-r.amount_due where id=a.id returning balance into v_after;
 insert into public.tax_collections(country_id,obligation_id,amount,currency_code_snapshot,confirmation_reference,confirmed_by)
 values(o.country_id,o.id,r.amount_due,v_code,'company-bank:'||p_idempotency_key,auth.uid()) returning id into v_collection;
 insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,currency_code_snapshot,signed_amount,source_type,source_id,idempotency_key,created_by)
 values(o.country_id,'revenue','company_tax','Tributo empresarial — '||r.description,r.amount_due,v_code,r.amount_due,'tax_collection',v_collection,'company-tax:'||p_idempotency_key,auth.uid());
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'tax_payment',r.amount_due,a.currency_id,v_after,'Pagamento de tributo empresarial ao Tesouro',v_collection,p_idempotency_key,auth.uid()) returning id into v_tx;
 select coalesce(sum(amount),0) into v_paid from public.tax_collections where obligation_id=o.id;
 update public.tax_obligations set status=case when v_paid>=amount_due then 'paid' else 'partially_paid' end,updated_at=now() where id=o.id;
 update public.company_tax_records set status='paid' where id=r.id;
 insert into public.company_financial_records(company_id,record_type,category,description,amount,currency_id,record_status,reference_type,reference_id,responsible_profile_id)
 values(p_company_id,'expense','tax','Pagamento de tributo — '||r.description,r.amount_due,r.currency_id,'paid','bank_transaction',v_tx,auth.uid());
 perform public.company_audit(p_company_id,'company_tax_paid','company_tax_record',r.id,jsonb_build_object('amount',r.amount_due,'treasury_collection_id',v_collection));
 return v_tx;
end;
$function$;
revoke all on function public.company_pay_tax_obligation(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.company_pay_tax_obligation(uuid,uuid,uuid,text) to authenticated;



create or replace function public.company_manage_owner(p_company_id uuid,p_profile_id uuid,p_ownership_percent numeric,p_owner_role text default 'shareholder',p_status text default 'active')
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid; v_total numeric;
begin
 if not public.is_company_member(p_company_id,'company.manage') then raise exception 'Somente proprietários ou diretores autorizados podem administrar sócios.'; end if;
 if p_ownership_percent is null or p_ownership_percent<=0 or p_ownership_percent>100 or p_ownership_percent<>round(p_ownership_percent,4) or p_owner_role not in ('owner','shareholder','founder') or p_status not in ('active','removed') then raise exception 'Participação societária inválida.'; end if;
 if not exists(select 1 from public.profiles where id=p_profile_id and registration_status='active' and coalesce(account_status,'active')='active') then raise exception 'Sócio deve ser cidadão ativo.'; end if;
 select coalesce(sum(ownership_percent),0) into v_total from public.company_owners where company_id=p_company_id and status='active' and profile_id<>p_profile_id;
 if p_status='active' and v_total+p_ownership_percent>100 then raise exception 'A soma das participações societárias não pode exceder 100%.'; end if;
 insert into public.company_owners(company_id,profile_id,ownership_percent,owner_role,status,appointed_by)
 values(p_company_id,p_profile_id,p_ownership_percent,p_owner_role,p_status,auth.uid())
 on conflict(company_id,profile_id) do update set ownership_percent=excluded.ownership_percent,owner_role=excluded.owner_role,status=excluded.status,appointed_by=auth.uid()
 returning id into v_id;
 if p_status='active' then
  insert into public.company_members(company_id,profile_id,member_role,permissions,appointed_by)
  values(p_company_id,p_profile_id,'employee',array['contracts.read'],auth.uid())
  on conflict(company_id,profile_id) do update set status='active';
 else
  update public.company_members set status='removed' where company_id=p_company_id and profile_id=p_profile_id and member_role in ('owner','director');
 end if;
 perform public.company_audit(p_company_id,'ownership_changed','company_owner',v_id,jsonb_build_object('profile_id',p_profile_id,'percent',p_ownership_percent,'status',p_status));
 return v_id;
end;
$function$;

create or replace function public.company_amend_employment_contract(p_contract_id uuid,p_job_title text,p_salary numeric,p_department_id uuid,p_ends_at date,p_conditions text,p_event text default 'salary_changed')
returns void language plpgsql security definer set search_path=public,auth as $function$
declare c public.employment_contracts%rowtype; v_old jsonb; v_new jsonb;
begin
 select * into c from public.employment_contracts where id=p_contract_id for update;
 if not found or c.status<>'active' or not public.is_company_member(c.company_id,'hr.manage') then raise exception 'Contrato ativo não encontrado ou sem permissão.'; end if;
 if length(trim(coalesce(p_job_title,'')))<2 or p_salary is null or p_salary<0 or p_salary<>round(p_salary,6) or p_event not in ('salary_changed','role_changed','department_changed','renewed') then raise exception 'Alteração contratual inválida.'; end if;
 if p_department_id is not null and not exists(select 1 from public.company_departments where id=p_department_id and company_id=c.company_id and status='active') then raise exception 'Departamento não pertence à empresa.'; end if;
 if p_ends_at is not null and p_ends_at<c.starts_at then raise exception 'Data final anterior ao início do contrato.'; end if;
 v_old:=to_jsonb(c);
 update public.employment_contracts set job_title=trim(p_job_title),salary_amount=p_salary,department_id=p_department_id,ends_at=p_ends_at,conditions=p_conditions,updated_at=now() where id=c.id returning * into c;
 v_new:=to_jsonb(c);
 insert into public.employment_contract_revisions(contract_id,previous_data,new_data,revised_by) values(c.id,v_old,v_new,auth.uid());
 insert into public.employment_history(contract_id,company_id,employee_profile_id,event_type,previous_data,new_data,actor_id)
 values(c.id,c.company_id,c.employee_profile_id,p_event,v_old,v_new,auth.uid());
 perform public.company_audit(c.company_id,'contract_amended','employment_contract',c.id,jsonb_build_object('event',p_event));
end;
$function$;

create or replace function public.company_pay_payroll_batch(p_company_id uuid,p_period text,p_from_account uuid)
returns integer language plpgsql security definer set search_path=public,auth as $function$
declare p record; v_count integer:=0; v_account uuid;
begin
 if not public.is_company_member(p_company_id,'payroll.manage') then raise exception 'Sem permissão para processar folha.'; end if;
 select id into v_account from public.bank_accounts where id=p_from_account and owner_company_id=p_company_id and status='active' for update;
 if v_account is null then raise exception 'Conta empresarial de pagamento inválida.'; end if;
 for p in select pr.id,pr.employee_profile_id,pa.account_id from public.payroll_records pr
  left join public.employment_payout_accounts pa on pa.contract_id=pr.contract_id
  where pr.company_id=p_company_id and pr.reference_period=trim(p_period) and pr.status='approved'
  order by pr.created_at,pr.id
 loop
  if p.account_id is null then raise exception 'Funcionário % ainda não autorizou uma conta de recebimento. Folha integral cancelada.',p.employee_profile_id; end if;
  perform public.company_pay_salary(p.id,v_account,p.account_id,'payroll-batch:'||p.id::text);
  v_count:=v_count+1;
 end loop;
 if v_count=0 then raise exception 'Não há folhas aprovadas neste período.'; end if;
 return v_count;
end;
$function$;


do $
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in (
   'request_company_registration','admin_review_company','company_upsert_department','company_upsert_position','company_manage_member',
   'company_open_job','citizen_apply_job','company_review_application','respond_employment_offer','company_terminate_employment',
   'company_create_payroll','company_approve_payroll','company_pay_salary','company_record_financial_event',
   'company_create_tax_record','admin_validate_company_tax','open_company_bank_account','set_my_employment_payout_account',
   'company_manage_owner','company_amend_employment_contract','company_pay_payroll_batch','company_pay_tax_obligation'
  )
 loop execute format('revoke all on function %s from public,anon',f.signature); execute format('grant execute on function %s to authenticated',f.signature); end loop;
end $;

commit;
