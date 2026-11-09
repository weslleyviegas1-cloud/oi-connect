-- WORLD ECONOMY / ETAPA 13 — Segurança pública, fiscalização e justiça.
-- Aditiva: usa profiles, countries, companies, vehicles, bank_accounts e treasury existentes.
begin;

create table if not exists public.security_departments(
 id uuid primary key default gen_random_uuid(), country_id uuid not null references public.countries(id) on delete restrict,
 name text not null, institution_type text not null check(institution_type in ('national','civil','military_police','highway','federal','border','investigation','municipal','other')),
 description text, status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 director_profile_id uuid references public.profiles(id) on delete restrict, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(country_id,name)
);
create table if not exists public.police_members(
 id uuid primary key default gen_random_uuid(), department_id uuid not null references public.security_departments(id) on delete restrict,
 country_id uuid not null references public.countries(id) on delete restrict, profile_id uuid not null references public.profiles(id) on delete restrict,
 badge_number text not null, position text not null, rank_level integer not null default 1 check(rank_level between 1 and 20),
 status text not null default 'pending' check(status in ('pending','active','suspended','transferred','dismissed')),
 appointed_by uuid references public.profiles(id), joined_at timestamptz not null default now(), ended_at timestamptz,
 created_at timestamptz not null default now(), unique(country_id,badge_number), unique(department_id,profile_id)
);
create table if not exists public.police_occurrences(
 id uuid primary key default gen_random_uuid(), occurrence_number text not null unique, country_id uuid not null references public.countries(id),
 department_id uuid not null references public.security_departments(id), category text not null, location text not null,
 description text not null, involved_profile_ids uuid[] not null default '{}', vehicle_id uuid references public.vehicles(id),
 status text not null default 'open' check(status in ('open','under_review','referred','closed','archived')),
 responsible_profile_id uuid not null references public.profiles(id), created_by uuid not null references public.profiles(id),
 occurred_at timestamptz not null default now(), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.citizen_reports(
 id uuid primary key default gen_random_uuid(), protocol text not null unique, country_id uuid not null references public.countries(id),
 category text not null, location text, description text not null, involved_profile_ids uuid[] not null default '{}',
 is_anonymous boolean not null default false, reporter_profile_id uuid references public.profiles(id), submitted_by uuid references public.profiles(id),
 assigned_department_id uuid references public.security_departments(id), status text not null default 'submitted'
 check(status in ('submitted','triaged','investigating','referred','dismissed','closed')),
 resolution_note text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.investigations(
 id uuid primary key default gen_random_uuid(), investigation_number text not null unique, country_id uuid not null references public.countries(id),
 occurrence_id uuid references public.police_occurrences(id), report_id uuid references public.citizen_reports(id),
 department_id uuid not null references public.security_departments(id), lead_profile_id uuid not null references public.profiles(id),
 subject_profile_ids uuid[] not null default '{}', title text not null, summary text not null,
 status text not null default 'open' check(status in ('open','in_progress','referred_to_court','closed','archived')),
 closing_note text, created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.traffic_violations(
 id uuid primary key default gen_random_uuid(), violation_number text not null unique, country_id uuid not null references public.countries(id),
 vehicle_id uuid not null references public.vehicles(id), responsible_profile_id uuid references public.profiles(id), responsible_company_id uuid references public.companies(id),
 category text not null, description text not null, officer_profile_id uuid not null references public.profiles(id),
 occurred_at timestamptz not null default now(), status text not null default 'recorded' check(status in ('recorded','fined','contested','cancelled','resolved')),
 created_at timestamptz not null default now()
);
create table if not exists public.administrative_fines(
 id uuid primary key default gen_random_uuid(), fine_number text not null unique, country_id uuid not null references public.countries(id),
 violation_id uuid references public.traffic_violations(id), recipient_profile_id uuid references public.profiles(id),
 recipient_company_id uuid references public.companies(id), category text not null, description text not null,
 amount numeric(24,2) not null check(amount>0), currency_id uuid not null references public.currencies(id),
 issuing_department_id uuid not null references public.security_departments(id), issued_by uuid not null references public.profiles(id),
 due_at date not null, status text not null default 'pending' check(status in ('pending','contested','paid','cancelled','overdue','under_review')),
 bank_transaction_id uuid references public.bank_transactions(id), idempotency_key text unique,
 created_at timestamptz not null default now(), check((recipient_profile_id is not null)::int+(recipient_company_id is not null)::int=1)
);
create table if not exists public.fine_appeals(
 id uuid primary key default gen_random_uuid(), fine_id uuid not null references public.administrative_fines(id) on delete restrict,
 appellant_profile_id uuid not null references public.profiles(id), grounds text not null,
 status text not null default 'submitted' check(status in ('submitted','under_review','accepted','rejected')),
 reviewed_by uuid references public.profiles(id), decision_note text, created_at timestamptz not null default now(), reviewed_at timestamptz
);
create table if not exists public.judicial_institutions(
 id uuid primary key default gen_random_uuid(), country_id uuid not null references public.countries(id), name text not null,
 institution_type text not null check(institution_type in ('national_court','regional_court','small_claims','specialized_court','prosecution','public_defender','bar_association','other')),
 status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 director_profile_id uuid references public.profiles(id), created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 unique(country_id,name)
);
create table if not exists public.judicial_members(
 id uuid primary key default gen_random_uuid(), institution_id uuid not null references public.judicial_institutions(id) on delete restrict,
 country_id uuid not null references public.countries(id), profile_id uuid not null references public.profiles(id),
 professional_role text not null check(professional_role in ('judge','prosecutor','defender','lawyer','clerk','administrator')),
 registration_number text not null, status text not null default 'pending' check(status in ('pending','active','suspended','removed')),
 appointed_by uuid references public.profiles(id), created_at timestamptz not null default now(),
 unique(country_id,registration_number), unique(institution_id,profile_id)
);
create table if not exists public.court_cases(
 id uuid primary key default gen_random_uuid(), case_number text not null unique, country_id uuid not null references public.countries(id),
 institution_id uuid not null references public.judicial_institutions(id), investigation_id uuid references public.investigations(id),
 fine_id uuid references public.administrative_fines(id), category text not null, title text not null, summary text not null,
 claimant_profile_id uuid references public.profiles(id), respondent_profile_id uuid references public.profiles(id),
 assigned_judge_id uuid references public.profiles(id), status text not null default 'open' check(status in ('open','under_review','in_hearing','suspended','concluded','archived')),
 opened_by uuid not null references public.profiles(id), opened_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.court_case_parties(
 id uuid primary key default gen_random_uuid(), case_id uuid not null references public.court_cases(id) on delete restrict,
 profile_id uuid not null references public.profiles(id), party_role text not null check(party_role in ('claimant','respondent','prosecutor','defender','lawyer','witness')),
 created_at timestamptz not null default now(), unique(case_id,profile_id,party_role)
);
create table if not exists public.court_hearings(
 id uuid primary key default gen_random_uuid(), case_id uuid not null references public.court_cases(id), scheduled_at timestamptz not null,
 responsible_judge_id uuid not null references public.profiles(id), participants jsonb not null default '[]', notes text,
 status text not null default 'scheduled' check(status in ('scheduled','held','cancelled','rescheduled')),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.court_decisions(
 id uuid primary key default gen_random_uuid(), case_id uuid not null references public.court_cases(id), decision_number text not null unique,
 judge_profile_id uuid not null references public.profiles(id), outcome text not null, reasoning text not null,
 published_at timestamptz not null default now(), supersedes_decision_id uuid references public.court_decisions(id), created_at timestamptz not null default now()
);
create table if not exists public.court_appeals(
 id uuid primary key default gen_random_uuid(), case_id uuid not null references public.court_cases(id), decision_id uuid references public.court_decisions(id),
 appellant_profile_id uuid not null references public.profiles(id), grounds text not null,
 status text not null default 'submitted' check(status in ('submitted','under_review','accepted','rejected','decided')),
 reviewed_by uuid references public.profiles(id), decision_note text, created_at timestamptz not null default now()
);
create table if not exists public.correctional_facilities(
 id uuid primary key default gen_random_uuid(), country_id uuid not null references public.countries(id), name text not null,
 facility_identifier text not null, responsible_profile_id uuid references public.profiles(id),
 administrative_capacity integer not null default 0 check(administrative_capacity>=0),
 status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(), unique(country_id,facility_identifier)
);
create table if not exists public.correctional_records(
 id uuid primary key default gen_random_uuid(), facility_id uuid not null references public.correctional_facilities(id),
 country_id uuid not null references public.countries(id), profile_id uuid not null references public.profiles(id),
 case_id uuid not null references public.court_cases(id), decision_id uuid not null references public.court_decisions(id),
 record_type text not null check(record_type in ('admission','release')), recorded_by uuid not null references public.profiles(id),
 recorded_at timestamptz not null default now(), legal_basis text not null
);
create table if not exists public.justice_audit_logs(
 id bigint generated always as identity primary key, country_id uuid references public.countries(id), actor_id uuid references public.profiles(id),
 action text not null, entity_type text not null, entity_id uuid, details jsonb not null default '{}', created_at timestamptz not null default now()
);

create index if not exists police_members_profile_idx on public.police_members(profile_id,status);
create index if not exists occurrences_country_date_idx on public.police_occurrences(country_id,created_at desc);
create index if not exists reports_country_date_idx on public.citizen_reports(country_id,created_at desc);
create index if not exists investigations_country_idx on public.investigations(country_id,status);
create index if not exists fines_recipient_idx on public.administrative_fines(recipient_profile_id,status);
create index if not exists court_cases_country_status_idx on public.court_cases(country_id,status,opened_at desc);
create index if not exists court_parties_profile_idx on public.court_case_parties(profile_id,case_id);
create index if not exists correctional_records_profile_idx on public.correctional_records(profile_id,recorded_at desc);

create or replace function public.is_police_member(p_country uuid,p_permission text default null)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.police_members m join public.security_departments d on d.id=m.department_id
 where m.profile_id=auth.uid() and m.country_id=p_country and m.status='active' and d.status='active'
 and (p_permission is null or p_permission in ('police.read','police.manage','police.investigate','police.fine')))
$$;
create or replace function public.is_judicial_member(p_country uuid,p_roles text[] default null)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.judicial_members m join public.judicial_institutions i on i.id=m.institution_id
 where m.profile_id=auth.uid() and m.country_id=p_country and m.status='active' and i.status='active'
 and (p_roles is null or m.professional_role=any(p_roles)))
$$;
create or replace function public.justice_audit(p_country uuid,p_action text,p_type text,p_id uuid,p_details jsonb default '{}')
returns void language plpgsql security definer set search_path=public,auth as $$
 begin insert into public.justice_audit_logs(country_id,actor_id,action,entity_type,entity_id,details)
 values(p_country,auth.uid(),p_action,p_type,p_id,coalesce(p_details,'{}')); end; $$;

-- Policies: read scopes are explicit; writes only through validated SECURITY DEFINER RPCs.
do $$ declare t text; begin
 foreach t in array array['security_departments','police_members','police_occurrences','citizen_reports','investigations','traffic_violations','administrative_fines','fine_appeals','judicial_institutions','judicial_members','court_cases','court_case_parties','court_hearings','court_decisions','court_appeals','correctional_facilities','correctional_records','justice_audit_logs'] loop
  execute format('alter table public.%I enable row level security',t);
 end loop;
end $$;
create policy security_departments_read on public.security_departments for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id));
create policy police_members_read on public.police_members for select to authenticated using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or public.is_police_member(country_id));
create policy police_occurrences_read on public.police_occurrences for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.is_police_member(country_id) or responsible_profile_id=auth.uid() or auth.uid()=any(involved_profile_ids));
create policy citizen_reports_read on public.citizen_reports for select to authenticated using(submitted_by=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or (assigned_department_id is not null and public.is_police_member(country_id)));
create policy investigations_read on public.investigations for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.is_police_member(country_id) or auth.uid()=any(subject_profile_ids));
create policy traffic_violations_read on public.traffic_violations for select to authenticated using(responsible_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or public.is_police_member(country_id));
create policy administrative_fines_read on public.administrative_fines for select to authenticated using(recipient_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or public.is_police_member(country_id) or (recipient_company_id is not null and public.is_company_member(recipient_company_id,'finance.read')));
create policy fine_appeals_read on public.fine_appeals for select to authenticated using(appellant_profile_id=auth.uid() or public.is_world_admin() or exists(select 1 from public.administrative_fines f where f.id=fine_id and (public.is_country_president(f.country_id) or public.is_police_member(f.country_id))));
create policy judicial_institutions_read on public.judicial_institutions for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id));
create policy judicial_members_read on public.judicial_members for select to authenticated using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or public.is_judicial_member(country_id));

