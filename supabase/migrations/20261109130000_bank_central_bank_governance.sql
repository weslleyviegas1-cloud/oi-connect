-- WORLD ECONOMY — Ajuste de governança bancária
-- Bancos comerciais vinculados ao Banco Central nacional; aprovação privada pelo Presidente.
begin;

alter table public.commercial_banks
 add column if not exists central_bank_id uuid;

-- Vincula bancos existentes ao Banco Central primário ativo do mesmo país, sem alterar saldos ou contas.
update public.commercial_banks b
 set central_bank_id=cb.id
 from public.central_banks cb
 where cb.country_id=b.country_id and cb.is_primary and cb.status='active'
   and b.central_bank_id is null;

do $$
begin
 if not exists(select 1 from pg_constraint where conname='commercial_banks_central_bank_country_fk') then
  alter table public.commercial_banks add constraint commercial_banks_central_bank_country_fk
   foreign key(central_bank_id,country_id) references public.central_banks(id,country_id) on delete restrict;
 end if;
end $$;
create index if not exists commercial_banks_central_bank_idx on public.commercial_banks(central_bank_id);

-- Vincula automaticamente ao Banco Central primário e impede instituição nova sem autoridade monetária nacional ativa.
create or replace function public.set_commercial_bank_central_bank()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_cb uuid;
begin
 if new.central_bank_id is null then
  select id into v_cb from public.central_banks
   where country_id=new.country_id and is_primary and status='active' order by created_at desc limit 1;
  if v_cb is null then raise exception 'Este país ainda não possui Banco Central nacional ativo. O Presidente deve regularizar a instituição antes de autorizar bancos comerciais.'; end if;
  new.central_bank_id:=v_cb;
 end if;
 if not exists(select 1 from public.central_banks cb where cb.id=new.central_bank_id and cb.country_id=new.country_id and cb.status='active') then
  raise exception 'O banco comercial precisa estar vinculado ao Banco Central ativo do mesmo país.';
 end if;
 return new;
end; $$;
drop trigger if exists commercial_banks_set_central_bank on public.commercial_banks;
create trigger commercial_banks_set_central_bank before insert or update of country_id,central_bank_id on public.commercial_banks
 for each row execute function public.set_commercial_bank_central_bank();

