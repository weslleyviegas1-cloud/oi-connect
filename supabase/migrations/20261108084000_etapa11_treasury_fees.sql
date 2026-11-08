-- WORLD ECONOMY — ETAPA 11: taxas documentais com liquidação bancária e crédito ao Tesouro
begin;

create table if not exists public.travel_fee_settings (
  country_id uuid primary key references public.countries(id) on delete restrict,
  passport_fee numeric(18,2) not null default 0 check(passport_fee>=0),
  currency_code text not null,
  updated_by uuid not null references public.profiles(id),
  updated_at timestamptz not null default now()
);
alter table public.travel_fee_settings enable row level security;
revoke all on public.travel_fee_settings from public,anon,authenticated;
grant select on public.travel_fee_settings to authenticated;
drop policy if exists travel_fee_settings_read_scope on public.travel_fee_settings;
create policy travel_fee_settings_read_scope on public.travel_fee_settings for select to authenticated
using(public.is_world_admin() or public.is_country_president(country_id) or public.has_government_permission(country_id,'immigration.rules',null,null));

create unique index if not exists travel_fee_related_unique_idx
on public.travel_fee_records(related_type,related_id);

create or replace function public.admin_set_travel_fee_settings(p_country_id uuid,p_passport_fee numeric)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare v_currency text;
begin
  if auth.uid() is null or not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_government_permission(p_country_id,'immigration.rules',null,null)) then raise exception 'Sem permissão para configurar taxas deste país.'; end if;
  if p_passport_fee is null or p_passport_fee<0 then raise exception 'Taxa inválida.'; end if;
  select currency_code into v_currency from public.countries where id=p_country_id and is_active;
  if v_currency is null then raise exception 'País ou moeda nacional não configurados.'; end if;
  insert into public.travel_fee_settings(country_id,passport_fee,currency_code,updated_by,updated_at)
  values(p_country_id,p_passport_fee,upper(v_currency),auth.uid(),now())
  on conflict(country_id) do update set passport_fee=excluded.passport_fee,currency_code=excluded.currency_code,updated_by=auth.uid(),updated_at=now();
end;$function$;

create or replace function public.create_passport_request_fee()
returns trigger language plpgsql security definer set search_path=public,auth as $function$
declare s public.travel_fee_settings%rowtype;
begin
  select * into s from public.travel_fee_settings where country_id=new.country_id;
  if found and s.passport_fee>0 then
    insert into public.travel_fee_records(profile_id,country_id,related_type,related_id,amount,currency_code,recipient_description,status)
    values(new.profile_id,new.country_id,'passport',new.id,s.passport_fee,s.currency_code,'Tesouro Nacional — taxa de emissão/renovação de passaporte','unpaid')
    on conflict(related_type,related_id) do nothing;
  end if;
  return new;
end;$function$;
drop trigger if exists passport_request_fee_trigger on public.passport_requests;
create trigger passport_request_fee_trigger after insert on public.passport_requests
for each row execute function public.create_passport_request_fee();

create or replace function public.create_visa_application_fee()
returns trigger language plpgsql security definer set search_path=public,auth as $function$
declare v public.visa_types%rowtype;
begin
  select * into v from public.visa_types where id=new.visa_type_id;
  if found and v.fee_amount>0 and v.currency_code is not null then
    insert into public.travel_fee_records(profile_id,country_id,related_type,related_id,amount,currency_code,recipient_description,status)
    values(new.profile_id,new.destination_country_id,'visa',new.id,v.fee_amount,v.currency_code,'Tesouro Nacional — taxa de visto '||v.name,'unpaid')
    on conflict(related_type,related_id) do nothing;
  end if;
  return new;
end;$function$;
drop trigger if exists visa_application_fee_trigger on public.visa_applications;
create trigger visa_application_fee_trigger after insert on public.visa_applications
for each row execute function public.create_visa_application_fee();

create or replace function public.enforce_passport_fee_before_issue()
returns trigger language plpgsql security definer set search_path=public,auth as $function$
begin
  if new.status='issued' and old.status is distinct from new.status and exists(
    select 1 from public.travel_fee_records f where f.related_type='passport' and f.related_id=new.id and f.status='unpaid'
  ) then raise exception 'A taxa de passaporte precisa ser paga ou dispensada antes da emissão.'; end if;
  return new;
end;$function$;
drop trigger if exists passport_fee_before_issue_trigger on public.passport_requests;
create trigger passport_fee_before_issue_trigger before update of status on public.passport_requests
for each row execute function public.enforce_passport_fee_before_issue();

create or replace function public.enforce_visa_fee_before_approval()
returns trigger language plpgsql security definer set search_path=public,auth as $function$
begin
  if new.status='approved' and old.status is distinct from new.status and exists(
    select 1 from public.travel_fee_records f where f.related_type='visa' and f.related_id=new.id and f.status='unpaid'
  ) then raise exception 'A taxa do visto precisa ser paga ou dispensada antes da aprovação.'; end if;
  return new;