create or replace function public.is_court_case_party(p_case uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
 select exists(select 1 from public.court_case_parties where case_id=p_case and profile_id=auth.uid())
$;
revoke all on function public.is_court_case_party(uuid) from public,anon;
grant execute on function public.is_court_case_party(uuid) to authenticated;

create policy court_cases_read on public.court_cases for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or public.is_judicial_member(country_id) or public.is_court_case_party(id));
create policy court_parties_read on public.court_case_parties for select to authenticated using(profile_id=auth.uid() or exists(select 1 from public.court_cases c where c.id=case_id and (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id))));
create policy court_hearings_read on public.court_hearings for select to authenticated using(exists(select 1 from public.court_cases c where c.id=case_id and (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id) or public.is_court_case_party(c.id))));
create policy court_decisions_read on public.court_decisions for select to authenticated using(exists(select 1 from public.court_cases c where c.id=case_id and (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id) or exists(select 1 from public.court_case_parties p where p.case_id=c.id and p.profile_id=auth.uid()))));
create policy court_appeals_read on public.court_appeals for select to authenticated using(appellant_profile_id=auth.uid() or exists(select 1 from public.court_cases c where c.id=case_id and (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id))));
create policy correctional_facilities_read on public.correctional_facilities for select to authenticated using(status='active' or public.is_world_admin() or public.is_country_president(country_id) or public.is_judicial_member(country_id,array['judge','administrator']));
create policy correctional_records_read on public.correctional_records for select to authenticated using(profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(country_id) or public.is_judicial_member(country_id,array['judge','administrator']));
create policy justice_audit_read on public.justice_audit_logs for select to authenticated using(public.is_world_admin() or (country_id is not null and public.is_country_president(country_id)));


