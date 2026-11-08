-- WORLD ECONOMY — ETAPA 7: moedas internacionais e câmbio
-- Migration aditiva: preserva os snapshots monetários históricos da Etapa 6.
begin;

create table if not exists public.currencies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  short_name text not null,
  internal_code text not null unique,
  symbol text not null,
  decimal_places smallint not null default 2 check (decimal_places between 0 and 6),
  description text,
  status text not null default 'active' check (status in ('active','suspended','inactive')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (internal_code ~ '^[A-Z][A-Z0-9]{2,7}$'),
  check (length(trim(name)) >= 2),
  check (length(trim(short_name)) >= 2),
  check (length(trim(symbol)) between 1 and 8)
);

create table if not exists public.country_currency_assignments (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  currency_id uuid not null references public.currencies(id) on delete restrict,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  justification text not null,
  created_at timestamptz not null default now(),
  check (effective_until is null or effective_until > effective_from)
);
create unique index if not exists country_currency_one_current
  on public.country_currency_assignments(country_id) where effective_until is null;
create index if not exists country_currency_history_idx
  on public.country_currency_assignments(country_id,effective_from desc);
create index if not exists currency_country_lookup_idx
  on public.country_currency_assignments(currency_id,effective_until);

create table if not exists public.currency_system_settings (
  singleton boolean primary key default true check (singleton),
  reference_currency_id uuid references public.currencies(id) on delete restrict,
  updated_by uuid references public.profiles(id) on delete restrict,
  updated_at timestamptz not null default now()
);
insert into public.currency_system_settings(singleton) values(true) on conflict(singleton) do nothing;

create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  from_currency_id uuid not null references public.currencies(id) on delete restrict,
  to_currency_id uuid not null references public.currencies(id) on delete restrict,
  rate numeric(30,12) not null check (rate > 0),
  effective_from timestamptz not null,
  effective_until timestamptz,
  status text not null default 'active' check (status in ('active','suspended','cancelled')),
  version integer not null,
  justification text not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (from_currency_id <> to_currency_id),
  check (effective_until is null or effective_until > effective_from),
  unique(from_currency_id,to_currency_id,version)
);
create index if not exists exchange_rates_pair_effective_idx
  on public.exchange_rates(from_currency_id,to_currency_id,effective_from desc)
  where status='active';
create index if not exists exchange_rates_currency_to_idx
  on public.exchange_rates(to_currency_id,effective_from desc);

create table if not exists public.exchange_rate_events (
  id uuid primary key default gen_random_uuid(),
  exchange_rate_id uuid not null references public.exchange_rates(id) on delete restrict,
  event_type text not null check (event_type in ('created','suspended','reactivated','cancelled','superseded')),
  previous_values jsonb,
  new_values jsonb not null,
  justification text not null,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists exchange_rate_events_rate_idx on public.exchange_rate_events(exchange_rate_id,created_at desc);

-- Sincroniza a unidade corrente do Tesouro com a atribuição nacional sem reescrever snapshots.
create or replace function public.sync_treasury_currency_from_country()
returns trigger language plpgsql security definer set search_path=public as $
begin
  update public.national_treasuries
    set currency_code=new.currency_code,
        currency_label=coalesce(nullif(new.currency_name,''),'Moeda nacional configurada'),
        updated_at=now()
  where country_id=new.id;
  return new;
end;
$;
drop trigger if exists countries_sync_treasury_currency on public.countries;
create trigger countries_sync_treasury_currency after update of currency_code on public.countries
for each row when (old.currency_code is distinct from new.currency_code)
execute function public.sync_treasury_currency_from_country();
revoke all on function public.sync_treasury_currency_from_country() from public,anon,authenticated;

create table if not exists public.currency_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  justification text,
  created_at timestamptz not null default now()
);
create index if not exists currency_audit_created_idx on public.currency_audit_logs(created_at desc);
create index if not exists currency_audit_entity_idx on public.currency_audit_logs(entity_type,entity_id,created_at desc);

alter table public.currencies enable row level security;
alter table public.country_currency_assignments enable row level security;
alter table public.currency_system_settings enable row level security;
alter table public.exchange_rates enable row level security;
alter table public.exchange_rate_events enable row level security;
alter table public.currency_audit_logs enable row level security;

