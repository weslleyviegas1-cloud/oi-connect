-- WORLD ECONOMY — Pagamento e aprovação presidencial da CNH.
-- A aprovação na avaliação não emite automaticamente a habilitação.
begin;

create table if not exists public.driving_license_requests (
 id uuid primary key default gen_random_uuid(),
 enrollment_id uuid not null unique references public.driving_enrollments(id) on delete restrict,
 student_profile_id uuid not null references public.profiles(id) on delete restrict,
 country_id uuid not null references public.countries(id) on delete restrict,
 category_code text not null check(category_code in ('A','B','C','D','E')),
 examination_id uuid not null unique references public.driving_examinations(id) on delete restrict,
 fee_amount numeric(24,2) not null default 0 check(fee_amount>=0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 status text not null default 'awaiting_payment' check(status in ('awaiting_payment','pending_presidency','issued','rejected')),
 bank_transaction_id uuid references public.bank_transactions(id) on delete restrict,
 license_id uuid references public.driving_licenses(id) on delete restrict,
 reviewed_by uuid references public.profiles(id),
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists driving_license_requests_student_idx on public.driving_license_requests(student_profile_id,status);
create index if not exists driving_license_requests_country_idx on public.driving_license_requests(country_id,status);
alter table public.driving_license_requests enable row level security;
drop policy if exists driving_license_requests_read on public.driving_license_requests;
create policy driving_license_requests_read on public.driving_license_requests for select to authenticated using(
 student_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id)
 or exists(select 1 from public.driving_schools s where s.id=(select e.school_id from public.driving_enrollments e where e.id=driving_license_requests.enrollment_id) and s.responsible_profile_id=auth.uid())
);

create or replace function public.vehicle_record_exam(p_enrollment uuid,p_score numeric,p_notes text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare e public.driving_enrollments%rowtype; s public.driving_schools%rowtype; r public.driving_category_rules%rowtype;
 n integer; v uuid; v_request uuid; v_result text;
begin
 select * into e from public.driving_enrollments where id=p_enrollment and status='active' for update;
 if not found then raise exception 'Matrícula ativa não encontrada.'; end if;
 select * into s from public.driving_schools where id=e.school_id;
 select * into r from public.driving_category_rules where country_id=e.country_id and category_code=e.category_code and is_active;
 if r.country_id is null or not (public.is_world_admin() or public.is_country_president(e.country_id) or s.responsible_profile_id=auth.uid()) then
  raise exception 'Sem permissão ou regra nacional ausente.';
 end if;
 select count(*) into n from public.driving_lessons where enrollment_id=e.id and completed;
 if n<r.minimum_lessons then raise exception 'Aulas concluídas insuficientes.'; end if;
 v_result:=case when p_score>=r.minimum_exam_score then 'approved' else 'failed' end;
 insert into public.driving_examinations(enrollment_id,examiner_id,score,result,notes)
 values(e.id,auth.uid(),p_score,v_result,p_notes) returning id into v;
 update public.driving_enrollments set status=case when v_result='approved' then 'completed' else 'active' end where id=e.id;
 if v_result='approved' then
  insert into public.driving_license_requests(enrollment_id,student_profile_id,country_id,category_code,examination_id,fee_amount,currency_id,status)
  values(e.id,e.student_profile_id,e.country_id,e.category_code,v,r.fee_amount,r.currency_id,
   case when r.fee_amount>0 then 'awaiting_payment' else 'pending_presidency' end)
  on conflict(enrollment_id) do nothing returning id into v_request;
  if v_request is null then select id into v_request from public.driving_license_requests where enrollment_id=e.id; end if;
 end if;
 perform public.vehicle_audit(e.country_id,'driving_exam',v,v_result,jsonb_build_object('license_request_id',v_request));
 return v;
end;
$function$;

create or replace function public.vehicle_pay_driving_license_fee(p_request uuid,p_account uuid,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare r public.driving_license_requests%rowtype; a public.bank_accounts%rowtype; t public.national_treasuries%rowtype;
 v_code text; v_tx uuid; v_balance numeric;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency,'')))<12 then raise exception 'Autenticação ou chave idempotente inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select * into r from public.driving_license_requests where id=p_request and student_profile_id=auth.uid() for update;
 if not found or r.status<>'awaiting_payment' or r.fee_amount<=0 then raise exception 'Taxa de CNH indisponível.'; end if;
 select * into a from public.bank_accounts where id=p_account and owner_profile_id=auth.uid() and country_id=r.country_id
  and currency_id=r.currency_id and status='active' for update;
 if not found or a.balance<r.fee_amount then raise exception 'Conta inválida ou saldo insuficiente.'; end if;
 select internal_code into v_code from public.currencies where id=r.currency_id and status='active';
 select * into t from public.national_treasuries where country_id=r.country_id for update;
 if not found or t.currency_code is distinct from v_code then raise exception 'Tesouro Nacional indisponível ou com moeda divergente.'; end if;
 if exists(select 1 from public.bank_transactions where idempotency_key=p_idempotency) then raise exception 'Chave idempotente já utilizada.'; end if;
 update public.bank_accounts set balance=balance-r.fee_amount where id=a.id returning balance into v_balance;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,idempotency_key,actor_id)
 values(a.id,'vehicle_fee',r.fee_amount,a.currency_id,v_balance,'Taxa de emissão da CNH',p_idempotency,auth.uid()) returning id into v_tx;
 insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,currency_code_snapshot,signed_amount,source_type,source_id,idempotency_key,created_by)
 values(r.country_id,'revenue','driving_license_fee','Taxa de emissão da CNH',r.fee_amount,v_code,r.fee_amount,
  'driving_license_fee',r.id,'driving-license-fee:'||p_idempotency,auth.uid());
 update public.driving_license_requests set status='pending_presidency',bank_transaction_id=v_tx where id=r.id;
 perform public.vehicle_audit(r.country_id,'driving_license_fee',r.id,'paid',jsonb_build_object('bank_transaction_id',v_tx));
 return v_tx;
