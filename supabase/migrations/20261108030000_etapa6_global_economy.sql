-- WORLD ECONOMY — ETAPA 6: economia, tributos, Tesouro e orçamento
-- Migration aditiva; não altera nem remove dados das etapas 1–5.
begin;

create extension if not exists pgcrypto;

create or replace function public.has_economy_permission(p_country_id uuid,p_permission text)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select auth.uid() is not null and exists(
    select 1 from public.government_members gm
    join public.government_member_permissions gp on gp.member_id=gm.id and gp.country_id=gm.country_id
    join public.profiles member_profile on member_profile.id=gm.profile_id
      and coalesce(member_profile.account_status,'active')='active'
      and member_profile.registration_status='active'
    where gm.profile_id=auth.uid() and gm.country_id=p_country_id and gm.status='active'
      and gp.permission_key in (p_permission,'economy.manage')
      and (gp.scope_type='country'
        or (gp.scope_type='ministry' and gp.scope_id=gm.ministry_id)
        or (gp.scope_type='department' and gp.scope_id=gm.department_id))
      and exists(select 1 from public.countries c where c.id=p_country_id and c.is_active)
  );
$$;


create table if not exists public.national_treasuries (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null unique references public.countries(id) on delete restrict,
  opening_balance numeric(24,2) not null default 0 check (opening_balance >= 0),
  opening_balance_set_at timestamptz,
  opening_balance_currency_code_snapshot text not null default 'UNCONFIGURED',
  currency_code text,
  currency_label text not null default 'Unidade monetária provisória (não configurada)',
  require_global_tax_approval boolean not null default true,
  require_global_budget_approval boolean not null default true,
  public_balance_visible boolean not null default false,
  operations_suspended boolean not null default false,
  suspended_at timestamptz,
  suspended_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.economic_gdp_records (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  total_value numeric(24,2) not null default 0 check (total_value >= 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  source text not null default 'manual',
  source_description text,
  status text not null default 'confirmed' check (status in ('draft','confirmed','revised','cancelled')),
  created_by uuid not null references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (period_start <= period_end),
  unique(country_id,period_start,period_end)
);
create table if not exists public.economic_gdp_revision_history (
  id uuid primary key default gen_random_uuid(),
  gdp_record_id uuid not null references public.economic_gdp_records(id) on delete restrict,
  previous_record jsonb not null,
  previous_components jsonb not null default '[]'::jsonb,
  revised_by uuid not null references public.profiles(id),
  revised_at timestamptz not null default now()
);
alter table public.economic_gdp_revision_history enable row level security;
drop policy if exists gdp_revision_history_read on public.economic_gdp_revision_history;
create policy gdp_revision_history_read on public.economic_gdp_revision_history for select to authenticated
using (exists(select 1 from public.economic_gdp_records r where r.id=gdp_record_id
  and (public.is_world_admin() or public.is_country_president(r.country_id)
    or public.has_economy_permission(r.country_id,'economy.read'))));
revoke all on public.economic_gdp_revision_history from public,anon,authenticated;
grant select on public.economic_gdp_revision_history to authenticated;

create table if not exists public.economic_gdp_components (
  id uuid primary key default gen_random_uuid(),
  gdp_record_id uuid not null references public.economic_gdp_records(id) on delete cascade,
  sector text not null,
  amount numeric(24,2) not null check (amount >= 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  created_at timestamptz not null default now(),
  unique(gdp_record_id,sector)
);

create table if not exists public.economic_price_items (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  name text not null,
  category text not null,
  base_weight numeric(12,6) not null default 1 check (base_weight > 0),
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(country_id,name)
);
create table if not exists public.economic_price_observations (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.economic_price_items(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  reference_date date not null,
  price numeric(24,4) not null check (price > 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(item_id,reference_date)
);
create table if not exists public.economic_price_item_weights (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.economic_price_items(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  weight numeric(12,6) not null check (weight>0),
  effective_from date not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(item_id,effective_from)
);
alter table public.economic_price_item_weights enable row level security;
drop policy if exists price_item_weights_read on public.economic_price_item_weights;
create policy price_item_weights_read on public.economic_price_item_weights for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'economy.read')
  or public.is_government_country_citizen(country_id));
revoke all on public.economic_price_item_weights from public,anon,authenticated;
grant select on public.economic_price_item_weights to authenticated;
create index if not exists price_item_weights_effective_idx on public.economic_price_item_weights(item_id,effective_from desc);
create table if not exists public.economic_price_observation_history (
  id uuid primary key default gen_random_uuid(),
  observation_id uuid not null references public.economic_price_observations(id) on delete restrict,
  previous_price numeric(24,4) not null,
  currency_code_snapshot text not null default 'UNCONFIGURED',
  previous_recorded_by uuid references public.profiles(id),
  revised_by uuid not null references public.profiles(id),
  revised_at timestamptz not null default now()
);
alter table public.economic_price_observation_history enable row level security;
drop policy if exists price_observation_history_read on public.economic_price_observation_history;
create policy price_observation_history_read on public.economic_price_observation_history for select to authenticated
using (exists(select 1 from public.economic_price_observations o where o.id=observation_id
  and (public.is_world_admin() or public.is_country_president(o.country_id)
    or public.has_economy_permission(o.country_id,'economy.read'))));
revoke all on public.economic_price_observation_history from public,anon,authenticated;
grant select on public.economic_price_observation_history to authenticated;

create table if not exists public.tax_rules (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  name text not null,
  identifier text not null,
  category text not null,
  description text,
  rate numeric(9,4) not null check (rate >= 0 and rate <= 100),
  calculation_base text not null default 'declared_value',
  status text not null default 'awaiting_approval'
    check (status in ('draft','awaiting_approval','approved','active','rejected','suspended','revoked')),
  effective_from date not null,
  effective_until date,
  created_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_until is null or effective_until >= effective_from),
  unique(country_id,identifier,effective_from)
);

create table if not exists public.tax_obligations (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  tax_rule_id uuid not null references public.tax_rules(id) on delete restrict,
  taxpayer_profile_id uuid references public.profiles(id) on delete restrict,
  taxpayer_label text,
  reference_period text not null,
  calculation_base numeric(24,2) not null check (calculation_base >= 0),
  applied_rate numeric(9,4) not null check (applied_rate >= 0 and applied_rate <= 100),
  amount_due numeric(24,2) not null check (amount_due >= 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  due_date date,
  status text not null default 'open'
    check (status in ('open','pending_confirmation','paid','partially_paid','overdue','cancelled','contested')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.tax_collections (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  obligation_id uuid not null references public.tax_obligations(id) on delete restrict,
  amount numeric(24,2) not null check (amount > 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  confirmation_reference text not null,
  confirmed_by uuid not null references public.profiles(id),
  confirmed_at timestamptz not null default now(),
  unique(country_id,confirmation_reference)
);

create table if not exists public.treasury_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  entry_type text not null check (entry_type in ('revenue','expense','reversal','adjustment')),
  category text not null,
  description text not null,
  amount numeric(24,2) not null check (amount > 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  signed_amount numeric(24,2) not null,
  source_type text not null,
  source_id uuid,
  budget_allocation_id uuid,
  investment_project_id uuid,
  reverses_entry_id uuid references public.treasury_ledger_entries(id),
  idempotency_key text not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint treasury_ledger_country_idempotency unique(country_id,idempotency_key),
  constraint treasury_ledger_source_unique unique(country_id,source_type,source_id)
);

create table if not exists public.budget_plans (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  name text not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft'
    check (status in ('draft','awaiting_approval','approved','rejected','in_execution','closed','cancelled')),
  total_planned numeric(24,2) not null default 0 check (total_planned >= 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  created_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(period_start <= period_end)
);
create table if not exists public.budget_allocations (
  id uuid primary key default gen_random_uuid(),
  budget_plan_id uuid not null references public.budget_plans(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  category text not null,
  ministry_id uuid,
  planned_amount numeric(24,2) not null check (planned_amount >= 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  created_at timestamptz not null default now(),
  unique(budget_plan_id,category,ministry_id),
  foreign key (ministry_id,country_id) references public.ministries(id,country_id) on delete restrict
);
alter table public.treasury_ledger_entries
  drop constraint if exists treasury_ledger_budget_allocation_fk;
alter table public.treasury_ledger_entries
  add constraint treasury_ledger_budget_allocation_fk
  foreign key (budget_allocation_id) references public.budget_allocations(id) on delete restrict;

create table if not exists public.public_investment_projects (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  name text not null,
  description text,
  category text not null,
  ministry_id uuid,
  budget_allocation_id uuid references public.budget_allocations(id) on delete restrict,
  planned_amount numeric(24,2) not null check (planned_amount >= 0),
  currency_code_snapshot text not null default 'UNCONFIGURED',
  approved_amount numeric(24,2) not null default 0 check (approved_amount >= 0),
  executed_amount numeric(24,2) not null default 0 check (executed_amount >= 0),
  status text not null default 'proposed'
    check (status in ('proposed','under_review','approved','rejected','in_progress','completed','suspended','cancelled')),
  starts_on date,
  expected_end date,
  created_by uuid not null references public.profiles(id),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(expected_end is null or starts_on is null or expected_end >= starts_on),
  check(executed_amount <= approved_amount)
);

alter table public.treasury_ledger_entries
  drop constraint if exists treasury_ledger_investment_project_fk;
alter table public.treasury_ledger_entries
  add constraint treasury_ledger_investment_project_fk
  foreign key (investment_project_id) references public.public_investment_projects(id) on delete restrict;

alter table public.public_investment_projects
  drop constraint if exists public_investment_projects_ministry_fk;
alter table public.public_investment_projects
  add constraint public_investment_projects_ministry_fk
  foreign key (ministry_id,country_id) references public.ministries(id,country_id) on delete restrict;

create table if not exists public.economic_audit_logs (
  id uuid primary key default gen_random_uuid(),
  country_id uuid references public.countries(id) on delete restrict,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index if not exists economic_gdp_country_period_idx on public.economic_gdp_records(country_id,period_end desc);
create index if not exists economic_gdp_components_record_idx on public.economic_gdp_components(gdp_record_id);
create index if not exists economic_prices_country_date_idx on public.economic_price_observations(country_id,reference_date desc);
create index if not exists tax_rules_country_status_idx on public.tax_rules(country_id,status,effective_from desc);
create index if not exists tax_obligations_country_period_idx on public.tax_obligations(country_id,reference_period,status);
create index if not exists tax_obligations_taxpayer_idx on public.tax_obligations(taxpayer_profile_id,created_at desc);
create unique index if not exists tax_obligations_natural_key_uidx
  on public.tax_obligations(country_id,tax_rule_id,reference_period,
    (coalesce(taxpayer_profile_id::text,lower(coalesce(taxpayer_label,'')))));
create index if not exists tax_collections_country_date_idx on public.tax_collections(country_id,confirmed_at desc);
create index if not exists treasury_ledger_country_date_idx on public.treasury_ledger_entries(country_id,created_at desc);
create index if not exists budget_plans_country_period_idx on public.budget_plans(country_id,period_start,period_end);
create index if not exists investments_country_status_idx on public.public_investment_projects(country_id,status,created_at desc);

create or replace function public.can_manage_economy(p_country_id uuid,p_permission text)
returns boolean language sql stable security definer set search_path=public,auth as $$
  select auth.uid() is not null and (
    public.is_world_admin()
    or (exists(select 1 from public.national_treasuries t where t.country_id=p_country_id and not t.operations_suspended)
      and (public.is_country_president(p_country_id) or public.has_economy_permission(p_country_id,p_permission)))
  );
$$;

create or replace function public.economy_audit(
  p_country_id uuid,p_action text,p_entity_type text,p_entity_id uuid,
  p_old jsonb default null,p_new jsonb default null
) returns void language sql security definer set search_path=public as $$
  insert into public.economic_audit_logs(country_id,actor_id,action,entity_type,entity_id,old_values,new_values)
  values(p_country_id,auth.uid(),p_action,p_entity_type,p_entity_id,p_old,p_new);
$$;

-- Cria o Tesouro somente quando o país já existe; unidade monetária fica provisória se não configurada.
insert into public.national_treasuries(country_id,currency_code,currency_label,opening_balance_currency_code_snapshot)
select c.id,c.currency_code,
  case when nullif(trim(c.currency_code),'') is null
    then 'Unidade monetária provisória (não configurada)'
    else 'Moeda configurada no cadastro nacional' end,
  coalesce(nullif(trim(c.currency_code),''),'UNCONFIGURED')
from public.countries c
on conflict(country_id) do nothing;

create or replace function public.ensure_national_treasury_for_country()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.national_treasuries(country_id,currency_code,currency_label,opening_balance_currency_code_snapshot)
  values(new.id,new.currency_code,case when nullif(trim(new.currency_code),'') is null
    then 'Unidade monetária provisória (não configurada)' else 'Moeda configurada no cadastro nacional' end,
    coalesce(nullif(trim(new.currency_code),''),'UNCONFIGURED'))
  on conflict(country_id) do nothing;
  return new;
end;
$$;
drop trigger if exists countries_ensure_national_treasury on public.countries;
create trigger countries_ensure_national_treasury after insert or update of currency_code on public.countries
for each row execute function public.ensure_national_treasury_for_country();
revoke all on function public.ensure_national_treasury_for_country() from public,anon,authenticated;

create or replace function public.stamp_economy_currency_snapshot()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_code text;
begin
  if tg_table_name='economic_gdp_components' then
    select currency_code_snapshot into v_code from public.economic_gdp_records where id=new.gdp_record_id;
  elsif tg_table_name='economic_price_observation_history' then
    select currency_code_snapshot into v_code from public.economic_price_observations where id=new.observation_id;
  elsif tg_table_name='tax_collections' then
    select currency_code_snapshot into v_code from public.tax_obligations where id=new.obligation_id;
  elsif tg_table_name='budget_allocations' then
    select currency_code_snapshot into v_code from public.budget_plans where id=new.budget_plan_id;
  elsif tg_table_name='public_investment_projects' then
    select currency_code_snapshot into v_code from public.budget_allocations where id=new.budget_allocation_id;
  elsif tg_table_name='treasury_ledger_entries' and new.entry_type='reversal' then
    select currency_code_snapshot into v_code from public.treasury_ledger_entries where id=new.reverses_entry_id;
  elsif tg_table_name='treasury_ledger_entries' and new.source_type='tax_collection' then
    select currency_code_snapshot into v_code from public.tax_collections where id=new.source_id;
  elsif tg_table_name='treasury_ledger_entries' and new.investment_project_id is not null then
    select currency_code_snapshot into v_code from public.public_investment_projects where id=new.investment_project_id;
  else
    select coalesce(nullif(currency_code,''),'UNCONFIGURED') into v_code
      from public.national_treasuries where country_id=new.country_id;
  end if;
  new.currency_code_snapshot:=coalesce(v_code,'UNCONFIGURED');
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'economic_gdp_records','economic_gdp_components','economic_price_observations',
    'economic_price_observation_history','tax_obligations','tax_collections',
    'treasury_ledger_entries','budget_plans','budget_allocations','public_investment_projects'
  ] loop
    execute format('drop trigger if exists %I on public.%I',t||'_stamp_currency',t);
    execute format('create trigger %I before insert on public.%I for each row execute function public.stamp_economy_currency_snapshot()',t||'_stamp_currency',t);
  end loop;
end $$;
revoke all on function public.stamp_economy_currency_snapshot() from public,anon,authenticated;

alter table public.national_treasuries enable row level security;
alter table public.economic_gdp_records enable row level security;
alter table public.economic_gdp_components enable row level security;
alter table public.economic_price_items enable row level security;
alter table public.economic_price_observations enable row level security;
alter table public.tax_rules enable row level security;
alter table public.tax_obligations enable row level security;
alter table public.tax_collections enable row level security;
alter table public.treasury_ledger_entries enable row level security;
alter table public.budget_plans enable row level security;
alter table public.budget_allocations enable row level security;
alter table public.public_investment_projects enable row level security;
alter table public.economic_audit_logs enable row level security;

drop policy if exists treasury_read_scoped on public.national_treasuries;
create policy treasury_read_scoped on public.national_treasuries for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'economy.read')
  or public.has_economy_permission(country_id,'treasury.read')
  or (public.is_government_country_citizen(country_id) and public_balance_visible));
drop policy if exists gdp_read_scoped on public.economic_gdp_records;
create policy gdp_read_scoped on public.economic_gdp_records for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'economy.read')
  or (status='confirmed' and public.is_government_country_citizen(country_id)));
drop policy if exists gdp_components_read_scoped on public.economic_gdp_components;
create policy gdp_components_read_scoped on public.economic_gdp_components for select to authenticated
using (exists(select 1 from public.economic_gdp_records r where r.id=gdp_record_id
  and (public.is_world_admin() or public.is_country_president(r.country_id)
    or public.has_economy_permission(r.country_id,'economy.read')
    or (r.status='confirmed' and public.is_government_country_citizen(r.country_id)))));
drop policy if exists price_items_read_scoped on public.economic_price_items;
create policy price_items_read_scoped on public.economic_price_items for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'economy.read')
  or (is_active and public.is_government_country_citizen(country_id)));
drop policy if exists price_observations_read_scoped on public.economic_price_observations;
create policy price_observations_read_scoped on public.economic_price_observations for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'economy.read')
  or public.is_government_country_citizen(country_id));
drop policy if exists tax_rules_read_scoped on public.tax_rules;
create policy tax_rules_read_scoped on public.tax_rules for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'tax.read')
  or (status='active' and public.is_government_country_citizen(country_id)));