drop policy if exists currencies_public_read on public.currencies;
create policy currencies_public_read on public.currencies for select to authenticated
using (status='active' or public.is_world_admin());
drop policy if exists country_currency_public_read on public.country_currency_assignments;
create policy country_currency_public_read on public.country_currency_assignments for select to authenticated
using (effective_until is null or public.is_world_admin());
drop policy if exists currency_settings_read on public.currency_system_settings;
create policy currency_settings_read on public.currency_system_settings for select to authenticated using (true);
drop policy if exists exchange_rates_public_read on public.exchange_rates;
create policy exchange_rates_public_read on public.exchange_rates for select to authenticated
using (status='active' or public.is_world_admin());
drop policy if exists exchange_rate_events_admin_read on public.exchange_rate_events;
create policy exchange_rate_events_admin_read on public.exchange_rate_events for select to authenticated
using (public.is_world_admin());
drop policy if exists currency_audit_admin_read on public.currency_audit_logs;
create policy currency_audit_admin_read on public.currency_audit_logs for select to authenticated
using (public.is_world_admin());

revoke all on public.currencies,public.country_currency_assignments,public.currency_system_settings,
  public.exchange_rates,public.exchange_rate_events,public.currency_audit_logs from public,anon,authenticated;
grant select on public.currencies,public.country_currency_assignments,public.currency_system_settings,
  public.exchange_rates,public.exchange_rate_events,public.currency_audit_logs to authenticated;

create or replace function public.currency_audit(
  p_action text,p_entity_type text,p_entity_id uuid,p_old jsonb,p_new jsonb,p_justification text
) returns void language sql security definer set search_path=public,auth as $$
  insert into public.currency_audit_logs(actor_id,action,entity_type,entity_id,old_values,new_values,justification)
  values(auth.uid(),p_action,p_entity_type,p_entity_id,p_old,p_new,p_justification);
$$;
revoke all on function public.currency_audit(text,text,uuid,jsonb,jsonb,text) from public,anon,authenticated;

create or replace function public.admin_create_currency(
  p_name text,p_short_name text,p_internal_code text,p_symbol text,p_decimal_places smallint,p_description text
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode cadastrar moedas.'; end if;
  if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_short_name,'')))<2
    or upper(trim(coalesce(p_internal_code,''))) !~ '^[A-Z][A-Z0-9]{2,7}$'
    or length(trim(coalesce(p_symbol,''))) not between 1 and 8
    or p_decimal_places not between 0 and 6 then raise exception 'Dados da moeda inválidos.'; end if;
  insert into public.currencies(name,short_name,internal_code,symbol,decimal_places,description,created_by)
  values(trim(p_name),trim(p_short_name),upper(trim(p_internal_code)),trim(p_symbol),p_decimal_places,nullif(trim(p_description),''),auth.uid())
  returning id into v_id;
  perform public.currency_audit('create','currency',v_id,null,to_jsonb(v_id), 'Cadastro de moeda');
  return v_id;
end;
$$;