end;
$function$;

create or replace function public.president_review_driving_license(p_request uuid,p_approve boolean)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare r public.driving_license_requests%rowtype; v_license uuid; rule_days integer;
begin
 select * into r from public.driving_license_requests where id=p_request for update;
 if not found or not public.is_country_president(r.country_id) then raise exception 'Somente o Presidente do país emissor pode decidir a emissão da CNH.'; end if;
 if r.status<>'pending_presidency' then raise exception 'Pedido ainda não está pago ou já foi analisado.'; end if;
 if not p_approve then
  update public.driving_license_requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now() where id=r.id;
  perform public.vehicle_audit(r.country_id,'driving_license_request',r.id,'rejected');
  return null;
 end if;
 select validity_days into rule_days from public.driving_category_rules where country_id=r.country_id and category_code=r.category_code and is_active;
 if rule_days is null then raise exception 'Regra nacional de validade não encontrada.'; end if;
 insert into public.driving_licenses(license_number,holder_profile_id,category_code,country_id,expires_at,examination_id)
 values('CNH-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,14)),r.student_profile_id,r.category_code,r.country_id,
  now()+make_interval(days=>rule_days),r.examination_id) returning id into v_license;
 update public.driving_license_requests set status='issued',license_id=v_license,reviewed_by=auth.uid(),reviewed_at=now() where id=r.id;
 perform public.vehicle_audit(r.country_id,'driving_license',v_license,'issued',jsonb_build_object('request_id',r.id));
 return v_license;
end;
$function$;

revoke all on function public.vehicle_pay_driving_license_fee(uuid,uuid,text) from public,anon;
grant execute on function public.vehicle_pay_driving_license_fee(uuid,uuid,text) to authenticated;
revoke all on function public.president_review_driving_license(uuid,boolean) from public,anon;
grant execute on function public.president_review_driving_license(uuid,boolean) to authenticated;

commit;
