-- WORLD ECONOMY — Política nacional de cobrança recorrente pelo CNPJ.
-- Aditiva: não altera saldos nem cria cobranças retroativas.
begin;

create table if not exists public.company_registration_tax_policies (
 country_id uuid primary key references public.countries(id) on delete restrict,
 billing_mode text not null check(billing_mode in ('fixed','percentage')),
 fixed_amount numeric(24,2) not null default 0 check(fixed_amount>=0),
 rate numeric(9,4) not null default 0 check(rate between 0 and 100),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 due_day integer not null default 10 check(due_day between 1 and 28),
 is_active boolean not null default true,
 tax_rule_id uuid references public.tax_rules(id) on delete restrict,
 updated_by uuid not null references public.profiles(id),
 updated_at timestamptz not null default now()
);
alter table public.company_registration_tax_policies enable row level security;
drop policy if exists company_registration_tax_policy_read on public.company_registration_tax_policies;
create policy company_registration_tax_policy_read on public.company_registration_tax_policies
 for select to authenticated using(
  public.is_world_admin() or public.is_country_president(country_id) or exists(
   select 1 from public.companies c where c.country_id=company_registration_tax_policies.country_id
    and public.is_company_member(c.id,null)
  )
 );
create unique index if not exists company_cnpj_tax_period_uidx
 on public.company_tax_records(company_id,reference_period) where description='Taxa mensal de CNPJ';

create or replace function public.president_set_company_registration_tax_policy(
 p_country_id uuid,p_mode text,p_fixed_amount numeric,p_rate numeric,p_currency_id uuid,
 p_due_day integer,p_active boolean
) returns void language plpgsql security definer set search_path=public,auth as $function$
declare v_currency_code text; v_rule_id uuid; v_rate numeric;
begin
 if auth.uid() is null or not public.is_country_president(p_country_id) then
  raise exception 'Somente o Presidente do país pode configurar a tributação do CNPJ.';
 end if;
 if p_mode not in ('fixed','percentage') or p_fixed_amount is null or p_fixed_amount<0
  or p_rate is null or p_rate<0 or p_rate>100 or p_due_day not between 1 and 28 then
  raise exception 'Configuração tributária inválida.';
 end if;
 select internal_code into v_currency_code from public.currencies
  where id=p_currency_id and status='active'
   and internal_code=(select currency_code from public.countries where id=p_country_id and is_active);
 if v_currency_code is null then raise exception 'Selecione a moeda nacional vigente do país.'; end if;
 v_rate:=case when p_mode='percentage' then p_rate else 0 end;
 select id into v_rule_id from public.tax_rules
  where country_id=p_country_id and identifier='CNPJ_REGISTRATION' and effective_from=current_date
  order by created_at desc limit 1;
 if v_rule_id is null then
  insert into public.tax_rules(country_id,name,identifier,category,description,rate,calculation_base,status,effective_from,created_by)
  values(p_country_id,'Taxa mensal de CNPJ','CNPJ_REGISTRATION','company_registration',
   case when p_mode='fixed' then 'Valor fixo mensal por empresa registrada' else 'Percentual mensal sobre o capital declarado da empresa' end,
   v_rate,'declared_value','active',current_date,auth.uid()) returning id into v_rule_id;
 else
  update public.tax_rules set name='Taxa mensal de CNPJ',category='company_registration',
   description=case when p_mode='fixed' then 'Valor fixo mensal por empresa registrada' else 'Percentual mensal sobre o capital declarado da empresa' end,
   rate=v_rate,status='active',updated_at=now() where id=v_rule_id;
 end if;
 insert into public.company_registration_tax_policies(country_id,billing_mode,fixed_amount,rate,currency_id,due_day,is_active,tax_rule_id,updated_by)
 values(p_country_id,p_mode,round(p_fixed_amount,2),p_rate,p_currency_id,p_due_day,p_active,v_rule_id,auth.uid())
 on conflict(country_id) do update set billing_mode=excluded.billing_mode,fixed_amount=excluded.fixed_amount,
  rate=excluded.rate,currency_id=excluded.currency_id,due_day=excluded.due_day,is_active=excluded.is_active,
  tax_rule_id=excluded.tax_rule_id,updated_by=auth.uid(),updated_at=now();