end;$function$;
drop trigger if exists visa_fee_before_approval_trigger on public.visa_applications;
create trigger visa_fee_before_approval_trigger before update of status on public.visa_applications
for each row execute function public.enforce_visa_fee_before_approval();

create or replace function public.pay_world_travel_fee(p_fee_id uuid,p_account_id uuid,p_idempotency_key text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare f public.travel_fee_records%rowtype; a public.bank_accounts%rowtype; t public.national_treasuries%rowtype; v_code text; v_after numeric; tx uuid; existing public.bank_transactions%rowtype;
begin
  if auth.uid() is null or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Autenticação ou chave idempotente inválida.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
  select * into existing from public.bank_transactions where idempotency_key=p_idempotency_key;
  if found then
    if existing.transaction_type='fee' and existing.actor_id=auth.uid() and existing.reference_id=p_fee_id then return existing.id; end if;
    raise exception 'Chave idempotente já utilizada em outra operação.';
  end if;
  select * into f from public.travel_fee_records where id=p_fee_id and profile_id=auth.uid() and status='unpaid' for update;
  if not found then raise exception 'Taxa não encontrada, já paga ou não pertence ao cidadão.'; end if;
  select * into a from public.bank_accounts where id=p_account_id and owner_profile_id=auth.uid() for update;
  if not found or a.status<>'active' or a.country_id<>f.country_id then raise exception 'Conta bancária pessoal ativa do país emissor/destino obrigatória.'; end if;
  select internal_code into v_code from public.currencies where id=a.currency_id and status='active';
  if v_code is null or upper(v_code)<>upper(f.currency_code) then raise exception 'Moeda da conta diverge da moeda da taxa.'; end if;
  if not exists(select 1 from public.commercial_banks b where b.id=a.bank_id and b.status='active') then raise exception 'Banco indisponível.'; end if;
  select * into t from public.national_treasuries where country_id=f.country_id for update;
  if not found or t.operations_suspended or t.currency_code is distinct from upper(f.currency_code) then raise exception 'Tesouro Nacional indisponível ou com moeda divergente.'; end if;
  if (t.opening_balance>0 and t.opening_balance_currency_code_snapshot<>upper(f.currency_code)) or exists(select 1 from public.treasury_ledger_entries e where e.country_id=f.country_id and e.currency_code_snapshot<>upper(f.currency_code)) then raise exception 'Tesouro requer conciliação monetária.'; end if;
  if a.balance<f.amount then raise exception 'Saldo bancário insuficiente.'; end if;
  update public.bank_accounts set balance=balance-f.amount where id=a.id returning balance into v_after;
  insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,currency_code_snapshot,signed_amount,source_type,source_id,idempotency_key,created_by)
  values(f.country_id,'revenue','travel_document_fee',f.recipient_description,f.amount,upper(f.currency_code),f.amount,'travel_fee',f.id,'travel-fee:'||p_idempotency_key,auth.uid());
  update public.travel_fee_records set status='paid',confirmed_by=auth.uid(),confirmed_at=now(),bank_transaction_id=null where id=f.id;
  insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
  values(a.id,'fee',f.amount,a.currency_id,v_after,f.recipient_description,f.id,p_idempotency_key,auth.uid()) returning id into tx;
  update public.travel_fee_records set bank_transaction_id=tx where id=f.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,new_values)
  values(auth.uid(),f.profile_id,f.country_id,'travel_fee',f.id,'paid','Taxa paga por débito bancário e crédito ao Tesouro Nacional.',jsonb_build_object('amount',f.amount,'currency',f.currency_code,'bank_transaction_id',tx));
  return tx;
end;$function$;

create or replace function public.waive_world_travel_fee(p_fee_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare f public.travel_fee_records%rowtype;
begin
  select * into f from public.travel_fee_records where id=p_fee_id and status='unpaid' for update;
  if not found then raise exception 'Taxa não encontrada ou já processada.'; end if;
  if not (public.is_world_admin() or public.is_country_president(f.country_id) or public.has_government_permission(f.country_id,'immigration.rules',null,null)) then raise exception 'Sem permissão para dispensar esta taxa.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Justificativa obrigatória.'; end if;
  update public.travel_fee_records set status='waived',confirmed_by=auth.uid(),confirmed_at=now() where id=f.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values)
  values(auth.uid(),f.profile_id,f.country_id,'travel_fee',f.id,'waived',trim(p_reason),jsonb_build_object('status','unpaid'),jsonb_build_object('status','waived'));
end;$function$;

do $grants$
begin
  revoke all on function public.admin_set_travel_fee_settings(uuid,numeric) from public,anon;
  grant execute on function public.admin_set_travel_fee_settings(uuid,numeric) to authenticated;
  revoke all on function public.pay_world_travel_fee(uuid,uuid,text) from public,anon;
  grant execute on function public.pay_world_travel_fee(uuid,uuid,text) to authenticated;
  revoke all on function public.waive_world_travel_fee(uuid,text) from public,anon;
  grant execute on function public.waive_world_travel_fee(uuid,text) to authenticated;
end;$grants$;
commit;