-- Presidente decide a autorização nacional. Super Admin mantém poderes globais de suspensão/encerramento.
create or replace function public.president_review_commercial_bank(p_bank_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare b public.commercial_banks%rowtype;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id for update;
 if not found then raise exception 'Solicitação bancária não encontrada.'; end if;
 if not public.is_country_president(b.country_id) then raise exception 'Somente o Presidente ativo do país pode decidir sobre a abertura de bancos nacionais.'; end if;
 if b.status<>'pending' then raise exception 'Esta solicitação já foi analisada.'; end if;
 if b.central_bank_id is null or not exists(select 1 from public.central_banks cb where cb.id=b.central_bank_id and cb.country_id=b.country_id and cb.status='active') then
  raise exception 'O país precisa possuir Banco Central ativo antes da autorização.';
 end if;
 update public.commercial_banks set status=case when p_decision='approved' then 'active' else 'closed' end,
  approved_by=case when p_decision='approved' then auth.uid() else null end,
  approved_at=case when p_decision='approved' then now() else null end,updated_at=now()
 where id=b.id;
 perform public.bank_audit(b.id,case when p_decision='approved' then 'bank_approved_by_president' else 'bank_rejected_by_president' end,
  'commercial_bank',b.id,jsonb_build_object('decision',p_decision,'note',nullif(trim(p_note),''),'central_bank_id',b.central_bank_id));
 if b.company_id is not null then
  perform public.company_audit(b.company_id,case when p_decision='approved' then 'commercial_bank_approved' else 'commercial_bank_rejected' end,
   'commercial_bank',b.id,jsonb_build_object('decision',p_decision,'note',nullif(trim(p_note),'')));
 end if;
end; $$;

-- Super Admin não aprova solicitações privadas; conserva apenas supervisão global e medidas administrativas.
create or replace function public.admin_review_commercial_bank(p_bank_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
declare b public.commercial_banks%rowtype;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode supervisionar globalmente os bancos.'; end if;
 if p_status not in ('suspended','closed') then raise exception 'O Super Admin pode suspender ou encerrar; a aprovação nacional é competência do Presidente.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id for update;
 if not found then raise exception 'Banco não encontrado.'; end if;
 if b.status='closed' and p_status<>'closed' then raise exception 'Instituição encerrada não pode ser reativada.'; end if;
 update public.commercial_banks set status=p_status,updated_at=now() where id=b.id;
 perform public.bank_audit(b.id,'bank_global_supervision','commercial_bank',b.id,jsonb_build_object('from',b.status,'to',p_status,'note',p_note));
end; $$;

-- O Presidente pode visualizar somente as solicitações pendentes do próprio país.
drop policy if exists commercial_banks_read on public.commercial_banks;
create policy commercial_banks_read on public.commercial_banks for select to authenticated
 using(status='active' or public.is_world_admin() or public.is_bank_member(id)
  or public.is_country_president(country_id)
  or (company_id is not null and public.is_company_member(company_id,'company.manage')));

-- Atualiza o pedido empresarial para associar automaticamente o Banco Central do país.
create or replace function public.request_commercial_bank_for_company(
 p_company_id uuid,p_name text,p_identifier text,p_logo_url text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare c public.companies%rowtype; v_id uuid; v_cb uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into c from public.companies where id=p_company_id for update;
 if not found or c.status<>'active' then raise exception 'A empresa precisa estar ativa para solicitar a abertura do banco.'; end if;
 if c.sector<>'banking' then raise exception 'A empresa precisa estar registrada no setor bancário.'; end if;
 if not public.is_company_member(p_company_id,'company.manage') then raise exception 'Somente o proprietário ou administrador da empresa pode solicitar o banco.'; end if;
 if c.company_type not in ('private','partnership') then raise exception 'Bancos públicos devem ser propostos pelo governo nacional.'; end if;
 if length(trim(coalesce(p_name,'')))<3 or upper(trim(coalesce(p_identifier,''))) !~ '^[A-Z0-9][A-Z0-9._-]{2,39}$' then raise exception 'Informe nome e identificador válidos.'; end if;
 select id into v_cb from public.central_banks where country_id=c.country_id and is_primary and status='active' order by created_at desc limit 1;
 if v_cb is null then raise exception 'Este país ainda não possui Banco Central ativo. O Presidente deve cadastrar ou ativar o Banco Central primeiro.'; end if;
 if exists(select 1 from public.commercial_banks where company_id=c.id) then raise exception 'Esta empresa já possui uma solicitação ou banco vinculado.'; end if;
 insert into public.commercial_banks(country_id,central_bank_id,name,bank_identifier,bank_type,owner_description,logo_url,director_profile_id,created_by,company_id,status)
 values(c.country_id,v_cb,trim(p_name),upper(trim(p_identifier)),'private',coalesce(c.trade_name,c.legal_name),nullif(trim(p_logo_url),''),auth.uid(),auth.uid(),c.id,'pending')
 returning id into v_id;
 insert into public.bank_members(bank_id,profile_id,position,permissions,status,appointed_by)
 values(v_id,auth.uid(),'Diretor fundador',array['bank.manage','staff.manage','account.read','transaction.read','loan.review','loan.read','audit.read'],'active',auth.uid());
 perform public.bank_audit(v_id,'bank_requested_by_company','commercial_bank',v_id,jsonb_build_object('company_id',c.id,'central_bank_id',v_cb,'status','pending'));
 perform public.company_audit(c.id,'commercial_bank_requested','commercial_bank',v_id,jsonb_build_object('name',trim(p_name),'identifier',upper(trim(p_identifier)),'central_bank_id',v_cb));
 return v_id;
end; $$;

-- Conta corrente só pode ser aberta em banco ativo e conectado ao Banco Central nacional ativo.
create or replace function public.open_bank_account(p_bank_id uuid,p_currency_id uuid,p_account_type text default 'checking',p_branch_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare b public.commercial_banks%rowtype; p public.profiles%rowtype; v_number text; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into p from public.profiles where id=auth.uid() for update;
 if not found or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' then raise exception 'Perfil não elegível para abrir conta.'; end if;
 if p_account_type not in ('checking','savings') then raise exception 'Tipo de conta inválido.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id and status='active';
 if not found or p.country_id is distinct from b.country_id then raise exception 'Banco indisponível para o país do cidadão.'; end if;
 if b.central_bank_id is null or not exists(select 1 from public.central_banks cb where cb.id=b.central_bank_id and cb.country_id=b.country_id and cb.status='active') then raise exception 'Banco sem vínculo ativo ao Banco Central nacional.'; end if;
 if not exists(select 1 from public.currencies c where c.id=p_currency_id and c.status='active') then raise exception 'Moeda indisponível.'; end if;
 if not exists(select 1 from public.country_currency_assignments a where a.country_id=b.country_id and a.currency_id=p_currency_id and a.effective_until is null) then raise exception 'A moeda não é a moeda nacional vigente do país.'; end if;
 if p_branch_id is not null and not exists(select 1 from public.bank_branches where id=p_branch_id and bank_id=b.id and status='active') then raise exception 'Agência inválida.'; end if;
 if exists(select 1 from public.bank_accounts where owner_profile_id=auth.uid() and bank_id=b.id and account_type=p_account_type and currency_id=p_currency_id and status<>'closed') then raise exception 'Você já possui uma conta ativa desta modalidade neste banco.'; end if;
 v_number:=lpad((floor(random()*90000000)+10000000)::bigint::text,8,'0');
 while exists(select 1 from public.bank_accounts where bank_id=b.id and account_number=v_number) loop v_number:=lpad((floor(random()*90000000)+10000000)::bigint::text,8,'0'); end loop;
 insert into public.bank_accounts(bank_id,branch_id,owner_profile_id,country_id,currency_id,account_number,account_type)
 values(b.id,p_branch_id,auth.uid(),b.country_id,p_currency_id,v_number,p_account_type) returning id into v_id;
 perform public.bank_audit(b.id,'account_opened','bank_account',v_id,jsonb_build_object('owner_profile_id',auth.uid(),'account_number',v_number));
 return v_id;
end; $$;

revoke all on function public.president_review_commercial_bank(uuid,text,text),public.admin_review_commercial_bank(uuid,text,text),
 public.request_commercial_bank_for_company(uuid,text,text,text),public.open_bank_account(uuid,uuid,text,uuid) from public,anon;
grant execute on function public.president_review_commercial_bank(uuid,text,text),public.admin_review_commercial_bank(uuid,text,text),
 public.request_commercial_bank_for_company(uuid,text,text,text),public.open_bank_account(uuid,uuid,text,uuid) to authenticated;

commit;