end;
$function$;

create or replace function public.company_generate_cnpj_tax_obligation(p_company_id uuid,p_period text default to_char(current_date,'YYYY-MM'))
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.companies%rowtype; p public.company_registration_tax_policies%rowtype;
 v_rule public.tax_rules%rowtype; v_code text; v_base numeric(24,2); v_amount numeric(24,2);
 v_obligation uuid; v_record uuid; v_due date;
begin
 if auth.uid() is null or not public.is_company_member(p_company_id,'tax.manage') then
  raise exception 'Sem permissão para gerar a obrigação do CNPJ.';
 end if;
 if p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Período inválido. Use AAAA-MM.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text||':'||p_period,0));
 select * into c from public.companies where id=p_company_id and status='active' for update;
 if not found then raise exception 'Empresa não está ativa.'; end if;
 select * into p from public.company_registration_tax_policies where country_id=c.country_id and is_active;
 if not found then raise exception 'O Presidente ainda não configurou a taxa de CNPJ deste país.'; end if;
 if exists(select 1 from public.company_tax_records where company_id=c.id and reference_period=p_period and description='Taxa mensal de CNPJ') then
  select id into v_record from public.company_tax_records where company_id=c.id and reference_period=p_period and description='Taxa mensal de CNPJ';
  return v_record;
 end if;
 select * into v_rule from public.tax_rules where id=p.tax_rule_id and status='active';
 if not found then raise exception 'Regra fiscal nacional indisponível.'; end if;
 select internal_code into v_code from public.currencies where id=p.currency_id and status='active';
 if v_code is null or v_code<>(select currency_code from public.countries where id=c.country_id) then
  raise exception 'A moeda da política não corresponde à moeda nacional vigente.';
 end if;
 v_base:=round(coalesce(c.declared_capital,0),2);
 v_amount:=case when p.billing_mode='fixed' then p.fixed_amount else round(v_base*p.rate/100,2) end;
 if v_amount<=0 then raise exception 'A taxa calculada é zero; não há obrigação a gerar.'; end if;
 v_due:=(make_date(split_part(p_period,'-',1)::int,split_part(p_period,'-',2)::int,1)+interval '1 month - 1 day')::date;
 v_due:=least(v_due,make_date(split_part(p_period,'-',1)::int,split_part(p_period,'-',2)::int,p.due_day));
 insert into public.tax_obligations(country_id,tax_rule_id,taxpayer_company_id,taxpayer_label,reference_period,
  calculation_base,applied_rate,amount_due,currency_code_snapshot,due_date,status,created_by)
 values(c.country_id,v_rule.id,c.id,coalesce(nullif(c.trade_name,''),c.legal_name),p_period,
  v_base,case when p.billing_mode='fixed' then 0 else p.rate end,v_amount,v_code,v_due,'open',auth.uid())
 returning id into v_obligation;
 insert into public.company_tax_records(company_id,tax_rule_id,tax_obligation_id,description,reference_period,
  tax_base,applied_rate,amount_due,currency_id,status,validated_by,validated_at,created_by)
 values(c.id,v_rule.id,v_obligation,'Taxa mensal de CNPJ',p_period,v_base,
  case when p.billing_mode='fixed' then 0 else p.rate end,v_amount,p.currency_id,'validated',auth.uid(),now(),auth.uid())
 returning id into v_record;
 perform public.company_audit(c.id,'cnpj_monthly_tax_generated','company_tax_record',v_record,
  jsonb_build_object('period',p_period,'mode',p.billing_mode,'amount',v_amount,'currency',v_code,'due_date',v_due));
 return v_record;
end;
$function$;

