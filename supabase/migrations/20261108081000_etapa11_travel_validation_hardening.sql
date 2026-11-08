-- Etapa 11 — hardening de datas de viagem e validação documental na autorização
begin;
alter table public.travel_requests
  add column if not exists intended_entry date,
  add column if not exists intended_exit date;

create or replace function public.submit_world_travel_request(p_origin_airport uuid,p_destination_airport uuid,p_document_id uuid,p_purpose text,p_entry date,p_exit date)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; o public.airports%rowtype; d public.airports%rowtype; doc public.citizen_documents%rowtype; rid uuid; br public.border_rules%rowtype; has_rule boolean;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if p_purpose not in ('tourism','work','business','residence','official_visit','transit') then raise exception 'Finalidade inválida.'; end if;
  select * into p from public.profiles where id=auth.uid();
  select * into o from public.airports where id=p_origin_airport and status='active';
  select * into d from public.airports where id=p_destination_airport and status='active';
  select * into doc from public.citizen_documents where id=p_document_id and profile_id=auth.uid() and status='active' and (expires_at is null or expires_at>now());
  if o.id is null or d.id is null or doc.id is null then raise exception 'Aeroportos ativos e documento válido são obrigatórios.'; end if;
  if o.country_id=d.country_id or o.country_id is distinct from p.country_id then raise exception 'Origem/destino ou nacionalidade incompatível.'; end if;
  if p_entry<current_date or p_exit<p_entry then raise exception 'Datas inválidas.'; end if;
  select * into br from public.border_rules where country_id=d.country_id and effective_from<=now() and (effective_until is null or effective_until>now()) order by effective_from desc limit 1;
  has_rule := found;
  if not exists(select 1 from public.citizen_passports cp where cp.profile_id=p.id and cp.status='active' and cp.expires_at::date>=p_exit) then
    raise exception 'Passaporte válido até o fim da viagem é obrigatório.';
  end if;
  if has_rule then
    if not br.allow_entry or o.country_id=any(br.restricted_origin_countries) then raise exception 'As regras atuais de fronteira não permitem esta entrada.'; end if;
    if br.requires_visa and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=p.id and ta.destination_country_id=d.country_id and ta.status='active' and ta.valid_from<=p_entry and ta.valid_until>=p_exit) then raise exception 'Visto/autorização válido obrigatório.'; end if;
    if br.requires_travel_authorization and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=p.id and ta.destination_country_id=d.country_id and ta.status='active' and ta.valid_from<=p_entry and ta.valid_until>=p_exit) then raise exception 'Autorização especial obrigatória.'; end if;
  end if;
  insert into public.travel_requests(profile_id,origin_country_id,destination_country_id,origin_airport_id,destination_airport_id,purpose,document_id,passport_id,status,intended_entry,intended_exit)
  values(p.id,o.country_id,d.country_id,o.id,d.id,p_purpose,doc.id,(select id from public.citizen_passports where profile_id=p.id and status='active'),'requested',p_entry,p_exit) returning id into rid;
  return rid;
end;$function$;

create or replace function public.decide_world_travel(p_request_id uuid,p_decision text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare r public.travel_requests%rowtype; br public.border_rules%rowtype;
begin
  select * into r from public.travel_requests where id=p_request_id and status in ('requested','in_review') for update;
  if not found then raise exception 'Viagem não encontrada ou já decidida.'; end if;
  if not (public.is_world_admin() or public.is_country_president(r.destination_country_id) or public.has_government_permission(r.destination_country_id,'immigration.review',null,null)) then raise exception 'Sem permissão para decidir entrada no país.'; end if;
  if p_decision not in ('authorized','rejected') or nullif(trim(p_reason),'') is null then raise exception 'Decisão e justificativa obrigatórias.'; end if;
  if p_decision='authorized' then
    if r.intended_entry is null or r.intended_exit is null then raise exception 'A solicitação não possui período de viagem válido.'; end if;
    if not exists(select 1 from public.citizen_documents cd where cd.id=r.document_id and cd.profile_id=r.profile_id and cd.status='active' and (cd.expires_at is null or cd.expires_at>=r.intended_exit::timestamptz)) then raise exception 'Documento utilizado está inválido para o período informado.'; end if;
    if not exists(select 1 from public.citizen_passports cp where cp.profile_id=r.profile_id and cp.status='active' and cp.expires_at::date>=r.intended_exit) then raise exception 'Passaporte não cobre todo o período da viagem.'; end if;
    select * into br from public.border_rules where country_id=r.destination_country_id and effective_from<=now() and (effective_until is null or effective_until>now()) order by effective_from desc limit 1;
    if found then
      if not br.allow_entry or r.origin_country_id=any(br.restricted_origin_countries) then raise exception 'Regra de fronteira impede a entrada.'; end if;
      if br.requires_visa and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=r.profile_id and ta.destination_country_id=r.destination_country_id and ta.status='active' and ta.valid_from<=r.intended_entry and ta.valid_until>=r.intended_exit) then raise exception 'Visto/autorização não cobre o período da viagem.'; end if;
      if br.requires_travel_authorization and not exists(select 1 from public.travel_authorizations ta where ta.profile_id=r.profile_id and ta.destination_country_id=r.destination_country_id and ta.status='active' and ta.valid_from<=r.intended_entry and ta.valid_until>=r.intended_exit) then raise exception 'Autorização especial não cobre o período da viagem.'; end if;
    end if;
  end if;
  update public.travel_requests set status=p_decision,decided_at=now(),decided_by=auth.uid(),decision_note=trim(p_reason) where id=r.id;
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,previous_values,new_values) values(auth.uid(),r.profile_id,r.destination_country_id,'travel_request',r.id,p_decision,trim(p_reason),jsonb_build_object('status',r.status),jsonb_build_object('status',p_decision));
end;$function$;
commit;