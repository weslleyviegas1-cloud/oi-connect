-- WORLD ECONOMY — Integração entre empresas do setor bancário e bancos comerciais.
-- Aditiva: preserva bancos, contas, saldos e histórico existentes.
begin;

alter table public.companies drop constraint if exists companies_sector_check;
alter table public.companies add constraint companies_sector_check
 check(sector in ('commerce','construction','agriculture','livestock','mining','industry','transport','technology','services','food','health','education','energy','tourism','banking','other'));

alter table public.commercial_banks
 add column if not exists company_id uuid references public.companies(id) on delete restrict;
create unique index if not exists commercial_banks_company_uidx
 on public.commercial_banks(company_id) where company_id is not null;
create index if not exists commercial_banks_company_status_idx
 on public.commercial_banks(company_id,status) where company_id is not null;

-- Recria a RPC de registro empresarial permitindo o setor bancário.
create or replace function public.request_company_registration(
 p_legal_name text,p_trade_name text,p_country_id uuid,p_city text,p_region text,p_sector text,p_company_type text,p_size_class text,
 p_description text,p_declared_capital numeric,p_currency_id uuid,p_government_entity_id uuid default null,p_logo_url text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; v_id uuid; v_code text;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into p from public.profiles where id=auth.uid() for update;
 if not found or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' or (p.country_id is distinct from p_country_id and not public.is_world_admin()) then raise exception 'Somente cidadão ativo do país de registro ou Super Admin pode solicitar empresa.'; end if;
 if length(trim(coalesce(p_legal_name,'')))<2 or p_sector not in ('commerce','construction','agriculture','livestock','mining','industry','transport','technology','services','food','health','education','energy','tourism','banking','other') or p_company_type not in ('private','public','state_owned','partnership') or p_size_class not in ('small_business','large_enterprise') or p_declared_capital is null or p_declared_capital<0 or p_declared_capital<>round(p_declared_capital,6) then raise exception 'Dados cadastrais inválidos.'; end if;
 if p_company_type in ('public','state_owned') and (p_government_entity_id is null or not (public.is_world_admin() or public.is_country_president(p_country_id) or public.has_economy_permission(p_country_id,'economy.manage'))) then raise exception 'Empresas públicas ou estatais exigem vínculo a ministério e autorização governamental.'; end if;
 if p_company_type in ('public','state_owned') and not exists(select 1 from public.ministries m where m.id=p_government_entity_id and m.country_id=p_country_id and m.status='active') then raise exception 'O ministério informado não pertence ao país de registro ou está inativo.'; end if;
 if not exists(select 1 from public.countries c join public.currencies cu on cu.internal_code=c.currency_code where c.id=p_country_id and c.is_active and cu.id=p_currency_id and cu.status='active') then raise exception 'A moeda deve corresponder à moeda nacional ativa do país.'; end if;
 v_code:='WE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.companies(company_identifier,legal_name,trade_name,country_id,city,region,sector,company_type,size_class,description,declared_capital,currency_id,government_entity_id,logo_url,created_by)
 values(v_code,trim(p_legal_name),nullif(trim(p_trade_name),''),p_country_id,nullif(trim(p_city),''),nullif(trim(p_region),''),p_sector,p_company_type,p_size_class,nullif(trim(p_description),''),p_declared_capital,p_currency_id,p_government_entity_id,nullif(trim(p_logo_url),''),auth.uid()) returning id into v_id;
 if p_company_type in ('private','partnership') then
  insert into public.company_owners(company_id,profile_id,ownership_percent,owner_role,appointed_by) values(v_id,auth.uid(),100,'founder',auth.uid());
 else
  insert into public.company_government_ownership(company_id,ministry_id,ownership_percent,created_by) values(v_id,p_government_entity_id,100,auth.uid());
 end if;
 insert into public.company_members(company_id,profile_id,member_role,permissions,appointed_by)
 values(v_id,auth.uid(),'owner',array['company.manage','staff.read','hr.read','contracts.read','payroll.read','finance.read','tax.read','department.manage','jobs.manage'],auth.uid());
 perform public.company_audit(v_id,'company_requested','company',v_id,jsonb_build_object('identifier',v_code,'status','pending','sector',p_sector));
 return v_id;
end;
$function$;

create or replace function public.request_commercial_bank_for_company(
 p_company_id uuid,p_name text,p_identifier text,p_logo_url text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare c public.companies%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into c from public.companies where id=p_company_id for update;
 if not found or c.status<>'active' then raise exception 'A empresa precisa estar ativa para solicitar autorização bancária.'; end if;
 if c.sector<>'banking' then raise exception 'Somente empresas registradas no setor bancário podem solicitar uma instituição bancária.'; end if;
 if not public.is_company_member(p_company_id,'company.manage') then raise exception 'Somente proprietário ou administrador autorizado da empresa pode solicitar a instituição.'; end if;
 if c.company_type not in ('private','partnership') then raise exception 'A abertura de banco privado exige empresa privada ou sociedade. Bancos públicos dependem de criação governamental.'; end if;
 if length(trim(coalesce(p_name,'')))<3 or upper(trim(coalesce(p_identifier,''))) !~ '^[A-Z0-9][A-Z0-9._-]{2,39}$' then raise exception 'Nome ou identificador bancário inválido.'; end if;
 if exists(select 1 from public.commercial_banks where company_id=c.id) then raise exception 'Esta empresa já possui uma solicitação ou instituição bancária vinculada.'; end if;
 insert into public.commercial_banks(country_id,name,bank_identifier,bank_type,owner_description,logo_url,director_profile_id,created_by,company_id,status)
 values(c.country_id,trim(p_name),upper(trim(p_identifier)),'private',coalesce(c.trade_name,c.legal_name),nullif(trim(p_logo_url),''),auth.uid(),auth.uid(),c.id,'pending')
 returning id into v_id;
 insert into public.bank_members(bank_id,profile_id,position,permissions,status,appointed_by)
 values(v_id,auth.uid(),'Diretor fundador',array['bank.manage','staff.manage','account.read','transaction.read','loan.review','loan.read','audit.read'],'active',auth.uid());
 perform public.bank_audit(v_id,'bank_requested_by_company','commercial_bank',v_id,jsonb_build_object('company_id',c.id,'company_identifier',c.company_identifier,'status','pending'));
 perform public.company_audit(c.id,'commercial_bank_requested','commercial_bank',v_id,jsonb_build_object('name',trim(p_name),'identifier',upper(trim(p_identifier))));
 return v_id;
end;
$function$;

drop policy if exists commercial_banks_read on public.commercial_banks;
create policy commercial_banks_read on public.commercial_banks for select to authenticated
 using(status='active' or public.is_world_admin() or public.is_bank_member(id) or (company_id is not null and public.is_company_member(company_id,'company.manage')));

revoke all on function public.request_commercial_bank_for_company(uuid,text,text,text) from public,anon;
grant execute on function public.request_commercial_bank_for_company(uuid,text,text,text) to authenticated;
revoke all on function public.request_company_registration(text,text,uuid,text,text,text,text,text,text,numeric,uuid,uuid,text) from public,anon;
grant execute on function public.request_company_registration(text,text,uuid,text,text,text,text,text,text,numeric,uuid,uuid,text) to authenticated;

commit;