revoke all on function public.president_set_company_registration_tax_policy(uuid,text,numeric,numeric,uuid,integer,boolean) from public,anon;
grant execute on function public.president_set_company_registration_tax_policy(uuid,text,numeric,numeric,uuid,integer,boolean) to authenticated;
revoke all on function public.company_generate_cnpj_tax_obligation(uuid,text) from public,anon;
grant execute on function public.company_generate_cnpj_tax_obligation(uuid,text) to authenticated;

commit;
 then raise exception 'Período inválido. Use AAAA-MM.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_company_id::text||':'||p_period,0));
 select * into c from public.companies where id=p_company_id and status='active' for update;
 if not found then raise exception 'Empresa não está ativa.'; end if;
 select * into p from public.company_registration_tax_policies where country_id=c.country_id and is_active;
 if not found then raise exception 'O Presidente ainda não configurou a taxa de CNPJ deste país.'; end if;
 if exists(select 1 from public.company_tax_records where company_id=c.id and reference_period=p_period and description='Taxa mensal de CNPJ') then
  select id into v_record from public.company_tax_records where company_id=c.id and reference_period=p_period and description='Taxa mensal de CNPJ';
  return v_record;
 end if;
 select * into v_rule from public.tax_rules where id=p.tax_rule_id and status='active';
 if not found then raise exception 'Regra fiscal nacional indisponível.'; end if;
 select internal_code into v_code from public.currencies where id=p.currency_id and status='active';
 if v_code is null or v_code<>(select currency_code from public.countries where id=c.country_id) then
  raise exception 'A moeda da política não corresponde à moeda nacional vigente.';
 end if;
 v_base:=round(coalesce(c.declared_capital,0),2);
 v_amount:=case when p.billing_mode='fixed' then p.fixed_amount else round(v_base*p.rate/100,2) end;
 if v_amount<=0 then raise exception 'A taxa calculada é zero; não há obrigação a gerar.'; end if;
 v_due:=(make_date(split_part(p_period,'-',1)::int,split_part(p_period,'-',2)::int,1)+interval '1 month - 1 day')::date;
 v_due:=least(v_due,make_date(split_part(p_period,'-',1)::int,split_part(p_period,'-',2)::int,p.due_day));
 insert into public.tax_obligations(country_id,tax_rule_id,taxpayer_company_id,taxpayer_label,reference_period,
  calculation_base,applied_rate,amount_due,currency_code_snapshot,due_date,status,created_by)
 values(c.country_id,v_rule.id,c.id,coalesce(nullif(c.trade_name,''),c.legal_name),p_period,
  v_base,case when p.billing_mode='fixed' then 0 else p.rate end,v_amount,v_code,v_due,'open',auth.uid())
 returning id into v_obligation;
 insert into public.company_tax_records(company_id,tax_rule_id,tax_obligation_id,description,reference_period,
  tax_base,applied_rate,amount_due,currency_id,status,validated_by,validated_at,created_by)
 values(c.id,v_rule.id,v_obligation,'Taxa mensal de CNPJ',p_period,v_base,
  case when p.billing_mode='fixed' then 0 else p.rate end,v_amount,p.currency_id,'validated',auth.uid(),now(),auth.uid())
 returning id into v_record;
 perform public.company_audit(c.id,'cnpj_monthly_tax_generated','company_tax_record',v_record,
  jsonb_build_object('period',p_period,'mode',p.billing_mode,'amount',v_amount,'currency',v_code,'due_date',v_due));
 return v_record;
end;
$function$;

revoke all on function public.president_set_company_registration_tax_policy(uuid,text,numeric,numeric,uuid,integer,boolean) from public,anon;
grant execute on function public.president_set_company_registration_tax_policy(uuid,text,numeric,numeric,uuid,integer,boolean) to authenticated;
revoke all on function public.company_generate_cnpj_tax_obligation(uuid,text) from public,anon;
grant execute on function public.company_generate_cnpj_tax_obligation(uuid,text) to authenticated;

commit;
