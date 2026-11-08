-- WORLD ECONOMY — ETAPA 8: Banco Central, oferta monetária e política monetária
-- Migration aditiva. Não altera saldos do Tesouro, cidadãos ou empresas.
begin;

create table if not exists public.central_banks (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  name text not null check (length(trim(name)) between 3 and 160),
  institutional_identifier text not null unique check (institutional_identifier ~ '^[A-Z0-9][A-Z0-9._-]{2,39}$'),
  created_on date not null default current_date,
  status text not null default 'active' check (status in ('active','suspended','inactive')),
  is_primary boolean not null default true,
  description text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,country_id)
);
create unique index if not exists central_banks_one_primary_per_country
  on public.central_banks(country_id) where is_primary;
create index if not exists central_banks_country_status_idx on public.central_banks(country_id,status);

create table if not exists public.central_bank_members (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  position text not null check (length(trim(position)) between 2 and 100),
  permissions text[] not null default '{}',
  status text not null default 'active' check (status in ('active','suspended','removed')),
  appointed_by uuid not null references public.profiles(id) on delete restrict,
  appointed_at timestamptz not null default now(),
  ended_at timestamptz,
  unique(central_bank_id,profile_id),
  check (ended_at is null or ended_at >= appointed_at)
);
create index if not exists central_bank_members_profile_idx on public.central_bank_members(profile_id,status);

create table if not exists public.monetary_issuances (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  amount numeric(30,6) not null check (amount > 0),
  reason text not null check (length(trim(reason)) >= 5),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id)
);
create index if not exists monetary_issuances_country_date_idx on public.monetary_issuances(country_id,created_at desc);

create table if not exists public.monetary_withdrawals (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  amount numeric(30,6) not null check (amount > 0),
  reason text not null check (length(trim(reason)) >= 5),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id)
);
create index if not exists monetary_withdrawals_country_date_idx on public.monetary_withdrawals(country_id,created_at desc);

-- Livro-razão exclusivo da oferta monetária. Não representa saldos bancários ou do Tesouro.
create table if not exists public.money_supply_records (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  operation_type text not null check (operation_type in ('issuance','withdrawal')),
  amount numeric(30,6) not null check (amount > 0),
  source_request_id uuid not null,
  reason text not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique(operation_type,source_request_id)
);
create index if not exists money_supply_country_date_idx on public.money_supply_records(country_id,created_at desc);

create table if not exists public.central_bank_reserves (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  direction text not null check (direction in ('increase','decrease')),
  amount numeric(30,6) not null check (amount > 0),
  national_amount numeric(30,6) not null check (national_amount > 0),
  exchange_rate_id uuid references public.exchange_rates(id) on delete restrict,
  asset_type text not null check (length(trim(asset_type)) between 2 and 80),
  description text not null check (length(trim(description)) >= 3),
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id)
);
create index if not exists central_bank_reserves_country_date_idx on public.central_bank_reserves(country_id,created_at desc);

create table if not exists public.interest_rate_records (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  annual_rate numeric(12,6) not null check (annual_rate between 0 and 10000),
  effective_from date not null,
  effective_until date,
  status text not null default 'pending' check (status in ('pending','active','rejected','superseded')),
  previous_rate numeric(12,6),
  justification text not null check (length(trim(justification)) >= 5),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id),
  check (effective_until is null or effective_until > effective_from)
);
create index if not exists interest_rate_country_effective_idx on public.interest_rate_records(country_id,effective_from desc);

create table if not exists public.monetary_policies (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  name text not null check (length(trim(name)) between 3 and 160),
  objective text not null check (length(trim(objective)) >= 5),
  description text not null check (length(trim(description)) >= 5),
  indicators jsonb not null default '[]'::jsonb check (jsonb_typeof(indicators)='array'),
  starts_on date not null,
  expected_end date,
  status text not null default 'proposed' check (status in ('proposed','active','completed','suspended','cancelled')),
  observed_result text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id),
  check (expected_end is null or expected_end >= starts_on)
);
create index if not exists monetary_policies_country_date_idx on public.monetary_policies(country_id,starts_on desc);

create table if not exists public.inflation_targets (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  target_rate numeric(12,6) not null check (target_rate between -100 and 10000),
  tolerance numeric(12,6) not null default 0 check (tolerance between 0 and 1000),
  period_type text not null check (period_type in ('monthly','annual')),
  effective_from date not null,
  effective_until date,
  justification text not null check (length(trim(justification)) >= 5),
  status text not null default 'pending' check (status in ('pending','active','rejected','superseded')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id),
  check (effective_until is null or effective_until > effective_from)
);
create index if not exists inflation_targets_country_date_idx on public.inflation_targets(country_id,effective_from desc);

create table if not exists public.central_bank_decisions (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid not null references public.central_banks(id) on delete restrict,
  country_id uuid not null references public.countries(id) on delete restrict,
  decision_type text not null check (decision_type in ('monetary_policy','exchange_policy','reserve_management','supervision','other')),
  title text not null check (length(trim(title)) between 3 and 160),
  description text not null check (length(trim(description)) >= 5),
  justification text not null check (length(trim(justification)) >= 5),
  status text not null default 'published' check (status in ('draft','published','cancelled')),
  decided_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  foreign key(central_bank_id,country_id) references public.central_banks(id,country_id)
);
create index if not exists central_bank_decisions_country_date_idx on public.central_bank_decisions(country_id,created_at desc);