drop policy if exists tax_obligations_read_scoped on public.tax_obligations;
create policy tax_obligations_read_scoped on public.tax_obligations for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'tax.read')
  or taxpayer_profile_id=auth.uid());
drop policy if exists tax_collections_read_scoped on public.tax_collections;
create policy tax_collections_read_scoped on public.tax_collections for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'tax.read')
  or exists(select 1 from public.tax_obligations o where o.id=obligation_id and o.taxpayer_profile_id=auth.uid()));
drop policy if exists ledger_read_scoped on public.treasury_ledger_entries;
create policy ledger_read_scoped on public.treasury_ledger_entries for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'treasury.read')
  or (public.is_government_country_citizen(country_id) and exists(
    select 1 from public.national_treasuries t where t.country_id=treasury_ledger_entries.country_id and t.public_balance_visible)));
drop policy if exists budget_read_scoped on public.budget_plans;
create policy budget_read_scoped on public.budget_plans for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'budget.read')
  or (status in ('approved','in_execution','closed') and public.is_government_country_citizen(country_id)));
drop policy if exists allocation_read_scoped on public.budget_allocations;
create policy allocation_read_scoped on public.budget_allocations for select to authenticated
using (exists(select 1 from public.budget_plans b where b.id=budget_plan_id
  and (public.is_world_admin() or public.is_country_president(b.country_id)
    or public.has_economy_permission(b.country_id,'budget.read')
    or (b.status in ('approved','in_execution','closed') and public.is_government_country_citizen(b.country_id)))));
