-- WORLD ECONOMY — Identidade fiscal, aprovação presidencial e integração de empresas por atividade.
-- Aditiva: preserva IDs, contas, saldos, empresas e históricos existentes.
begin;

create sequence if not exists public.world_cpf_number_seq start 1;
create sequence if not exists public.world_cnpj_number_seq start 1;
alter table public.profiles add column if not exists cpf_number text;
alter table public.companies add column if not exists cnpj text;
alter table public.companies add column if not exists business_activity text not null default 'general';

do $$
declare r record; n text;
begin
 for r in select id from public.profiles where cpf_number is null order by created_at,id loop
  n:=lpad(nextval('public.world_cpf_number_seq')::text,11,'0');
  update public.profiles set cpf_number=n where id=r.id;
 end loop;
 for r in select id from public.companies where cnpj is null order by created_at,id loop
  n:=lpad(nextval('public.world_cnpj_number_seq')::text,14,'0');
  update public.companies set cnpj=n where id=r.id;
 end loop;
end $$;
create unique index if not exists profiles_cpf_number_uidx on public.profiles(cpf_number) where cpf_number is not null;
create unique index if not exists companies_cnpj_uidx on public.companies(cnpj) where cnpj is not null;
alter table public.companies drop constraint if exists companies_business_activity_check;
alter table public.companies add constraint companies_business_activity_check
 check(business_activity in ('general','bank','vehicle_dealership','driving_school','transport_logistics','retail','food_service','healthcare','education','technology','construction','agriculture','industry','professional_services'));

create or replace function public.assign_world_cpf()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.cpf_number is null or length(trim(new.cpf_number))=0 then
  new.cpf_number:=lpad(nextval('public.world_cpf_number_seq')::text,11,'0');
 end if;
 return new;
end; $$;
drop trigger if exists profiles_assign_world_cpf on public.profiles;
create trigger profiles_assign_world_cpf before insert on public.profiles
for each row execute function public.assign_world_cpf();

create or replace function public.assign_world_cnpj()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.cnpj is null or length(trim(new.cnpj))=0 then
  new.cnpj:=lpad(nextval('public.world_cnpj_number_seq')::text,14,'0');
 end if;
 return new;
end; $$;
drop trigger if exists companies_assign_world_cnpj on public.companies;
create trigger companies_assign_world_cnpj before insert on public.companies
for each row execute function public.assign_world_cnpj();

