-- WORLD ECONOMY — ETAPA 11: emissão de identidade, revisão de vistos e travessia efetiva
begin;

-- A Etapa 5 criou a estrutura documental, mas não provisionava o documento de identidade.
update public.citizen_documents
set identification_code = 'ID-WE-' || upper(substr(replace(id::text,'-',''),1,12))
where document_type='national_identity' and identification_code is null;

create or replace function public.ensure_my_national_identity()
returns jsonb
language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; d public.citizen_documents%rowtype; v_number text; v_code text;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into p from public.profiles where id=auth.uid() for update;
  if not found or p.role<>'citizen' or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' then
    raise exception 'Somente cidadãos com cadastro ativo podem emitir identidade digital.';
  end if;
  if p.country_id is null then raise exception 'Defina sua nacionalidade antes de emitir a identidade digital.'; end if;
  select * into d from public.citizen_documents where profile_id=p.id and document_type='national_identity' and status='active' order by issued_at desc limit 1;
  if d.id is null then
    v_number := 'WE-ID-' || coalesce(p.player_number::text,upper(substr(replace(p.id::text,'-',''),1,12)));
    v_code := 'ID-WE-' || coalesce(p.player_number::text,upper(substr(replace(p.id::text,'-',''),1,12)));
    insert into public.citizen_documents(profile_id,country_id,document_type,document_number,status,issued_by,identification_code,metadata)
    values(p.id,p.country_id,'national_identity',v_number,'active',auth.uid(),v_code,jsonb_build_object('fictional',true,'permanent_player_number',p.player_number))
    returning * into d;
    insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,new_values)
    values(auth.uid(),p.id,p.country_id,'national_identity',d.id,'issued','Emissão inicial da identidade digital fictícia.',jsonb_build_object('document_number',d.document_number,'identification_code',d.identification_code));
  elsif d.identification_code is null then
    update public.citizen_documents set identification_code='ID-WE-'||upper(substr(replace(id::text,'-',''),1,12)) where id=d.id returning * into d;
  end if;
  return jsonb_build_object('id',d.id,'document_number',d.document_number,'identification_code',d.identification_code,'status',d.status,'issued_at',d.issued_at,'expires_at',d.expires_at,'country_id',d.country_id);
end;$function$;

create or replace function public.submit_visa_application(p_visa_type_id uuid,p_entry date,p_exit date,p_purpose text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v public.visa_types%rowtype; p public.profiles%rowtype; rid uuid;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into p from public.profiles where id=auth.uid() for update;
  if not found or p.role<>'citizen' or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' then raise exception 'Conta não elegível para solicitar visto.'; end if;
  select * into v from public.visa_types where id=p_visa_type_id and is_active;
  if not found then raise exception 'Tipo de visto indisponível.'; end if;
  if p_purpose not in ('tourism','work','business','residence','official_visit','transit') or p_purpose<>v.purpose then raise exception 'A finalidade precisa corresponder à categoria de visto.'; end if;
  if p_entry is null or p_exit is null or p_exit<p_entry or p_entry<current_date or p_exit>p_entry+v.duration_days then raise exception 'Período inválido ou superior à duração permitida para este visto.'; end if;
  if not exists(select 1 from public.citizen_passports cp where cp.profile_id=p.id and cp.status='active' and cp.expires_at::date>=p_exit) then raise exception 'É necessário passaporte válido até o fim do período solicitado.'; end if;
  if exists(select 1 from public.visa_applications where profile_id=p.id and visa_type_id=v.id and status in ('pending','in_review','approved') and intended_entry<=p_exit and intended_exit>=p_entry) then raise exception 'Já existe solicitação ou autorização de visto para período sobreposto.'; end if;
  insert into public.visa_applications(profile_id,destination_country_id,visa_type_id,purpose,intended_entry,intended_exit)
  values(p.id,v.country_id,v.id,p_purpose,p_entry,p_exit) returning id into rid;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,new_values)
  values(auth.uid(),p.id,v.country_id,'visa_application',rid,'requested','Solicitação de visto enviada.',jsonb_build_object('purpose',p_purpose,'entry',p_entry,'exit',p_exit));
  return rid;
end;$function$;