create or replace function public.admin_set_currency_status(p_currency_id uuid,p_status text,p_justification text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare c public.currencies%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode alterar a situação das moedas.'; end if;
  if p_status not in ('active','suspended','inactive') or length(trim(coalesce(p_justification,'')))<5 then raise exception 'Situação ou justificativa inválida.'; end if;
  select * into c from public.currencies where id=p_currency_id for update;
  if not found then raise exception 'Moeda não encontrada.'; end if;
  update public.currencies set status=p_status,updated_at=now() where id=c.id;
  perform public.currency_audit('status_change','currency',c.id,to_jsonb(c),jsonb_build_object('status',p_status),p_justification);
end;
$$;

create or replace function public.admin_assign_country_currency(
  p_country_id uuid,p_currency_id uuid,p_effective_from timestamptz,p_justification text
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.currencies%rowtype; v_old public.country_currency_assignments%rowtype; v_id uuid; v_country public.countries%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode definir a moeda nacional.'; end if;
  if p_effective_from is null or p_effective_from>now()+interval '1 minute'
    or length(trim(coalesce(p_justification,'')))<5 then raise exception 'A vigência deve ser imediata ou passada, com justificativa válida.'; end if;
  select * into c from public.currencies where id=p_currency_id and status='active';
  if not found then raise exception 'A moeda precisa estar ativa.'; end if;
  select * into v_country from public.countries where id=p_country_id for update;
  if not found then raise exception 'País não encontrado.'; end if;
  select * into v_old from public.country_currency_assignments
    where country_id=p_country_id and effective_until is null for update;
  if found then
    if p_effective_from<=v_old.effective_from then raise exception 'A nova vigência deve ser posterior à atribuição atual.'; end if;
    update public.country_currency_assignments set effective_until=p_effective_from where id=v_old.id;
  end if;
  insert into public.country_currency_assignments(country_id,currency_id,effective_from,assigned_by,justification)
  values(p_country_id,p_currency_id,p_effective_from,auth.uid(),trim(p_justification)) returning id into v_id;
  -- Mantém os campos legados sincronizados para os módulos da Etapa 6.
  update public.countries set currency_code=c.internal_code,currency_name=c.name where id=p_country_id;
  perform public.currency_audit('assign_national_currency','country_currency_assignment',v_id,
    case when v_old.id is null then null else to_jsonb(v_old) end,
    jsonb_build_object('country_id',p_country_id,'currency_id',p_currency_id,'code',c.internal_code,'effective_from',p_effective_from),
    p_justification);
  return v_id;
end;
$$;

create or replace function public.admin_set_reference_currency(p_currency_id uuid,p_justification text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare c public.currencies%rowtype; old_id uuid;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode alterar a moeda de referência.'; end if;
  if length(trim(coalesce(p_justification,'')))<5 then raise exception 'Informe uma justificativa.'; end if;
  select * into c from public.currencies where id=p_currency_id and status='active';
  if not found then raise exception 'A moeda de referência precisa estar ativa.'; end if;
  select reference_currency_id into old_id from public.currency_system_settings where singleton=true for update;
  update public.currency_system_settings set reference_currency_id=p_currency_id,updated_by=auth.uid(),updated_at=now() where singleton=true;
  perform public.currency_audit('set_reference_currency','currency_settings',null,
    jsonb_build_object('reference_currency_id',old_id),jsonb_build_object('reference_currency_id',p_currency_id),p_justification);
end;
$$;

create or replace function public.admin_create_exchange_rate(
  p_from_currency_id uuid,p_to_currency_id uuid,p_rate numeric,p_effective_from timestamptz,p_effective_until timestamptz,p_justification text
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_version integer; c1 public.currencies%rowtype; c2 public.currencies%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode cadastrar cotações oficiais.'; end if;
  if p_from_currency_id=p_to_currency_id or p_rate is null or p_rate<=0
    or p_rate>1000000000000000000::numeric or p_effective_from is null
    or (p_effective_until is not null and p_effective_until<=p_effective_from)
    or length(trim(coalesce(p_justification,'')))<5 then raise exception 'Cotação inválida.'; end if;
  select * into c1 from public.currencies where id=p_from_currency_id and status='active';
  select * into c2 from public.currencies where id=p_to_currency_id and status='active';
  if c1.id is null or c2.id is null then raise exception 'As duas moedas precisam estar ativas.'; end if;
  select coalesce(max(version),0)+1 into v_version from public.exchange_rates
    where from_currency_id=p_from_currency_id and to_currency_id=p_to_currency_id;
  insert into public.exchange_rates(from_currency_id,to_currency_id,rate,effective_from,effective_until,status,version,justification,created_by)
  values(p_from_currency_id,p_to_currency_id,p_rate,p_effective_from,p_effective_until,'active',v_version,trim(p_justification),auth.uid())
  returning id into v_id;
  insert into public.exchange_rate_events(exchange_rate_id,event_type,new_values,justification,actor_id)
  values(v_id,'created',jsonb_build_object('rate',p_rate,'effective_from',p_effective_from,'effective_until',p_effective_until,'version',v_version),p_justification,auth.uid());
  perform public.currency_audit('create_exchange_rate','exchange_rate',v_id,null,
    jsonb_build_object('from',p_from_currency_id,'to',p_to_currency_id,'rate',p_rate,'version',v_version),p_justification);
  return v_id;
end;
$$;

create or replace function public.admin_set_exchange_rate_status(p_rate_id uuid,p_status text,p_justification text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare r public.exchange_rates%rowtype; v_event text;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode alterar a situação da cotação.'; end if;
  if p_status not in ('active','suspended','cancelled') or length(trim(coalesce(p_justification,'')))<5 then raise exception 'Situação ou justificativa inválida.'; end if;
  select * into r from public.exchange_rates where id=p_rate_id for update;
  if not found then raise exception 'Cotação não encontrada.'; end if;
  if r.status=p_status then return; end if;
  update public.exchange_rates set status=p_status where id=r.id;
  v_event:=case when p_status='active' then 'reactivated' when p_status='suspended' then 'suspended' else 'cancelled' end;
  insert into public.exchange_rate_events(exchange_rate_id,event_type,previous_values,new_values,justification,actor_id)
  values(r.id,v_event,to_jsonb(r),jsonb_build_object('status',p_status),p_justification,auth.uid());
  perform public.currency_audit('exchange_rate_status','exchange_rate',r.id,to_jsonb(r),jsonb_build_object('status',p_status),p_justification);
end;
$$;

create or replace function public.get_currency_market_snapshot(p_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select jsonb_build_object(
    'currencies',coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from public.currencies c
      where c.status='active' or public.is_world_admin()),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object('country_id',a.country_id,'country_name',co.name,
      'country_flag',co.flag,'currency_id',a.currency_id,'effective_from',a.effective_from)
      order by co.name) from public.country_currency_assignments a
      join public.countries co on co.id=a.country_id where a.effective_until is null),'[]'::jsonb),
    'rates',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'from_currency_id',r.from_currency_id,
      'to_currency_id',r.to_currency_id,'rate',r.rate,'effective_from',r.effective_from,
      'effective_until',r.effective_until,'version',r.version,'status',r.status,'created_at',r.created_at)
      order by r.effective_from desc) from public.exchange_rates r
      where (r.status='active' or public.is_world_admin())
        and r.effective_from<=coalesce(p_at,now())
        and (r.effective_until is null or r.effective_until>coalesce(p_at,now()))),'[]'::jsonb),
    'reference_currency_id',(select reference_currency_id from public.currency_system_settings where singleton=true)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.convert_currency_amount(
  p_amount numeric,p_from_currency_id uuid,p_to_currency_id uuid,p_at timestamptz default now()
) returns jsonb language plpgsql stable security definer set search_path=public,auth as $$
declare r public.exchange_rates%rowtype; v_rate numeric(38,18); v_direct boolean; v_converted numeric(38,12);
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if p_amount is null or p_amount<0 or p_amount>999999999999999999999999::numeric then raise exception 'Valor de conversão inválido.'; end if;
  if p_from_currency_id is null or p_to_currency_id is null then raise exception 'Selecione as duas moedas.'; end if;
  if not exists(select 1 from public.currencies where id=p_from_currency_id and status='active')
    or not exists(select 1 from public.currencies where id=p_to_currency_id and status='active') then raise exception 'Moeda inexistente ou indisponível.'; end if;
  if p_from_currency_id=p_to_currency_id then
    return jsonb_build_object('amount',p_amount,'rate',1,'rate_id',null,'from_currency_id',p_from_currency_id,
      'to_currency_id',p_to_currency_id,'as_of',coalesce(p_at,now()),'direction','same');
  end if;
  select * into r from public.exchange_rates x where x.from_currency_id=p_from_currency_id and x.to_currency_id=p_to_currency_id
    and x.status='active' and x.effective_from<=coalesce(p_at,now())
    and (x.effective_until is null or x.effective_until>coalesce(p_at,now()))
    order by x.effective_from desc,x.version desc limit 1;
  if found then v_rate:=r.rate;v_direct:=true;
  else
    select * into r from public.exchange_rates x where x.from_currency_id=p_to_currency_id and x.to_currency_id=p_from_currency_id
      and x.status='active' and x.effective_from<=coalesce(p_at,now())
      and (x.effective_until is null or x.effective_until>coalesce(p_at,now()))
      order by x.effective_from desc,x.version desc limit 1;
    if not found then raise exception 'Não existe cotação vigente entre as moedas selecionadas.'; end if;
    v_rate:=1::numeric/r.rate;v_direct:=false;
  end if;
  v_converted:=p_amount*v_rate;
  return jsonb_build_object('amount',v_converted,'rate',v_rate,'rate_id',r.id,
    'from_currency_id',p_from_currency_id,'to_currency_id',p_to_currency_id,
    'as_of',coalesce(p_at,now()),'direction',case when v_direct then 'direct' else 'inverse' end);
