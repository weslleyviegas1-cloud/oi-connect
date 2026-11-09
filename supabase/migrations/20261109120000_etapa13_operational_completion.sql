-- WORLD ECONOMY / ETAPA 13 — Complements: country traffic rules, case parties and case documents.
begin;

create table if not exists public.traffic_fine_rules(
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 category text not null,
 description text not null,
 fine_amount numeric(24,2) not null check(fine_amount>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 is_active boolean not null default true,
 created_by uuid not null references public.profiles(id),
 updated_at timestamptz not null default now(),
 unique(country_id,category)
);
create index if not exists traffic_fine_rules_country_idx on public.traffic_fine_rules(country_id,is_active);
alter table public.traffic_fine_rules enable row level security;
create policy traffic_fine_rules_read on public.traffic_fine_rules for select to authenticated
 using(is_active or public.is_world_admin() or public.is_country_president(country_id));
revoke all on public.traffic_fine_rules from anon,authenticated;
grant select on public.traffic_fine_rules to authenticated;

create or replace function public.security_upsert_traffic_fine_rule(
 p_country uuid,p_category text,p_description text,p_amount numeric,p_active boolean default true
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_currency uuid; v_id uuid;
begin
 if not (public.is_world_admin() or public.is_country_president(p_country)) then raise exception 'Somente Super Admin ou Presidente pode configurar multas nacionais.'; end if;
 if length(trim(coalesce(p_category,'')))<2 or length(trim(coalesce(p_description,'')))<5 or p_amount<=0 then raise exception 'Regra de infração inválida.'; end if;
 select cu.id into v_currency from public.countries c join public.currencies cu on cu.internal_code=c.currency_code
 where c.id=p_country and c.is_active and cu.status='active';
 if v_currency is null then raise exception 'Moeda nacional ativa não configurada.'; end if;
 insert into public.traffic_fine_rules(country_id,category,description,fine_amount,currency_id,is_active,created_by,updated_at)
 values(p_country,trim(p_category),trim(p_description),p_amount,v_currency,p_active,auth.uid(),now())
 on conflict(country_id,category) do update set description=excluded.description,fine_amount=excluded.fine_amount,currency_id=excluded.currency_id,is_active=excluded.is_active,updated_at=now()
 returning id into v_id;
 perform public.justice_audit(p_country,'traffic_fine_rule_saved','traffic_fine_rule',v_id,jsonb_build_object('category',p_category,'amount',p_amount,'active',p_active));
 return v_id;
end; $$;

create or replace function public.traffic_issue_fine(p_violation uuid,p_amount numeric,p_due date,p_description text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.traffic_violations%rowtype; m public.police_members%rowtype; rule public.traffic_fine_rules%rowtype; f uuid; code text;
begin
 select * into v from public.traffic_violations where id=p_violation for update;
 if not found or v.officer_profile_id<>auth.uid() or not exists(
   select 1 from public.police_members x where x.profile_id=auth.uid() and x.department_id=v.department_id and x.status='active' and 'police.fine'=any(x.permissions)
 ) or p_amount<=0 then raise exception 'Somente agente autorizado que registrou a infração pode emitir a multa.'; end if;
 select * into m from public.police_members where profile_id=auth.uid() and country_id=v.country_id and department_id=v.department_id and status='active';
 select * into rule from public.traffic_fine_rules where country_id=v.country_id and lower(category)=lower(v.category) and is_active;
 if rule.id is null then raise exception 'O país ainda não configurou uma regra ativa para esta infração.'; end if;
 if p_amount<>rule.fine_amount then raise exception 'Valor diferente do valor oficial configurado para esta infração.'; end if;
 code:='ML-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.administrative_fines(fine_number,country_id,violation_id,recipient_profile_id,recipient_company_id,category,description,amount,currency_id,issuing_department_id,issued_by,due_at)
 values(code,v.country_id,v.id,v.responsible_profile_id,v.responsible_company_id,v.category,coalesce(nullif(trim(p_description),''),rule.description),rule.fine_amount,rule.currency_id,m.department_id,auth.uid(),p_due) returning id into f;
 update public.traffic_violations set status='fined' where id=v.id;
 perform public.justice_audit(v.country_id,'administrative_fine_issued','administrative_fine',f,jsonb_build_object('amount',rule.fine_amount,'rule_id',rule.id));
 return f;
end; $$;

create or replace function public.judicial_assign_case_party(p_case uuid,p_profile uuid,p_role text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.court_cases%rowtype; v uuid;
begin
 select * into c from public.court_cases where id=p_case for update;
 if not found or not (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id,array['judge','administrator'])) then raise exception 'Sem autorização para designar parte ou representante.'; end if;
 if p_role not in ('prosecutor','defender','lawyer','witness') then raise exception 'Função processual inválida.'; end if;
 if not exists(select 1 from public.profiles where id=p_profile and country_id=c.country_id and registration_status='active') then raise exception 'Perfil deve estar ativo e pertencer ao país do processo.'; end if;
 if p_role in ('prosecutor','defender','lawyer') and not exists(select 1 from public.judicial_members where profile_id=p_profile and country_id=c.country_id and status='active' and professional_role=case when p_role='prosecutor' then 'prosecutor' when p_role='defender' then 'defender' else 'lawyer' end) then raise exception 'O profissional não possui nomeação ativa para esta função.'; end if;
 if p_role='prosecutor' and exists(select 1 from public.court_case_parties where case_id=c.id and profile_id=p_profile and party_role in ('respondent','defender','lawyer')) then raise exception 'Conflito de função no processo.'; end if;
 if p_role='defender' and exists(select 1 from public.court_case_parties where case_id=c.id and profile_id=p_profile and party_role in ('claimant','prosecutor')) then raise exception 'Conflito de função no processo.'; end if;
 if c.assigned_judge_id=p_profile then raise exception 'O juiz designado não pode atuar como parte ou representante.'; end if;
 insert into public.court_case_parties(case_id,profile_id,party_role) values(c.id,p_profile,p_role) on conflict(case_id,profile_id,party_role) do nothing returning id into v;
 if v is null then select id into v from public.court_case_parties where case_id=c.id and profile_id=p_profile and party_role=p_role; end if;
 perform public.justice_audit(c.country_id,'case_party_assigned','court_case_party',v,jsonb_build_object('case_id',c.id,'profile_id',p_profile,'role',p_role));
 return v;
end; $$;

create or replace function public.judicial_add_case_document(
 p_case uuid,p_title text,p_storage_path text,p_description text default null,p_visibility text default 'parties'
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.court_cases%rowtype; v uuid;
begin
 select * into c from public.court_cases where id=p_case;
 if not found or not (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id) or public.is_court_case_party(c.id)) then raise exception 'Sem autorização para anexar documento ao processo.'; end if;
 if p_visibility='judicial_only' and not (public.is_world_admin() or public.is_judicial_member(c.country_id)) then raise exception 'Somente o Judiciário pode registrar documento sigiloso.'; end if;
 if p_visibility not in ('parties','judicial_only') or length(trim(coalesce(p_title,'')))<2 or length(trim(coalesce(p_storage_path,'')))<5 then raise exception 'Documento inválido. Informe título e referência de arquivo.'; end if;
 insert into public.court_case_documents(case_id,uploaded_by,document_title,storage_path,description,visibility)
 values(c.id,auth.uid(),trim(p_title),trim(p_storage_path),nullif(trim(p_description),''),p_visibility) returning id into v;
 perform public.justice_audit(c.country_id,'case_document_added','court_case_document',v,jsonb_build_object('case_id',c.id,'visibility',p_visibility));
 return v;
end; $$;

revoke all on function public.security_upsert_traffic_fine_rule(uuid,text,text,numeric,boolean),
 public.traffic_issue_fine(uuid,numeric,date,text),public.judicial_assign_case_party(uuid,uuid,text),
 public.judicial_add_case_document(uuid,text,text,text,text) from public,anon;
grant execute on function public.security_upsert_traffic_fine_rule(uuid,text,text,numeric,boolean),
 public.traffic_issue_fine(uuid,numeric,date,text),public.judicial_assign_case_party(uuid,uuid,text),
 public.judicial_add_case_document(uuid,text,text,text,text) to authenticated;
commit;