create or replace function public.review_visa_application(p_application_id uuid,p_decision text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare v public.visa_applications%rowtype; auth_id uuid;
begin
  if auth.uid() is null or p_decision not in ('approve','reject') then raise exception 'Decisão inválida.'; end if;
  select * into v from public.visa_applications where id=p_application_id and status in ('pending','in_review') for update;
  if not found then raise exception 'Solicitação não encontrada ou já processada.'; end if;
  if not (public.is_world_admin() or public.is_country_president(v.destination_country_id) or public.has_government_permission(v.destination_country_id,'immigration.review',null,null)) then raise exception 'Sem permissão para analisar vistos deste país.'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'Justificativa obrigatória.'; end if;
  if p_decision='approve' then
    if not exists(select 1 from public.citizen_passports cp where cp.profile_id=v.profile_id and cp.status='active' and cp.expires_at::date>=v.intended_exit) then raise exception 'Passaporte do solicitante não cobre mais o período do visto.'; end if;
    if not exists(select 1 from public.visa_types vt where vt.id=v.visa_type_id and vt.country_id=v.destination_country_id and vt.is_active and vt.purpose=v.purpose) then raise exception 'Categoria de visto desativada ou incompatível.'; end if;
    insert into public.travel_authorizations(profile_id,destination_country_id,visa_application_id,authorization_type,valid_from,valid_until,issued_by)
    values(v.profile_id,v.destination_country_id,v.id,'visa',v.intended_entry,v.intended_exit,auth.uid()) returning id into auth_id;
    update public.visa_applications set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_reason) where id=v.id;
  else
    update public.visa_applications set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),review_note=trim(p_reason) where id=v.id;
  end if;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values)
  values(auth.uid(),v.profile_id,v.destination_country_id,'visa_application',v.id,p_decision,trim(p_reason),jsonb_build_object('status',v.status),jsonb_build_object('status',case when p_decision='approve' then 'approved' else 'rejected' end,'authorization_id',auth_id));
  return jsonb_build_object('status',case when p_decision='approve' then 'approved' else 'rejected' end,'authorization_id',auth_id);
end;$function$;

create or replace function public.admin_create_visa_type(p_country_id uuid,p_code text,p_name text,p_purpose text,p_duration_days integer,p_fee numeric,p_currency text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare rid uuid; v_currency text;
begin
  if auth.uid() is null or not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_government_permission(p_country_id,'immigration.rules',null,null)) then raise exception 'Sem permissão para configurar vistos.'; end if;
  if nullif(trim(p_code),'') is null or nullif(trim(p_name),'') is null or p_purpose not in ('tourism','work','business','residence','official_visit','transit') or p_duration_days not between 1 and 3650 or p_fee is null or p_fee<0 then raise exception 'Parâmetros inválidos.'; end if;
  select currency_code into v_currency from public.countries where id=p_country_id and is_active;
  if v_currency is null then raise exception 'País ou moeda nacional não configurados.'; end if;
  if p_currency is not null and upper(trim(p_currency))<>upper(v_currency) then raise exception 'A taxa do visto deve usar a moeda nacional vigente do país.'; end if;
  insert into public.visa_types(country_id,code,name,purpose,duration_days,fee_amount,currency_code,created_by)
  values(p_country_id,upper(trim(p_code)),trim(p_name),p_purpose,p_duration_days,p_fee,upper(v_currency),auth.uid()) returning id into rid;
  insert into public.document_audit_logs(actor_id,country_id,object_type,object_id,action,reason,new_values)
  values(auth.uid(),p_country_id,'visa_type',rid,'created','Categoria de visto configurada.',jsonb_build_object('code',upper(trim(p_code)),'purpose',p_purpose,'duration_days',p_duration_days,'fee_amount',p_fee,'currency_code',upper(v_currency)));
  return rid;
end;$function$;

create or replace function public.admin_set_passport_status(p_profile_id uuid,p_status text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare cp public.citizen_passports%rowtype; p_country uuid;
begin
  select country_id into p_country from public.profiles where id=p_profile_id;
  if p_country is null then raise exception 'Cidadão sem país emissor.'; end if;
  if not (public.is_world_admin() or public.is_country_president(p_country) or public.has_government_permission(p_country,'documents.manage',null,null)) then raise exception 'Sem permissão para administrar este passaporte.'; end if;
  if p_status not in ('active','suspended','cancelled') or nullif(trim(p_reason),'') is null then raise exception 'Situação e justificativa obrigatórias.'; end if;
  select * into cp from public.citizen_passports where profile_id=p_profile_id for update;
  if not found then raise exception 'Passaporte não encontrado.'; end if;
  update public.citizen_passports set status=case when p_status='suspended' then 'under_review' else p_status end,updated_at=now() where profile_id=p_profile_id;
  update public.citizen_documents set status=case when p_status='suspended' then 'under_review' else p_status end,revoked_at=case when p_status in ('cancelled','suspended') then now() else revoked_at end,revocation_reason=case when p_status in ('cancelled','suspended') then trim(p_reason) else revocation_reason end
  where profile_id=p_profile_id and document_type='other' and metadata->>'kind'='passport' and status in ('active','under_review');
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values)
  values(auth.uid(),p_profile_id,p_country,'passport',cp.id,'status_changed',trim(p_reason),jsonb_build_object('status',cp.status),jsonb_build_object('status',p_status));