create table if not exists public.central_bank_audit_logs (
  id uuid primary key default gen_random_uuid(),
  central_bank_id uuid references public.central_banks(id) on delete restrict,
  country_id uuid references public.countries(id) on delete restrict,
  actor_id uuid references public.profiles(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  justification text,
  created_at timestamptz not null default now()
);
create index if not exists central_bank_audit_date_idx on public.central_bank_audit_logs(created_at desc);
create index if not exists central_bank_audit_country_idx on public.central_bank_audit_logs(country_id,created_at desc);

create table if not exists public.central_bank_settings (
  central_bank_id uuid primary key references public.central_banks(id) on delete restrict,
  issuance_requires_approval boolean not null default true,
  withdrawal_requires_approval boolean not null default true,
  max_issuance_per_operation numeric(30,6),
  max_issuance_total numeric(30,6),
  updated_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now(),
  check (max_issuance_per_operation is null or max_issuance_per_operation > 0),
  check (max_issuance_total is null or max_issuance_total > 0)
);

create or replace function public.has_central_bank_permission(p_country_id uuid,p_permission text)
returns boolean language sql stable security definer set search_path=public,auth as $function$
  select public.is_world_admin() or exists (
    select 1 from public.central_bank_members m
    join public.central_banks b on b.id=m.central_bank_id
    where b.country_id=p_country_id and b.status='active' and m.profile_id=auth.uid()
      and m.status='active' and (p_permission=any(m.permissions) or 'central_bank.manage'=any(m.permissions))
  );
$function$;

create or replace function public.central_bank_audit(
  p_bank_id uuid,p_country_id uuid,p_action text,p_entity_type text,p_entity_id uuid,
  p_old jsonb,p_new jsonb,p_justification text
) returns void language sql security definer set search_path=public,auth as $function$
  insert into public.central_bank_audit_logs(central_bank_id,country_id,actor_id,action,entity_type,entity_id,old_values,new_values,justification)
  values(p_bank_id,p_country_id,auth.uid(),p_action,p_entity_type,p_entity_id,p_old,p_new,p_justification);
$function$;

create or replace function public.sync_central_bank_currency_from_country()
returns trigger language plpgsql security definer set search_path=public as $function$
declare v_currency_id uuid;
begin
  if old.currency_code is distinct from new.currency_code then
    select id into v_currency_id from public.currencies where internal_code=new.currency_code and status='active' limit 1;
    if v_currency_id is not null then
      update public.central_banks set currency_id=v_currency_id,updated_at=now() where country_id=new.id;
      insert into public.central_bank_audit_logs(central_bank_id,country_id,actor_id,action,entity_type,new_values,justification)
      select id,new.id,auth.uid(),'national_currency_synchronized','central_bank',
        jsonb_build_object('currency_id',v_currency_id,'currency_code',new.currency_code),
        'Sincronização automática com a moeda nacional da Etapa 7'
      from public.central_banks where country_id=new.id;
    end if;
  end if;
  return new;
end;
$function$;
drop trigger if exists countries_sync_central_bank_currency on public.countries;
create trigger countries_sync_central_bank_currency after update of currency_code on public.countries
for each row when (old.currency_code is distinct from new.currency_code)
execute function public.sync_central_bank_currency_from_country();
revoke all on function public.sync_central_bank_currency_from_country() from public,anon,authenticated;

create or replace function public.admin_create_central_bank(
  p_country_id uuid,p_name text,p_identifier text,p_description text default null,p_is_primary boolean default true
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.countries%rowtype; cur public.currencies%rowtype; v_id uuid;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode criar Bancos Centrais.'; end if;
  if length(trim(coalesce(p_name,'')))<3 or length(trim(coalesce(p_identifier,'')))<3 then raise exception 'Nome e identificador são obrigatórios.'; end if;
  select * into c from public.countries where id=p_country_id for update;
  if not found then raise exception 'País não encontrado.'; end if;
  select * into cur from public.currencies where internal_code=c.currency_code and status='active' limit 1;
  if not found then raise exception 'O país precisa ter uma moeda nacional ativa configurada na Etapa 7.'; end if;
  if p_is_primary and exists(select 1 from public.central_banks where country_id=p_country_id and is_primary) then
    raise exception 'Este país já possui um Banco Central principal.';
  end if;
  insert into public.central_banks(country_id,currency_id,name,institutional_identifier,description,is_primary,created_by)
  values(p_country_id,cur.id,trim(p_name),upper(trim(p_identifier)),nullif(trim(p_description),''),coalesce(p_is_primary,true),auth.uid())
  returning id into v_id;
  insert into public.central_bank_settings(central_bank_id) values(v_id);
  perform public.central_bank_audit(v_id,p_country_id,'created','central_bank',v_id,null,to_jsonb(v_id),'Criação institucional');
  return v_id;
end;
$function$;

create or replace function public.admin_set_central_bank_status(p_bank_id uuid,p_status text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode alterar a situação institucional.'; end if;
  if p_status not in ('active','suspended','inactive') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'Situação ou justificativa inválida.'; end if;
  select * into b from public.central_banks where id=p_bank_id for update;
  if not found then raise exception 'Banco Central não encontrado.'; end if;
  update public.central_banks set status=p_status,updated_at=now() where id=p_bank_id;
  perform public.central_bank_audit(b.id,b.country_id,'status_changed','central_bank',b.id,to_jsonb(b),jsonb_build_object('status',p_status),p_reason);
end;
$function$;

create or replace function public.admin_set_central_bank_settings(
  p_bank_id uuid,p_issuance_approval boolean,p_withdrawal_approval boolean,
  p_max_operation numeric,p_max_total numeric
) returns void language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; old_row public.central_bank_settings%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode definir limites e aprovações.'; end if;
  if (p_max_operation is not null and p_max_operation<=0) or (p_max_total is not null and p_max_total<=0) then raise exception 'Limites devem ser positivos.'; end if;
  select * into b from public.central_banks where id=p_bank_id for update;
  if not found then raise exception 'Banco Central não encontrado.'; end if;
  select * into old_row from public.central_bank_settings where central_bank_id=p_bank_id for update;
  update public.central_bank_settings set issuance_requires_approval=p_issuance_approval,
    withdrawal_requires_approval=p_withdrawal_approval,max_issuance_per_operation=p_max_operation,
    max_issuance_total=p_max_total,updated_by=auth.uid(),updated_at=now() where central_bank_id=p_bank_id;
  perform public.central_bank_audit(b.id,b.country_id,'settings_changed','central_bank_settings',b.id,to_jsonb(old_row),
    jsonb_build_object('issuance_requires_approval',p_issuance_approval,'withdrawal_requires_approval',p_withdrawal_approval,
      'max_issuance_per_operation',p_max_operation,'max_issuance_total',p_max_total),'Configuração monetária');
end;
$function$;

create or replace function public.admin_set_central_bank_member(
  p_bank_id uuid,p_profile_id uuid,p_position text,p_permissions text[],p_status text
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; m public.central_bank_members%rowtype; v_id uuid;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode nomear dirigentes.'; end if;
  if p_status not in ('active','suspended','removed') or length(trim(coalesce(p_position,'')))<2 then raise exception 'Cargo ou situação inválidos.'; end if;
  if not exists(select 1 from public.profiles where id=p_profile_id) then raise exception 'Perfil não encontrado.'; end if;
  select * into b from public.central_banks where id=p_bank_id for update;
  if not found then raise exception 'Banco Central não encontrado.'; end if;
  select * into m from public.central_bank_members where central_bank_id=p_bank_id and profile_id=p_profile_id for update;
  if found then
    update public.central_bank_members set position=trim(p_position),permissions=coalesce(p_permissions,'{}'),
      status=p_status,ended_at=case when p_status='active' then null else now() end where id=m.id returning id into v_id;
    perform public.central_bank_audit(b.id,b.country_id,'member_updated','central_bank_member',m.id,to_jsonb(m),
      jsonb_build_object('position',p_position,'permissions',p_permissions,'status',p_status),'Atualização de dirigente');
  else
    insert into public.central_bank_members(central_bank_id,profile_id,position,permissions,status,appointed_by,ended_at)
    values(p_bank_id,p_profile_id,trim(p_position),coalesce(p_permissions,'{}'),p_status,auth.uid(),
      case when p_status='active' then null else now() end) returning id into v_id;
    perform public.central_bank_audit(b.id,b.country_id,'member_appointed','central_bank_member',v_id,null,
      jsonb_build_object('profile_id',p_profile_id,'position',p_position,'permissions',p_permissions,'status',p_status),'Nomeação de dirigente');
  end if;
  return v_id;
end;
$function$;

create or replace function public.request_monetary_issuance(p_bank_id uuid,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; s public.central_bank_settings%rowtype; v_id uuid; v_total numeric;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if p_amount is null or p_amount<=0 or p_amount>999999999999999999999999::numeric or length(trim(coalesce(p_reason,'')))<5 then raise exception 'Quantidade ou justificativa inválida.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active' for update;
  if not found then raise exception 'Banco Central indisponível.'; end if;
  if not public.has_central_bank_permission(b.country_id,'issuance.request') then raise exception 'Sem permissão para solicitar emissão.'; end if;
  select * into s from public.central_bank_settings where central_bank_id=b.id;
  if s.max_issuance_per_operation is not null and p_amount>s.max_issuance_per_operation then raise exception 'A operação excede o limite por emissão.'; end if;
  select coalesce(sum(amount),0) into v_total from public.money_supply_records where country_id=b.country_id and operation_type='issuance';
  if s.max_issuance_total is not null and v_total+p_amount>s.max_issuance_total then raise exception 'A emissão excede o limite total configurado.'; end if;
  insert into public.monetary_issuances(central_bank_id,country_id,currency_id,amount,reason,requested_by)
  values(b.id,b.country_id,b.currency_id,p_amount,trim(p_reason),auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'issuance_requested','monetary_issuance',v_id,null,jsonb_build_object('amount',p_amount),p_reason);
  return v_id;
end;
$function$;

create or replace function public.admin_review_monetary_issuance(p_request_id uuid,p_approve boolean,p_note text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.monetary_issuances%rowtype; s public.central_bank_settings%rowtype; v_total numeric;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode aprovar emissões.'; end if;
  select * into r from public.monetary_issuances where id=p_request_id for update;
  if not found or r.status<>'pending' then raise exception 'Solicitação inexistente ou já revisada.'; end if;
  select * into s from public.central_bank_settings where central_bank_id=r.central_bank_id;
  if p_approve then
    select coalesce(sum(amount),0) into v_total from public.money_supply_records where country_id=r.country_id and operation_type='issuance';
    if s.max_issuance_total is not null and v_total+r.amount>s.max_issuance_total then raise exception 'O limite total de emissão foi atingido.'; end if;
    insert into public.money_supply_records(central_bank_id,country_id,currency_id,operation_type,amount,source_request_id,reason,actor_id)
    values(r.central_bank_id,r.country_id,r.currency_id,'issuance',r.amount,r.id,r.reason,auth.uid());
    update public.monetary_issuances set status='approved',approved_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=r.id;
  else
    update public.monetary_issuances set status='rejected',approved_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=r.id;
  end if;
  perform public.central_bank_audit(r.central_bank_id,r.country_id,case when p_approve then 'issuance_approved' else 'issuance_rejected' end,
    'monetary_issuance',r.id,to_jsonb(r),jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'note',p_note),p_note);
end;
$function$;

create or replace function public.request_monetary_withdrawal(p_bank_id uuid,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; s public.central_bank_settings%rowtype; v_id uuid; v_supply numeric; v_pending numeric;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if p_amount is null or p_amount<=0 or length(trim(coalesce(p_reason,'')))<5 then raise exception 'Quantidade ou justificativa inválida.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active' for update;
  if not found then raise exception 'Banco Central indisponível.'; end if;
  if not public.has_central_bank_permission(b.country_id,'withdrawal.request') then raise exception 'Sem permissão para solicitar retirada.'; end if;
  select coalesce(sum(case when operation_type='issuance' then amount else -amount end),0) into v_supply from public.money_supply_records where country_id=b.country_id;
  select coalesce(sum(amount),0) into v_pending from public.monetary_withdrawals where country_id=b.country_id and status='pending';
  if p_amount>v_supply-v_pending then raise exception 'A retirada supera a oferta monetária disponível.'; end if;
  insert into public.monetary_withdrawals(central_bank_id,country_id,currency_id,amount,reason,requested_by)
  values(b.id,b.country_id,b.currency_id,p_amount,trim(p_reason),auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'withdrawal_requested','monetary_withdrawal',v_id,null,jsonb_build_object('amount',p_amount),p_reason);
  return v_id;
end;
$function$;

create or replace function public.admin_review_monetary_withdrawal(p_request_id uuid,p_approve boolean,p_note text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.monetary_withdrawals%rowtype; v_supply numeric; v_pending numeric;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode aprovar retiradas.'; end if;
  select * into r from public.monetary_withdrawals where id=p_request_id for update;
  if not found or r.status<>'pending' then raise exception 'Solicitação inexistente ou já revisada.'; end if;
  if p_approve then
    select coalesce(sum(case when operation_type='issuance' then amount else -amount end),0) into v_supply from public.money_supply_records where country_id=r.country_id;
    select coalesce(sum(amount),0) into v_pending from public.monetary_withdrawals where country_id=r.country_id and status='pending' and id<>r.id;
    if r.amount>v_supply-v_pending then raise exception 'A oferta disponível mudou; a retirada não pode ser aprovada.'; end if;
    insert into public.money_supply_records(central_bank_id,country_id,currency_id,operation_type,amount,source_request_id,reason,actor_id)
    values(r.central_bank_id,r.country_id,r.currency_id,'withdrawal',r.amount,r.id,r.reason,auth.uid());
    update public.monetary_withdrawals set status='approved',approved_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=r.id;
  else
    update public.monetary_withdrawals set status='rejected',approved_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=r.id;
  end if;
  perform public.central_bank_audit(r.central_bank_id,r.country_id,case when p_approve then 'withdrawal_approved' else 'withdrawal_rejected' end,
    'monetary_withdrawal',r.id,to_jsonb(r),jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'note',p_note),p_note);
end;
$function$;

create or replace function public.record_central_bank_reserve(
  p_bank_id uuid,p_currency_id uuid,p_direction text,p_amount numeric,p_asset_type text,p_description text
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; c public.currencies%rowtype; v_national numeric; v_conversion jsonb; v_rate_id uuid; v_id uuid; v_existing numeric;
begin
  if p_direction not in ('increase','decrease') or p_amount is null or p_amount<=0 or length(trim(coalesce(p_asset_type,'')))<2 or length(trim(coalesce(p_description,'')))<3 then raise exception 'Dados da reserva inválidos.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active' for update;
  if not found or not public.has_central_bank_permission(b.country_id,'reserves.manage') then raise exception 'Banco Central indisponível ou sem permissão.'; end if;
  select * into c from public.currencies where id=p_currency_id and status='active';
  if not found then raise exception 'Moeda de reserva indisponível.'; end if;
  if c.id=b.currency_id then v_national:=round(p_amount,6);
  else
    v_conversion:=public.convert_currency_amount(p_amount,p_currency_id,b.currency_id,now());
    v_national:=(v_conversion->>'amount')::numeric;
    v_rate_id:=nullif(v_conversion->>'rate_id','')::uuid;
  end if;
  select coalesce(sum(case when direction='increase' then national_amount else -national_amount end),0) into v_existing from public.central_bank_reserves where central_bank_id=b.id;
  if p_direction='decrease' and v_national>v_existing then raise exception 'A retirada supera as reservas disponíveis.'; end if;
  insert into public.central_bank_reserves(central_bank_id,country_id,currency_id,direction,amount,national_amount,exchange_rate_id,asset_type,description,recorded_by)
  values(b.id,b.country_id,c.id,p_direction,p_amount,v_national,v_rate_id,trim(p_asset_type),trim(p_description),auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'reserve_'||p_direction,'central_bank_reserve',v_id,null,
    jsonb_build_object('currency_id',c.id,'amount',p_amount,'national_amount',v_national,'exchange_rate_id',v_rate_id,'asset_type',p_asset_type),p_description);
  return v_id;
end;
$function$;

create or replace function public.request_interest_rate_change(p_bank_id uuid,p_annual_rate numeric,p_effective_from date,p_justification text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; v_old numeric; v_id uuid;
begin
  if p_annual_rate is null or p_annual_rate<0 or p_annual_rate>10000 or p_effective_from is null or length(trim(coalesce(p_justification,'')))<5 then raise exception 'Taxa, vigência ou justificativa inválida.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active' for update;
  if not found or not public.has_central_bank_permission(b.country_id,'interest.manage') then raise exception 'Sem permissão para propor taxa de juros.'; end if;
  select annual_rate into v_old from public.interest_rate_records where country_id=b.country_id and status='active' and effective_from<=current_date and (effective_until is null or effective_until>current_date) order by effective_from desc limit 1;
  insert into public.interest_rate_records(central_bank_id,country_id,annual_rate,effective_from,previous_rate,justification,requested_by)
  values(b.id,b.country_id,p_annual_rate,p_effective_from,v_old,trim(p_justification),auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'interest_rate_proposed','interest_rate',v_id,null,jsonb_build_object('annual_rate',p_annual_rate,'previous_rate',v_old,'effective_from',p_effective_from),p_justification);
  return v_id;
end;
$function$;

create or replace function public.admin_review_interest_rate_change(p_record_id uuid,p_approve boolean,p_note text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.interest_rate_records%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode aprovar taxas básicas.'; end if;
  select * into r from public.interest_rate_records where id=p_record_id for update;
  if not found or r.status<>'pending' then raise exception 'Proposta inexistente ou já revisada.'; end if;
  if p_approve then
    update public.interest_rate_records set effective_until=r.effective_from,status='superseded'
      where country_id=r.country_id and status='active' and effective_from<r.effective_from and (effective_until is null or effective_until>r.effective_from);
    update public.interest_rate_records set status='active',approved_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=r.id;
  else
    update public.interest_rate_records set status='rejected',approved_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'') where id=r.id;
  end if;
  perform public.central_bank_audit(r.central_bank_id,r.country_id,case when p_approve then 'interest_rate_approved' else 'interest_rate_rejected' end,
    'interest_rate',r.id,to_jsonb(r),jsonb_build_object('status',case when p_approve then 'active' else 'rejected' end,'note',p_note),p_note);
end;
$function$;

create or replace function public.create_monetary_policy(
  p_bank_id uuid,p_name text,p_objective text,p_description text,p_indicators jsonb,p_starts_on date,p_expected_end date
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; v_id uuid;
begin
  if length(trim(coalesce(p_name,'')))<3 or length(trim(coalesce(p_objective,'')))<5 or length(trim(coalesce(p_description,'')))<5 or p_starts_on is null or (p_expected_end is not null and p_expected_end<p_starts_on) then raise exception 'Dados da política monetária inválidos.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active';
  if not found or not public.has_central_bank_permission(b.country_id,'policy.manage') then raise exception 'Sem permissão para registrar política monetária.'; end if;
  insert into public.monetary_policies(central_bank_id,country_id,name,objective,description,indicators,starts_on,expected_end,created_by)
  values(b.id,b.country_id,trim(p_name),trim(p_objective),trim(p_description),coalesce(p_indicators,'[]'),p_starts_on,p_expected_end,auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'policy_created','monetary_policy',v_id,null,jsonb_build_object('name',p_name,'objective',p_objective,'starts_on',p_starts_on),p_description);
  return v_id;
end;
$function$;

create or replace function public.admin_review_monetary_policy(p_policy_id uuid,p_status text,p_result text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare p public.monetary_policies%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode publicar ou alterar a situação das políticas.'; end if;
  if p_status not in ('active','completed','suspended','cancelled') then raise exception 'Situação inválida.'; end if;
  select * into p from public.monetary_policies where id=p_policy_id for update;
  if not found then raise exception 'Política não encontrada.'; end if;
  update public.monetary_policies set status=p_status,observed_result=nullif(trim(p_result),''),updated_at=now() where id=p.id;
  perform public.central_bank_audit(p.central_bank_id,p.country_id,'policy_status_changed','monetary_policy',p.id,to_jsonb(p),jsonb_build_object('status',p_status,'observed_result',p_result),p_result);
end;
$function$;

create or replace function public.request_inflation_target(
  p_bank_id uuid,p_target_rate numeric,p_tolerance numeric,p_period_type text,p_effective_from date,p_effective_until date,p_justification text
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; v_id uuid;
begin
  if p_target_rate not between -100 and 10000 or p_tolerance<0 or p_period_type not in ('monthly','annual') or p_effective_from is null or (p_effective_until is not null and p_effective_until<=p_effective_from) or length(trim(coalesce(p_justification,'')))<5 then raise exception 'Meta de inflação inválida.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active';
  if not found or not public.has_central_bank_permission(b.country_id,'targets.manage') then raise exception 'Sem permissão para propor meta de inflação.'; end if;
  insert into public.inflation_targets(central_bank_id,country_id,target_rate,tolerance,period_type,effective_from,effective_until,justification,created_by)
  values(b.id,b.country_id,p_target_rate,p_tolerance,p_period_type,p_effective_from,p_effective_until,trim(p_justification),auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'inflation_target_proposed','inflation_target',v_id,null,jsonb_build_object('target_rate',p_target_rate,'tolerance',p_tolerance,'period_type',p_period_type,'effective_from',p_effective_from),p_justification);
  return v_id;
end;
$function$;

create or replace function public.admin_review_inflation_target(p_target_id uuid,p_approve boolean,p_note text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare t public.inflation_targets%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode aprovar metas de inflação.'; end if;
  select * into t from public.inflation_targets where id=p_target_id for update;
  if not found or t.status<>'pending' then raise exception 'Meta inexistente ou já revisada.'; end if;
  if p_approve then
    update public.inflation_targets set effective_until=t.effective_from,status='superseded'
      where country_id=t.country_id and status='active' and period_type=t.period_type and effective_from<t.effective_from and (effective_until is null or effective_until>t.effective_from);
    update public.inflation_targets set status='active',approved_by=auth.uid(),reviewed_at=now() where id=t.id;
  else
    update public.inflation_targets set status='rejected',approved_by=auth.uid(),reviewed_at=now() where id=t.id;
  end if;
  perform public.central_bank_audit(t.central_bank_id,t.country_id,case when p_approve then 'inflation_target_approved' else 'inflation_target_rejected' end,
    'inflation_target',t.id,to_jsonb(t),jsonb_build_object('status',case when p_approve then 'active' else 'rejected' end,'note',p_note),p_note);
end;
$function$;

create or replace function public.record_central_bank_decision(
  p_bank_id uuid,p_type text,p_title text,p_description text,p_justification text,p_publish boolean
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.central_banks%rowtype; v_id uuid;
begin
  if p_type not in ('monetary_policy','exchange_policy','reserve_management','supervision','other') or length(trim(coalesce(p_title,'')))<3 or length(trim(coalesce(p_description,'')))<5 or length(trim(coalesce(p_justification,'')))<5 then raise exception 'Decisão inválida.'; end if;
  select * into b from public.central_banks where id=p_bank_id and status='active';
  if not found or not public.has_central_bank_permission(b.country_id,'decisions.manage') then raise exception 'Sem permissão para registrar decisão.'; end if;
  insert into public.central_bank_decisions(central_bank_id,country_id,decision_type,title,description,justification,status,decided_by)
  values(b.id,b.country_id,p_type,trim(p_title),trim(p_description),trim(p_justification),case when p_publish then 'published' else 'draft' end,auth.uid()) returning id into v_id;
  perform public.central_bank_audit(b.id,b.country_id,'decision_recorded','central_bank_decision',v_id,null,jsonb_build_object('type',p_type,'title',p_title,'status',case when p_publish then 'published' else 'draft' end),p_justification);
  return v_id;
end;
$function$;

create or replace function public.get_central_bank_dashboard(p_country_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,auth as $function$
declare v_country uuid; v_bank public.central_banks%rowtype; v_data jsonb; v_economy jsonb; v_can_manage boolean; v_ref_currency_id uuid; v_ref_conversion jsonb;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if public.is_world_admin() then
    v_country:=p_country_id;
  else
    select country_id into v_country from public.profiles where id=auth.uid();
    if v_country is null or (p_country_id is not null and p_country_id<>v_country) then raise exception 'Acesso restrito ao país da conta.'; end if;
  end if;
  if v_country is null then
    if not public.is_world_admin() then raise exception 'País não definido.'; end if;
    return jsonb_build_object('banks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'country_id',b.country_id,'country_name',c.name,'name',b.name,'status',b.status,'currency_id',b.currency_id,'currency_code',cu.internal_code,'currency_name',cu.name,'is_primary',b.is_primary) order by c.name) from public.central_banks b join public.countries c on c.id=b.country_id join public.currencies cu on cu.id=b.currency_id),'[]'::jsonb));
  end if;
  select * into v_bank from public.central_banks where country_id=v_country and is_primary order by created_at limit 1;
  if not found then return jsonb_build_object('bank',null,'country_id',v_country,'message','Este país ainda não possui Banco Central cadastrado.'); end if;
  v_can_manage:=public.has_central_bank_permission(v_country,'dashboard.manage');
  v_economy:=public.get_economy_dashboard(v_country);
  select reference_currency_id into v_ref_currency_id from public.currency_system_settings where singleton=true;
  if v_can_manage and v_ref_currency_id is not null then
    begin
      v_ref_conversion:=public.convert_currency_amount(
        coalesce((select sum(case when direction='increase' then national_amount else -national_amount end) from public.central_bank_reserves where central_bank_id=v_bank.id),0),
        v_bank.currency_id,v_ref_currency_id,now()
      );
    exception when others then
      v_ref_conversion:=jsonb_build_object('error','Cotação de referência indisponível');
    end;
  end if;
  select jsonb_build_object(
    'bank',jsonb_build_object('id',v_bank.id,'country_id',v_bank.country_id,'name',v_bank.name,'institutional_identifier',v_bank.institutional_identifier,'status',v_bank.status,'description',v_bank.description,'created_on',v_bank.created_on,'currency_id',v_bank.currency_id,'currency_code',cu.internal_code,'currency_name',cu.name,'currency_symbol',cu.symbol),
    'supply',jsonb_build_object(
      'issued',coalesce((select sum(amount) from public.money_supply_records where country_id=v_country and operation_type='issuance'),0),
      'withdrawn',coalesce((select sum(amount) from public.money_supply_records where country_id=v_country and operation_type='withdrawal'),0),
      'circulating',coalesce((select sum(case when operation_type='issuance' then amount else -amount end) from public.money_supply_records where country_id=v_country),0)
    ),
    'reserves',case when v_can_manage then coalesce((select jsonb_agg(jsonb_build_object('currency_id',r.currency_id,'currency_code',c.internal_code,'currency_name',c.name,'asset_type',r.asset_type,'amount',r.amount,'national_amount',r.national_amount,'direction',r.direction,'exchange_rate_id',r.exchange_rate_id,'created_at',r.created_at) order by r.created_at desc) from public.central_bank_reserves r join public.currencies c on c.id=r.currency_id where r.central_bank_id=v_bank.id),'[]'::jsonb) else '[]'::jsonb end,
    'reserve_total',case when v_can_manage then coalesce((select sum(case when direction='increase' then national_amount else -national_amount end) from public.central_bank_reserves where central_bank_id=v_bank.id),0) else null end,\n    'reference_currency_id',v_ref_currency_id,'reserve_reference_conversion',v_ref_conversion,
    'interest_rate',(select annual_rate from public.interest_rate_records where country_id=v_country and status='active' and effective_from<=current_date and (effective_until is null or effective_until>current_date) order by effective_from desc limit 1),
    'interest_history',coalesce((select jsonb_agg(to_jsonb(i) order by i.effective_from desc) from public.interest_rate_records i where i.country_id=v_country and (v_can_manage or i.status='active')),'[]'::jsonb),
    'inflation',v_economy->'inflation','ipc',v_economy->'ipc','inflation_history',v_economy->'inflation_history',
    'inflation_targets',coalesce((select jsonb_agg(to_jsonb(t) order by t.effective_from desc) from public.inflation_targets t where t.country_id=v_country and (v_can_manage or t.status='active')),'[]'::jsonb),
    'policies',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.monetary_policies p where p.country_id=v_country and (v_can_manage or p.status in ('active','completed'))),'[]'::jsonb),
    'decisions',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from public.central_bank_decisions d where d.country_id=v_country and (v_can_manage or d.status='published')),'[]'::jsonb),
    'issuances',case when v_can_manage then coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.monetary_issuances i where i.country_id=v_country),'[]'::jsonb) else '[]'::jsonb end,
    'withdrawals',case when v_can_manage then coalesce((select jsonb_agg(to_jsonb(w) order by w.created_at desc) from public.monetary_withdrawals w where w.country_id=v_country),'[]'::jsonb) else '[]'::jsonb end,
    'members',case when public.is_world_admin() or v_can_manage then coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'profile_id',m.profile_id,'position',m.position,'permissions',m.permissions,'status',m.status,'appointed_at',m.appointed_at) order by m.appointed_at desc) from public.central_bank_members m where m.central_bank_id=v_bank.id),'[]'::jsonb) else '[]'::jsonb end,
    'audit',case when public.is_world_admin() or v_can_manage then coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.central_bank_audit_logs a where a.country_id=v_country),'[]'::jsonb) else '[]'::jsonb end,
    'settings',case when public.is_world_admin() then (select to_jsonb(s) from public.central_bank_settings s where s.central_bank_id=v_bank.id) else null end,
    'can_manage',v_can_manage
  ) into v_data from public.currencies cu where cu.id=v_bank.currency_id;
  return v_data;
end;
$function$;

alter table public.central_banks enable row level security;
alter table public.central_bank_members enable row level security;
alter table public.monetary_issuances enable row level security;
alter table public.monetary_withdrawals enable row level security;
alter table public.money_supply_records enable row level security;
alter table public.central_bank_reserves enable row level security;
alter table public.interest_rate_records enable row level security;
alter table public.monetary_policies enable row level security;
alter table public.inflation_targets enable row level security;
alter table public.central_bank_decisions enable row level security;
alter table public.central_bank_audit_logs enable row level security;
alter table public.central_bank_settings enable row level security;

drop policy if exists central_banks_read on public.central_banks;
create policy central_banks_read on public.central_banks for select to authenticated
using (status='active' or public.is_world_admin() or public.has_central_bank_permission(country_id,'dashboard.manage'));
drop policy if exists central_bank_members_read on public.central_bank_members;
create policy central_bank_members_read on public.central_bank_members for select to authenticated
using (profile_id=auth.uid() or public.is_world_admin() or exists(select 1 from public.central_banks b where b.id=central_bank_id and public.has_central_bank_permission(b.country_id,'dashboard.manage')));
drop policy if exists central_bank_issuances_read on public.monetary_issuances;
create policy central_bank_issuances_read on public.monetary_issuances for select to authenticated
using (public.is_world_admin() or public.has_central_bank_permission(country_id,'issuance.request'));
drop policy if exists central_bank_withdrawals_read on public.monetary_withdrawals;
create policy central_bank_withdrawals_read on public.monetary_withdrawals for select to authenticated
using (public.is_world_admin() or public.has_central_bank_permission(country_id,'withdrawal.request'));
drop policy if exists money_supply_public_read on public.money_supply_records;
create policy money_supply_public_read on public.money_supply_records for select to authenticated
using (public.is_world_admin() or public.has_central_bank_permission(country_id,'dashboard.manage'));
drop policy if exists central_bank_reserves_read on public.central_bank_reserves;
create policy central_bank_reserves_read on public.central_bank_reserves for select to authenticated
using (public.is_world_admin() or public.has_central_bank_permission(country_id,'reserves.manage'));
drop policy if exists interest_rates_read on public.interest_rate_records;
create policy interest_rates_read on public.interest_rate_records for select to authenticated
using (status='active' or public.is_world_admin() or public.has_central_bank_permission(country_id,'interest.manage'));
drop policy if exists monetary_policies_read on public.monetary_policies;
create policy monetary_policies_read on public.monetary_policies for select to authenticated
using (status in ('active','completed') or public.is_world_admin() or public.has_central_bank_permission(country_id,'policy.manage'));
drop policy if exists inflation_targets_read on public.inflation_targets;
create policy inflation_targets_read on public.inflation_targets for select to authenticated
using (status='active' or public.is_world_admin() or public.has_central_bank_permission(country_id,'targets.manage'));
drop policy if exists central_bank_decisions_read on public.central_bank_decisions;
create policy central_bank_decisions_read on public.central_bank_decisions for select to authenticated
using (status='published' or public.is_world_admin() or public.has_central_bank_permission(country_id,'decisions.manage'));
drop policy if exists central_bank_audit_read on public.central_bank_audit_logs;
create policy central_bank_audit_read on public.central_bank_audit_logs for select to authenticated
using (public.is_world_admin() or (country_id is not null and public.has_central_bank_permission(country_id,'audit.read')));
drop policy if exists central_bank_settings_read on public.central_bank_settings;
create policy central_bank_settings_read on public.central_bank_settings for select to authenticated
using (public.is_world_admin());

revoke all on public.central_banks,public.central_bank_members,public.monetary_issuances,public.monetary_withdrawals,
 public.money_supply_records,public.central_bank_reserves,public.interest_rate_records,public.monetary_policies,
 public.inflation_targets,public.central_bank_decisions,public.central_bank_audit_logs,public.central_bank_settings
 from public,anon,authenticated;
grant select on public.central_banks,public.central_bank_members,public.monetary_issuances,public.monetary_withdrawals,
 public.money_supply_records,public.central_bank_reserves,public.interest_rate_records,public.monetary_policies,
 public.inflation_targets,public.central_bank_decisions,public.central_bank_audit_logs,public.central_bank_settings to authenticated;

revoke all on function public.has_central_bank_permission(uuid,text) from public,anon;
revoke all on function public.central_bank_audit(uuid,uuid,text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated;
revoke all on function public.admin_create_central_bank(uuid,text,text,text,boolean) from public,anon;
revoke all on function public.admin_set_central_bank_status(uuid,text,text) from public,anon;
revoke all on function public.admin_set_central_bank_settings(uuid,boolean,boolean,numeric,numeric) from public,anon;
revoke all on function public.admin_set_central_bank_member(uuid,uuid,text,text[],text) from public,anon;
revoke all on function public.request_monetary_issuance(uuid,numeric,text) from public,anon;
revoke all on function public.admin_review_monetary_issuance(uuid,boolean,text) from public,anon;
revoke all on function public.request_monetary_withdrawal(uuid,numeric,text) from public,anon;
revoke all on function public.admin_review_monetary_withdrawal(uuid,boolean,text) from public,anon;
revoke all on function public.record_central_bank_reserve(uuid,uuid,text,numeric,text,text) from public,anon;
revoke all on function public.request_interest_rate_change(uuid,numeric,date,text) from public,anon;
revoke all on function public.admin_review_interest_rate_change(uuid,boolean,text) from public,anon;
revoke all on function public.create_monetary_policy(uuid,text,text,text,jsonb,date,date) from public,anon;
revoke all on function public.admin_review_monetary_policy(uuid,text,text) from public,anon;
revoke all on function public.request_inflation_target(uuid,numeric,numeric,text,date,date,text) from public,anon;
revoke all on function public.admin_review_inflation_target(uuid,boolean,text) from public,anon;
revoke all on function public.record_central_bank_decision(uuid,text,text,text,text,boolean) from public,anon;
revoke all on function public.get_central_bank_dashboard(uuid) from public,anon;

grant execute on function public.has_central_bank_permission(uuid,text) to authenticated;
grant execute on function public.admin_create_central_bank(uuid,text,text,text,boolean) to authenticated;
grant execute on function public.admin_set_central_bank_status(uuid,text,text) to authenticated;
grant execute on function public.admin_set_central_bank_settings(uuid,boolean,boolean,numeric,numeric) to authenticated;
grant execute on function public.admin_set_central_bank_member(uuid,uuid,text,text[],text) to authenticated;
grant execute on function public.request_monetary_issuance(uuid,numeric,text) to authenticated;
grant execute on function public.admin_review_monetary_issuance(uuid,boolean,text) to authenticated;
grant execute on function public.request_monetary_withdrawal(uuid,numeric,text) to authenticated;
grant execute on function public.admin_review_monetary_withdrawal(uuid,boolean,text) to authenticated;
grant execute on function public.record_central_bank_reserve(uuid,uuid,text,numeric,text,text) to authenticated;
grant execute on function public.request_interest_rate_change(uuid,numeric,date,text) to authenticated;
grant execute on function public.admin_review_interest_rate_change(uuid,boolean,text) to authenticated;
grant execute on function public.create_monetary_policy(uuid,text,text,text,jsonb,date,date) to authenticated;
grant execute on function public.admin_review_monetary_policy(uuid,text,text) to authenticated;
grant execute on function public.request_inflation_target(uuid,numeric,numeric,text,date,date,text) to authenticated;
grant execute on function public.admin_review_inflation_target(uuid,boolean,text) to authenticated;
grant execute on function public.record_central_bank_decision(uuid,text,text,text,text,boolean) to authenticated;
grant execute on function public.get_central_bank_dashboard(uuid) to authenticated;

commit;
