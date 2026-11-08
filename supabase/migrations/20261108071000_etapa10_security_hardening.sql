-- WORLD ECONOMY — ETAPA 10: endurecimento adicional de permissões
-- Corrige validações de país, atribuição de gestores e conciliação financeira.
begin;

create or replace function public.company_manage_member(p_company_id uuid,p_profile_id uuid,p_role text,p_permissions text[],p_status text default 'active')
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid; v_country uuid;
begin
 if not public.is_company_member(p_company_id,'company.manage') then raise exception 'Sem permissão para administrar membros.'; end if;
 select country_id into v_country from public.companies where id=p_company_id and status='active';
 if v_country is null then raise exception 'Empresa indisponível.'; end if;
 if p_role not in ('director','manager','hr','finance','employee') or p_status not in ('active','suspended','removed')
  or not exists(select 1 from public.profiles where id=p_profile_id and country_id=v_country and registration_status='active' and coalesce(account_status,'active')='active') then
  raise exception 'O membro deve ser cidadão ativo do país da empresa e possuir função válida.';
 end if;
 insert into public.company_members(company_id,profile_id,member_role,permissions,status,appointed_by)
 values(p_company_id,p_profile_id,p_role,coalesce(p_permissions,'{}'),p_status,auth.uid())
 on conflict(company_id,profile_id) do update set member_role=excluded.member_role,permissions=excluded.permissions,status=excluded.status
 returning id into v_id;
 perform public.company_audit(p_company_id,'member_updated','company_member',v_id,jsonb_build_object('profile_id',p_profile_id,'role',p_role,'status',p_status));
 return v_id;
end;
$function$;

create or replace function public.company_upsert_department(p_company_id uuid,p_department_id uuid,p_name text,p_description text,p_manager uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_company_member(p_company_id,'department.manage') then raise exception 'Sem permissão para administrar departamentos.'; end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'Nome de departamento inválido.'; end if;
 if p_manager is not null and not exists(select 1 from public.company_members where company_id=p_company_id and profile_id=p_manager and status='active') then
  raise exception 'O responsável pelo departamento deve ser membro ativo da empresa.';
 end if;
 if p_department_id is null then
  insert into public.company_departments(company_id,name,description,manager_profile_id,created_by)
  values(p_company_id,trim(p_name),nullif(trim(p_description),''),p_manager,auth.uid()) returning id into v_id;
 else
  update public.company_departments set name=trim(p_name),description=nullif(trim(p_description),''),manager_profile_id=p_manager
  where id=p_department_id and company_id=p_company_id returning id into v_id;
  if v_id is null then raise exception 'Departamento não encontrado.'; end if;
 end if;
 perform public.company_audit(p_company_id,'department_saved','department',v_id,jsonb_build_object('name',p_name,'manager',p_manager));
 return v_id;
end;
$function$;

create or replace function public.company_upsert_position(p_company_id uuid,p_position_id uuid,p_title text,p_description text,p_department_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_company_member(p_company_id,'jobs.manage') then raise exception 'Sem permissão para administrar cargos.'; end if;
 if length(trim(coalesce(p_title,'')))<2 then raise exception 'Cargo inválido.'; end if;
 if p_department_id is not null and not exists(select 1 from public.company_departments where id=p_department_id and company_id=p_company_id and status='active') then
  raise exception 'Departamento não pertence à empresa ou está inativo.';
 end if;
 if p_position_id is null then
  insert into public.job_positions(company_id,title,description,department_id,created_by)
  values(p_company_id,trim(p_title),nullif(trim(p_description),''),p_department_id,auth.uid()) returning id into v_id;
 else
  update public.job_positions set title=trim(p_title),description=nullif(trim(p_description),''),department_id=p_department_id
  where id=p_position_id and company_id=p_company_id returning id into v_id;
  if v_id is null then raise exception 'Cargo não encontrado.'; end if;
 end if;
 perform public.company_audit(p_company_id,'position_saved','job_position',v_id,jsonb_build_object('title',p_title));
 return v_id;
end;
$function$;

create or replace function public.company_reconcile_financial_record(p_record_id uuid,p_bank_transaction_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.company_financial_records%rowtype; t public.bank_transactions%rowtype; a public.bank_accounts%rowtype; v_status text;
begin
 select * into r from public.company_financial_records where id=p_record_id for update;
 if not found or not public.is_company_member(r.company_id,'finance.manage') then raise exception 'Registro financeiro indisponível ou sem permissão.'; end if;
 if r.record_status<>'planned' then raise exception 'Somente registros planejados podem ser conciliados.'; end if;
 select * into t from public.bank_transactions where id=p_bank_transaction_id and status='completed';
 if not found then raise exception 'Movimentação bancária não encontrada ou não concluída.'; end if;
 select * into a from public.bank_accounts where id=t.account_id;
 if not found or a.owner_company_id<>r.company_id or a.currency_id<>r.currency_id or t.amount<>r.amount then raise exception 'Movimentação não corresponde à conta, empresa, moeda e valor do registro.'; end if;
 if r.record_type='revenue' and t.transaction_type not in ('transfer_in','deposit','loan_disbursement') then raise exception 'Movimentação não representa recebimento.'; end if;
 if r.record_type='expense' and t.transaction_type not in ('transfer_out','withdrawal','fee','tax_payment','loan_payment') then raise exception 'Movimentação não representa despesa.'; end if;
 v_status:=case when r.record_type='revenue' then 'received' else 'paid' end;
 update public.company_financial_records set record_status=v_status,reference_type='bank_transaction',reference_id=t.id where id=r.id;
 perform public.company_audit(r.company_id,'financial_record_reconciled','financial_record',r.id,jsonb_build_object('bank_transaction_id',t.id,'status',v_status));
end;
$function$;

do $etapa10$
declare f record;
begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('company_manage_member','company_upsert_department','company_upsert_position','company_reconcile_financial_record')
 loop
  execute format('revoke all on function %s from public,anon',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $etapa10$;

commit;