drop policy if exists investment_read_scoped on public.public_investment_projects;
create policy investment_read_scoped on public.public_investment_projects for select to authenticated
using (public.is_world_admin() or public.is_country_president(country_id)
  or public.has_economy_permission(country_id,'investment.read')
  or (status in ('approved','in_progress','completed') and public.is_government_country_citizen(country_id)));
drop policy if exists economic_audit_read_scoped on public.economic_audit_logs;
create policy economic_audit_read_scoped on public.economic_audit_logs for select to authenticated
using (public.is_world_admin() or (country_id is not null and public.is_country_president(country_id)));

revoke all on public.national_treasuries,public.economic_gdp_records,public.economic_gdp_components,
  public.economic_price_items,public.economic_price_observations,public.tax_rules,public.tax_obligations,
  public.tax_collections,public.treasury_ledger_entries,public.budget_plans,public.budget_allocations,
  public.public_investment_projects,public.economic_audit_logs from public,anon,authenticated;
grant select on public.national_treasuries,public.economic_gdp_records,public.economic_gdp_components,
  public.economic_price_items,public.economic_price_observations,public.tax_rules,public.tax_obligations,
  public.tax_collections,public.treasury_ledger_entries,public.budget_plans,public.budget_allocations,
  public.public_investment_projects,public.economic_audit_logs to authenticated;

