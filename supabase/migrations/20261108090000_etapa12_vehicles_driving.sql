begin;

create table if not exists public.vehicle_categories (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(code ~ '^[a-z][a-z0-9_]{1,39}$'),
 name text not null check(length(trim(name)) between 2 and 80),
 is_active boolean not null default true,
 created_at timestamptz not null default now()
);

insert into public.vehicle_categories(code,name) values
 ('cars','Carros'),('motorcycles','Motocicletas'),('trucks','Caminhões'),
 ('buses','Ônibus'),('commercial','Veículos comerciais'),('special','Veículos especiais')
on conflict(code) do nothing;

create table if not exists public.vehicle_catalog (
 id uuid primary key default gen_random_uuid(),
 category_id uuid not null references public.vehicle_categories(id) on delete restrict,
 brand text not null check(length(trim(brand)) between 1 and 100),
 model text not null check(length(trim(model)) between 1 and 120),
 model_year integer not null check(model_year between 1900 and 2200),
 image_url text,
 description text,
 country_id uuid references public.countries(id) on delete restrict,
 base_price numeric(30,6) not null check(base_price>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 is_active boolean not null default true,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists vehicle_catalog_active_idx on public.vehicle_catalog(is_active,category_id);

create table if not exists public.vehicle_dealerships (
 id uuid primary key default gen_random_uuid(),
 identifier text not null unique check(identifier ~ '^[A-Z0-9][A-Z0-9._-]{2,39}$'),
 name text not null check(length(trim(name)) between 2 and 160),
 country_id uuid not null references public.countries(id) on delete restrict,
 city text, region text, logo_url text,
 company_id uuid not null references public.companies(id) on delete restrict,
 bank_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 created_by uuid not null references public.profiles(id),
 approved_by uuid references public.profiles(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists vehicle_dealerships_country_status_idx on public.vehicle_dealerships(country_id,status);

create table if not exists public.vehicles (
 id uuid primary key default gen_random_uuid(),
 vehicle_number text not null unique,
 plate text not null,
 catalog_id uuid references public.vehicle_catalog(id) on delete restrict,
 brand text not null, model text not null, category_code text not null,
 model_year integer not null check(model_year between 1900 and 2200),
 country_id uuid not null references public.countries(id) on delete restrict,
 owner_profile_id uuid references public.profiles(id) on delete restrict,
 owner_company_id uuid references public.companies(id) on delete restrict,
 registered_at timestamptz not null default now(),
 document_status text not null default 'pending' check(document_status in ('pending','regular','suspended','cancelled')),
 status text not null default 'active' check(status in ('active','for_sale','suspended','scrapped')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check ((owner_profile_id is not null)::integer + (owner_company_id is not null)::integer = 1),
 unique(country_id,plate)
);
create index if not exists vehicles_owner_profile_idx on public.vehicles(owner_profile_id,status);
create index if not exists vehicles_owner_company_idx on public.vehicles(owner_company_id,status);

create table if not exists public.vehicle_ownership_history (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,
 previous_profile_id uuid references public.profiles(id),
 previous_company_id uuid references public.companies(id),
 new_profile_id uuid references public.profiles(id),
 new_company_id uuid references public.companies(id),
 transfer_value numeric(30,6) not null default 0 check(transfer_value>=0),
 currency_id uuid references public.currencies(id),
 transfer_type text not null check(transfer_type in ('initial_registration','dealership_purchase','private_sale','correction')),
 sale_id uuid,
 transferred_at timestamptz not null default now(),
 actor_id uuid references public.profiles(id),
 check ((new_profile_id is not null)::integer + (new_company_id is not null)::integer = 1)
);
create index if not exists vehicle_ownership_history_vehicle_idx on public.vehicle_ownership_history(vehicle_id,transferred_at desc);

create table if not exists public.vehicle_inventory (
 id uuid primary key default gen_random_uuid(),
 dealership_id uuid not null references public.vehicle_dealerships(id) on delete restrict,
 catalog_id uuid not null references public.vehicle_catalog(id) on delete restrict,
 asking_price numeric(30,6) not null check(asking_price>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 vehicle_id uuid references public.vehicles(id) on delete restrict,
 status text not null default 'available' check(status in ('available','reserved','sold','withdrawn')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists vehicle_inventory_available_idx on public.vehicle_inventory(dealership_id,status);

create table if not exists public.vehicle_sales (
 id uuid primary key default gen_random_uuid(),
 inventory_id uuid references public.vehicle_inventory(id) on delete restrict,
 vehicle_id uuid references public.vehicles(id) on delete restrict,
 seller_dealership_id uuid references public.vehicle_dealerships(id) on delete restrict,
 seller_profile_id uuid references public.profiles(id),
 seller_company_id uuid references public.companies(id),
 buyer_profile_id uuid references public.profiles(id),
 buyer_company_id uuid references public.companies(id),
 seller_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 buyer_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 amount numeric(30,6) not null check(amount>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 idempotency_key text not null unique,
 status text not null default 'completed' check(status in ('completed','reversed')),
 created_at timestamptz not null default now(),
 check ((buyer_profile_id is not null)::integer + (buyer_company_id is not null)::integer = 1)
);
create unique index if not exists vehicle_sales_inventory_once_uidx on public.vehicle_sales(inventory_id) where inventory_id is not null and status='completed';

create table if not exists public.vehicle_documents (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,
 document_number text not null unique,
 document_type text not null check(document_type in ('registration','ownership','license','transfer_history','administrative')),
 issuer_country_id uuid not null references public.countries(id) on delete restrict,
 issued_by uuid not null references public.profiles(id),
 issued_at timestamptz not null default now(),
 valid_until timestamptz,
 status text not null default 'active' check(status in ('active','expired','suspended','cancelled')),
 payload jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists vehicle_documents_vehicle_idx on public.vehicle_documents(vehicle_id,issued_at desc);

create table if not exists public.vehicle_fee_settings (
 country_id uuid primary key references public.countries(id) on delete restrict,
 license_fee numeric(30,6) not null default 0 check(license_fee>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 validity_days integer not null default 365 check(validity_days between 1 and 3650),
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now()
);
create table if not exists public.vehicle_fees (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,
 owner_profile_id uuid references public.profiles(id),
 owner_company_id uuid references public.companies(id),
 country_id uuid not null references public.countries(id) on delete restrict,
 amount numeric(30,6) not null check(amount>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 due_at date not null,
 status text not null default 'pending' check(status in ('pending','paid','waived','cancelled')),
 paid_at timestamptz,
 bank_transaction_id uuid,
 idempotency_key text unique,
 created_at timestamptz not null default now(),
 check ((owner_profile_id is not null)::integer + (owner_company_id is not null)::integer = 1)
);
create index if not exists vehicle_fees_owner_idx on public.vehicle_fees(owner_profile_id,owner_company_id,status);

create table if not exists public.driving_schools (
 id uuid primary key default gen_random_uuid(),
 identifier text not null unique,
 name text not null check(length(trim(name)) between 2 and 160),
 country_id uuid not null references public.countries(id) on delete restrict,
 city text, region text, responsible_profile_id uuid not null references public.profiles(id),
 company_id uuid references public.companies(id) on delete restrict,
 is_public boolean not null default false,
 status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 created_by uuid not null references public.profiles(id),
 approved_by uuid references public.profiles(id),
 approved_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.driving_instructors (
 id uuid primary key default gen_random_uuid(),
 school_id uuid not null references public.driving_schools(id) on delete restrict,
 profile_id uuid not null references public.profiles(id) on delete restrict,
 categories text[] not null default '{}',
 status text not null default 'active' check(status in ('active','suspended')),
 created_at timestamptz not null default now(),
 unique(school_id,profile_id)
);
create table if not exists public.driving_category_rules (
 country_id uuid not null references public.countries(id) on delete restrict,
 category_code text not null check(category_code in ('A','B','C','D','E')),
 minimum_lessons integer not null default 1 check(minimum_lessons>=0),
 minimum_exam_score numeric(5,2) not null default 70 check(minimum_exam_score between 0 and 100),
 validity_days integer not null default 1825 check(validity_days between 1 and 3650),
 fee_amount numeric(30,6) not null default 0 check(fee_amount>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 is_active boolean not null default true,
 updated_by uuid references public.profiles(id),
 updated_at timestamptz not null default now(),
 primary key(country_id,category_code)
);
create table if not exists public.driving_enrollments (
 id uuid primary key default gen_random_uuid(),
 student_profile_id uuid not null references public.profiles(id) on delete restrict,
 school_id uuid not null references public.driving_schools(id) on delete restrict,
 country_id uuid not null references public.countries(id) on delete restrict,
 category_code text not null check(category_code in ('A','B','C','D','E')),
 status text not null default 'pending' check(status in ('pending','active','completed','rejected','cancelled')),
 enrolled_at timestamptz not null default now(),
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz
);
create index if not exists driving_enrollments_student_idx on public.driving_enrollments(student_profile_id,status);
create table if not exists public.driving_lessons (
 id uuid primary key default gen_random_uuid(),
 enrollment_id uuid not null references public.driving_enrollments(id) on delete restrict,
 instructor_id uuid not null references public.driving_instructors(id) on delete restrict,
 lesson_at timestamptz not null default now(),
 duration_minutes integer not null default 50 check(duration_minutes between 10 and 300),
 notes text,
 completed boolean not null default false,
 recorded_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now()
);
create table if not exists public.driving_examinations (
 id uuid primary key default gen_random_uuid(),
 enrollment_id uuid not null references public.driving_enrollments(id) on delete restrict,
 examiner_id uuid not null references public.profiles(id),
 score numeric(5,2) not null check(score between 0 and 100),
 result text not null check(result in ('approved','failed')),
 notes text,
 examined_at timestamptz not null default now()
);
create table if not exists public.driving_licenses (
 id uuid primary key default gen_random_uuid(),
 license_number text not null unique,
 holder_profile_id uuid not null references public.profiles(id) on delete restrict,
 category_code text not null check(category_code in ('A','B','C','D','E')),
 country_id uuid not null references public.countries(id) on delete restrict,
 issued_at timestamptz not null default now(),
 expires_at timestamptz not null,
 status text not null default 'active' check(status in ('active','expired','suspended','cancelled')),
 examination_id uuid not null references public.driving_examinations(id) on delete restrict,
 created_at timestamptz not null default now()
);
create index if not exists driving_licenses_holder_idx on public.driving_licenses(holder_profile_id,status);

create table if not exists public.vehicle_audit_logs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references public.profiles(id),
 country_id uuid references public.countries(id),
 entity_type text not null,
 entity_id uuid,
 action text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

do $$
declare t text;
begin
 foreach t in array array['vehicle_categories','vehicle_catalog','vehicle_dealerships','vehicles','vehicle_ownership_history','vehicle_inventory','vehicle_sales','vehicle_documents','vehicle_fee_settings','vehicle_fees','driving_schools','driving_instructors','driving_category_rules','driving_enrollments','driving_lessons','driving_examinations','driving_licenses','vehicle_audit_logs']
 loop execute format('alter table public.%I enable row level security',t); end loop;
end $$;

drop policy if exists vehicle_categories_read on public.vehicle_categories;
create policy vehicle_categories_read on public.vehicle_categories for select to authenticated using(is_active or public.is_world_admin());
drop policy if exists vehicle_catalog_read on public.vehicle_catalog;
create policy vehicle_catalog_read on public.vehicle_catalog for select to authenticated using(is_active or public.is_world_admin() or (country_id is not null and public.is_country_president(country_id)));
drop policy if exists vehicles_read_scope on public.vehicles;
create policy vehicles_read_scope on public.vehicles for select to authenticated using(owner_profile_id=auth.uid() or public.is_world_admin() or (owner_company_id is not null and public.is_company_member(owner_company_id,'fleet.read')) or public.is_country_president(country_id));
drop policy if exists vehicle_history_read_scope on public.vehicle_ownership_history;
create policy vehicle_history_read_scope on public.vehicle_ownership_history for select to authenticated using(new_profile_id=auth.uid() or previous_profile_id=auth.uid() or public.is_world_admin() or (new_company_id is not null and public.is_company_member(new_company_id,'fleet.read')) or (previous_company_id is not null and public.is_company_member(previous_company_id,'fleet.read')));
drop policy if exists dealerships_read on public.vehicle_dealerships;
create policy dealerships_read on public.vehicle_dealerships for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id) or public.is_company_member(company_id,'dealership.manage'));
drop policy if exists inventory_read on public.vehicle_inventory;
create policy inventory_read on public.vehicle_inventory for select to authenticated using(status='available' or public.is_world_admin() or exists(select 1 from public.vehicle_dealerships d where d.id=dealership_id and public.is_company_member(d.company_id,'dealership.manage')));
drop policy if exists vehicle_sales_read on public.vehicle_sales;
create policy vehicle_sales_read on public.vehicle_sales for select to authenticated using(buyer_profile_id=auth.uid() or seller_profile_id=auth.uid() or public.is_world_admin() or (buyer_company_id is not null and public.is_company_member(buyer_company_id,'finance.read')) or (seller_company_id is not null and public.is_company_member(seller_company_id,'finance.read')));
drop policy if exists vehicle_documents_read on public.vehicle_documents;
create policy vehicle_documents_read on public.vehicle_documents for select to authenticated using(exists(select 1 from public.vehicles v where v.id=vehicle_id and (v.owner_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(v.country_id) or (v.owner_company_id is not null and public.is_company_member(v.owner_company_id,'fleet.read')))));
drop policy if exists vehicle_fees_read on public.vehicle_fees;
create policy vehicle_fees_read on public.vehicle_fees for select to authenticated using(owner_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or (owner_company_id is not null and public.is_company_member(owner_company_id,'fleet.read')));
drop policy if exists vehicle_fee_settings_read on public.vehicle_fee_settings;
create policy vehicle_fee_settings_read on public.vehicle_fee_settings for select to authenticated using(true);
drop policy if exists driving_schools_read on public.driving_schools;
create policy driving_schools_read on public.driving_schools for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id) or responsible_profile_id=auth.uid());
drop policy if exists driving_instructors_read on public.driving_instructors;
create policy driving_instructors_read on public.driving_instructors for select to authenticated using(public.is_world_admin() or profile_id=auth.uid() or exists(select 1 from public.driving_schools s where s.id=school_id and (s.status='active' or public.is_country_president(s.country_id))));
drop policy if exists driving_category_rules_read on public.driving_category_rules;
create policy driving_category_rules_read on public.driving_category_rules for select to authenticated using(is_active or public.is_world_admin() or public.is_country_president(country_id));
drop policy if exists driving_enrollments_read on public.driving_enrollments;
create policy driving_enrollments_read on public.driving_enrollments for select to authenticated using(student_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or exists(select 1 from public.driving_schools s where s.id=school_id and s.responsible_profile_id=auth.uid()));
drop policy if exists driving_lessons_read on public.driving_lessons;
create policy driving_lessons_read on public.driving_lessons for select to authenticated using(exists(select 1 from public.driving_enrollments e where e.id=enrollment_id and (e.student_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(e.country_id) or exists(select 1 from public.driving_schools s where s.id=e.school_id and s.responsible_profile_id=auth.uid()))));
drop policy if exists driving_examinations_read on public.driving_examinations;
create policy driving_examinations_read on public.driving_examinations for select to authenticated using(exists(select 1 from public.driving_enrollments e where e.id=enrollment_id and (e.student_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(e.country_id) or exists(select 1 from public.driving_schools s where s.id=e.school_id and s.responsible_profile_id=auth.uid()))));
drop policy if exists driving_licenses_read on public.driving_licenses;
create policy driving_licenses_read on public.driving_licenses for select to authenticated using(holder_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id));
drop policy if exists vehicle_audit_read on public.vehicle_audit_logs;
create policy vehicle_audit_read on public.vehicle_audit_logs for select to authenticated using(public.is_world_admin() or (country_id is not null and public.is_country_president(country_id)));

revoke all on public.vehicle_categories,public.vehicle_catalog,public.vehicle_dealerships,public.vehicles,public.vehicle_ownership_history,public.vehicle_inventory,public.vehicle_sales,public.vehicle_documents,public.vehicle_fee_settings,public.vehicle_fees,public.driving_schools,public.driving_instructors,public.driving_category_rules,public.driving_enrollments,public.driving_lessons,public.driving_examinations,public.driving_licenses,public.vehicle_audit_logs from public,anon,authenticated;
grant select on public.vehicle_categories,public.vehicle_catalog,public.vehicle_dealerships,public.vehicles,public.vehicle_ownership_history,public.vehicle_inventory,public.vehicle_sales,public.vehicle_documents,public.vehicle_fee_settings,public.vehicle_fees,public.driving_schools,public.driving_instructors,public.driving_category_rules,public.driving_enrollments,public.driving_lessons,public.driving_examinations,public.driving_licenses,public.vehicle_audit_logs to authenticated;

create or replace function public.vehicle_audit(p_country uuid,p_type text,p_id uuid,p_action text,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,auth as $$
begin insert into public.vehicle_audit_logs(actor_id,country_id,entity_type,entity_id,action,details) values(auth.uid(),p_country,p_type,p_id,p_action,coalesce(p_details,'{}'::jsonb)); end; $$;

create or replace function public.vehicle_admin_upsert_catalog(p_id uuid,p_category uuid,p_brand text,p_model text,p_year integer,p_image text,p_description text,p_country uuid,p_price numeric,p_currency uuid,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
 if not public.is_world_admin() then raise exception 'Somente Super Admin pode administrar o catálogo global.'; end if;
 if length(trim(coalesce(p_brand,'')))=0 or length(trim(coalesce(p_model,'')))=0 or p_year not between 1900 and 2200 or p_price<0 then raise exception 'Dados do veículo inválidos.'; end if;
 if p_id is null then insert into public.vehicle_catalog(category_id,brand,model,model_year,image_url,description,country_id,base_price,currency_id,is_active,created_by) values(p_category,trim(p_brand),trim(p_model),p_year,nullif(trim(p_image),''),p_description,p_country,p_price,p_currency,p_active,auth.uid()) returning id into v_id;
 else update public.vehicle_catalog set category_id=p_category,brand=trim(p_brand),model=trim(p_model),model_year=p_year,image_url=nullif(trim(p_image),''),description=p_description,country_id=p_country,base_price=p_price,currency_id=p_currency,is_active=p_active,updated_at=now() where id=p_id returning id into v_id; end if;
 if v_id is null then raise exception 'Modelo não encontrado.'; end if;
 perform public.vehicle_audit(p_country,'catalog',v_id,'catalog_upserted',jsonb_build_object('brand',p_brand,'model',p_model)); return v_id;
end; $$;

create or replace function public.vehicle_request_dealership(p_identifier text,p_name text,p_country uuid,p_city text,p_region text,p_company uuid,p_bank_account uuid,p_logo text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.companies%rowtype; a public.bank_accounts%rowtype; v_id uuid;
begin
 select * into c from public.companies where id=p_company and status='active' for share;
 if not found or not public.is_company_member(p_company,'company.manage') then raise exception 'Empresa ativa e permissão de gestão necessárias.'; end if;
 select * into a from public.bank_accounts where id=p_bank_account and owner_company_id=p_company and country_id=p_country and status='active';
 if not found or c.country_id<>p_country then raise exception 'Conta bancária empresarial ou país inválido.'; end if;
 insert into public.vehicle_dealerships(identifier,name,country_id,city,region,logo_url,company_id,bank_account_id,created_by)
 values(upper(trim(p_identifier)),trim(p_name),p_country,nullif(trim(p_city),''),nullif(trim(p_region),''),nullif(trim(p_logo),''),p_company,p_bank_account,auth.uid()) returning id into v_id;
 perform public.vehicle_audit(p_country,'dealership',v_id,'requested'); return v_id;
end; $$;

create or replace function public.vehicle_review_dealership(p_id uuid,p_approve boolean,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare d public.vehicle_dealerships%rowtype;
begin
 select * into d from public.vehicle_dealerships where id=p_id for update;
 if not found or not (public.is_world_admin() or public.is_country_president(d.country_id)) then raise exception 'Sem permissão.'; end if;
 if d.status<>'pending' then raise exception 'Solicitação já analisada.'; end if;
 update public.vehicle_dealerships set status=case when p_approve then 'active' else 'closed' end,approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=p_id;
 perform public.vehicle_audit(d.country_id,'dealership',p_id,case when p_approve then 'approved' else 'rejected' end,jsonb_build_object('note',p_note));
end; $$;

create or replace function public.vehicle_dealership_set_status(p_id uuid,p_status text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare d public.vehicle_dealerships%rowtype;
begin
 select * into d from public.vehicle_dealerships where id=p_id for update;
 if not found or not (public.is_world_admin() or public.is_country_president(d.country_id)) or p_status not in ('active','suspended','closed') then raise exception 'Operação não autorizada.'; end if;
 update public.vehicle_dealerships set status=p_status,updated_at=now() where id=p_id;
 perform public.vehicle_audit(d.country_id,'dealership',p_id,'status_changed',jsonb_build_object('status',p_status,'reason',p_reason));
end; $$;

create or replace function public.vehicle_dealership_add_inventory(p_dealership uuid,p_catalog uuid,p_price numeric,p_currency uuid)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare d public.vehicle_dealerships%rowtype; m public.vehicle_catalog%rowtype; v_id uuid;
begin
 select * into d from public.vehicle_dealerships where id=p_dealership and status='active' for share;
 if not found or not public.is_company_member(d.company_id,'dealership.manage') then raise exception 'Concessionária indisponível ou sem permissão.'; end if;
 select * into m from public.vehicle_catalog where id=p_catalog and is_active=true;
 if not found or (m.country_id is not null and m.country_id<>d.country_id) or p_price<=0 or p_currency<>m.currency_id then raise exception 'Modelo, preço ou moeda inválidos.'; end if;
 insert into public.vehicle_inventory(dealership_id,catalog_id,asking_price,currency_id) values(p_dealership,p_catalog,p_price,p_currency) returning id into v_id;
 perform public.vehicle_audit(d.country_id,'inventory',v_id,'listed'); return v_id;
end; $$;

create or replace function public.vehicle_purchase(p_inventory uuid,p_buyer_account uuid,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare i public.vehicle_inventory%rowtype; d public.vehicle_dealerships%rowtype; c public.vehicle_catalog%rowtype; a public.bank_accounts%rowtype; seller public.bank_accounts%rowtype; s uuid; v uuid; plate_no text; vnum text; ownerp uuid; ownerc uuid;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency,'')))<12 then raise exception 'Autenticação ou chave idempotente inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select id into s from public.vehicle_sales where idempotency_key=p_idempotency and status='completed'; if s is not null then return s; end if;
 select * into i from public.vehicle_inventory where id=p_inventory and status='available' for update;
 if not found then raise exception 'Veículo indisponível.'; end if;
 select * into d from public.vehicle_dealerships where id=i.dealership_id and status='active';
 select * into c from public.vehicle_catalog where id=i.catalog_id and is_active=true;
 select * into a from public.bank_accounts where id=p_buyer_account and owner_profile_id=auth.uid() and status='active' for update;
 if not found then select * into a from public.bank_accounts where id=p_buyer_account and owner_company_id is not null and status='active' and public.is_company_member(owner_company_id,'finance.manage') for update; end if;
 if not found or a.country_id<>d.country_id or a.currency_id<>i.currency_id then raise exception 'Conta de comprador incompatível com país ou moeda.'; end if;
 if a.owner_profile_id is not null then ownerp:=a.owner_profile_id; else ownerc:=a.owner_company_id; end if;
 select * into seller from public.bank_accounts where id=d.bank_account_id and owner_company_id=d.company_id and status='active' for update;
 if not found or seller.currency_id<>i.currency_id then raise exception 'Conta da concessionária incompatível com moeda.'; end if;
 if a.balance<i.asking_price then raise exception 'Saldo insuficiente.'; end if;
 update public.bank_accounts set balance=balance-i.asking_price where id=a.id returning * into a;
 update public.bank_accounts set balance=balance+i.asking_price where id=seller.id returning * into seller;
 insert into public.vehicle_sales(inventory_id,seller_dealership_id,seller_company_id,buyer_profile_id,buyer_company_id,seller_account_id,buyer_account_id,amount,currency_id,idempotency_key)
 values(i.id,d.id,d.company_id,ownerp,ownerc,seller.id,a.id,i.asking_price,i.currency_id,p_idempotency) returning id into s;
 plate_no:='WE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,7));
 vnum:='VEH-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.vehicles(vehicle_number,plate,catalog_id,brand,model,category_code,model_year,country_id,owner_profile_id,owner_company_id,document_status)
 values(vnum,plate_no,c.id,c.brand,c.model,(select code from public.vehicle_categories where id=c.category_id),c.model_year,d.country_id,ownerp,ownerc,'regular') returning id into v;
 update public.vehicle_inventory set status='sold',vehicle_id=v,updated_at=now() where id=i.id;
 insert into public.vehicle_ownership_history(vehicle_id,new_profile_id,new_company_id,transfer_value,currency_id,transfer_type,sale_id,actor_id)
 values(v,ownerp,ownerc,i.asking_price,i.currency_id,'dealership_purchase',s,auth.uid());
 insert into public.vehicle_documents(vehicle_id,document_number,document_type,issuer_country_id,issued_by,payload)
 values(v,'REG-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'registration',d.country_id,auth.uid(),jsonb_build_object('fictional',true,'vehicle_number',vnum)),
 (v,'OWN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'ownership',d.country_id,auth.uid(),jsonb_build_object('fictional',true,'sale_id',s));
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'vehicle_purchase',i.asking_price,a.currency_id,a.balance,'Compra de veículo',s,'veh-buyer-'||p_idempotency,auth.uid()),
 (seller.id,'vehicle_sale',i.asking_price,seller.currency_id,seller.balance,'Venda de veículo',s,'veh-seller-'||p_idempotency,auth.uid());
 perform public.vehicle_audit(d.country_id,'vehicle',v,'purchased',jsonb_build_object('sale_id',s,'amount',i.asking_price));
 return s;
end; $$;

create or replace function public.vehicle_private_transfer(p_vehicle uuid,p_buyer_profile uuid,p_buyer_company uuid,p_seller_account uuid,p_buyer_account uuid,p_amount numeric,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.vehicles%rowtype; sa public.bank_accounts%rowtype; ba public.bank_accounts%rowtype; sale uuid; oldp uuid; oldc uuid;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency,'')))<12 or p_amount<=0 or ((p_buyer_profile is not null)::integer+(p_buyer_company is not null)::integer<>1) then raise exception 'Dados da transferência inválidos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select id into sale from public.vehicle_sales where idempotency_key=p_idempotency; if sale is not null then return sale; end if;
 select * into v from public.vehicles where id=p_vehicle and status in ('active','for_sale') for update;
 if not found or (v.owner_profile_id<>auth.uid() and not (v.owner_company_id is not null and public.is_company_member(v.owner_company_id,'fleet.manage'))) then raise exception 'Veículo não pertence ao vendedor ou está indisponível.'; end if;
 oldp:=v.owner_profile_id; oldc:=v.owner_company_id;
 select * into sa from public.bank_accounts where id=p_seller_account and status='active' and ((owner_profile_id=auth.uid()) or (owner_company_id=oldc and public.is_company_member(oldc,'finance.manage'))) for update;
 select * into ba from public.bank_accounts where id=p_buyer_account and status='active' and ((owner_profile_id=p_buyer_profile) or (owner_company_id=p_buyer_company and public.is_company_member(p_buyer_company,'finance.manage'))) for update;
 if sa.id is null or ba.id is null or sa.currency_id<>ba.currency_id or sa.currency_id is distinct from (select currency_id from public.vehicle_catalog where id=v.catalog_id) then raise exception 'Contas ou moeda incompatíveis.'; end if;
 if sa.balance<p_amount then raise exception 'Saldo insuficiente do comprador.'; end if;
 update public.bank_accounts set balance=balance-p_amount where id=ba.id returning * into ba;
 update public.bank_accounts set balance=balance+p_amount where id=sa.id returning * into sa;
 insert into public.vehicle_sales(vehicle_id,seller_profile_id,seller_company_id,buyer_profile_id,buyer_company_id,seller_account_id,buyer_account_id,amount,currency_id,idempotency_key)
 values(v.id,oldp,oldc,p_buyer_profile,p_buyer_company,p_seller_account,p_buyer_account,p_amount,sa.currency_id,p_idempotency) returning id into sale;
 update public.vehicles set owner_profile_id=p_buyer_profile,owner_company_id=p_buyer_company,status='active',document_status='regular',updated_at=now() where id=v.id;
 insert into public.vehicle_ownership_history(vehicle_id,previous_profile_id,previous_company_id,new_profile_id,new_company_id,transfer_value,currency_id,transfer_type,sale_id,actor_id)
 values(v.id,oldp,oldc,p_buyer_profile,p_buyer_company,p_amount,sa.currency_id,'private_sale',sale,auth.uid());
 insert into public.vehicle_documents(vehicle_id,document_number,document_type,issuer_country_id,issued_by,payload)
 values(v.id,'OWN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'ownership',v.country_id,auth.uid(),jsonb_build_object('fictional',true,'sale_id',sale));
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(ba.id,'vehicle_purchase',p_amount,ba.currency_id,ba.balance,'Compra particular de veículo',sale,'veh-buyer-'||p_idempotency,auth.uid()),
 (sa.id,'vehicle_sale',p_amount,sa.currency_id,sa.balance,'Venda particular de veículo',sale,'veh-seller-'||p_idempotency,auth.uid());
 perform public.vehicle_audit(v.country_id,'vehicle',v.id,'ownership_transferred',jsonb_build_object('sale_id',sale)); return sale;
end; $$;

create or replace function public.vehicle_pay_fee(p_fee uuid,p_account uuid,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare f public.vehicle_fees%rowtype; a public.bank_accounts%rowtype; tx uuid; treasury public.national_treasuries%rowtype; code text;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency,'')))<12 then raise exception 'Chave inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select * into f from public.vehicle_fees where id=p_fee for update;
 if not found or f.status<>'pending' then raise exception 'Taxa não disponível.'; end if;
 if f.owner_profile_id is distinct from auth.uid() and not (f.owner_company_id is not null and public.is_company_member(f.owner_company_id,'finance.manage')) then raise exception 'Taxa não pertence ao pagador.'; end if;
 select * into a from public.bank_accounts where id=p_account and status='active' and currency_id=f.currency_id and ((owner_profile_id=auth.uid()) or (owner_company_id=f.owner_company_id and public.is_company_member(f.owner_company_id,'finance.manage'))) for update;
 if not found or a.balance<f.amount then raise exception 'Conta inválida ou saldo insuficiente.'; end if;
 select * into treasury from public.national_treasuries where country_id=f.country_id for update;
 if not found then raise exception 'Tesouro Nacional não cadastrado.'; end if;
 select internal_code into code from public.currencies where id=f.currency_id;
 if treasury.currency_code is distinct from code then raise exception 'Moeda da taxa diverge da moeda do Tesouro.'; end if;
 update public.bank_accounts set balance=balance-f.amount where id=a.id returning * into a;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,idempotency_key,actor_id)
 values(a.id,'vehicle_fee',f.amount,a.currency_id,a.balance,'Taxa veicular ao Tesouro',p_idempotency,auth.uid()) returning id into tx;
 insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,currency_code_snapshot,signed_amount,source_type,source_id,idempotency_key,created_by)
 values(f.country_id,'revenue','vehicle_fee','Taxa veicular '||f.id,f.amount,code,f.amount,'vehicle_fee',f.id,'vehicle-fee:'||p_idempotency,auth.uid());
 update public.vehicle_fees set status='paid',paid_at=now(),bank_transaction_id=tx,idempotency_key=p_idempotency where id=f.id;
 perform public.vehicle_audit(f.country_id,'vehicle_fee',f.id,'paid',jsonb_build_object('transaction_id',tx)); return tx;
end; $$;

create or replace function public.vehicle_admin_set_fee(p_country uuid,p_amount numeric,p_currency uuid,p_validity integer)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if not (public.is_world_admin() or public.is_country_president(p_country)) then raise exception 'Sem permissão.'; end if;
 if p_amount<0 or p_validity not between 1 and 3650 or not exists(select 1 from public.countries c join public.currencies x on x.internal_code=c.currency_code where c.id=p_country and x.id=p_currency) then raise exception 'Taxa ou moeda nacional inválida.'; end if;
 insert into public.vehicle_fee_settings(country_id,license_fee,currency_id,validity_days,updated_by) values(p_country,p_amount,p_currency,p_validity,auth.uid())
 on conflict(country_id) do update set license_fee=excluded.license_fee,currency_id=excluded.currency_id,validity_days=excluded.validity_days,updated_by=auth.uid(),updated_at=now();
end; $$;

create or replace function public.vehicle_request_school(p_identifier text,p_name text,p_country uuid,p_city text,p_region text,p_company uuid default null,p_public boolean default false)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v uuid; c public.companies%rowtype;
begin
 if p_company is not null then select * into c from public.companies where id=p_company and country_id=p_country and status='active'; if not found or not public.is_company_member(p_company,'company.manage') then raise exception 'Empresa não autorizada.'; end if; end if;
 insert into public.driving_schools(identifier,name,country_id,city,region,responsible_profile_id,company_id,is_public,created_by)
 values(upper(trim(p_identifier)),trim(p_name),p_country,nullif(trim(p_city),''),nullif(trim(p_region),''),auth.uid(),p_company,p_public,auth.uid()) returning id into v;
 perform public.vehicle_audit(p_country,'driving_school',v,'requested'); return v;
end; $$;

create or replace function public.vehicle_review_school(p_school uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public,auth as $$
declare s public.driving_schools%rowtype;
begin
 select * into s from public.driving_schools where id=p_school for update;
 if not found or not (public.is_world_admin() or public.is_country_president(s.country_id)) then raise exception 'Sem permissão.'; end if;
 if s.status<>'pending' then raise exception 'Solicitação já revisada.'; end if;
 update public.driving_schools set status=case when p_approve then 'active' else 'closed' end,approved_by=auth.uid(),approved_at=now() where id=p_school;
 perform public.vehicle_audit(s.country_id,'driving_school',p_school,case when p_approve then 'approved' else 'rejected' end);
end; $$;

create or replace function public.vehicle_enroll_driving(p_school uuid,p_category text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare s public.driving_schools%rowtype; v uuid;
begin
 select * into s from public.driving_schools where id=p_school and status='active';
 if not found or not exists(select 1 from public.profiles where id=auth.uid() and role='citizen' and registration_status='active' and country_id=s.country_id) then raise exception 'Autoescola ou cidadão não elegível.'; end if;
 if not exists(select 1 from public.driving_category_rules where country_id=s.country_id and category_code=p_category and is_active) then raise exception 'Categoria não configurada.'; end if;
 insert into public.driving_enrollments(student_profile_id,school_id,country_id,category_code) values(auth.uid(),p_school,s.country_id,p_category) returning id into v;
 perform public.vehicle_audit(s.country_id,'driving_enrollment',v,'enrolled'); return v;
end; $$;

create or replace function public.vehicle_record_lesson(p_enrollment uuid,p_instructor uuid,p_duration integer,p_notes text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare e public.driving_enrollments%rowtype; i public.driving_instructors%rowtype; v uuid;
begin
 select * into e from public.driving_enrollments where id=p_enrollment and status='active';
 select * into i from public.driving_instructors where id=p_instructor and status='active';
 if e.id is null or i.id is null or i.school_id<>e.school_id or not (i.profile_id=auth.uid() or exists(select 1 from public.driving_schools s where s.id=e.school_id and s.responsible_profile_id=auth.uid())) or not (e.category_code=any(i.categories)) then raise exception 'Instrutor, matrícula ou categoria inválidos.'; end if;
 insert into public.driving_lessons(enrollment_id,instructor_id,duration_minutes,notes,completed,recorded_by) values(e.id,i.id,p_duration,p_notes,true,auth.uid()) returning id into v;
 perform public.vehicle_audit(e.country_id,'driving_lesson',v,'completed'); return v;
end; $$;

create or replace function public.vehicle_record_exam(p_enrollment uuid,p_score numeric,p_notes text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare e public.driving_enrollments%rowtype; s public.driving_schools%rowtype; r public.driving_category_rules%rowtype; n integer; v uuid; result text;
begin
 select * into e from public.driving_enrollments where id=p_enrollment and status='active' for update;
 select * into s from public.driving_schools where id=e.school_id;
 select * into r from public.driving_category_rules where country_id=e.country_id and category_code=e.category_code and is_active;
 if e.id is null or r.country_id is null or not (public.is_world_admin() or public.is_country_president(e.country_id) or s.responsible_profile_id=auth.uid()) then raise exception 'Sem permissão ou regra ausente.'; end if;
 select count(*) into n from public.driving_lessons where enrollment_id=e.id and completed;
 if n<r.minimum_lessons then raise exception 'Aulas concluídas insuficientes.'; end if;
 result:=case when p_score>=r.minimum_exam_score then 'approved' else 'failed' end;
 insert into public.driving_examinations(enrollment_id,examiner_id,score,result,notes) values(e.id,auth.uid(),p_score,result,p_notes) returning id into v;
 update public.driving_enrollments set status=case when result='approved' then 'completed' else 'active' end where id=e.id;
 if result='approved' then
  insert into public.driving_licenses(license_number,holder_profile_id,category_code,country_id,expires_at,examination_id)
  values('CNH-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,14)),e.student_profile_id,e.category_code,e.country_id,now()+make_interval(days=>r.validity_days),v);
 end if;
 perform public.vehicle_audit(e.country_id,'driving_exam',v,result); return v;
end; $$;

create or replace function public.vehicle_register_initial(p_catalog uuid,p_plate text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.vehicle_catalog%rowtype; p public.profiles%rowtype; v uuid; vnum text;
begin
 select * into p from public.profiles where id=auth.uid() and role='citizen' and registration_status='active';
 if not found or p.country_id is null then raise exception 'Cidadão ativo e país são necessários.'; end if;
 select * into c from public.vehicle_catalog where id=p_catalog and is_active=true and (country_id is null or country_id=p.country_id);
 if not found then raise exception 'Modelo indisponível.'; end if;
 vnum:='VEH-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.vehicles(vehicle_number,plate,catalog_id,brand,model,category_code,model_year,country_id,owner_profile_id,document_status)
 values(vnum,upper(trim(p_plate)),c.id,c.brand,c.model,(select code from public.vehicle_categories where id=c.category_id),c.model_year,p.country_id,p.id,'regular') returning id into v;
 insert into public.vehicle_ownership_history(vehicle_id,new_profile_id,transfer_type,actor_id) values(v,p.id,'initial_registration',auth.uid());
 insert into public.vehicle_documents(vehicle_id,document_number,document_type,issuer_country_id,issued_by,payload)
 values(v,'REG-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'registration',p.country_id,auth.uid(),jsonb_build_object('fictional',true));
 perform public.vehicle_audit(p.country_id,'vehicle',v,'registered'); return v;
end; $$;

grant execute on function public.vehicle_admin_upsert_catalog(uuid,uuid,text,text,integer,text,text,uuid,numeric,uuid,boolean) to authenticated;
grant execute on function public.vehicle_request_dealership(text,text,uuid,text,text,uuid,uuid,text) to authenticated;
grant execute on function public.vehicle_review_dealership(uuid,boolean,text) to authenticated;
grant execute on function public.vehicle_dealership_set_status(uuid,text,text) to authenticated;
grant execute on function public.vehicle_dealership_add_inventory(uuid,uuid,numeric,uuid) to authenticated;
grant execute on function public.vehicle_purchase(uuid,uuid,text) to authenticated;
grant execute on function public.vehicle_private_transfer(uuid,uuid,uuid,uuid,uuid,numeric,text) to authenticated;
grant execute on function public.vehicle_pay_fee(uuid,uuid,text) to authenticated;
grant execute on function public.vehicle_admin_set_fee(uuid,numeric,uuid,integer) to authenticated;
grant execute on function public.vehicle_request_school(text,text,uuid,text,text,uuid,boolean) to authenticated;
grant execute on function public.vehicle_review_school(uuid,boolean) to authenticated;
grant execute on function public.vehicle_enroll_driving(uuid,text) to authenticated;
grant execute on function public.vehicle_record_lesson(uuid,uuid,integer,text) to authenticated;
grant execute on function public.vehicle_record_exam(uuid,numeric,text) to authenticated;
grant execute on function public.vehicle_register_initial(uuid,text) to authenticated;

commit;
