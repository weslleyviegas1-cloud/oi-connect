begin;
create or replace function public.vehicle_admin_set_driving_rule(p_country uuid,p_category text,p_lessons integer,p_score numeric,p_days integer,p_fee numeric,p_currency uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
 if not (public.is_world_admin() or public.is_country_president(p_country)) then raise exception 'Sem permissão para configurar habilitação.'; end if;
 if p_category not in ('A','B','C','D','E') or p_lessons<0 or p_score not between 0 and 100 or p_days not between 1 and 3650 or p_fee<0 then raise exception 'Regra de habilitação inválida.'; end if;
 if not exists(select 1 from public.countries c join public.currencies x on x.internal_code=c.currency_code where c.id=p_country and x.id=p_currency) then raise exception 'Use a moeda nacional vigente.'; end if;
 insert into public.driving_category_rules(country_id,category_code,minimum_lessons,minimum_exam_score,validity_days,fee_amount,currency_id,is_active,updated_by)
 values(p_country,p_category,p_lessons,p_score,p_days,p_fee,p_currency,p_active,auth.uid())
 on conflict(country_id,category_code) do update set minimum_lessons=excluded.minimum_lessons,minimum_exam_score=excluded.minimum_exam_score,validity_days=excluded.validity_days,fee_amount=excluded.fee_amount,currency_id=excluded.currency_id,is_active=excluded.is_active,updated_by=auth.uid(),updated_at=now();
end; $$;

create or replace function public.vehicle_school_add_instructor(p_school uuid,p_profile uuid,p_categories text[])
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare s public.driving_schools%rowtype; v uuid;
begin
 select * into s from public.driving_schools where id=p_school and status='active';
 if not found or not (s.responsible_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(s.country_id)) then raise exception 'Sem permissão para gerenciar instrutores.'; end if;
 if not exists(select 1 from public.profiles where id=p_profile and role='citizen' and country_id=s.country_id and registration_status='active') or cardinality(coalesce(p_categories,'{}'))=0 then raise exception 'Instrutor ou categorias inválidos.'; end if;
 if exists(select 1 from unnest(p_categories) x where x not in ('A','B','C','D','E')) then raise exception 'Categoria inválida.'; end if;
 insert into public.driving_instructors(school_id,profile_id,categories) values(p_school,p_profile,p_categories)
 on conflict(school_id,profile_id) do update set categories=excluded.categories,status='active' returning id into v;
 perform public.vehicle_audit(s.country_id,'driving_instructor',v,'appointed'); return v;
end; $$;

create or replace function public.vehicle_school_review_enrollment(p_enrollment uuid,p_approve boolean)
returns void language plpgsql security definer set search_path=public,auth as $$
declare e public.driving_enrollments%rowtype; s public.driving_schools%rowtype;
begin
 select * into e from public.driving_enrollments where id=p_enrollment for update;
 select * into s from public.driving_schools where id=e.school_id;
 if e.id is null or not (s.responsible_profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(e.country_id)) then raise exception 'Sem permissão.'; end if;
 if e.status<>'pending' then raise exception 'Matrícula já analisada.'; end if;
 update public.driving_enrollments set status=case when p_approve then 'active' else 'rejected' end,reviewed_by=auth.uid(),reviewed_at=now() where id=e.id;
 perform public.vehicle_audit(e.country_id,'driving_enrollment',e.id,case when p_approve then 'approved' else 'rejected' end);
end; $$;

create or replace function public.vehicle_issue_license_fee(p_vehicle uuid,p_due date default (current_date+30))
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.vehicles%rowtype; f public.vehicle_fee_settings%rowtype; id uuid; p uuid; c uuid;
begin
 select * into v from public.vehicles where id=p_vehicle;
 if not found or not (public.is_world_admin() or public.is_country_president(v.country_id)) then raise exception 'Sem permissão para emitir taxa.'; end if;
 select * into f from public.vehicle_fee_settings where country_id=v.country_id;
 if not found then raise exception 'Taxa veicular ainda não configurada.'; end if;
 if exists(select 1 from public.vehicle_fees where vehicle_id=v.id and status='pending') then raise exception 'Já existe taxa pendente para este veículo.'; end if;
 insert into public.vehicle_fees(vehicle_id,owner_profile_id,owner_company_id,country_id,amount,currency_id,due_at)
 values(v.id,v.owner_profile_id,v.owner_company_id,v.country_id,f.license_fee,f.currency_id,p_due) returning id into id;
 perform public.vehicle_audit(v.country_id,'vehicle_fee',id,'issued',jsonb_build_object('vehicle_id',v.id,'amount',f.license_fee)); return id;
end; $$;

grant execute on function public.vehicle_admin_set_driving_rule(uuid,text,integer,numeric,integer,numeric,uuid,boolean) to authenticated;
grant execute on function public.vehicle_school_add_instructor(uuid,uuid,text[]) to authenticated;
grant execute on function public.vehicle_school_review_enrollment(uuid,boolean) to authenticated;
grant execute on function public.vehicle_issue_license_fee(uuid,date) to authenticated;
commit;