create or replace function public.get_economy_dashboard(p_country_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_country uuid:=p_country_id; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  if public.is_world_admin() then
    if v_country is null then
      select jsonb_build_object(
        'scope','global',
        'countries_active',(select count(*) from public.countries where is_active),
        'countries_without_gdp',(select count(*) from public.countries c where c.is_active and not exists(
          select 1 from public.economic_gdp_records r where r.country_id=c.id and r.status in ('confirmed','revised'))),
        'countries_growth_positive',(select count(*) from (
          select cur.country_id from (
            select distinct on (country_id) country_id,total_value,period_start,period_end
            from public.economic_gdp_records where status in ('confirmed','revised') order by country_id,period_end desc
          ) cur join public.economic_gdp_records prev on prev.country_id=cur.country_id
            and prev.status in ('confirmed','revised') and prev.period_end=cur.period_start-1
            and (prev.period_end-prev.period_start)=(cur.period_end-cur.period_start)
          where prev.total_value>0 and cur.total_value>prev.total_value
        ) positive_growth),
        'countries_growth_negative',(select count(*) from (
          select cur.country_id from (
            select distinct on (country_id) country_id,total_value,period_start,period_end
            from public.economic_gdp_records where status in ('confirmed','revised') order by country_id,period_end desc
          ) cur join public.economic_gdp_records prev on prev.country_id=cur.country_id
            and prev.status in ('confirmed','revised') and prev.period_end=cur.period_start-1
            and (prev.period_end-prev.period_start)=(cur.period_end-cur.period_start)
          where prev.total_value>0 and cur.total_value<prev.total_value
        ) negative_growth),
        'gdp_total',(select sum(latest.total_value) from (
          select distinct on (country_id) country_id,total_value
          from public.economic_gdp_records where status in ('confirmed','revised')
          order by country_id,period_end desc
        ) latest),
        'currency_mismatched_countries',(select count(*) from public.national_treasuries t
          where (t.opening_balance>0 and t.opening_balance_currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
            or exists(select 1 from public.treasury_ledger_entries x where x.country_id=t.country_id
              and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))),
        'treasury_total',(select sum(t.opening_balance + coalesce(l.total,0)) from public.national_treasuries t
          left join lateral (select sum(signed_amount) total from public.treasury_ledger_entries x where x.country_id=t.country_id) l on true
          where (t.opening_balance=0 or t.opening_balance_currency_code_snapshot=coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
            and not exists(select 1 from public.treasury_ledger_entries x where x.country_id=t.country_id
              and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))),
        'revenue_total',(select coalesce(sum(case when x.entry_type='revenue' then x.amount
          when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='revenue') then -x.amount else 0 end),0)
          from public.treasury_ledger_entries x),
        'expenses_total',(select coalesce(sum(case when x.entry_type='expense' then x.amount
          when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='expense') then -x.amount else 0 end),0)
          from public.treasury_ledger_entries x),
        'investment_total',(select coalesce(sum(approved_amount),0) from public.public_investment_projects where status in ('approved','in_progress','completed')),
        'budget_approved_total',(select coalesce(sum(total_planned),0) from public.budget_plans where status in ('approved','in_execution')),
        'budget_executed_total',(select coalesce(sum(case when x.entry_type='expense' then x.amount
          when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='expense') then -x.amount else 0 end),0)
          from public.treasury_ledger_entries x where x.budget_allocation_id is not null),
        'tax_revenue_total',(select coalesce(sum(amount),0) from public.tax_collections),
        'inflation_average',(select round(avg(country_index.inflation),2) from (
          select c.id,(select case when old_ipc>0 then ((new_ipc-old_ipc)/old_ipc)*100 end from (
            select reference_date,
              (sum((o.price/base.price)*w.weight)/nullif(sum(w.weight),0))*100 as new_ipc,
              lag((sum((o.price/base.price)*w.weight)/nullif(sum(w.weight),0))*100) over(order by reference_date) as old_ipc
            from public.economic_price_observations o
            join public.economic_price_items i on i.id=o.item_id and i.is_active
            join lateral(select price from public.economic_price_observations b where b.item_id=i.id order by b.reference_date limit 1) base on true
            where o.country_id=c.id group by reference_date
            having count(distinct o.item_id)=(select count(*) from public.economic_price_items ai where ai.country_id=c.id and ai.is_active)
          ) index_values order by reference_date desc limit 1) as inflation
          from public.countries c where c.is_active
        ) country_index where country_index.inflation is not null),
        'countries',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'flag',c.flag,'continent',c.continent,'is_active',c.is_active,
          'currency_code',t.currency_code,'currency_label',t.currency_label,
          'treasury_balance',case when (t.opening_balance=0 or t.opening_balance_currency_code_snapshot=coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
            and not exists(select 1 from public.treasury_ledger_entries x where x.country_id=c.id
              and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
            then t.opening_balance+coalesce(l.total,0) else null end,
          'gdp',(select r.total_value from public.economic_gdp_records r where r.country_id=c.id and r.status in ('confirmed','revised') order by r.period_end desc limit 1),
          'gdp_period_end',(select r.period_end from public.economic_gdp_records r where r.country_id=c.id and r.status in ('confirmed','revised') order by r.period_end desc limit 1),
          'gdp_growth',(select case when prev.total_value>0 then round(((cur.total_value-prev.total_value)/prev.total_value)*100,2) end
            from (select total_value,period_start,period_end from public.economic_gdp_records where country_id=c.id and status in ('confirmed','revised') order by period_end desc limit 1) cur
            left join public.economic_gdp_records prev on prev.country_id=c.id and prev.status in ('confirmed','revised')
              and prev.period_end=cur.period_start-1 and (prev.period_end-prev.period_start)=(cur.period_end-cur.period_start))
        ) order by c.name),'[]'::jsonb) from public.countries c
        left join public.national_treasuries t on t.country_id=c.id
        left join lateral(select sum(signed_amount) total from public.treasury_ledger_entries x where x.country_id=c.id) l on true)
      ) into v_result;
      return v_result;
    end if;
  else
    if v_country is null then
      select country_id into v_country from public.profiles where id=auth.uid();
    end if;
    if v_country is null or not (
      public.is_country_president(v_country)
      or public.has_economy_permission(v_country,'economy.read')
      or public.has_economy_permission(v_country,'economy.manage')
      or public.has_economy_permission(v_country,'treasury.read')
      or public.has_economy_permission(v_country,'tax.read')
      or public.is_government_country_citizen(v_country)
    ) then raise exception 'Sem permissão para consultar a economia deste país.'; end if;
  end if;
  select jsonb_build_object(
    'scope','national','country_id',c.id,'country_name',c.name,'country_flag',c.flag,
    'currency_code',t.currency_code,'currency_label',t.currency_label,
    'currency_consistent',((t.opening_balance=0 or t.opening_balance_currency_code_snapshot=coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
      and not exists(select 1 from public.treasury_ledger_entries x where x.country_id=c.id
        and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))),
    'gdp',(select r.total_value from public.economic_gdp_records r where r.country_id=c.id and r.status='confirmed' order by r.period_end desc limit 1),
    'gdp_period_end',(select r.period_end from public.economic_gdp_records r where r.country_id=c.id and r.status='confirmed' order by r.period_end desc limit 1),
    'previous_gdp',(select r.total_value from public.economic_gdp_records r where r.country_id=c.id and r.status='confirmed' order by r.period_end desc offset 1 limit 1),
    'gdp_growth',(select case when prev.total_value>0 then round(((cur.total_value-prev.total_value)/prev.total_value)*100,2) end
      from (select total_value,period_start,period_end from public.economic_gdp_records where country_id=c.id and status in ('confirmed','revised') order by period_end desc limit 1) cur
      left join public.economic_gdp_records prev on prev.country_id=c.id and prev.status in ('confirmed','revised')
        and prev.period_end=cur.period_start-1
        and (prev.period_end-prev.period_start)=(cur.period_end-cur.period_start)),
    'revenue',(select coalesce(sum(case when x.entry_type='revenue' then x.amount
      when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='revenue') then -x.amount else 0 end),0)
      from public.treasury_ledger_entries x where x.country_id=c.id),
    'expenses',(select coalesce(sum(case when x.entry_type='expense' then x.amount
      when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='expense') then -x.amount else 0 end),0)
      from public.treasury_ledger_entries x where x.country_id=c.id),
    'treasury_balance',case when public.is_world_admin() or public.is_country_president(c.id)
      or public.has_economy_permission(c.id,'treasury.read')
      or public.has_economy_permission(c.id,'economy.read')
      or t.public_balance_visible then case when (t.opening_balance=0 or t.opening_balance_currency_code_snapshot=coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
        and not exists(select 1 from public.treasury_ledger_entries x where x.country_id=c.id
          and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
        then t.opening_balance+(select coalesce(sum(signed_amount),0) from public.treasury_ledger_entries where country_id=c.id) else null end else null end,
    'tax_collected',(select coalesce(sum(amount),0) from public.tax_collections where country_id=c.id),
    'tax_open',case when public.is_world_admin() or public.is_country_president(c.id) or public.has_economy_permission(c.id,'tax.read')
      then (select coalesce(sum(greatest(o.amount_due-coalesce((select sum(col.amount) from public.tax_collections col where col.obligation_id=o.id),0),0)),0)
        from public.tax_obligations o where o.country_id=c.id and o.status in ('open','pending_confirmation','partially_paid','overdue'))
      else null end,
    'budget_approved',(select coalesce(sum(total_planned),0) from public.budget_plans where country_id=c.id and status in ('approved','in_execution')),
    'budget_executed',(select coalesce(sum(case when x.entry_type='expense' then x.amount
      when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='expense') then -x.amount else 0 end),0)
      from public.treasury_ledger_entries x where x.country_id=c.id and x.budget_allocation_id is not null),
    'budget_available',(select coalesce(sum(total_planned),0) from public.budget_plans where country_id=c.id and status in ('approved','in_execution'))
      -(select coalesce(sum(case when x.entry_type='expense' then x.amount
        when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='expense') then -x.amount else 0 end),0)
        from public.treasury_ledger_entries x where x.country_id=c.id and x.budget_allocation_id is not null),
    'budget_execution_pct',(select case when sum(total_planned)>0 then round((
      (select coalesce(sum(case when x.entry_type='expense' then x.amount
        when x.entry_type='reversal' and exists(select 1 from public.treasury_ledger_entries original where original.id=x.reverses_entry_id and original.entry_type='expense') then -x.amount else 0 end),0)
       from public.treasury_ledger_entries x where x.country_id=c.id and x.budget_allocation_id is not null)
      /sum(total_planned))*100,2) end from public.budget_plans where country_id=c.id and status in ('approved','in_execution')),
    'investment_approved',(select coalesce(sum(approved_amount),0) from public.public_investment_projects where country_id=c.id and status in ('approved','in_progress','completed')),
    'ipc',(select round(new_ipc,2) from (
      select reference_date,
        (sum((o.price/base.price)*w.weight)/nullif(sum(w.weight),0))*100 as new_ipc
      from public.economic_price_observations o
      join public.economic_price_items i on i.id=o.item_id and i.is_active
      join lateral(select weight from public.economic_price_item_weights wh where wh.item_id=i.id and wh.effective_from<=o.reference_date order by wh.effective_from desc limit 1) w on true
      join lateral(select price from public.economic_price_observations b where b.item_id=i.id order by b.reference_date limit 1) base on true
      where o.country_id=c.id group by reference_date
      having count(distinct o.item_id)=(select count(*) from public.economic_price_items active_items where active_items.country_id=c.id and active_items.is_active)
    ) ipc_values order by reference_date desc limit 1),
    'inflation_history',(select coalesce(jsonb_agg(jsonb_build_object(
      'reference_date',reference_date,'ipc',round(new_ipc,2),
      'inflation',case when old_ipc>0 then round(((new_ipc-old_ipc)/old_ipc)*100,2) end
    ) order by reference_date),'[]'::jsonb) from (
      select reference_date,new_ipc,lag(new_ipc) over(order by reference_date) as old_ipc
      from (
        select reference_date,
          (sum((o.price/base.price)*w.weight)/nullif(sum(w.weight),0))*100 as new_ipc
        from public.economic_price_observations o
        join public.economic_price_items i on i.id=o.item_id and i.is_active
        join lateral(select weight from public.economic_price_item_weights wh where wh.item_id=i.id and wh.effective_from<=o.reference_date order by wh.effective_from desc limit 1) w on true
        join lateral(select price from public.economic_price_observations b where b.item_id=i.id order by b.reference_date limit 1) base on true
        where o.country_id=c.id group by reference_date
        having count(distinct o.item_id)=(select count(*) from public.economic_price_items active_items where active_items.country_id=c.id and active_items.is_active)
      ) periods
    ) index_history),
    'inflation',(select case when old_ipc>0 then round(((new_ipc-old_ipc)/old_ipc)*100,2) end from (
      select reference_date,
        (sum((o.price/base.price)*w.weight)/nullif(sum(w.weight),0))*100 as new_ipc,
        lag((sum((o.price/base.price)*w.weight)/nullif(sum(w.weight),0))*100) over(order by reference_date) as old_ipc
      from public.economic_price_observations o
      join public.economic_price_items i on i.id=o.item_id and i.is_active
      join lateral(select weight from public.economic_price_item_weights wh where wh.item_id=i.id and wh.effective_from<=o.reference_date order by wh.effective_from desc limit 1) w on true
      join lateral(select price from public.economic_price_observations b where b.item_id=i.id order by b.reference_date limit 1) base on true
      where o.country_id=c.id group by reference_date
      having count(distinct o.item_id)=(select count(*) from public.economic_price_items active_items where active_items.country_id=c.id and active_items.is_active)
    ) ix order by reference_date desc limit 1)
  ) into v_result
  from public.countries c join public.national_treasuries t on t.country_id=c.id where c.id=v_country;
  if v_result is null then raise exception 'País ou Tesouro Nacional não encontrado.'; end if;
  return v_result;