revoke all on function public.justice_audit(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
create or replace function public.judicial_create_facility(p_country uuid,p_name text,p_identifier text,p_capacity integer)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v uuid;
begin
 if not (public.is_world_admin() or public.is_country_president(p_country) or public.is_judicial_member(p_country,array['administrator'])) then raise exception 'Sem permissão para cadastrar unidade.'; end if;
 insert into public.correctional_facilities(country_id,name,facility_identifier,administrative_capacity,status,created_by)
 values(p_country,trim(p_name),upper(trim(p_identifier)),p_capacity,'active',auth.uid()) returning id into v;
 perform public.justice_audit(p_country,'correctional_facility_created','correctional_facility',v,'{}'); return v;
end; $;

create table if not exists public.police_member_history(
 id uuid primary key default gen_random_uuid(), member_id uuid not null references public.police_members(id), country_id uuid not null references public.countries(id),
 previous_status text, new_status text not null, previous_position text, new_position text, changed_by uuid not null references public.profiles(id),
 reason text not null, created_at timestamptz not null default now()
);
create table if not exists public.investigation_notes(
 id uuid primary key default gen_random_uuid(), investigation_id uuid not null references public.investigations(id),
 author_profile_id uuid not null references public.profiles(id), note_type text not null check(note_type in ('note','statement','evidence_reference','referral')),
 content text not null, evidence_url text, created_at timestamptz not null default now()
);
create table if not exists public.court_case_documents(
 id uuid primary key default gen_random_uuid(), case_id uuid not null references public.court_cases(id),
 uploaded_by uuid not null references public.profiles(id), document_title text not null, storage_path text,
 description text, visibility text not null default 'parties' check(visibility in ('parties','judicial_only')),
 created_at timestamptz not null default now()
);
alter table public.police_member_history enable row level security;
alter table public.investigation_notes enable row level security;
alter table public.court_case_documents enable row level security;
create policy police_member_history_read on public.police_member_history for select to authenticated using(public.is_world_admin() or public.is_country_president(country_id) or exists(select 1 from public.police_members m where m.id=member_id and m.profile_id=auth.uid()));
create policy investigation_notes_read on public.investigation_notes for select to authenticated using(exists(select 1 from public.investigations i where i.id=investigation_id and (public.is_world_admin() or public.is_country_president(i.country_id) or public.is_police_member(i.country_id) or auth.uid()=any(i.subject_profile_ids))));
create policy court_case_documents_read on public.court_case_documents for select to authenticated using(exists(select 1 from public.court_cases c where c.id=case_id and (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id) or (visibility='parties' and exists(select 1 from public.court_case_parties p where p.case_id=c.id and p.profile_id=auth.uid())))));
revoke all on public.police_member_history,public.investigation_notes,public.court_case_documents from anon,authenticated;
grant select on public.police_member_history,public.investigation_notes,public.court_case_documents to authenticated;
create or replace function public.police_update_member(p_member uuid,p_status text,p_position text,p_reason text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare m public.police_members%rowtype;
begin select * into m from public.police_members where id=p_member for update;
 if not found or not (public.is_world_admin() or public.is_country_president(m.country_id)) then raise exception 'Sem autorização para alterar vínculo funcional.'; end if;
 if p_status not in ('active','suspended','transferred','dismissed') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'Alteração inválida ou sem justificativa.'; end if;
 update public.police_members set status=p_status,position=coalesce(nullif(trim(p_position),''),position),ended_at=case when p_status='dismissed' then now() else null end where id=m.id;
 insert into public.police_member_history(member_id,country_id,previous_status,new_status,previous_position,new_position,changed_by,reason)
 values(m.id,m.country_id,m.status,p_status,m.position,coalesce(nullif(trim(p_position),''),m.position),auth.uid(),trim(p_reason));
 perform public.justice_audit(m.country_id,'police_member_updated','police_member',m.id,jsonb_build_object('status',p_status,'reason',p_reason));
end; $;
create or replace function public.police_add_investigation_note(p_investigation uuid,p_type text,p_content text,p_evidence_url text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare i public.investigations%rowtype; v uuid;
begin select * into i from public.investigations where id=p_investigation for update;
 if not found or not public.is_police_member(i.country_id) or (i.lead_profile_id<>auth.uid() and not public.is_world_admin() and not public.is_country_president(i.country_id)) then raise exception 'Sem autorização para registrar informação.'; end if;
 insert into public.investigation_notes(investigation_id,author_profile_id,note_type,content,evidence_url)
 values(i.id,auth.uid(),p_type,trim(p_content),nullif(trim(p_evidence_url),'')) returning id into v;
 perform public.justice_audit(i.country_id,'investigation_note_added','investigation_note',v,'{}'); return v;
end; $;
create or replace function public.judicial_review_fine_appeal(p_appeal uuid,p_accept boolean,p_note text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare a public.fine_appeals%rowtype; f public.administrative_fines%rowtype;
begin select * into a from public.fine_appeals where id=p_appeal for update; select * into f from public.administrative_fines where id=a.fine_id;
 if a.id is null or not (public.is_world_admin() or public.is_country_president(f.country_id) or public.is_judicial_member(f.country_id,array['judge','administrator'])) then raise exception 'Sem autorização para julgar contestação.'; end if;
 update public.fine_appeals set status=case when p_accept then 'accepted' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now(),decision_note=trim(p_note) where id=a.id;
 if p_accept then update public.administrative_fines set status='cancelled' where id=f.id and status='contested'; else update public.administrative_fines set status='pending' where id=f.id and status='contested'; end if;
 perform public.justice_audit(f.country_id,'fine_appeal_reviewed','fine_appeal',a.id,jsonb_build_object('accepted',p_accept,'note',p_note));
end; $;

create or replace function public.security_create_department(p_country uuid,p_name text,p_type text,p_description text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v uuid;
begin
 if not (public.is_world_admin() or public.is_country_president(p_country)) then raise exception 'Sem autorização para criar instituição de segurança.'; end if;
 if length(trim(coalesce(p_name,'')))<3 then raise exception 'Nome inválido.'; end if;
 insert into public.security_departments(country_id,name,institution_type,description,status,created_by)
 values(p_country,trim(p_name),p_type,nullif(trim(p_description),''),'active',auth.uid()) returning id into v;
 perform public.justice_audit(p_country,'security_institution_created','security_department',v,jsonb_build_object('name',p_name,'type',p_type)); return v;
end; $$;
create or replace function public.security_appoint_officer(p_department uuid,p_profile uuid,p_badge text,p_position text,p_rank integer default 1)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare d public.security_departments%rowtype; v uuid;
begin
 select * into d from public.security_departments where id=p_department;
 if not found or not (public.is_world_admin() or public.is_country_president(d.country_id) or (d.director_profile_id=auth.uid() and public.is_police_member(d.country_id))) then raise exception 'Sem autorização para nomear agente.'; end if;
 if not exists(select 1 from public.profiles where id=p_profile and country_id=d.country_id and role='citizen' and registration_status='active') then raise exception 'Agente deve ser cidadão ativo do país.'; end if;
 insert into public.police_members(department_id,country_id,profile_id,badge_number,position,rank_level,status,appointed_by)
 values(p_department,d.country_id,p_profile,upper(trim(p_badge)),trim(p_position),p_rank,'active',auth.uid()) returning id into v;
 perform public.justice_audit(d.country_id,'police_member_appointed','police_member',v,jsonb_build_object('profile_id',p_profile,'badge',p_badge)); return v;
end; $$;
create or replace function public.police_register_occurrence(p_department uuid,p_category text,p_location text,p_description text,p_involved uuid[] default '{}',p_vehicle uuid default null,p_occurred timestamptz default now())
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare d public.security_departments%rowtype; v uuid; n text;
begin
 select * into d from public.security_departments where id=p_department and status='active';
 if not found or not public.is_police_member(d.country_id) then raise exception 'Somente agente ativo pode registrar ocorrência.'; end if;
 if length(trim(p_description))<10 then raise exception 'Descrição insuficiente.'; end if;
 if p_vehicle is not null and not exists(select 1 from public.vehicles where id=p_vehicle and country_id=d.country_id) then raise exception 'Veículo não pertence ao país.'; end if;
 n:='OC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.police_occurrences(occurrence_number,country_id,department_id,category,location,description,involved_profile_ids,vehicle_id,responsible_profile_id,created_by,occurred_at)
 values(n,d.country_id,d.id,trim(p_category),trim(p_location),trim(p_description),coalesce(p_involved,'{}'),p_vehicle,auth.uid(),auth.uid(),p_occurred) returning id into v;
 perform public.justice_audit(d.country_id,'occurrence_created','police_occurrence',v,jsonb_build_object('number',n)); return v;
end; $$;
create or replace function public.citizen_submit_report(p_country uuid,p_category text,p_location text,p_description text,p_anonymous boolean default false)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare p public.profiles%rowtype; v uuid; n text;
begin
 select * into p from public.profiles where id=auth.uid() and role='citizen' and registration_status='active';
 if not found or p.country_id is distinct from p_country then raise exception 'Somente cidadão ativo do país pode enviar denúncia.'; end if;
 if length(trim(coalesce(p_description,'')))<15 then raise exception 'Descreva a situação com pelo menos 15 caracteres.'; end if;
 n:='DEN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.citizen_reports(protocol,country_id,category,location,description,is_anonymous,reporter_profile_id)
 values(n,p_country,trim(p_category),nullif(trim(p_location),''),trim(p_description),p_anonymous,case when p_anonymous then null else auth.uid() end,auth.uid()) returning id into v;
 perform public.justice_audit(p_country,'citizen_report_submitted','citizen_report',v,jsonb_build_object('anonymous',p_anonymous)); return v;
end; $$;
create or replace function public.police_open_investigation(p_occurrence uuid,p_title text,p_summary text,p_subjects uuid[] default '{}')
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare o public.police_occurrences%rowtype; v uuid; n text;
begin
 select * into o from public.police_occurrences where id=p_occurrence;
 if not found or not public.is_police_member(o.country_id) then raise exception 'Sem autorização para investigar.'; end if;
 n:='INV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.investigations(investigation_number,country_id,occurrence_id,department_id,lead_profile_id,subject_profile_ids,title,summary,created_by)
 values(n,o.country_id,o.id,o.department_id,auth.uid(),coalesce(p_subjects,'{}'),trim(p_title),trim(p_summary),auth.uid()) returning id into v;
 update public.police_occurrences set status='under_review',updated_at=now() where id=o.id;
 perform public.justice_audit(o.country_id,'investigation_opened','investigation',v,jsonb_build_object('occurrence_id',o.id)); return v;
end; $$;
create or replace function public.traffic_record_violation(p_vehicle uuid,p_category text,p_description text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.vehicles%rowtype; d uuid; x uuid; n text;
begin
 select * into v from public.vehicles where id=p_vehicle;
 if not found or not public.is_police_member(v.country_id) then raise exception 'Consulta ou fiscalização não autorizada.'; end if;
 select m.department_id into d from public.police_members m join public.security_departments s on s.id=m.department_id where m.profile_id=auth.uid() and m.country_id=v.country_id and m.status='active' and s.status='active' limit 1;
 n:='TR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.traffic_violations(violation_number,country_id,vehicle_id,responsible_profile_id,responsible_company_id,category,description,officer_profile_id)
 values(n,v.country_id,v.id,v.owner_profile_id,v.owner_company_id,trim(p_category),trim(p_description),auth.uid()) returning id into x;
 perform public.justice_audit(v.country_id,'traffic_violation_recorded','traffic_violation',x,jsonb_build_object('vehicle_id',v.id)); return x;
end; $$;
create or replace function public.traffic_issue_fine(p_violation uuid,p_amount numeric,p_due date,p_description text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.traffic_violations%rowtype; m public.police_members%rowtype; c uuid; f uuid; code text;
begin
 select * into v from public.traffic_violations where id=p_violation for update;
 if not found or not public.is_police_member(v.country_id) or p_amount<=0 then raise exception 'Infração ou valor inválido.'; end if;
 select * into m from public.police_members where profile_id=auth.uid() and country_id=v.country_id and status='active' limit 1;
 select id into c from public.currencies where internal_code=(select currency_code from public.countries where id=v.country_id) and status='active';
 if c is null then raise exception 'Moeda nacional ativa não configurada.'; end if;
 code:='ML-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.administrative_fines(fine_number,country_id,violation_id,recipient_profile_id,recipient_company_id,category,description,amount,currency_id,issuing_department_id,issued_by,due_at)
 values(code,v.country_id,v.id,v.responsible_profile_id,v.responsible_company_id,v.category,trim(p_description),p_amount,c,m.department_id,auth.uid(),p_due) returning id into f;
 update public.traffic_violations set status='fined' where id=v.id;
 perform public.justice_audit(v.country_id,'administrative_fine_issued','administrative_fine',f,jsonb_build_object('amount',p_amount)); return f;
end; $$;

create or replace function public.police_triage_report(p_report uuid,p_department uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare r public.citizen_reports%rowtype; d public.security_departments%rowtype;
begin
 select * into r from public.citizen_reports where id=p_report for update;
 select * into d from public.security_departments where id=p_department and status='active';
 if r.id is null or d.id is null or r.country_id<>d.country_id or not (public.is_world_admin() or public.is_country_president(r.country_id) or exists(select 1 from public.police_members m where m.profile_id=auth.uid() and m.department_id=d.id and m.status='active')) then raise exception 'Denúncia ou departamento indisponível.'; end if;
 if p_status not in ('triaged','investigating','referred','dismissed','closed') then raise exception 'Situação inválida.'; end if;
 update public.citizen_reports set assigned_department_id=d.id,status=p_status,resolution_note=nullif(trim(p_note),''),updated_at=now() where id=r.id;
 perform public.justice_audit(r.country_id,'report_triaged','citizen_report',r.id,jsonb_build_object('status',p_status,'department_id',d.id));
end; $;
create or replace function public.citizen_pay_fine(p_fine uuid,p_account uuid,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare f public.administrative_fines%rowtype; a public.bank_accounts%rowtype; tx uuid; code text;
begin
 if length(trim(coalesce(p_idempotency,'')))<12 then raise exception 'Chave de pagamento inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select * into f from public.administrative_fines where id=p_fine for update;
 if f.id is null then raise exception 'Multa não encontrada.'; end if;
 if f.status='paid' and f.idempotency_key=p_idempotency then return f.bank_transaction_id; end if;
 if f.status not in ('pending','overdue') or not (f.recipient_profile_id=auth.uid() or (f.recipient_company_id is not null and public.is_company_member(f.recipient_company_id,'finance.manage'))) then raise exception 'Multa não pode ser paga por esta conta.'; end if;
 select * into a from public.bank_accounts where id=p_account and status='active' and ((f.recipient_profile_id is not null and owner_profile_id=f.recipient_profile_id) or (f.recipient_company_id is not null and owner_company_id=f.recipient_company_id)) for update;
 if a.id is null or a.country_id<>f.country_id or a.currency_id<>f.currency_id then raise exception 'Conta bancária, país ou moeda incompatível.'; end if;
 if a.balance<f.amount then raise exception 'Saldo insuficiente.'; end if;
 update public.bank_accounts set balance=balance-f.amount where id=a.id returning * into a;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'fee',f.amount,a.currency_id,a.balance,'Pagamento de multa administrativa',f.id,'fine-'||p_idempotency,auth.uid()) returning id into tx;
 select currency_code into code from public.countries where id=f.country_id;
 insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,currency_code_snapshot,signed_amount,source_type,source_id,idempotency_key,created_by)
 values(f.country_id,'revenue','administrative_fine','Pagamento de multa '||f.fine_number,f.amount,code,f.amount,'administrative_fine',f.id,'fine-treasury-'||p_idempotency,auth.uid())
 on conflict(country_id,idempotency_key) do nothing;
 update public.administrative_fines set status='paid',bank_transaction_id=tx,idempotency_key=p_idempotency where id=f.id;
 perform public.justice_audit(f.country_id,'fine_paid','administrative_fine',f.id,jsonb_build_object('bank_transaction_id',tx));
 return tx;
end; $;

create or replace function public.citizen_appeal_fine(p_fine uuid,p_grounds text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare f public.administrative_fines%rowtype; v uuid;
begin
 select * into f from public.administrative_fines where id=p_fine for update;
 if not found or f.status not in ('pending','overdue') or not (f.recipient_profile_id=auth.uid() or (f.recipient_company_id is not null and public.is_company_member(f.recipient_company_id,'finance.manage'))) then raise exception 'Multa não disponível para contestação.'; end if;
 insert into public.fine_appeals(fine_id,appellant_profile_id,grounds) values(p_fine,auth.uid(),trim(p_grounds)) returning id into v;
 update public.administrative_fines set status='contested' where id=p_fine;
 perform public.justice_audit(f.country_id,'fine_appealed','fine_appeal',v,'{}'); return v;
end; $$;
create or replace function public.judicial_create_institution(p_country uuid,p_name text,p_type text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v uuid;
begin if not (public.is_world_admin() or public.is_country_president(p_country)) then raise exception 'Sem permissão para criar instituição judicial.'; end if;
 insert into public.judicial_institutions(country_id,name,institution_type,status,created_by) values(p_country,trim(p_name),p_type,'active',auth.uid()) returning id into v;
 perform public.justice_audit(p_country,'judicial_institution_created','judicial_institution',v,'{}'); return v; end; $$;
create or replace function public.judicial_appoint_member(p_institution uuid,p_profile uuid,p_role text,p_registration text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare i public.judicial_institutions%rowtype; v uuid;
begin
 select * into i from public.judicial_institutions where id=p_institution;
 if not found or not (public.is_world_admin() or public.is_country_president(i.country_id) or exists(select 1 from public.judicial_members m where m.institution_id=i.id and m.profile_id=auth.uid() and m.professional_role='administrator' and m.status='active')) then raise exception 'Sem permissão para nomear profissional.'; end if;
 if not exists(select 1 from public.profiles where id=p_profile and country_id=i.country_id and registration_status='active') then raise exception 'Perfil inválido.'; end if;
 insert into public.judicial_members(institution_id,country_id,profile_id,professional_role,registration_number,status,appointed_by)
 values(i.id,i.country_id,p_profile,p_role,upper(trim(p_registration)),'active',auth.uid()) returning id into v;
 perform public.justice_audit(i.country_id,'judicial_member_appointed','judicial_member',v,jsonb_build_object('role',p_role)); return v;
end; $$;
create or replace function public.judicial_open_case(p_institution uuid,p_category text,p_title text,p_summary text,p_respondent uuid default null,p_investigation uuid default null,p_fine uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare i public.judicial_institutions%rowtype; v uuid; n text;
begin
 select * into i from public.judicial_institutions where id=p_institution and status='active';
 if not found or not (public.is_world_admin() or public.is_country_president(i.country_id) or public.is_judicial_member(i.country_id,array['judge','prosecutor','defender','lawyer','administrator']) or exists(select 1 from public.investigations x where x.id=p_investigation and x.lead_profile_id=auth.uid())) then raise exception 'Sem permissão para iniciar processo.'; end if;
 n:='PROC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.court_cases(case_number,country_id,institution_id,investigation_id,fine_id,category,title,summary,claimant_profile_id,respondent_profile_id,opened_by)
 values(n,i.country_id,i.id,p_investigation,p_fine,p_category,trim(p_title),trim(p_summary),auth.uid(),p_respondent,auth.uid()) returning id into v;
 insert into public.court_case_parties(case_id,profile_id,party_role) values(v,auth.uid(),'claimant') on conflict do nothing;
 if p_respondent is not null then insert into public.court_case_parties(case_id,profile_id,party_role) values(v,p_respondent,'respondent') on conflict do nothing; end if;
 perform public.justice_audit(i.country_id,'court_case_opened','court_case',v,jsonb_build_object('number',n)); return v;
end; $$;
create or replace function public.judicial_assign_judge(p_case uuid,p_judge uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
declare c public.court_cases%rowtype;
begin select * into c from public.court_cases where id=p_case for update;
 if not found or not (public.is_world_admin() or public.is_country_president(c.country_id) or public.is_judicial_member(c.country_id,array['administrator'])) then raise exception 'Sem permissão.'; end if;
 if not exists(select 1 from public.judicial_members where profile_id=p_judge and country_id=c.country_id and professional_role='judge' and status='active') then raise exception 'Juiz não está habilitado neste país.'; end if;
 if exists(select 1 from public.court_case_parties where case_id=c.id and profile_id=p_judge and party_role in ('claimant','respondent','prosecutor')) then raise exception 'Conflito de função: juiz é parte ou acusação.'; end if;
 update public.court_cases set assigned_judge_id=p_judge,status='under_review',updated_at=now() where id=c.id;
 perform public.justice_audit(c.country_id,'judge_assigned','court_case',c.id,jsonb_build_object('judge',p_judge)); end; $$;
create or replace function public.judicial_record_hearing(p_case uuid,p_when timestamptz,p_participants jsonb default '[]',p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.court_cases%rowtype; v uuid;
begin select * into c from public.court_cases where id=p_case for update;
 if not found or c.assigned_judge_id<>auth.uid() or not public.is_judicial_member(c.country_id,array['judge']) then raise exception 'Somente o juiz designado pode registrar audiência.'; end if;
 insert into public.court_hearings(case_id,scheduled_at,responsible_judge_id,participants,notes,created_by)
 values(c.id,p_when,auth.uid(),coalesce(p_participants,'[]'),p_notes,auth.uid()) returning id into v;
 update public.court_cases set status='in_hearing',updated_at=now() where id=c.id;
 perform public.justice_audit(c.country_id,'hearing_recorded','court_hearing',v,'{}'); return v; end; $$;
create or replace function public.judicial_publish_decision(p_case uuid,p_outcome text,p_reasoning text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.court_cases%rowtype; v uuid; n text;
begin select * into c from public.court_cases where id=p_case for update;
 if not found or c.assigned_judge_id<>auth.uid() or not public.is_judicial_member(c.country_id,array['judge']) then raise exception 'Somente juiz designado pode decidir.'; end if;
 if length(trim(coalesce(p_reasoning,'')))<20 then raise exception 'Fundamentação obrigatória.'; end if;
 n:='DEC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.court_decisions(case_id,decision_number,judge_profile_id,outcome,reasoning) values(c.id,n,auth.uid(),trim(p_outcome),trim(p_reasoning)) returning id into v;
 update public.court_cases set status='concluded',updated_at=now() where id=c.id;
 perform public.justice_audit(c.country_id,'court_decision_published','court_decision',v,jsonb_build_object('case_id',c.id)); return v; end; $$;

create or replace function public.judicial_review_case_appeal(p_appeal uuid,p_accept boolean,p_note text)
returns void language plpgsql security definer set search_path=public,auth as $$
declare a public.court_appeals%rowtype; c public.court_cases%rowtype;
begin
 select * into a from public.court_appeals where id=p_appeal for update;
 select * into c from public.court_cases where id=a.case_id;
 if a.id is null or not (public.is_world_admin() or public.is_judicial_member(c.country_id,array['judge','administrator'])) then raise exception 'Sem autorização para analisar recurso.'; end if;
 if a.decision_id is not null and exists(select 1 from public.court_decisions d where d.id=a.decision_id and d.judge_profile_id=auth.uid()) then raise exception 'O juiz que proferiu a decisão original não pode julgar o próprio recurso.'; end if;
 update public.court_appeals set status=case when p_accept then 'accepted' else 'rejected' end,reviewed_by=auth.uid(),decision_note=trim(p_note) where id=a.id;
 perform public.justice_audit(c.country_id,'court_appeal_reviewed','court_appeal',a.id,jsonb_build_object('accepted',p_accept,'note',p_note));
end; $;

create or replace function public.citizen_appeal_decision(p_decision uuid,p_grounds text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare d public.court_decisions%rowtype; c public.court_cases%rowtype; v uuid;
begin select * into d from public.court_decisions where id=p_decision; select * into c from public.court_cases where id=d.case_id;
 if d.id is null or not exists(select 1 from public.court_case_parties where case_id=c.id and profile_id=auth.uid()) then raise exception 'Somente parte do processo pode recorrer.'; end if;
 insert into public.court_appeals(case_id,decision_id,appellant_profile_id,grounds) values(c.id,d.id,auth.uid(),trim(p_grounds)) returning id into v;
 perform public.justice_audit(c.country_id,'court_appeal_submitted','court_appeal',v,'{}'); return v; end; $$;
create or replace function public.correctional_record_event(p_facility uuid,p_profile uuid,p_case uuid,p_decision uuid,p_type text,p_basis text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare f public.correctional_facilities%rowtype; d public.court_decisions%rowtype; v uuid;
begin
 select * into f from public.correctional_facilities where id=p_facility and status='active';
 select * into d from public.court_decisions where id=p_decision and case_id=p_case;
 if not found or f.id is null or f.country_id is distinct from (select country_id from public.court_cases where id=p_case) or not (public.is_world_admin() or public.is_country_president(f.country_id) or public.is_judicial_member(f.country_id,array['judge','administrator'])) then raise exception 'Registro penitenciário sem autorização ou decisão válida.'; end if;
 if p_type='admission' and lower(d.outcome) !~ '(culp|conden|guilty|convict)' then raise exception 'Admissão exige decisão condenatória expressa.'; end if;
 if p_type='release' and lower(d.outcome) !~ '(absolv|liber|acquit|release)' then raise exception 'Saída exige decisão de absolvição ou liberação expressa.'; end if;
 if length(trim(coalesce(p_basis,'')))<10 then raise exception 'Fundamento legal obrigatório.'; end if;
 insert into public.correctional_records(facility_id,country_id,profile_id,case_id,decision_id,record_type,recorded_by,legal_basis)
 values(f.id,f.country_id,p_profile,p_case,p_decision,p_type,auth.uid(),trim(p_basis)) returning id into v;
 perform public.justice_audit(f.country_id,'correctional_recorded','correctional_record',v,jsonb_build_object('type',p_type)); return v; end; $$;

-- Exposição controlada: sem escrita direta nas tabelas de justiça.
revoke all on public.security_departments,public.police_members,public.police_occurrences,public.citizen_reports,public.investigations,public.traffic_violations,public.administrative_fines,public.fine_appeals,public.judicial_institutions,public.judicial_members,public.court_cases,public.court_case_parties,public.court_hearings,public.court_decisions,public.court_appeals,public.correctional_facilities,public.correctional_records,public.justice_audit_logs from anon,authenticated;
grant select on public.security_departments,public.police_members,public.police_occurrences,public.citizen_reports,public.investigations,public.traffic_violations,public.administrative_fines,public.fine_appeals,public.judicial_institutions,public.judicial_members,public.court_cases,public.court_case_parties,public.court_hearings,public.court_decisions,public.court_appeals,public.correctional_facilities,public.correctional_records,public.justice_audit_logs to authenticated;
grant execute on function public.police_update_member(uuid,text,text,text),public.police_add_investigation_note(uuid,text,text,text),public.judicial_review_fine_appeal(uuid,boolean,text),public.is_police_member(uuid,text),public.is_judicial_member(uuid,text[]),
 public.judicial_create_facility(uuid,text,text,integer),public.security_create_department(uuid,text,text,text),public.security_appoint_officer(uuid,uuid,text,text,integer),
 public.police_register_occurrence(uuid,text,text,text,uuid[],uuid,timestamptz),public.citizen_submit_report(uuid,text,text,text,boolean),
 public.police_open_investigation(uuid,text,text,uuid[]),public.traffic_record_violation(uuid,text,text),public.traffic_issue_fine(uuid,numeric,date,text),
 public.citizen_appeal_fine(uuid,text),public.citizen_pay_fine(uuid,uuid,text),public.police_triage_report(uuid,uuid,text,text),public.judicial_create_institution(uuid,text,text),public.judicial_appoint_member(uuid,uuid,text,text),
 public.judicial_open_case(uuid,text,text,text,uuid,uuid,uuid),public.judicial_assign_judge(uuid,uuid),public.judicial_record_hearing(uuid,timestamptz,jsonb,text),
 public.judicial_publish_decision(uuid,text,text),public.judicial_review_case_appeal(uuid,boolean,text),public.citizen_appeal_decision(uuid,text),public.correctional_record_event(uuid,uuid,uuid,uuid,text,text) to authenticated;

commit;