end;$function$;

create or replace function public.record_world_border_crossing(p_travel_request_id uuid,p_result text,p_reason text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare r public.travel_requests%rowtype; iid uuid; v_doc boolean; v_passport boolean; v_rule public.border_rules%rowtype;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  select * into r from public.travel_requests where id=p_travel_request_id and status='authorized' for update;
  if not found then raise exception 'Viagem autorizada não encontrada ou travessia já registrada.'; end if;
  if not (public.is_world_admin() or public.is_country_president(r.destination_country_id) or public.has_government_permission(r.destination_country_id,'immigration.review',null,null)) then raise exception 'Sem permissão para controle de fronteira do país de destino.'; end if;
  if p_result not in ('approved','rejected') or nullif(trim(p_reason),'') is null then raise exception 'Resultado e justificativa obrigatórios.'; end if;
  if r.intended_entry is not null and current_date<r.intended_entry then raise exception 'A data prevista da viagem ainda não chegou.'; end if;
  if r.intended_exit is not null and current_date>r.intended_exit then raise exception 'O período autorizado já terminou.'; end if;
  select exists(select 1 from public.citizen_documents cd where cd.id=r.document_id and cd.profile_id=r.profile_id and cd.status='active' and (cd.expires_at is null or cd.expires_at>now())) into v_doc;
  select exists(select 1 from public.citizen_passports cp where cp.profile_id=r.profile_id and cp.status='active' and cp.expires_at::date>=current_date) into v_passport;
  if p_result='approved' and (not v_doc or not v_passport) then raise exception 'Documento ou passaporte inválido no momento da travessia.'; end if;
  select * into v_rule from public.border_rules where country_id=r.destination_country_id and effective_from<=now() and (effective_until is null or effective_until>now()) order by effective_from desc limit 1;
  if found and p_result='approved' then
    if not v_rule.allow_entry or r.origin_country_id=any(v_rule.restricted_origin_countries) then raise exception 'Regra de fronteira não permite a entrada.'; end if;
    if v_rule.requires_visa and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=r.profile_id and ta.destination_country_id=r.destination_country_id and ta.status='active' and ta.valid_from<=current_date and ta.valid_until>=current_date) then raise exception 'Visto não está válido na data da entrada.'; end if;
    if v_rule.requires_travel_authorization and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=r.profile_id and ta.destination_country_id=r.destination_country_id and ta.status='active' and ta.valid_from<=current_date and ta.valid_until>=current_date) then raise exception 'Autorização especial não está válida na data da entrada.'; end if;
  end if;
  insert into public.immigration_records(travel_request_id,profile_id,origin_country_id,destination_country_id,document_id,airport_id,result,reason,officer_id)
  values(r.id,r.profile_id,r.origin_country_id,r.destination_country_id,r.document_id,r.destination_airport_id,p_result,trim(p_reason),auth.uid()) returning id into iid;
  insert into public.emigration_records(travel_request_id,profile_id,origin_country_id,destination_country_id,document_id,airport_id,result,reason,officer_id)
  values(r.id,r.profile_id,r.origin_country_id,r.destination_country_id,r.document_id,r.origin_airport_id,case when p_result='approved' then 'approved' else 'approved' end,case when p_result='rejected' then 'Saída registrada; entrada recusada no destino. '||trim(p_reason) else trim(p_reason) end,auth.uid());
  update public.travel_requests set status=case when p_result='approved' then 'completed' else 'rejected' end where id=r.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values)
  values(auth.uid(),r.profile_id,r.destination_country_id,'border_crossing',iid,p_result,trim(p_reason),jsonb_build_object('status',r.status),jsonb_build_object('status',case when p_result='approved' then 'completed' else 'rejected' end));
  return iid;
end;$function$;

do $grants$
begin
  revoke all on function public.ensure_my_national_identity() from public,anon;
  grant execute on function public.ensure_my_national_identity() to authenticated;
  revoke all on function public.admin_set_passport_status(uuid,text,text) from public,anon;
  grant execute on function public.admin_set_passport_status(uuid,text,text) to authenticated;
end;$grants$;
commit;