end;
$$;

create or replace function public.save_gdp_record(
  p_country_id uuid,p_period_start date,p_period_end date,p_components jsonb,p_source_description text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_total numeric(24,2); v_old jsonb;
begin
  if not public.can_manage_economy(p_country_id,'economy.manage') then raise exception 'Sem permissão para registrar o PIB.'; end if;
  if p_period_start is null or p_period_end is null or p_period_start>p_period_end then raise exception 'Período inválido.'; end if;
  if jsonb_typeof(p_components)<>'array' or jsonb_array_length(p_components)=0 then raise exception 'Informe ao menos um componente do PIB.'; end if;
  if exists(select 1 from jsonb_to_recordset(p_components) as x(sector text,amount numeric) where nullif(trim(sector),'') is null or amount is null or amount<0) then raise exception 'Componente do PIB inválido.'; end if;
  select coalesce(sum(amount),0) into v_total from jsonb_to_recordset(p_components) as x(sector text,amount numeric);
  select id,to_jsonb(r) into v_id,v_old from public.economic_gdp_records r
    where country_id=p_country_id and period_start=p_period_start and period_end=p_period_end for update;
  if v_id is null then
    insert into public.economic_gdp_records(country_id,period_start,period_end,total_value,source,source_description,status,created_by,updated_by)
    values(p_country_id,p_period_start,p_period_end,v_total,'manual',p_source_description,'confirmed',auth.uid(),auth.uid()) returning id into v_id;
  else
    insert into public.economic_gdp_revision_history(gdp_record_id,previous_record,previous_components,revised_by)
    select v_id,to_jsonb(r),coalesce((select jsonb_agg(to_jsonb(c)) from public.economic_gdp_components c where c.gdp_record_id=v_id),'[]'::jsonb),auth.uid()
    from public.economic_gdp_records r where r.id=v_id;
    update public.economic_gdp_records set total_value=v_total,source='manual',source_description=p_source_description,status='confirmed',updated_by=auth.uid(),updated_at=now() where id=v_id;
    delete from public.economic_gdp_components where gdp_record_id=v_id;
  end if;
  insert into public.economic_gdp_components(gdp_record_id,sector,amount)
  select v_id,x.sector,x.amount from jsonb_to_recordset(p_components) as x(sector text,amount numeric);
  perform public.economy_audit(p_country_id,'upsert','gdp_record',v_id,v_old,jsonb_build_object('total_value',v_total,'components',p_components));
  return v_id;
end;
$$;

create or replace function public.save_price_item(
  p_country_id uuid,p_name text,p_category text,p_weight numeric,p_price numeric,p_reference_date date
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_item uuid; v_current_weight numeric(12,6); v_weight_date date;
begin
  if not public.can_manage_economy(p_country_id,'economy.manage') then raise exception 'Sem permissão para atualizar preços.'; end if;
  if length(trim(coalesce(p_name,'')))<2 or p_weight<=0 or p_price<=0 or p_reference_date is null then raise exception 'Dados de preço inválidos.'; end if;
  insert into public.economic_price_items(country_id,name,category,base_weight,created_by)
  values(p_country_id,trim(p_name),trim(p_category),p_weight,auth.uid())
  on conflict(country_id,name) do update set category=excluded.category,updated_at=now()
  returning id into v_item;
  select weight,effective_from into v_current_weight,v_weight_date
    from public.economic_price_item_weights where item_id=v_item and effective_from<=p_reference_date
    order by effective_from desc limit 1;
  if v_current_weight is null then
    insert into public.economic_price_item_weights(item_id,country_id,weight,effective_from,created_by)
    values(v_item,p_country_id,p_weight,p_reference_date,auth.uid());
  elsif v_current_weight<>p_weight then
    if p_reference_date<=v_weight_date then raise exception 'A nova ponderação deve começar após a ponderação vigente para esta data.'; end if;
    insert into public.economic_price_item_weights(item_id,country_id,weight,effective_from,created_by)
    values(v_item,p_country_id,p_weight,p_reference_date,auth.uid());
  end if;
  insert into public.economic_price_observation_history(observation_id,previous_price,previous_recorded_by,revised_by)
  select id,price,recorded_by,auth.uid() from public.economic_price_observations
  where item_id=v_item and reference_date=p_reference_date;
  insert into public.economic_price_observations(item_id,country_id,reference_date,price,recorded_by)
  values(v_item,p_country_id,p_reference_date,p_price,auth.uid())
  on conflict(item_id,reference_date) do update set price=excluded.price,recorded_by=excluded.recorded_by;
  perform public.economy_audit(p_country_id,'upsert','price_item',v_item,null,
    jsonb_build_object('name',p_name,'category',p_category,'weight',p_weight,'price',p_price,'date',p_reference_date));
  return v_item;
end;
$$;

create or replace function public.create_tax_rule(
  p_country_id uuid,p_name text,p_identifier text,p_category text,p_description text,
  p_rate numeric,p_calculation_base text,p_effective_from date
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_status text;
begin
  if not public.can_manage_economy(p_country_id,'tax.manage') then raise exception 'Sem permissão para propor tributos.'; end if;
  if p_rate<0 or p_rate>100 or p_effective_from is null or length(trim(coalesce(p_name,'')))<2
    or length(trim(coalesce(p_identifier,'')))<2 or length(trim(coalesce(p_category,'')))<2 then raise exception 'Regra tributária inválida.'; end if;
  select case when require_global_tax_approval then 'awaiting_approval' else 'active' end into v_status from public.national_treasuries where country_id=p_country_id;
  insert into public.tax_rules(country_id,name,identifier,category,description,rate,calculation_base,status,effective_from,created_by)
  values(p_country_id,trim(p_name),lower(trim(p_identifier)),trim(p_category),p_description,p_rate,p_calculation_base,v_status,p_effective_from,auth.uid())
  returning id into v_id;
  perform public.economy_audit(p_country_id,'create','tax_rule',v_id,null,to_jsonb(v_id));
  return v_id;
end;
$$;

create or replace function public.review_tax_rule(p_rule_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare r public.tax_rules%rowtype; require_admin boolean;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode revisar regras tributárias nesta configuração.'; end if;
  if p_decision not in ('approved','rejected','suspended','revoked') then raise exception 'Decisão inválida.'; end if;
  select * into r from public.tax_rules where id=p_rule_id for update;
  if not found then raise exception 'Regra tributária não encontrada.'; end if;
  update public.tax_rules set status=case when p_decision='approved' then 'active' else p_decision end,
    reviewed_by=auth.uid(),reviewed_at=now(),review_note=p_note,updated_at=now() where id=r.id;
  perform public.economy_audit(r.country_id,'review','tax_rule',r.id,to_jsonb(r),jsonb_build_object('status',p_decision,'note',p_note));
end;
$$;

create or replace function public.create_tax_obligation(
  p_country_id uuid,p_rule_id uuid,p_taxpayer_profile_id uuid,p_taxpayer_label text,
  p_reference_period text,p_calculation_base numeric,p_due_date date
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare r public.tax_rules%rowtype; v_id uuid; v_amount numeric(24,2); v_period_start date;
begin
  if not public.can_manage_economy(p_country_id,'tax.manage') then raise exception 'Sem permissão para lançar obrigação tributária.'; end if;
  select * into r from public.tax_rules where id=p_rule_id and country_id=p_country_id and status='active'
    and effective_from<=current_date and (effective_until is null or effective_until>=current_date);
  if not found then raise exception 'Regra tributária não está vigente.'; end if;
  if p_calculation_base<0 or coalesce(p_reference_period,'') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'Informe o período no formato AAAA-MM e uma base válida.'; end if;
  v_period_start:=to_date(p_reference_period||'-01','YYYY-MM-DD');
  if v_period_start<date_trunc('month',current_date)::date or v_period_start<r.effective_from then
    raise exception 'Cobranças retroativas não são permitidas por esta operação.'; end if;
  if p_taxpayer_profile_id is null and length(trim(coalesce(p_taxpayer_label,'')))<2 then
    raise exception 'Informe o cidadão ou contribuinte desta obrigação.'; end if;
  if p_taxpayer_profile_id is not null and not exists(select 1 from public.profiles where id=p_taxpayer_profile_id and country_id=p_country_id) then
    raise exception 'O contribuinte informado não pertence a este país.'; end if;
  v_amount:=round(p_calculation_base*r.rate/100,2);
  insert into public.tax_obligations(country_id,tax_rule_id,taxpayer_profile_id,taxpayer_label,reference_period,
    calculation_base,applied_rate,amount_due,due_date,status,created_by)
  values(p_country_id,p_rule_id,p_taxpayer_profile_id,nullif(trim(p_taxpayer_label),''),p_reference_period,
    p_calculation_base,r.rate,v_amount,p_due_date,case when p_due_date<current_date then 'overdue' else 'open' end,auth.uid()) returning id into v_id;
  perform public.economy_audit(p_country_id,'create','tax_obligation',v_id,null,jsonb_build_object('amount_due',v_amount,'rate',r.rate));
  return v_id;
end;
$$;

create or replace function public.confirm_tax_collection(
  p_obligation_id uuid,p_amount numeric,p_confirmation_reference text
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare o public.tax_obligations%rowtype; v_col uuid; v_paid numeric; v_currency text; v_opening_snapshot text; v_opening numeric;
begin
  select * into o from public.tax_obligations where id=p_obligation_id for update;
  if not found then raise exception 'Obrigação não encontrada ou sem permissão.'; end if;
  if not public.can_manage_economy(o.country_id,'tax.collect') then raise exception 'Obrigação não encontrada ou sem permissão.'; end if;
  if p_amount<=0 or length(trim(coalesce(p_confirmation_reference,'')))<3 then raise exception 'Valor ou referência inválidos.'; end if;
  select currency_code,opening_balance_currency_code_snapshot,opening_balance
    into v_currency,v_opening_snapshot,v_opening
    from public.national_treasuries where country_id=o.country_id for update;
  if not found then raise exception 'Tesouro Nacional não encontrado.'; end if;
  if (v_opening>0 and v_opening_snapshot<>coalesce(nullif(v_currency,''),'UNCONFIGURED'))
    or exists(select 1 from public.treasury_ledger_entries x where x.country_id=o.country_id
      and x.currency_code_snapshot<>coalesce(nullif(v_currency,''),'UNCONFIGURED')) then
    raise exception 'O Tesouro possui registros em outra unidade monetária; a conciliação deve ocorrer antes de arrecadar.'; end if;
  if o.currency_code_snapshot<>coalesce(nullif(v_currency,''),'UNCONFIGURED') then raise exception 'A unidade monetária da obrigação diverge da unidade atual do Tesouro.'; end if;
  if o.status not in ('open','partially_paid','overdue','pending_confirmation') then raise exception 'Esta obrigação não aceita novas arrecadações.'; end if;
  select coalesce(sum(amount),0) into v_paid from public.tax_collections where obligation_id=o.id;
  if v_paid+p_amount>o.amount_due then raise exception 'A arrecadação excede o valor ainda devido.'; end if;
  insert into public.tax_collections(country_id,obligation_id,amount,confirmation_reference,confirmed_by)
  values(o.country_id,o.id,p_amount,trim(p_confirmation_reference),auth.uid()) returning id into v_col;
  insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,signed_amount,source_type,source_id,
    idempotency_key,created_by)
  values(o.country_id,'revenue','tax_collection','Arrecadação tributária — obrigação '||o.id,p_amount,p_amount,
    'tax_collection',v_col,'tax-collection:'||v_col,auth.uid());
  v_paid:=v_paid+p_amount;
  update public.tax_obligations set status=case when v_paid>=amount_due then 'paid' else 'partially_paid' end,updated_at=now()
  where id=o.id;
  perform public.economy_audit(o.country_id,'confirm','tax_collection',v_col,null,jsonb_build_object('amount',p_amount,'obligation_id',o.id));
  return v_col;
end;
$$;

create or replace function public.create_budget_plan(
  p_country_id uuid,p_name text,p_period_start date,p_period_end date,p_allocations jsonb
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_total numeric(24,2); v_status text;
begin
  if not public.can_manage_economy(p_country_id,'budget.manage') then raise exception 'Sem permissão para elaborar orçamento.'; end if;
  if p_period_start>p_period_end or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations)=0 then raise exception 'Período ou alocações inválidos.'; end if;
  if exists(select 1 from jsonb_to_recordset(p_allocations) as x(category text,planned_amount numeric,ministry_id uuid)
    where nullif(trim(category),'') is null or planned_amount is null or planned_amount<0) then raise exception 'Alocação inválida.'; end if;
  if exists(select 1 from jsonb_to_recordset(p_allocations) as x(category text,planned_amount numeric,ministry_id uuid)
    where ministry_id is not null and not exists(select 1 from public.ministries m where m.id=x.ministry_id and m.country_id=p_country_id)) then
    raise exception 'Uma alocação referencia ministério de outro país.'; end if;
  select sum(planned_amount) into v_total from jsonb_to_recordset(p_allocations) as x(category text,planned_amount numeric,ministry_id uuid);
  select case when require_global_budget_approval then 'awaiting_approval' else 'approved' end into v_status
  from public.national_treasuries where country_id=p_country_id;
  insert into public.budget_plans(country_id,name,period_start,period_end,status,total_planned,created_by)
  values(p_country_id,trim(p_name),p_period_start,p_period_end,v_status,v_total,auth.uid()) returning id into v_id;
  insert into public.budget_allocations(budget_plan_id,country_id,category,planned_amount,ministry_id)
  select v_id,p_country_id,x.category,x.planned_amount,x.ministry_id
  from jsonb_to_recordset(p_allocations) as x(category text,planned_amount numeric,ministry_id uuid);
  perform public.economy_audit(p_country_id,'create','budget_plan',v_id,null,jsonb_build_object('total_planned',v_total));
  return v_id;
end;
$$;

create or replace function public.review_budget_plan(p_plan_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare b public.budget_plans%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode aprovar orçamento globalmente.'; end if;
  if p_decision not in ('approved','rejected','cancelled') then raise exception 'Decisão inválida.'; end if;
  select * into b from public.budget_plans where id=p_plan_id for update;
  if not found then raise exception 'Orçamento não encontrado.'; end if;
  update public.budget_plans set status=case when p_decision='approved' then 'approved' else p_decision end,
    reviewed_by=auth.uid(),reviewed_at=now(),review_note=p_note,updated_at=now() where id=b.id;
  perform public.economy_audit(b.country_id,'review','budget_plan',b.id,to_jsonb(b),jsonb_build_object('status',p_decision,'note',p_note));
end;
$$;

drop function if exists public.create_investment_project(uuid,text,text,text,uuid,numeric,date,date);
create or replace function public.create_investment_project(
  p_country_id uuid,p_name text,p_description text,p_category text,p_budget_allocation_id uuid,
  p_planned_amount numeric,p_starts_on date,p_expected_end date,p_ministry_id uuid default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_allocation_limit numeric(24,2); v_allocation_currency text; v_treasury_currency text;
begin
  if not public.can_manage_economy(p_country_id,'investment.manage') then raise exception 'Sem permissão para propor investimento.'; end if;
  if p_planned_amount<0 or length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_category,'')))<2 then
    raise exception 'Projeto inválido.'; end if;
  select a.planned_amount,a.currency_code_snapshot into v_allocation_limit,v_allocation_currency
    from public.budget_allocations a join public.budget_plans b on b.id=a.budget_plan_id
    where a.id=p_budget_allocation_id and a.country_id=p_country_id and b.status in ('approved','in_execution');
  select currency_code into v_treasury_currency from public.national_treasuries where country_id=p_country_id;
  if v_allocation_limit is null then raise exception 'O projeto precisa de uma alocação orçamentária aprovada neste país.'; end if;
  if v_allocation_currency<>coalesce(nullif(v_treasury_currency,''),'UNCONFIGURED') then
    raise exception 'A unidade monetária do orçamento diverge da unidade atual do Tesouro.'; end if;
  if p_planned_amount>v_allocation_limit then raise exception 'O valor previsto excede a alocação orçamentária.'; end if;
  if p_ministry_id is not null and not exists(select 1 from public.ministries where id=p_ministry_id and country_id=p_country_id and status='active') then
    raise exception 'O ministério informado não pertence a este país ou está inativo.'; end if;
  insert into public.public_investment_projects(country_id,name,description,category,budget_allocation_id,planned_amount,starts_on,expected_end,ministry_id,created_by)
  values(p_country_id,trim(p_name),p_description,trim(p_category),p_budget_allocation_id,p_planned_amount,p_starts_on,p_expected_end,p_ministry_id,auth.uid())
  returning id into v_id;
  perform public.economy_audit(p_country_id,'create','investment_project',v_id,null,jsonb_build_object('planned_amount',p_planned_amount,'ministry_id',p_ministry_id));
  return v_id;
end;
$$;

create or replace function public.review_investment_project(p_project_id uuid,p_decision text,p_approved_amount numeric default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare p public.public_investment_projects%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode aprovar projetos nesta configuração.'; end if;
  if p_decision not in ('approved','rejected','suspended','cancelled') then raise exception 'Decisão inválida.'; end if;
  select * into p from public.public_investment_projects where id=p_project_id for update;
  if not found then raise exception 'Projeto não encontrado.'; end if;
  if p_decision='approved' and (p_approved_amount is null or p_approved_amount<0 or p_approved_amount>p.planned_amount
    or p_approved_amount>(select planned_amount from public.budget_allocations where id=p.budget_allocation_id)) then
    raise exception 'Valor aprovado inválido ou superior à alocação orçamentária.'; end if;
  update public.public_investment_projects set status=case when p_decision='approved' then 'approved' else p_decision end,
    approved_amount=case when p_decision='approved' then p_approved_amount else approved_amount end,
    reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=p.id;
  perform public.economy_audit(p.country_id,'review','investment_project',p.id,to_jsonb(p),jsonb_build_object('status',p_decision,'approved_amount',p_approved_amount));
end;
$$;

create or replace function public.post_treasury_entry(
  p_country_id uuid,p_entry_type text,p_category text,p_description text,p_amount numeric,
  p_idempotency_key text,p_budget_allocation_id uuid default null,p_investment_project_id uuid default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; a public.budget_allocations%rowtype; p public.public_investment_projects%rowtype; t public.national_treasuries%rowtype; v_spent numeric; v_balance numeric;
begin
  if p_entry_type not in ('revenue','expense') or p_amount<=0 or length(trim(coalesce(p_idempotency_key,'')))<8
    or length(trim(coalesce(p_category,'')))<2 or length(trim(coalesce(p_description,'')))<3 then raise exception 'Lançamento inválido.'; end if;
  select * into t from public.national_treasuries where country_id=p_country_id for update;
  if not found then raise exception 'Tesouro Nacional não encontrado.'; end if;
  if (t.opening_balance>0 and t.opening_balance_currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
    or exists(select 1 from public.treasury_ledger_entries x where x.country_id=p_country_id
      and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED')) then
    raise exception 'O Tesouro possui registros em outra unidade monetária; a conciliação deve ocorrer antes de novas operações.'; end if;
  if p_budget_allocation_id is not null and not exists(select 1 from public.budget_allocations a where a.id=p_budget_allocation_id and a.country_id=p_country_id) then
    raise exception 'A alocação orçamentária não pertence a este país.'; end if;
  select t.opening_balance+coalesce(sum(x.signed_amount),0) into v_balance from public.treasury_ledger_entries x where x.country_id=p_country_id;
  if p_entry_type='revenue' then
    if p_budget_allocation_id is not null then raise exception 'Receitas não podem ser vinculadas a alocações de despesas.'; end if;
    if not public.can_manage_economy(p_country_id,'treasury.revenue') then raise exception 'Sem permissão para registrar receita.'; end if;
  else
    if not public.can_manage_economy(p_country_id,'treasury.expense') then raise exception 'Sem permissão para registrar despesa.'; end if;
    if v_balance<p_amount then raise exception 'Saldo insuficiente no Tesouro Nacional para esta despesa.'; end if;
    if p_budget_allocation_id is null then raise exception 'Toda despesa precisa estar vinculada a uma alocação aprovada.'; end if;
    select * into a from public.budget_allocations where id=p_budget_allocation_id and country_id=p_country_id for update;
    if not found then raise exception 'Alocação não encontrada neste país.'; end if;
    if a.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED') then raise exception 'A moeda da alocação diverge da moeda atual do Tesouro.'; end if;
    if not exists(select 1 from public.budget_plans b where b.id=a.budget_plan_id and b.status in ('approved','in_execution')) then
      raise exception 'O orçamento ainda não está aprovado.'; end if;
    select greatest(coalesce(sum(-signed_amount),0),0) into v_spent from public.treasury_ledger_entries where budget_allocation_id=a.id;
    if v_spent+p_amount>a.planned_amount then raise exception 'A despesa excede o limite orçamentário disponível.'; end if;
  end if;
  if p_investment_project_id is not null then
    select * into p from public.public_investment_projects where id=p_investment_project_id and country_id=p_country_id for update;
    if not found or p.status not in ('approved','in_progress') then raise exception 'Projeto não aprovado ou não encontrado.'; end if;
    if p.budget_allocation_id is distinct from p_budget_allocation_id then raise exception 'A execução deve usar a alocação aprovada do próprio projeto.'; end if;
    if p.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED') then raise exception 'A moeda do projeto diverge da moeda atual do Tesouro.'; end if;
    if p_entry_type<>'expense' or p.executed_amount+p_amount>p.approved_amount then raise exception 'Execução excede o valor aprovado.'; end if;
    update public.public_investment_projects set executed_amount=executed_amount+p_amount,
      status=case when executed_amount+p_amount>=approved_amount then 'completed' else 'in_progress' end,updated_at=now()
    where id=p.id;
  end if;
  insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,signed_amount,source_type,source_id,
    budget_allocation_id,investment_project_id,idempotency_key,created_by)
  values(p_country_id,p_entry_type,p_category,trim(p_description),p_amount,
    case when p_entry_type='revenue' then p_amount else -p_amount end,
    case when p_investment_project_id is not null then 'investment_execution' else 'manual' end,
    case when p_investment_project_id is not null then gen_random_uuid() else null end,
    p_budget_allocation_id,p_investment_project_id,p_idempotency_key,auth.uid())
  returning id into v_id;
  perform public.economy_audit(p_country_id,'post','treasury_entry',v_id,null,jsonb_build_object('type',p_entry_type,'amount',p_amount,'category',p_category));
  return v_id;
exception when unique_violation then
  raise exception 'Operação duplicada: chave de idempotência ou origem já utilizada.';
end;
$$;

create or replace function public.reverse_treasury_entry(p_entry_id uuid,p_reason text,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare e public.treasury_ledger_entries%rowtype; v_id uuid; t public.national_treasuries%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode estornar lançamentos.'; end if;
  select * into e from public.treasury_ledger_entries where id=p_entry_id for update;
  if not found then raise exception 'Lançamento não encontrado.'; end if;
  select * into t from public.national_treasuries where country_id=e.country_id for update;
  if not found then raise exception 'Tesouro Nacional não encontrado.'; end if;
  if (t.opening_balance>0 and t.opening_balance_currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED'))
    or exists(select 1 from public.treasury_ledger_entries x where x.country_id=e.country_id
      and x.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED')) then
    raise exception 'O Tesouro possui registros em outra unidade monetária; a conciliação deve ocorrer antes do estorno.'; end if;
  if e.currency_code_snapshot<>coalesce(nullif(t.currency_code,''),'UNCONFIGURED') then raise exception 'A unidade monetária do lançamento diverge da unidade atual do Tesouro.'; end if;
  if e.source_type='tax_collection' then raise exception 'Arrecadação tributária exige procedimento próprio de retificação; estorno genérico bloqueado.'; end if;
  if e.entry_type='reversal' then raise exception 'Um estorno não pode ser estornado por este procedimento.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 or length(trim(coalesce(p_idempotency_key,'')))<8 then raise exception 'Informe o motivo e uma chave de estorno válida.'; end if;
  if e.signed_amount>0 and (select t.opening_balance+coalesce((select sum(x.signed_amount) from public.treasury_ledger_entries x where x.country_id=e.country_id),0)
    from public.national_treasuries t where t.country_id=e.country_id)<e.amount then
    raise exception 'O estorno reduziria o saldo do Tesouro abaixo de zero.'; end if;
  if exists(select 1 from public.treasury_ledger_entries where reverses_entry_id=e.id) then raise exception 'Este lançamento já foi estornado.'; end if;
  insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,signed_amount,source_type,source_id,
    reverses_entry_id,budget_allocation_id,investment_project_id,idempotency_key,created_by)
  values(e.country_id,'reversal',e.category,'Estorno: '||trim(p_reason),e.amount,-e.signed_amount,'reversal',e.id,
    e.id,e.budget_allocation_id,e.investment_project_id,p_idempotency_key,auth.uid())
  returning id into v_id;
  if e.investment_project_id is not null then
    update public.public_investment_projects set executed_amount=greatest(0,executed_amount-e.amount),
      status=case when status='completed' then 'in_progress' else status end,updated_at=now()
    where id=e.investment_project_id;
  end if;
  perform public.economy_audit(e.country_id,'reverse','treasury_entry',v_id,to_jsonb(e),jsonb_build_object('reverses_entry_id',e.id,'reason',p_reason));
  return v_id;
end;
$$;

create or replace function public.set_treasury_opening_balance(p_country_id uuid,p_amount numeric)
returns void language plpgsql security definer set search_path=public,auth as $$
declare t public.national_treasuries%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode definir o saldo inicial.'; end if;
  if p_amount<0 then raise exception 'Saldo inicial não pode ser negativo.'; end if;
  select * into t from public.national_treasuries where country_id=p_country_id for update;
  if not found then raise exception 'Tesouro Nacional não encontrado.'; end if;
  if t.opening_balance_set_at is not null or exists(select 1 from public.treasury_ledger_entries where country_id=p_country_id) then
    raise exception 'O saldo inicial só pode ser definido uma vez, antes do primeiro lançamento.';
  end if;
  update public.national_treasuries set opening_balance=p_amount,opening_balance_set_at=now(),
    opening_balance_currency_code_snapshot=coalesce(nullif(currency_code,''),'UNCONFIGURED'),updated_at=now() where country_id=p_country_id;
  perform public.economy_audit(p_country_id,'initialize','national_treasury',t.id,to_jsonb(t),jsonb_build_object('opening_balance',p_amount));
end;
$$;

create or replace function public.set_economy_operations_suspended(p_country_id uuid,p_suspended boolean,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare t public.national_treasuries%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode suspender operações econômicas.'; end if;
  if p_suspended and length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe um motivo para a suspensão.'; end if;
  select * into t from public.national_treasuries where country_id=p_country_id for update;
  if not found then raise exception 'Tesouro Nacional não encontrado.'; end if;
  update public.national_treasuries set operations_suspended=p_suspended,
    suspended_at=case when p_suspended then now() else null end,
    suspended_by=case when p_suspended then auth.uid() else null end,updated_at=now()
  where country_id=p_country_id;
  perform public.economy_audit(p_country_id,case when p_suspended then 'suspend' else 'reactivate' end,
    'economy_operations',t.id,to_jsonb(t),jsonb_build_object('suspended',p_suspended,'reason',nullif(trim(p_reason),'')));
end;
$$;

create or replace function public.set_treasury_public_visibility(p_country_id uuid,p_visible boolean)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_world_admin() and not public.is_country_president(p_country_id) then raise exception 'Sem permissão para alterar visibilidade do Tesouro.'; end if;
  update public.national_treasuries set public_balance_visible=p_visible,updated_at=now() where country_id=p_country_id;
  perform public.economy_audit(p_country_id,'visibility','national_treasury',null,null,jsonb_build_object('public_balance_visible',p_visible));
end;
$$;

-- Nenhuma tabela de dinheiro pessoal, banco comercial, câmbio ou Banco Central é criada nesta etapa.
revoke all on function public.can_manage_economy(uuid,text) from public,anon;
revoke all on function public.has_economy_permission(uuid,text) from public,anon;
grant execute on function public.has_economy_permission(uuid,text) to authenticated;
revoke all on function public.economy_audit(uuid,text,text,uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.get_economy_dashboard(uuid) from public,anon;
revoke all on function public.save_gdp_record(uuid,date,date,jsonb,text) from public,anon;
revoke all on function public.save_price_item(uuid,text,text,numeric,numeric,date) from public,anon;
revoke all on function public.create_tax_rule(uuid,text,text,text,text,numeric,text,date) from public,anon;
revoke all on function public.review_tax_rule(uuid,text,text) from public,anon;
revoke all on function public.create_tax_obligation(uuid,uuid,uuid,text,text,numeric,date) from public,anon;
revoke all on function public.confirm_tax_collection(uuid,numeric,text) from public,anon;
revoke all on function public.create_budget_plan(uuid,text,date,date,jsonb) from public,anon;
revoke all on function public.review_budget_plan(uuid,text,text) from public,anon;
revoke all on function public.create_investment_project(uuid,text,text,text,uuid,numeric,date,date,uuid) from public,anon;
revoke all on function public.review_investment_project(uuid,text,numeric) from public,anon;
revoke all on function public.post_treasury_entry(uuid,text,text,text,numeric,text,uuid,uuid) from public,anon;
revoke all on function public.reverse_treasury_entry(uuid,text,text) from public,anon;
revoke all on function public.set_treasury_public_visibility(uuid,boolean) from public,anon;
revoke all on function public.set_economy_operations_suspended(uuid,boolean,text) from public,anon;
revoke all on function public.set_treasury_opening_balance(uuid,numeric) from public,anon;

grant execute on function public.get_economy_dashboard(uuid) to authenticated;
grant execute on function public.save_gdp_record(uuid,date,date,jsonb,text) to authenticated;
grant execute on function public.save_price_item(uuid,text,text,numeric,numeric,date) to authenticated;
grant execute on function public.create_tax_rule(uuid,text,text,text,text,numeric,text,date) to authenticated;
grant execute on function public.review_tax_rule(uuid,text,text) to authenticated;
grant execute on function public.create_tax_obligation(uuid,uuid,uuid,text,text,numeric,date) to authenticated;
grant execute on function public.confirm_tax_collection(uuid,numeric,text) to authenticated;
grant execute on function public.create_budget_plan(uuid,text,date,date,jsonb) to authenticated;
grant execute on function public.review_budget_plan(uuid,text,text) to authenticated;
grant execute on function public.create_investment_project(uuid,text,text,text,uuid,numeric,date,date,uuid) to authenticated;
grant execute on function public.review_investment_project(uuid,text,numeric) to authenticated;
grant execute on function public.post_treasury_entry(uuid,text,text,text,numeric,text,uuid,uuid) to authenticated;
grant execute on function public.reverse_treasury_entry(uuid,text,text) to authenticated;
grant execute on function public.set_treasury_public_visibility(uuid,boolean) to authenticated;
grant execute on function public.set_economy_operations_suspended(uuid,boolean,text) to authenticated;
grant execute on function public.set_treasury_opening_balance(uuid,numeric) to authenticated;

commit;
