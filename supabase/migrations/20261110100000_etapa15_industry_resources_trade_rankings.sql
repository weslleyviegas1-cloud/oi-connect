-- WORLD ECONOMY — Etapa 15: produção, recursos, comércio, rankings e resiliência
-- Todas as operações são dados fictícios da simulação. Nenhum saldo é criado automaticamente.

create table if not exists public.natural_resources (
 id uuid primary key default gen_random_uuid(),
 code text not null unique,
 name text not null unique,
 category text not null check(category in ('metallic_ore','mineral','energy','forest','agricultural','other')),
 unit text not null,
 description text,
 classification text not null default 'renewable' check(classification in ('renewable','non_renewable','mixed','other')),
 is_active boolean not null default true,
 created_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.country_natural_resources (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 resource_id uuid not null references public.natural_resources(id) on delete restrict,
 estimated_reserve numeric(30,6) check(estimated_reserve is null or estimated_reserve>=0),
 confirmed_reserve numeric(30,6) check(confirmed_reserve is null or confirmed_reserve>=0),
 extracted_quantity numeric(30,6) not null default 0 check(extracted_quantity>=0),
 unit_snapshot text not null,
 region text,
 status text not null default 'under_review' check(status in ('under_review','estimated','confirmed','suspended','depleted')),
 source_description text,
 recorded_by uuid not null references public.profiles(id) on delete restrict,
 updated_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists country_resources_region_uidx on public.country_natural_resources(country_id,resource_id,coalesce(region,''));
create index if not exists country_resources_scope_idx on public.country_natural_resources(country_id,status);

create table if not exists public.product_catalog (
 id uuid primary key default gen_random_uuid(),
 code text not null unique,
 name text not null,
 category text not null,
 unit text not null,
 description text,
 country_id uuid references public.countries(id) on delete restrict,
 is_active boolean not null default true,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(country_id,name)
);

create table if not exists public.industrial_facilities (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 company_id uuid not null references public.companies(id) on delete restrict,
 name text not null check(length(trim(name)) between 2 and 160),
 category text not null check(category in ('steel','metallurgy','construction','agriculture_food','energy','fuels','wood_paper','technology','transport_logistics','chemical_admin','custom')),
 location text,
 latitude numeric(10,7),
 longitude numeric(10,7),
 responsible_profile_id uuid references public.profiles(id) on delete restrict,
 capacity numeric(30,6) check(capacity is null or capacity>=0),
 capacity_unit text,
 status text not null default 'pending' check(status in ('pending','active','rejected','suspended','closed')),
 notes text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 approved_by uuid references public.profiles(id) on delete restrict,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(company_id,name),
 check((latitude is null or latitude between -90 and 90) and (longitude is null or longitude between -180 and 180))
);
create index if not exists industrial_facilities_country_idx on public.industrial_facilities(country_id,status,category);

create or replace function public.validate_industry_shipment()
returns trigger language plpgsql security definer set search_path=public as $
declare t public.trade_contracts%rowtype; v_existing numeric;
begin
 select * into t from public.trade_contracts where id=new.contract_id;
 if not found or t.status not in ('accepted','fulfilled') then raise exception 'A remessa exige contrato aceito.'; end if;
 select coalesce(sum(quantity),0) into v_existing from public.shipment_records where contract_id=new.contract_id and status<>'cancelled';
 if v_existing+new.quantity>t.quantity then raise exception 'A quantidade total das remessas excede a quantidade contratada.'; end if;
 return new;
end; $;
drop trigger if exists industry_shipment_quantity_guard on public.shipment_records;
create trigger industry_shipment_quantity_guard before insert on public.shipment_records
for each row execute function public.validate_industry_shipment();

create or replace function public.validate_industry_company_country()
returns trigger language plpgsql security definer set search_path=public as $
begin
 if new.company_id is not null and not exists(select 1 from public.companies c where c.id=new.company_id and c.country_id=new.country_id) then
  raise exception 'A empresa informada não pertence ao país do registro.';
 end if;
 return new;
end; $;
drop trigger if exists industrial_facility_country_guard on public.industrial_facilities;
create trigger industrial_facility_country_guard before insert or update of country_id,company_id on public.industrial_facilities
for each row execute function public.validate_industry_company_country();

create table if not exists public.extraction_records (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 company_id uuid references public.companies(id) on delete restrict,
 resource_id uuid not null references public.natural_resources(id) on delete restrict,
 country_resource_id uuid references public.country_natural_resources(id) on delete restrict,
 quantity numeric(30,6) not null check(quantity>0),
 unit_snapshot text not null,
 origin_location text not null,
 occurred_at timestamptz not null default now(),
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 proof_url text,
 notes text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 reviewed_by uuid references public.profiles(id) on delete restrict,
 reviewed_at timestamptz,
 review_note text,
 idempotency_key text not null,
 created_at timestamptz not null default now(),
 unique(country_id,idempotency_key)
);
create index if not exists extraction_country_status_idx on public.extraction_records(country_id,status,occurred_at desc);

create table if not exists public.production_recipes (
 id uuid primary key default gen_random_uuid(),
 country_id uuid references public.countries(id) on delete restrict,
 name text not null,
 description text,
 output_product_id uuid not null references public.product_catalog(id) on delete restrict,
 output_quantity numeric(30,6) not null check(output_quantity>0),
 duration_minutes integer check(duration_minutes is null or duration_minutes>=0),
 status text not null default 'draft' check(status in ('draft','active','inactive')),
 is_global boolean not null default false,
 created_by uuid not null references public.profiles(id) on delete restrict,
 approved_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((is_global and country_id is null) or (not is_global and country_id is not null))
);
create unique index if not exists production_recipes_global_name_uidx on public.production_recipes(lower(name)) where is_global;
create unique index if not exists production_recipes_country_name_uidx on public.production_recipes(country_id,lower(name)) where not is_global;

create table if not exists public.production_recipe_inputs (
 id uuid primary key default gen_random_uuid(),
 recipe_id uuid not null references public.production_recipes(id) on delete restrict,
 item_type text not null check(item_type in ('resource','product')),
 resource_id uuid references public.natural_resources(id) on delete restrict,
 product_id uuid references public.product_catalog(id) on delete restrict,
 quantity_per_batch numeric(30,6) not null check(quantity_per_batch>0),
 unit_snapshot text not null,
 created_at timestamptz not null default now(),
 check((item_type='resource' and resource_id is not null and product_id is null) or (item_type='product' and product_id is not null and resource_id is null))
);
create unique index if not exists production_recipe_input_resource_uidx on public.production_recipe_inputs(recipe_id,resource_id) where item_type='resource';
create unique index if not exists production_recipe_input_product_uidx on public.production_recipe_inputs(recipe_id,product_id) where item_type='product';

create table if not exists public.inventory_movements (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 company_id uuid references public.companies(id) on delete restrict,
 item_type text not null check(item_type in ('resource','product')),
 resource_id uuid references public.natural_resources(id) on delete restrict,
 product_id uuid references public.product_catalog(id) on delete restrict,
 movement_type text not null check(movement_type in ('in','out','adjustment_in','adjustment_out','reserved','released')),
 quantity numeric(30,6) not null check(quantity>0),
 unit_snapshot text not null,
 source_type text not null,
 source_id uuid,
 destination_description text,
 reason text,
 idempotency_key text not null,
 actor_id uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 check((item_type='resource' and resource_id is not null and product_id is null) or (item_type='product' and product_id is not null and resource_id is null)),
 unique(country_id,idempotency_key)
);
create index if not exists inventory_company_created_idx on public.inventory_movements(company_id,created_at desc);
create index if not exists inventory_country_item_idx on public.inventory_movements(country_id,item_type,resource_id,product_id);

create or replace view public.inventory_balances with (security_invoker=true) as
select country_id,company_id,item_type,resource_id,product_id,unit_snapshot,
 sum(case when movement_type in ('in','adjustment_in','released') then quantity
          when movement_type in ('out','adjustment_out','reserved') then -quantity else 0 end) as balance
from public.inventory_movements
group by country_id,company_id,item_type,resource_id,product_id,unit_snapshot;

create table if not exists public.production_orders (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 company_id uuid not null references public.companies(id) on delete restrict,
 facility_id uuid not null references public.industrial_facilities(id) on delete restrict,
 recipe_id uuid not null references public.production_recipes(id) on delete restrict,
 batch_count integer not null check(batch_count between 1 and 1000000),
 status text not null default 'planned' check(status in ('planned','in_progress','completed','cancelled','blocked')),
 started_at timestamptz,
 completed_at timestamptz,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 idempotency_key text not null,
 unique(company_id,idempotency_key)
);
create index if not exists production_orders_company_idx on public.production_orders(company_id,status,created_at desc);

create table if not exists public.energy_facilities (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 company_id uuid references public.companies(id) on delete restrict,
 name text not null,
 facility_type text not null check(facility_type in ('power_plant','renewable_plant','fuel_storage','warehouse','logistics_center','other')),
 location text,
 latitude numeric(10,7),
 longitude numeric(10,7),
 registered_capacity numeric(30,6) check(registered_capacity is null or registered_capacity>=0),
 capacity_unit text,
 status text not null default 'registered' check(status in ('registered','active','inactive','under_maintenance','decommissioned')),
 responsible_profile_id uuid references public.profiles(id) on delete restrict,
 notes text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 check((latitude is null or latitude between -90 and 90) and (longitude is null or longitude between -180 and 180))
);

create table if not exists public.product_prices (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 product_id uuid references public.product_catalog(id) on delete restrict,
 resource_id uuid references public.natural_resources(id) on delete restrict,
 price_type text not null check(price_type in ('reference','announced','practiced')),
 amount numeric(30,6) not null check(amount>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 valid_from date not null,
 valid_until date,
 source_description text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 check((product_id is not null)::int + (resource_id is not null)::int = 1),
 check(valid_until is null or valid_until>=valid_from)
);
create index if not exists product_prices_scope_date_idx on public.product_prices(country_id,valid_from desc);

create table if not exists public.trade_contracts (
 id uuid primary key default gen_random_uuid(),
 seller_country_id uuid not null references public.countries(id) on delete restrict,
 buyer_country_id uuid not null references public.countries(id) on delete restrict,
 seller_company_id uuid not null references public.companies(id) on delete restrict,
 buyer_company_id uuid not null references public.companies(id) on delete restrict,
 product_id uuid references public.product_catalog(id) on delete restrict,
 resource_id uuid references public.natural_resources(id) on delete restrict,
 quantity numeric(30,6) not null check(quantity>0),
 unit_snapshot text not null,
 unit_price numeric(30,6) not null check(unit_price>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 total_value numeric(30,6) generated always as (quantity*unit_price) stored,
 trade_type text not null check(trade_type in ('domestic','export','import')),
 status text not null default 'proposed' check(status in ('proposed','accepted','rejected','cancelled','fulfilled')),
 payment_status text not null default 'unpaid' check(payment_status in ('unpaid','pending','paid','refunded')),
 delivery_status text not null default 'not_shipped' check(delivery_status in ('not_shipped','shipped','partially_received','received')),
 terms text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 accepted_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 idempotency_key text not null,
 check((product_id is not null)::int + (resource_id is not null)::int = 1),
 check((trade_type='domestic' and seller_country_id=buyer_country_id) or (trade_type in ('export','import') and seller_country_id<>buyer_country_id)),
 unique(seller_company_id,idempotency_key)
);
create index if not exists trade_contracts_country_idx on public.trade_contracts(seller_country_id,buyer_country_id,status,created_at desc);

create table if not exists public.shipment_records (
 id uuid primary key default gen_random_uuid(),
 contract_id uuid not null references public.trade_contracts(id) on delete restrict,
 origin text not null,
 destination text not null,
 transport_mode text not null check(transport_mode in ('road','rail','air','sea','other')),
 quantity numeric(30,6) not null check(quantity>0),
 status text not null default 'planned' check(status in ('planned','in_transit','delivered','cancelled')),
 tracking_reference text,
 departure_at timestamptz,
 estimated_arrival_at timestamptz,
 delivered_at timestamptz,
 coordinates jsonb not null default '{}'::jsonb,
 notes text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now()
);

create table if not exists public.environmental_records (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 company_id uuid references public.companies(id) on delete restrict,
 facility_id uuid references public.industrial_facilities(id) on delete restrict,
 extraction_id uuid references public.extraction_records(id) on delete restrict,
 record_type text not null check(record_type in ('license','protected_area','restoration_project','resource_consumption','incident','inspection')),
 title text not null,
 description text,
 status text not null default 'registered' check(status in ('registered','pending','approved','rejected','in_progress','completed','closed')),
 authority_profile_id uuid references public.profiles(id) on delete restrict,
 valid_from date,
 valid_until date,
 created_by uuid not null references public.profiles(id) on delete restrict,
 reviewed_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now()
);

create table if not exists public.global_security_indicators (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 indicator_type text not null check(indicator_type in ('institutional_stability','essential_services','critical_infrastructure','international_cooperation','disaster_preparedness','administrative_response','civil_protection')),
 value numeric(12,4) check(value is null or value between 0 and 100),
 status text not null default 'reported' check(status in ('reported','under_review','verified','archived')),
 methodology text not null,
 period_start date,
 period_end date,
 source_description text not null,
 recorded_by uuid not null references public.profiles(id) on delete restrict,
 verified_by uuid references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now()
);

create table if not exists public.global_events (
 id uuid primary key default gen_random_uuid(),
 country_id uuid references public.countries(id) on delete restrict,
 event_type text not null check(event_type in ('administrative_alert','natural_disaster','service_disruption','environmental_event','international_cooperation','civil_protection_project','institutional_event')),
 title text not null,
 description text,
 severity text not null default 'informational' check(severity in ('informational','low','moderate','high','critical')),
 status text not null default 'open' check(status in ('open','monitoring','resolved','closed')),
 occurred_at timestamptz not null default now(),
 responsible_profile_id uuid references public.profiles(id) on delete restrict,
 source_description text,
 created_by uuid not null references public.profiles(id) on delete restrict,
 updated_at timestamptz not null default now()
);

create table if not exists public.industry_audit_logs (
 id uuid primary key default gen_random_uuid(),
 country_id uuid references public.countries(id) on delete restrict,
 company_id uuid references public.companies(id) on delete restrict,
 actor_id uuid references public.profiles(id) on delete restrict,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create table if not exists public.industry_notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_profile_id uuid not null references public.profiles(id) on delete restrict,
 country_id uuid references public.countries(id) on delete restrict,
 event_type text not null,
 title text not null,
 message text not null,
 entity_type text,
 entity_id uuid,
 read_at timestamptz,
 created_at timestamptz not null default now()
);

create or replace function public.can_manage_industry_company(p_company_id uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select auth.uid() is not null and (
  public.is_world_admin()
  or exists(select 1 from public.companies c where c.id=p_company_id and c.status='active' and c.created_by=auth.uid())
  or exists(select 1 from public.company_members m join public.companies c on c.id=m.company_id
    join public.profiles p on p.id=m.profile_id
    where m.company_id=p_company_id and m.profile_id=auth.uid() and m.status='active' and c.status='active'
     and coalesce(p.account_status,'active')='active' and p.registration_status='active'
     and (m.member_role in ('owner','director','manager') or m.permissions && array['company.manage','industry.manage','production.manage','inventory.manage','trade.manage','resources.manage']))
  or exists(select 1 from public.company_owners o join public.companies c on c.id=o.company_id
    where o.company_id=p_company_id and o.profile_id=auth.uid() and o.status='active' and c.status='active')
 );
$$;

create or replace function public.can_manage_industry_country(p_country_id uuid,p_permission text default 'industry.manage')
returns boolean language sql stable security definer set search_path=public,auth as $
 select auth.uid() is not null and (
  public.is_world_admin()
  or public.is_country_president(p_country_id)
  or exists(
   select 1 from public.government_members gm
   join public.government_member_permissions gp on gp.member_id=gm.id and gp.country_id=gm.country_id
   join public.profiles p on p.id=gm.profile_id
   where gm.profile_id=auth.uid() and gm.country_id=p_country_id and gm.status='active'
    and coalesce(p.account_status,'active')='active' and p.registration_status='active'
    and gp.permission_key in (p_permission,'industry.manage')
    and (gp.scope_type='country'
      or (gp.scope_type='ministry' and exists(select 1 from public.ministries m where m.id=gp.scope_id and m.country_id=p_country_id))
      or (gp.scope_type='department' and exists(select 1 from public.government_departments d where d.id=gp.scope_id and d.country_id=p_country_id)))
  )
 );
$;

create or replace function public.industry_audit(p_country_id uuid,p_company_id uuid,p_action text,p_type text,p_id uuid,p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path=public,auth as $$
 insert into public.industry_audit_logs(country_id,company_id,actor_id,action,entity_type,entity_id,details)
 values(p_country_id,p_company_id,auth.uid(),p_action,p_type,p_id,coalesce(p_details,'{}'::jsonb));
$$;

alter table public.natural_resources enable row level security;
alter table public.country_natural_resources enable row level security;
alter table public.product_catalog enable row level security;
alter table public.industrial_facilities enable row level security;
alter table public.extraction_records enable row level security;
alter table public.production_recipes enable row level security;
alter table public.production_recipe_inputs enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.production_orders enable row level security;
alter table public.energy_facilities enable row level security;
alter table public.product_prices enable row level security;
alter table public.trade_contracts enable row level security;
alter table public.shipment_records enable row level security;
alter table public.environmental_records enable row level security;
alter table public.global_security_indicators enable row level security;
alter table public.global_events enable row level security;
alter table public.industry_audit_logs enable row level security;
alter table public.industry_notifications enable row level security;

create policy natural_resources_read on public.natural_resources for select to authenticated using(is_active or public.is_world_admin());
create policy natural_resources_admin_insert on public.natural_resources for insert to authenticated with check(public.is_world_admin() and created_by=auth.uid());
create policy natural_resources_admin_update on public.natural_resources for update to authenticated using(public.is_world_admin()) with check(public.is_world_admin());
create policy country_resources_read on public.country_natural_resources for select to authenticated using(public.is_world_admin() or public.is_government_country_citizen(country_id));
create policy country_resources_insert on public.country_natural_resources for insert to authenticated with check(recorded_by=auth.uid() and public.can_manage_industry_country(country_id,'resources.manage'));
create policy country_resources_update on public.country_natural_resources for update to authenticated using(public.can_manage_industry_country(country_id,'resources.manage')) with check(public.can_manage_industry_country(country_id,'resources.manage'));
create policy product_catalog_read on public.product_catalog for select to authenticated using(is_active or public.is_world_admin() or (country_id is not null and public.is_government_country_citizen(country_id)));
create policy product_catalog_insert on public.product_catalog for insert to authenticated with check(created_by=auth.uid() and (public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'industry.manage'))));
create policy product_catalog_update on public.product_catalog for update to authenticated using(public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'industry.manage'))) with check(public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'industry.manage')));
create policy industrial_facilities_read on public.industrial_facilities for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id) or public.can_manage_industry_company(company_id));
create policy industrial_facilities_insert on public.industrial_facilities for insert to authenticated with check(created_by=auth.uid() and public.can_manage_industry_company(company_id));
create policy industrial_facilities_update on public.industrial_facilities for update to authenticated using(public.can_manage_industry_company(company_id)) with check(public.can_manage_industry_company(company_id));
create policy extraction_records_read on public.extraction_records for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.is_government_country_citizen(country_id) and (company_id is null or public.can_manage_industry_company(company_id)) or (company_id is not null and public.can_manage_industry_company(company_id)));
create policy extraction_records_insert on public.extraction_records for insert to authenticated with check(created_by=auth.uid() and (public.is_world_admin() or (company_id is not null and public.can_manage_industry_company(company_id)) or (company_id is null and public.can_manage_industry_country(country_id,'resources.manage'))));
create policy production_recipes_read on public.production_recipes for select to authenticated using((status='active' and (is_global or public.is_government_country_citizen(country_id))) or public.is_world_admin() or (country_id is not null and public.is_country_president(country_id)));
create policy production_recipes_insert on public.production_recipes for insert to authenticated with check(created_by=auth.uid() and (public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'industry.manage'))));
create policy production_recipes_update on public.production_recipes for update to authenticated using(public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'industry.manage'))) with check(public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'industry.manage')));
create policy production_recipe_inputs_read on public.production_recipe_inputs for select to authenticated using(exists(select 1 from public.production_recipes r where r.id=recipe_id and (r.status='active' or public.is_world_admin() or (r.country_id is not null and public.is_country_president(r.country_id)))));
create policy production_recipe_inputs_insert on public.production_recipe_inputs for insert to authenticated with check(exists(select 1 from public.production_recipes r where r.id=recipe_id and (public.is_world_admin() or (r.country_id is not null and public.can_manage_industry_country(r.country_id,'industry.manage')))));
create policy production_recipe_inputs_update on public.production_recipe_inputs for update to authenticated using(exists(select 1 from public.production_recipes r where r.id=recipe_id and (public.is_world_admin() or (r.country_id is not null and public.can_manage_industry_country(r.country_id,'industry.manage'))))) with check(exists(select 1 from public.production_recipes r where r.id=recipe_id and (public.is_world_admin() or (r.country_id is not null and public.can_manage_industry_country(r.country_id,'industry.manage')))));
create policy inventory_movements_read on public.inventory_movements for select to authenticated using(public.is_world_admin() or (company_id is null and public.is_country_president(country_id)) or (company_id is not null and public.can_manage_industry_company(company_id)));
create policy production_orders_read on public.production_orders for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.can_manage_industry_company(company_id));
create policy energy_facilities_read on public.energy_facilities for select to authenticated using(public.is_world_admin() or public.is_government_country_citizen(country_id) or (company_id is not null and public.can_manage_industry_company(company_id)));
create policy energy_facilities_insert on public.energy_facilities for insert to authenticated with check(created_by=auth.uid() and (public.is_world_admin() or (company_id is not null and public.can_manage_industry_company(company_id)) or public.can_manage_industry_country(country_id,'infrastructure.manage')));
create policy energy_facilities_update on public.energy_facilities for update to authenticated using(public.is_world_admin() or (company_id is not null and public.can_manage_industry_company(company_id)) or public.can_manage_industry_country(country_id,'infrastructure.manage')) with check(public.is_world_admin() or (company_id is not null and public.can_manage_industry_company(company_id)) or public.can_manage_industry_country(country_id,'infrastructure.manage'));
create policy product_prices_read on public.product_prices for select to authenticated using(public.is_world_admin() or public.is_government_country_citizen(country_id));
create policy product_prices_write on public.product_prices for insert to authenticated with check(created_by=auth.uid() and public.can_manage_industry_country(country_id,'prices.manage'));
create policy trade_contracts_read on public.trade_contracts for select to authenticated using(public.is_world_admin() or public.can_manage_industry_company(seller_company_id) or public.can_manage_industry_company(buyer_company_id));
create policy trade_contracts_insert on public.trade_contracts for insert to authenticated with check(created_by=auth.uid() and public.can_manage_industry_company(seller_company_id) and exists(select 1 from public.companies s where s.id=seller_company_id and s.country_id=seller_country_id and s.status='active') and exists(select 1 from public.companies b where b.id=buyer_company_id and b.country_id=buyer_country_id and b.status='active'));
-- Contratos são alterados apenas por RPCs de transição de estado; clientes não editam pagamento/entrega diretamente.
create policy shipment_records_read on public.shipment_records for select to authenticated using(exists(select 1 from public.trade_contracts t where t.id=contract_id and (public.is_world_admin() or public.can_manage_industry_company(t.seller_company_id) or public.can_manage_industry_company(t.buyer_company_id))));
create policy shipment_records_insert on public.shipment_records for insert to authenticated with check(created_by=auth.uid() and exists(select 1 from public.trade_contracts t where t.id=contract_id and (public.can_manage_industry_company(t.seller_company_id) or public.can_manage_industry_company(t.buyer_company_id))));
-- Situação de remessas é alterada exclusivamente por RPC validada.
create policy environmental_records_read on public.environmental_records for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.is_government_country_citizen(country_id) and (company_id is null or public.can_manage_industry_company(company_id)) or (company_id is not null and public.can_manage_industry_company(company_id)));
create policy environmental_records_insert on public.environmental_records for insert to authenticated with check(created_by=auth.uid() and (public.is_world_admin() or public.can_manage_industry_country(country_id,'environment.manage') or (company_id is not null and public.can_manage_industry_company(company_id))));
create policy environmental_records_update on public.environmental_records for update to authenticated using(public.can_manage_industry_country(country_id,'environment.manage') or (company_id is not null and public.can_manage_industry_company(company_id))) with check(public.can_manage_industry_country(country_id,'environment.manage') or (company_id is not null and public.can_manage_industry_company(company_id)));
create policy security_indicators_read on public.global_security_indicators for select to authenticated using(public.is_world_admin() or public.is_government_country_citizen(country_id));
create policy security_indicators_insert on public.global_security_indicators for insert to authenticated with check(recorded_by=auth.uid() and public.can_manage_industry_country(country_id,'security.manage'));
create policy security_indicators_update on public.global_security_indicators for update to authenticated using(public.can_manage_industry_country(country_id,'security.manage')) with check(public.can_manage_industry_country(country_id,'security.manage'));
create policy global_events_read on public.global_events for select to authenticated using(country_id is null or public.is_world_admin() or public.is_government_country_citizen(country_id));
create policy global_events_insert on public.global_events for insert to authenticated with check(created_by=auth.uid() and (public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'security.manage'))));
create policy global_events_update on public.global_events for update to authenticated using(public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'security.manage'))) with check(public.is_world_admin() or (country_id is not null and public.can_manage_industry_country(country_id,'security.manage')));
create policy industry_audit_read on public.industry_audit_logs for select to authenticated using(public.is_world_admin() or actor_id=auth.uid() or (country_id is not null and public.is_country_president(country_id)) or (company_id is not null and public.can_manage_industry_company(company_id)));
drop policy if exists bank_accounts_industry_trade_read on public.bank_accounts;
create policy bank_accounts_industry_trade_read on public.bank_accounts for select to authenticated
using(owner_company_id is not null and public.can_manage_industry_company(owner_company_id));