end;
$$;

revoke all on function public.admin_create_currency(text,text,text,text,smallint,text) from public,anon;
revoke all on function public.admin_set_currency_status(uuid,text,text) from public,anon;
revoke all on function public.admin_assign_country_currency(uuid,uuid,timestamptz,text) from public,anon;
revoke all on function public.admin_set_reference_currency(uuid,text) from public,anon;
revoke all on function public.admin_create_exchange_rate(uuid,uuid,numeric,timestamptz,timestamptz,text) from public,anon;
revoke all on function public.admin_set_exchange_rate_status(uuid,text,text) from public,anon;
revoke all on function public.get_currency_market_snapshot(timestamptz) from public,anon;
revoke all on function public.convert_currency_amount(numeric,uuid,uuid,timestamptz) from public,anon;

grant execute on function public.admin_create_currency(text,text,text,text,smallint,text) to authenticated;
grant execute on function public.admin_set_currency_status(uuid,text,text) to authenticated;
grant execute on function public.admin_assign_country_currency(uuid,uuid,timestamptz,text) to authenticated;
grant execute on function public.admin_set_reference_currency(uuid,text) to authenticated;
grant execute on function public.admin_create_exchange_rate(uuid,uuid,numeric,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.admin_set_exchange_rate_status(uuid,text,text) to authenticated;
grant execute on function public.get_currency_market_snapshot(timestamptz) to authenticated;
grant execute on function public.convert_currency_amount(numeric,uuid,uuid,timestamptz) to authenticated;

commit;