create or replace function public.request_company_registration_v2(
 p_legal_name text,p_trade_name text,p_country_id uuid,p_city text,p_region text,p_sector text,
 p_company_type text,p_size_class text,p_description text,p_declared_capital numeric,p_currency_id uuid,
 p_business_activity text,p_government_entity_id uuid default null,p_logo_url text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid;
begin
 if p_business_activity not in ('general','bank','vehicle_dealership','driving_school','transport_logistics','retail','food_service','healthcare','education','technology','construction','agriculture','industry','professional_services') then
  raise exception 'Atividade empresarial inválida.';
 end if;
 if p_business_activity='bank' and p_sector<>'banking' then raise exception 'Para abrir um banco, selecione o setor Serviços bancários.'; end if;
 if p_business_activity='vehicle_dealership' and p_sector not in ('commerce','transport') then raise exception 'Concessionárias devem estar no setor Comércio ou Transporte.'; end if;
 if p_business_activity='driving_school' and p_sector not in ('education','services') then raise exception 'Autoescolas devem estar no setor Educação ou Serviços.'; end if;
 v_id:=public.request_company_registration(
  p_legal_name,p_trade_name,p_country_id,p_city,p_region,p_sector,p_company_type,p_size_class,
  p_description,p_declared_capital,p_currency_id,p_government_entity_id,p_logo_url
 );
 update public.companies set business_activity=p_business_activity where id=v_id;
 perform public.company_audit(v_id,'business_activity_selected','company',v_id,jsonb_build_object('business_activity',p_business_activity));
 return v_id;
end; $$;

create or replace function public.president_review_company(p_company_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare c public.companies%rowtype;
begin
 if auth.uid() is null or p_decision not in ('approved','rejected') then raise exception 'Decisão inválida ou autenticação necessária.'; end if;
 select * into c from public.companies where id=p_company_id for update;
 if not found then raise exception 'Empresa não encontrada.'; end if;
 if not public.is_country_president(c.country_id) then raise exception 'Somente o Presidente do país de registro pode aprovar esta empresa.'; end if;
 if c.status<>'pending' then raise exception 'Esta solicitação empresarial já foi analisada.'; end if;
 update public.companies set status=case when p_decision='approved' then 'active' else 'closed' end,
  approved_by=case when p_decision='approved' then auth.uid() else null end,
  approved_at=case when p_decision='approved' then now() else null end,updated_at=now()
 where id=c.id;
 perform public.company_audit(c.id,case when p_decision='approved' then 'company_approved_by_president' else 'company_rejected_by_president' end,
  'company',c.id,jsonb_build_object('decision',p_decision,'note',nullif(trim(p_note),''),'business_activity',c.business_activity));
end; $$;

create or replace function public.admin_review_company(p_company_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare c public.companies%rowtype;
begin
 if not public.is_world_admin() or p_status not in ('suspended','closed') then
  raise exception 'O Super Admin supervisiona globalmente; a aprovação inicial é competência do Presidente do país.';
 end if;
 select * into c from public.companies where id=p_company_id for update;
 if not found then raise exception 'Empresa não encontrada.'; end if;
 if c.status='closed' and p_status<>'closed' then raise exception 'Empresa encerrada não pode ser reativada por esta operação.'; end if;
 update public.companies set status=p_status,updated_at=now() where id=c.id;
 perform public.company_audit(c.id,'company_global_supervision','company',c.id,jsonb_build_object('from',c.status,'to',p_status,'note',p_note));
end; $$;

alter table public.vehicle_dealerships alter column bank_account_id drop not null;

create or replace function public.sync_company_business_institution()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
 if new.status='active' and (tg_op='INSERT' or old.status is distinct from new.status) then
  if new.business_activity='vehicle_dealership' and not exists(select 1 from public.vehicle_dealerships d where d.company_id=new.id) then
   insert into public.vehicle_dealerships(identifier,name,country_id,city,region,logo_url,company_id,bank_account_id,status,created_by,approved_by,approved_at)
   values('DLR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),coalesce(nullif(new.trade_name,''),new.legal_name),
    new.country_id,new.city,new.region,new.logo_url,new.id,null,'active',new.created_by,new.approved_by,coalesce(new.approved_at,now()));
   perform public.company_audit(new.id,'dealership_created_from_company','vehicle_dealership',null,jsonb_build_object('status','active'));
  elsif new.business_activity='driving_school' and not exists(select 1 from public.driving_schools s where s.company_id=new.id) then
   insert into public.driving_schools(identifier,name,country_id,city,region,responsible_profile_id,company_id,is_public,status,created_by,approved_by,approved_at)
   values('SCH-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),coalesce(nullif(new.trade_name,''),new.legal_name),
    new.country_id,new.city,new.region,new.created_by,new.id,false,'active',new.created_by,new.approved_by,coalesce(new.approved_at,now()));
   perform public.company_audit(new.id,'driving_school_created_from_company','driving_school',null,jsonb_build_object('status','active'));
  end if;
 end if;
 return new;
end; $$;
drop trigger if exists companies_sync_business_institution on public.companies;
create trigger companies_sync_business_institution after insert or update of status on public.companies
for each row execute function public.sync_company_business_institution();

create or replace function public.link_company_bank_account_to_dealership()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.owner_company_id is not null and new.status='active' then
  update public.vehicle_dealerships set bank_account_id=new.id,updated_at=now()
   where company_id=new.owner_company_id and bank_account_id is null and status='active';
 end if;
 return new;
end; $$;
drop trigger if exists bank_account_link_company_dealership on public.bank_accounts;
create trigger bank_account_link_company_dealership after insert or update of status,owner_company_id on public.bank_accounts
for each row execute function public.link_company_bank_account_to_dealership();

update public.vehicle_dealerships d set bank_account_id=a.id
from public.bank_accounts a
where a.owner_company_id=d.company_id and a.status='active' and d.bank_account_id is null;

create or replace function public.get_my_bank_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare v jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select jsonb_build_object(
  'cash_wallets',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'country_id',w.country_id,'currency_id',w.currency_id,'currency_code',c.internal_code,'currency_name',c.name,'symbol',c.symbol,'balance',w.balance) order by c.name) from public.bank_cash_wallets w join public.currencies c on c.id=w.currency_id where w.profile_id=auth.uid()),'[]'::jsonb),
  'wallet_transactions',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'type',t.transaction_type,'amount',t.amount,'balance_after',t.balance_after,'description',t.description,'created_at',t.created_at) order by t.created_at desc) from public.bank_cash_wallet_transactions t join public.bank_cash_wallets w on w.id=t.wallet_id where w.profile_id=auth.uid()),'[]'::jsonb),
  'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'bank_id',a.bank_id,'bank_name',b.name,'bank_identifier',b.bank_identifier,'account_number',a.account_number,'account_type',a.account_type,'status',a.status,'balance',a.balance,'currency_id',a.currency_id,'currency_code',c.internal_code,'currency_symbol',c.symbol,'country_id',a.country_id) order by a.created_at desc) from public.bank_accounts a join public.commercial_banks b on b.id=a.bank_id join public.currencies c on c.id=a.currency_id where a.owner_profile_id=auth.uid()),'[]'::jsonb),
  'banks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'identifier',b.bank_identifier,'country_id',b.country_id,'country_name',co.name,'type',b.bank_type,'status',b.status,'currency_id',(select a.currency_id from public.country_currency_assignments a where a.country_id=b.country_id and a.effective_until is null order by a.effective_from desc limit 1),'currency_code',(select cu.internal_code from public.country_currency_assignments a join public.currencies cu on cu.id=a.currency_id where a.country_id=b.country_id and a.effective_until is null order by a.effective_from desc limit 1)) order by b.name) from public.commercial_banks b join public.countries co on co.id=b.country_id where b.status='active' and (public.is_world_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.country_id=b.country_id))),'[]'::jsonb),
  'bank_memberships',coalesce((select jsonb_agg(jsonb_build_object('bank_id',m.bank_id,'permissions',m.permissions,'status',m.status)) from public.bank_members m where m.profile_id=auth.uid()),'[]'::jsonb),
  'countries',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.countries c where c.is_active and public.is_world_admin()),'[]'::jsonb),
  'transactions',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'account_id',t.account_id,'type',t.transaction_type,'amount',t.amount,'currency_id',t.currency_id,'balance_after',t.balance_after,'description',t.description,'created_at',t.created_at,'status',t.status) order by t.created_at desc) from public.bank_transactions t join public.bank_accounts a on a.id=t.account_id where a.owner_profile_id=auth.uid()),'[]'::jsonb)
 ) into v;
 return v;
end; $function$;

revoke all on function public.request_company_registration_v2(text,text,uuid,text,text,text,text,text,text,numeric,uuid,text,uuid,text) from public,anon;
grant execute on function public.request_company_registration_v2(text,text,uuid,text,text,text,text,text,text,numeric,uuid,text,uuid,text) to authenticated;
revoke all on function public.president_review_company(uuid,text,text) from public,anon;
grant execute on function public.president_review_company(uuid,text,text) to authenticated;
revoke all on function public.admin_review_company(uuid,text,text) from public,anon;
grant execute on function public.admin_review_company(uuid,text,text) to authenticated;
revoke all on function public.get_my_bank_dashboard() from public,anon;
grant execute on function public.get_my_bank_dashboard() to authenticated;

commit;