create policy industry_notifications_read on public.industry_notifications for select to authenticated using(recipient_profile_id=auth.uid() or public.is_world_admin());
create policy industry_notifications_update on public.industry_notifications for update to authenticated using(recipient_profile_id=auth.uid()) with check(recipient_profile_id=auth.uid());

create or replace function public.validate_industry_company_country()
returns trigger language plpgsql security definer set search_path=public as $
begin
 if new.company_id is not null and not exists(select 1 from public.companies c where c.id=new.company_id and c.country_id=new.country_id) then
  raise exception 'A empresa informada não pertence ao país do registro.';
 end if;
 return new;
end; $;
drop trigger if exists energy_facility_country_guard on public.energy_facilities;
create trigger energy_facility_country_guard before insert or update of country_id,company_id on public.energy_facilities
for each row execute function public.validate_industry_company_country();
drop trigger if exists environmental_record_country_guard on public.environmental_records;
create trigger environmental_record_country_guard before insert or update of country_id,company_id on public.environmental_records
for each row execute function public.validate_industry_company_country();

create or replace function public.review_industrial_facility(p_facility_id uuid,p_decision text,p_note text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $
declare f public.industrial_facilities%rowtype;
begin
 if p_decision not in ('active','rejected','suspended') then raise exception 'Decisão inválida.'; end if;
 select * into f from public.industrial_facilities where id=p_facility_id for update;
 if not found then raise exception 'Instalação não encontrada.'; end if;
 if not (public.is_world_admin() or public.can_manage_industry_country(f.country_id,'industry.approve')) then raise exception 'Somente a autoridade nacional ou Super Admin pode revisar instalações.'; end if;
 if f.status<>'pending' then raise exception 'Esta instalação já foi revisada.'; end if;
 update public.industrial_facilities set status=p_decision,approved_by=auth.uid(),approved_at=now(),notes=concat_ws(E'\\n',notes,nullif(trim(p_note),'')),updated_at=now() where id=f.id;
 perform public.industry_audit(f.country_id,f.company_id,'facility_'||p_decision,'industrial_facility',f.id,jsonb_build_object('note',p_note));
 insert into public.industry_notifications(recipient_profile_id,country_id,event_type,title,message,entity_type,entity_id)
 select distinct m.profile_id,f.country_id,'facility_'||p_decision,'Revisão da instalação industrial',
 case when p_decision='active' then 'A instalação industrial foi aprovada.' else 'A situação da instalação foi atualizada: '||p_decision end,'industrial_facility',f.id
 from public.company_members m where m.company_id=f.company_id and m.status='active';
 return f.id;
end; $;

create or replace function public.accept_trade_contract(p_contract_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path=public,auth as $
declare t public.trade_contracts%rowtype;
begin
 if p_decision not in ('accepted','rejected') then raise exception 'Decisão inválida.'; end if;
 select * into t from public.trade_contracts where id=p_contract_id for update;
 if not found or t.status<>'proposed' then raise exception 'Contrato inexistente ou já analisado.'; end if;
 if not (public.is_world_admin() or public.can_manage_industry_company(t.buyer_company_id)) then raise exception 'Somente a empresa compradora pode aceitar ou rejeitar a proposta.'; end if;
 update public.trade_contracts set status=p_decision,accepted_by=auth.uid(),updated_at=now() where id=t.id;
 perform public.industry_audit(t.seller_country_id,t.seller_company_id,'trade_'||p_decision,'trade_contract',t.id,'{}'::jsonb);
 insert into public.industry_notifications(recipient_profile_id,country_id,event_type,title,message,entity_type,entity_id)
 select distinct m.profile_id,t.seller_country_id,'trade_'||p_decision,'Resposta à proposta comercial',
 case when p_decision='accepted' then 'A empresa compradora aceitou a proposta.' else 'A empresa compradora rejeitou a proposta.' end,'trade_contract',t.id
 from public.company_members m where m.company_id=t.seller_company_id and m.status='active';
 return t.id;
end; $;

create or replace function public.settle_trade_contract(p_contract_id uuid,p_from_account_id uuid,p_to_account_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $
declare t public.trade_contracts%rowtype; a public.bank_accounts%rowtype; b public.bank_accounts%rowtype; v_transfer uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória.'; end if;
 if length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Chave de idempotência inválida.'; end if;
 select * into t from public.trade_contracts where id=p_contract_id for update;
 if not found or t.status not in ('accepted','fulfilled') then raise exception 'Contrato ainda não foi aceito.'; end if;
 if t.payment_status='paid' then raise exception 'Este contrato já foi pago.'; end if;
 if not public.can_manage_industry_company(t.buyer_company_id) then raise exception 'Somente a empresa compradora pode efetuar o pagamento.'; end if;
 if t.buyer_country_id<>t.seller_country_id then raise exception 'Liquidação internacional está bloqueada pela regra bancária atual. O contrato pode ser negociado, mas a transferência entre países exige autorização bancária internacional.'; end if;
 select * into a from public.bank_accounts where id=p_from_account_id for update;
 select * into b from public.bank_accounts where id=p_to_account_id for update;
 if a.id is null or a.owner_company_id<>t.buyer_company_id or a.status<>'active' then raise exception 'Conta de origem não pertence à empresa compradora ou está indisponível.'; end if;
 if b.id is null or b.owner_company_id<>t.seller_company_id or b.status<>'active' then raise exception 'Conta de destino não pertence à empresa vendedora ou está indisponível.'; end if;
 if a.country_id<>b.country_id or a.country_id<>t.buyer_country_id then raise exception 'Transferência entre países não autorizada.'; end if;
 if a.currency_id<>t.currency_id or b.currency_id<>t.currency_id then raise exception 'As duas contas devem utilizar a moeda do contrato.'; end if;
 if a.balance<t.total_value then raise exception 'Saldo insuficiente na conta da empresa compradora.'; end if;
 perform 1 from public.bank_accounts where id in (a.id,b.id) order by id for update;
 update public.bank_accounts set balance=balance-t.total_value where id=a.id returning * into a;
 update public.bank_accounts set balance=balance+t.total_value where id=b.id returning * into b;
 insert into public.bank_transfers(from_account_id,to_account_id,amount_sent,from_currency_id,amount_received,to_currency_id,exchange_rate_id,exchange_rate,fee_amount,idempotency_key,initiated_by,description)
 values(a.id,b.id,t.total_value,a.currency_id,t.total_value,b.currency_id,null,1,0,p_idempotency_key,auth.uid(),'Liquidação do contrato comercial '||t.id::text) returning id into v_transfer;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'transfer_out',t.total_value,a.currency_id,a.balance,'Pagamento de contrato comercial',v_transfer,p_idempotency_key||':out',auth.uid()),
       (b.id,'transfer_in',t.total_value,b.currency_id,b.balance,'Recebimento de contrato comercial',v_transfer,p_idempotency_key||':in',auth.uid());
 update public.trade_contracts set payment_status='paid',updated_at=now() where id=t.id;
 perform public.bank_audit(a.bank_id,'trade_payment_sent','bank_transfer',v_transfer,jsonb_build_object('contract_id',t.id,'seller_company_id',t.seller_company_id));
 perform public.industry_audit(t.seller_country_id,t.seller_company_id,'trade_paid','trade_contract',t.id,jsonb_build_object('transfer_id',v_transfer,'amount',t.total_value));
 insert into public.industry_notifications(recipient_profile_id,country_id,event_type,title,message,entity_type,entity_id)
 select distinct m.profile_id,t.seller_country_id,'trade_paid','Pagamento comercial recebido','O pagamento do contrato comercial foi confirmado no banco da simulação.','trade_contract',t.id
 from public.company_members m where m.company_id=t.seller_company_id and m.status='active';
 return v_transfer;
end; $;

create or replace function public.update_industry_shipment(p_shipment_id uuid,p_status text)
returns uuid language plpgsql security definer set search_path=public,auth as $
declare s public.shipment_records%rowtype; t public.trade_contracts%rowtype; v_delivered numeric;
begin
 if p_status not in ('in_transit','delivered','cancelled') then raise exception 'Situação de remessa inválida.'; end if;
 select * into s from public.shipment_records where id=p_shipment_id for update;
 if not found or s.status in ('delivered','cancelled') then raise exception 'Remessa inexistente ou encerrada.'; end if;
 select * into t from public.trade_contracts where id=s.contract_id for update;
 if not (public.is_world_admin() or public.can_manage_industry_company(t.seller_company_id) or public.can_manage_industry_company(t.buyer_company_id)) then raise exception 'Sem permissão para atualizar esta remessa.'; end if;
 if p_status='delivered' then
  perform pg_advisory_xact_lock(hashtextextended(t.seller_company_id::text,0));
  if t.product_id is not null then
   select coalesce(sum(case when movement_type in ('in','adjustment_in','released') then quantity else -quantity end),0) into v_balance
    from public.inventory_movements where company_id=t.seller_company_id and item_type='product' and product_id=t.product_id;
  else
   select coalesce(sum(case when movement_type in ('in','adjustment_in','released') then quantity else -quantity end),0) into v_balance
    from public.inventory_movements where company_id=t.seller_company_id and item_type='resource' and resource_id=t.resource_id;
  end if;
  if v_balance<s.quantity then raise exception 'Estoque insuficiente na empresa vendedora para entregar esta remessa.'; end if;
  if t.product_id is not null then
   insert into public.inventory_movements(country_id,company_id,item_type,product_id,movement_type,quantity,unit_snapshot,source_type,source_id,reason,idempotency_key,actor_id)
   values(t.seller_country_id,t.seller_company_id,'product',t.product_id,'out',s.quantity,t.unit_snapshot,'shipment',s.id,'Expedição de contrato comercial','shipment:'||s.id::text||':seller',auth.uid()),
         (t.buyer_country_id,t.buyer_company_id,'product',t.product_id,'in',s.quantity,t.unit_snapshot,'shipment',s.id,'Recebimento de contrato comercial','shipment:'||s.id::text||':buyer',auth.uid());
  else
   insert into public.inventory_movements(country_id,company_id,item_type,resource_id,movement_type,quantity,unit_snapshot,source_type,source_id,reason,idempotency_key,actor_id)
   values(t.seller_country_id,t.seller_company_id,'resource',t.resource_id,'out',s.quantity,t.unit_snapshot,'shipment',s.id,'Expedição de contrato comercial','shipment:'||s.id::text||':seller',auth.uid()),
         (t.buyer_country_id,t.buyer_company_id,'resource',t.resource_id,'in',s.quantity,t.unit_snapshot,'shipment',s.id,'Recebimento de contrato comercial','shipment:'||s.id::text||':buyer',auth.uid());
  end if;
 end if;
 update public.shipment_records set status=p_status,departure_at=case when p_status='in_transit' then coalesce(departure_at,now()) else departure_at end,delivered_at=case when p_status='delivered' then now() else delivered_at end where id=s.id;
 select coalesce(sum(quantity),0) into v_delivered from public.shipment_records where contract_id=t.id and status='delivered';
 update public.trade_contracts set delivery_status=case when v_delivered>=t.quantity then 'received' when v_delivered>0 then 'partially_received' when p_status='in_transit' then 'shipped' else delivery_status end,updated_at=now() where id=t.id;
 perform public.industry_audit(t.seller_country_id,t.seller_company_id,'shipment_'||p_status,'shipment',s.id,jsonb_build_object('delivered_total',v_delivered));
 return s.id;
end; $;

create or replace function public.guard_country_resource_reserve()
returns trigger language plpgsql set search_path=public as $
begin
 if new.extracted_quantity is distinct from old.extracted_quantity
   and current_setting('app.industry_ledger_write',true) is distinct from 'on' then
  raise exception 'A quantidade extraída só pode ser alterada por uma aprovação de extração registrada.';
 end if;
 if new.confirmed_reserve is not null and new.extracted_quantity>new.confirmed_reserve then
  raise exception 'A reserva confirmada não pode ser inferior ao total já extraído.';
 end if;
 return new;
end; $;
drop trigger if exists country_resource_reserve_guard on public.country_natural_resources;
create trigger country_resource_reserve_guard before update on public.country_natural_resources
for each row execute function public.guard_country_resource_reserve();

create or replace function public.record_industry_extraction(
 p_country_id uuid,p_company_id uuid,p_resource_id uuid,p_country_resource_id uuid,p_quantity numeric,p_origin text,p_notes text default null,p_proof_url text default null,p_idempotency_key text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_unit text; v_key text;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória.'; end if;
 if p_quantity is null or p_quantity<=0 or nullif(trim(p_origin),'') is null then raise exception 'Quantidade e origem são obrigatórias.'; end if;
 if p_company_id is not null and not public.can_manage_industry_company(p_company_id) then raise exception 'Sem permissão sobre a empresa informada.'; end if;
 if p_company_id is null and not public.can_manage_industry_country(p_country_id,'resources.manage') then raise exception 'Sem permissão para registrar extração nacional.'; end if;
 if not exists(select 1 from public.companies c where c.id=p_company_id and c.country_id=p_country_id and c.status='active') and p_company_id is not null then raise exception 'Empresa não pertence ao país ou não está ativa.'; end if;
 select unit into v_unit from public.natural_resources where id=p_resource_id and is_active;
 if not found then raise exception 'Recurso inexistente ou inativo.'; end if;
 if p_country_resource_id is null or not exists(select 1 from public.country_natural_resources cr where cr.id=p_country_resource_id and cr.country_id=p_country_id and cr.resource_id=p_resource_id and cr.status='confirmed' and cr.confirmed_reserve is not null) then raise exception 'Selecione uma reserva confirmada para este recurso e país. Reservas estimadas não autorizam extração.'; end if;
 v_key:=coalesce(nullif(trim(p_idempotency_key),''),gen_random_uuid()::text);
 insert into public.extraction_records(country_id,company_id,resource_id,country_resource_id,quantity,unit_snapshot,origin_location,proof_url,notes,created_by,idempotency_key)
 values(p_country_id,p_company_id,p_resource_id,p_country_resource_id,p_quantity,v_unit,trim(p_origin),nullif(trim(p_proof_url),''),nullif(trim(p_notes),''),auth.uid(),v_key)
 returning id into v_id;
 perform public.industry_audit(p_country_id,p_company_id,'extraction_requested','extraction',v_id,jsonb_build_object('quantity',p_quantity,'resource_id',p_resource_id));
 return v_id;
end; $$;

create or replace function public.review_industry_extraction(p_extraction_id uuid,p_decision text,p_note text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare e public.extraction_records%rowtype; v_balance numeric;
begin
 if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;
 select * into e from public.extraction_records where id=p_extraction_id for update;
 if not found then raise exception 'Registro de extração não encontrado.'; end if;
 if not (public.is_world_admin() or public.can_manage_industry_country(e.country_id,'resources.approve')) then raise exception 'Aprovação restrita ao Super Admin ou autoridade nacional autorizada.'; end if;
 if e.status<>'pending' then raise exception 'Esta extração já foi analisada.'; end if;
 if p_decision='approved' and e.country_resource_id is not null then
  perform pg_advisory_xact_lock(hashtextextended(e.country_resource_id::text,0));
  select greatest(confirmed_reserve-extracted_quantity,0) into v_balance from public.country_natural_resources where id=e.country_resource_id for update;
  if v_balance is null or e.quantity>v_balance then raise exception 'Quantidade superior à reserva confirmada ainda disponível.'; end if;
  perform set_config('app.industry_ledger_write','on',true);
  update public.country_natural_resources set extracted_quantity=extracted_quantity+e.quantity,updated_by=auth.uid(),updated_at=now() where id=e.country_resource_id;
 end if;
 update public.extraction_records set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=e.id;
 if p_decision='approved' then
  insert into public.inventory_movements(country_id,company_id,item_type,resource_id,movement_type,quantity,unit_snapshot,source_type,source_id,reason,idempotency_key,actor_id)
  values(e.country_id,e.company_id,'resource',e.resource_id,'in',e.quantity,e.unit_snapshot,'extraction',e.id,'Extração aprovada', 'extraction:'||e.id::text,auth.uid());
 end if;
 perform public.industry_audit(e.country_id,e.company_id,'extraction_'||p_decision,'extraction',e.id,jsonb_build_object('note',p_note));
 insert into public.industry_notifications(recipient_profile_id,country_id,event_type,title,message,entity_type,entity_id)
 values(e.created_by,e.country_id,'extraction_'||p_decision,case when p_decision='approved' then 'Extração aprovada' else 'Extração rejeitada' end,
 case when p_decision='approved' then 'Sua extração foi aprovada e o estoque foi atualizado.' else 'Sua extração foi rejeitada: '||coalesce(p_note,'consulte a autoridade responsável') end,'extraction',e.id);
 return e.id;
end; $$;

create or replace function public.create_industry_recipe(
 p_country_id uuid,p_name text,p_description text,p_output_product_id uuid,p_output_quantity numeric,
 p_duration_minutes integer,p_is_global boolean,p_inputs jsonb
) returns uuid language plpgsql security definer set search_path=public,auth as $
declare v_id uuid; v_item jsonb; v_unit text; v_type text; v_resource uuid; v_product uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória.'; end if;
 if nullif(trim(p_name),'') is null or p_output_quantity is null or p_output_quantity<=0 then raise exception 'Nome e quantidade de saída são obrigatórios.'; end if;
 if p_inputs is null or jsonb_typeof(p_inputs)<>'array' or jsonb_array_length(p_inputs)=0 then raise exception 'Informe ao menos um insumo.'; end if;
 if p_is_global then
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode criar receitas globais.'; end if;
 else
  if p_country_id is null or not public.can_manage_industry_country(p_country_id,'industry.manage') then raise exception 'Sem permissão para criar receita nacional.'; end if;
 end if;
 if not exists(select 1 from public.product_catalog p where p.id=p_output_product_id and p.is_active and (p.country_id is null or p.country_id=p_country_id)) then raise exception 'Produto de saída não disponível para este escopo.'; end if;
 insert into public.production_recipes(country_id,name,description,output_product_id,output_quantity,duration_minutes,status,is_global,created_by,approved_by)
 values(case when p_is_global then null else p_country_id end,trim(p_name),nullif(trim(p_description),''),p_output_product_id,p_output_quantity,p_duration_minutes,'active',p_is_global,auth.uid(),auth.uid())
 returning id into v_id;
 for v_item in select * from jsonb_array_elements(p_inputs) loop
  v_type:=v_item->>'item_type';
  if v_type='resource' then
   v_resource:=nullif(v_item->>'item_id','')::uuid; v_product:=null;
   select unit into v_unit from public.natural_resources where id=v_resource and is_active;
  elsif v_type='product' then
   v_product:=nullif(v_item->>'item_id','')::uuid; v_resource:=null;
   select unit into v_unit from public.product_catalog where id=v_product and is_active and (country_id is null or country_id=p_country_id);
  else raise exception 'Tipo de insumo inválido.'; end if;
  if v_unit is null then raise exception 'Insumo inexistente ou indisponível.'; end if;
  if coalesce((v_item->>'quantity')::numeric,0)<=0 then raise exception 'Quantidade de insumo inválida.'; end if;
  insert into public.production_recipe_inputs(recipe_id,item_type,resource_id,product_id,quantity_per_batch,unit_snapshot)
  values(v_id,v_type,v_resource,v_product,(v_item->>'quantity')::numeric,v_unit);
 end loop;
 perform public.industry_audit(p_country_id,null,'recipe_created','production_recipe',v_id,jsonb_build_object('global',p_is_global));
 return v_id;
end; $;

create or replace function public.create_production_order(p_facility_id uuid,p_recipe_id uuid,p_batch_count integer,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare f public.industrial_facilities%rowtype; r public.production_recipes%rowtype; v_id uuid;
begin
 if p_batch_count is null or p_batch_count<1 or p_batch_count>1000000 then raise exception 'Quantidade de lotes inválida.'; end if;
 select * into f from public.industrial_facilities where id=p_facility_id and status='active';
 if not found or not public.can_manage_industry_company(f.company_id) then raise exception 'Instalação inexistente, inativa ou sem permissão.'; end if;
 select * into r from public.production_recipes where id=p_recipe_id and status='active' and (is_global or country_id=f.country_id);
 if not found then raise exception 'Receita ativa não disponível para este país.'; end if;
 insert into public.production_orders(country_id,company_id,facility_id,recipe_id,batch_count,created_by,idempotency_key)
 values(f.country_id,f.company_id,f.id,r.id,p_batch_count,auth.uid(),coalesce(nullif(trim(p_idempotency_key),''),gen_random_uuid()::text))
 returning id into v_id;
 perform public.industry_audit(f.country_id,f.company_id,'production_order_created','production_order',v_id,jsonb_build_object('recipe_id',r.id,'batches',p_batch_count));
 return v_id;
end; $$;

create or replace function public.complete_production_order(p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare o public.production_orders%rowtype; r public.production_recipes%rowtype; i record; v_balance numeric; v_output_unit text;
begin
 select * into o from public.production_orders where id=p_order_id for update;
 if not found or o.status not in ('planned','in_progress') then raise exception 'Ordem não encontrada ou não pode ser concluída.'; end if;
 if not public.can_manage_industry_company(o.company_id) then raise exception 'Somente administradores autorizados da empresa podem concluir a produção.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(o.company_id::text,0));
 select * into r from public.production_recipes where id=o.recipe_id and status='active';
 if not found then raise exception 'Receita não está ativa.'; end if;
 if not exists(select 1 from public.production_recipe_inputs where recipe_id=r.id) then raise exception 'A receita não possui insumos configurados.'; end if;
 for i in select * from public.production_recipe_inputs where recipe_id=r.id loop
  select coalesce(sum(case when movement_type in ('in','adjustment_in','released') then quantity else -quantity end),0)
   into v_balance from public.inventory_movements
   where country_id=o.country_id and company_id=o.company_id and item_type=i.item_type
    and ((i.item_type='resource' and resource_id=i.resource_id) or (i.item_type='product' and product_id=i.product_id));
  if v_balance < i.quantity_per_batch*o.batch_count then raise exception 'Estoque insuficiente para um ou mais insumos da receita.'; end if;
 end loop;
 for i in select * from public.production_recipe_inputs where recipe_id=r.id loop
  insert into public.inventory_movements(country_id,company_id,item_type,resource_id,product_id,movement_type,quantity,unit_snapshot,source_type,source_id,reason,idempotency_key,actor_id)
  values(o.country_id,o.company_id,i.item_type,i.resource_id,i.product_id,'out',i.quantity_per_batch*o.batch_count,i.unit_snapshot,'production',o.id,'Consumo de insumo na produção','production:'||o.id::text||':input:'||i.id::text,auth.uid());
 end loop;
 select unit into v_output_unit from public.product_catalog where id=r.output_product_id and is_active;
 if not found then raise exception 'Produto de saída inexistente ou inativo.'; end if;
 insert into public.inventory_movements(country_id,company_id,item_type,product_id,movement_type,quantity,unit_snapshot,source_type,source_id,reason,idempotency_key,actor_id)
 values(o.country_id,o.company_id,'product',r.output_product_id,'in',r.output_quantity*o.batch_count,v_output_unit,'production',o.id,'Produto final da ordem de produção','production:'||o.id::text||':output',auth.uid());
 update public.production_orders set status='completed',started_at=coalesce(started_at,now()),completed_at=now(),updated_at=now() where id=o.id;
 perform public.industry_audit(o.country_id,o.company_id,'production_completed','production_order',o.id,jsonb_build_object('batches',o.batch_count,'output',r.output_quantity*o.batch_count));
 insert into public.industry_notifications(recipient_profile_id,country_id,event_type,title,message,entity_type,entity_id)
 select distinct m.profile_id,o.country_id,'production_completed','Produção concluída','A ordem de produção foi concluída e o estoque atualizado.','production_order',o.id
 from public.company_members m where m.company_id=o.company_id and m.status='active';
 return o.id;
end; $$;

create or replace view public.global_industry_rankings as
select 'industrial_output'::text as ranking_type,m.country_id,c.name as country_name,sum(m.quantity)::numeric(30,6) as metric_value,
 max(m.created_at)::date as reference_date,'Produção industrial acumulada registrada no livro de estoque; não representa valor monetário'::text as methodology
from public.inventory_movements m join public.countries c on c.id=m.country_id
where m.item_type='product' and m.movement_type='in' and m.source_type='production'
group by m.country_id,c.name
union all
select 'confirmed_reserves',r.country_id,c.name,sum(r.confirmed_reserve)::numeric(30,6),max(r.updated_at)::date,
 'Soma das reservas confirmadas cadastradas; não representa estoque disponível'
from public.country_natural_resources r join public.countries c on c.id=r.country_id
where r.status='confirmed' group by r.country_id,c.name
union all
select 'exports',t.seller_country_id,c.name,sum(t.total_value)::numeric(30,6),max(t.updated_at)::date,
 'Valor nominal contratado em moeda de cada contrato; moedas não normalizadas, não comparar diretamente entre moedas'
from public.trade_contracts t join public.countries c on c.id=t.seller_country_id
where t.trade_type in ('export','import') and t.status in ('accepted','fulfilled')
group by t.seller_country_id,c.name
union all
select 'imports',t.buyer_country_id,c.name,sum(t.total_value)::numeric(30,6),max(t.updated_at)::date,
 'Valor nominal contratado em moeda de cada contrato; moedas não normalizadas, não comparar diretamente entre moedas'
from public.trade_contracts t join public.countries c on c.id=t.buyer_country_id
where t.trade_type in ('export','import') and t.status in ('accepted','fulfilled')
group by t.buyer_country_id,c.name;

grant select on public.inventory_balances,public.global_industry_rankings to authenticated;
grant execute on function public.can_manage_industry_company(uuid) to authenticated;
grant execute on function public.can_manage_industry_country(uuid,text) to authenticated;
grant execute on function public.review_industrial_facility(uuid,text,text) to authenticated;
grant execute on function public.accept_trade_contract(uuid,text) to authenticated;
grant execute on function public.update_industry_shipment(uuid,text) to authenticated;
grant execute on function public.settle_trade_contract(uuid,uuid,uuid,text) to authenticated;
grant execute on function public.record_industry_extraction(uuid,uuid,uuid,uuid,numeric,text,text,text,text) to authenticated;
grant execute on function public.review_industry_extraction(uuid,text,text) to authenticated;
grant execute on function public.create_industry_recipe(uuid,text,text,uuid,numeric,integer,boolean,jsonb) to authenticated;
grant execute on function public.create_production_order(uuid,uuid,integer,text) to authenticated;
grant execute on function public.complete_production_order(uuid) to authenticated;
