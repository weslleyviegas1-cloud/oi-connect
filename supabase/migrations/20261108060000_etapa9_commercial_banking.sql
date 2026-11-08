-- WORLD ECONOMY — ETAPA 9: bancos comerciais e contas bancárias
-- Aditiva: mantém as Etapas 1–8 e não converte a carteira local demonstrativa em dinheiro.
begin;

create table if not exists public.commercial_banks (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 name text not null check(length(trim(name)) between 3 and 160),
 logo_url text,
 bank_identifier text not null unique check(bank_identifier ~ '^[A-Z0-9][A-Z0-9._-]{2,39}$'),
 bank_type text not null check(bank_type in ('public','private')),
 owner_description text,
 director_profile_id uuid references public.profiles(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','active','suspended','closed')),
 created_by uuid not null references public.profiles(id) on delete restrict,
 approved_by uuid references public.profiles(id) on delete restrict,
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists commercial_banks_country_status_idx on public.commercial_banks(country_id,status);

create table if not exists public.bank_branches (
 id uuid primary key default gen_random_uuid(),
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 name text not null,
 region text,
 city text,
 branch_code text not null,
 status text not null default 'active' check(status in ('active','suspended','closed')),
 created_at timestamptz not null default now(),
 unique(bank_id,branch_code)
);
create table if not exists public.bank_members (
 id uuid primary key default gen_random_uuid(),
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 profile_id uuid not null references public.profiles(id) on delete restrict,
 position text not null,
 permissions text[] not null default '{}',
 status text not null default 'active' check(status in ('active','suspended','removed')),
 appointed_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 unique(bank_id,profile_id)
);
create index if not exists bank_members_profile_idx on public.bank_members(profile_id,status);

create table if not exists public.bank_accounts (
 id uuid primary key default gen_random_uuid(),
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 branch_id uuid references public.bank_branches(id) on delete restrict,
 owner_profile_id uuid not null references public.profiles(id) on delete restrict,
 country_id uuid not null references public.countries(id) on delete restrict,
 currency_id uuid not null references public.currencies(id) on delete restrict,
 account_number text not null,
 account_type text not null default 'checking' check(account_type in ('checking','savings','business','institutional')),
 status text not null default 'active' check(status in ('active','blocked','closed')),
 balance numeric(30,6) not null default 0 check(balance>=0),
 opened_at timestamptz not null default now(),
 closed_at timestamptz,
 created_at timestamptz not null default now(),
 unique(bank_id,account_number),
 unique(owner_profile_id,bank_id,account_type,currency_id),
 unique(id,currency_id)
);
create index if not exists bank_accounts_owner_idx on public.bank_accounts(owner_profile_id,status);
create index if not exists bank_accounts_bank_idx on public.bank_accounts(bank_id,status);

create table if not exists public.bank_transactions (
 id uuid primary key default gen_random_uuid(),
 account_id uuid not null references public.bank_accounts(id) on delete restrict,
 transaction_type text not null check(transaction_type in ('opening','deposit','withdrawal','transfer_in','transfer_out','fee','loan_disbursement','loan_payment','reversal')),
 amount numeric(30,6) not null check(amount>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 balance_after numeric(30,6) not null check(balance_after>=0),
 description text not null,
 reference_id uuid,
 idempotency_key text not null unique,
 actor_id uuid not null references public.profiles(id) on delete restrict,
 status text not null default 'completed' check(status in ('completed','reversed')),
 created_at timestamptz not null default now()
);
create index if not exists bank_transactions_account_date_idx on public.bank_transactions(account_id,created_at desc);

create table if not exists public.bank_transfers (
 id uuid primary key default gen_random_uuid(),
 from_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 to_account_id uuid not null references public.bank_accounts(id) on delete restrict,
 amount_sent numeric(30,6) not null check(amount_sent>0),
 from_currency_id uuid not null references public.currencies(id) on delete restrict,
 amount_received numeric(30,6) not null check(amount_received>0),
 to_currency_id uuid not null references public.currencies(id) on delete restrict,
 exchange_rate_id uuid references public.exchange_rates(id) on delete restrict,
 exchange_rate numeric(30,12) not null check(exchange_rate>0),
 fee_amount numeric(30,6) not null default 0 check(fee_amount>=0),
 status text not null default 'completed' check(status in ('completed','reversed')),
 description text,
 idempotency_key text not null unique,
 initiated_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 check(from_account_id<>to_account_id)
);

create table if not exists public.bank_fees (
 id uuid primary key default gen_random_uuid(),
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 fee_type text not null check(fee_type in ('maintenance','transfer','international','withdrawal')),
 amount numeric(30,6) not null default 0 check(amount>=0),
 currency_id uuid references public.currencies(id) on delete restrict,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(bank_id,fee_type)
);
create table if not exists public.bank_limits (
 id uuid primary key default gen_random_uuid(),
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 operation_type text not null check(operation_type in ('withdrawal','transfer')),
 daily_limit numeric(30,6) not null check(daily_limit>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 updated_by uuid not null references public.profiles(id) on delete restrict,
 updated_at timestamptz not null default now(),
 unique(bank_id,operation_type,currency_id)
);

create table if not exists public.loan_applications (
 id uuid primary key default gen_random_uuid(),
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 applicant_profile_id uuid not null references public.profiles(id) on delete restrict,
 account_id uuid not null references public.bank_accounts(id) on delete restrict,
 amount numeric(30,6) not null check(amount>0),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 term_months integer not null check(term_months between 1 and 360),
 annual_interest_rate numeric(12,6) not null check(annual_interest_rate between 0 and 10000),
 installments_count integer not null check(installments_count between 1 and 360),
 purpose text not null check(length(trim(purpose))>=5),
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 reviewed_by uuid references public.profiles(id) on delete restrict,
 reviewed_at timestamptz,
 created_at timestamptz not null default now()
);
create table if not exists public.bank_loans (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null unique references public.loan_applications(id) on delete restrict,
 bank_id uuid not null references public.commercial_banks(id) on delete restrict,
 borrower_profile_id uuid not null references public.profiles(id) on delete restrict,
 account_id uuid not null references public.bank_accounts(id) on delete restrict,
 principal numeric(30,6) not null check(principal>0),
 total_due numeric(30,6) not null check(total_due>=principal),
 currency_id uuid not null references public.currencies(id) on delete restrict,
 annual_interest_rate numeric(12,6) not null,
 installments_count integer not null,
 status text not null default 'active' check(status in ('active','paid','defaulted','cancelled')),
 created_at timestamptz not null default now()
);
create table if not exists public.loan_installments (
 id uuid primary key default gen_random_uuid(),
 loan_id uuid not null references public.bank_loans(id) on delete restrict,
 installment_number integer not null,
 due_date date not null,
 amount_due numeric(30,6) not null check(amount_due>0),
 amount_paid numeric(30,6) not null default 0 check(amount_paid>=0 and amount_paid<=amount_due),
 paid_at timestamptz,
 status text not null default 'pending' check(status in ('pending','partial','paid','overdue')),
 unique(loan_id,installment_number)
);
create table if not exists public.bank_audit_logs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references public.profiles(id) on delete restrict,
 bank_id uuid references public.commercial_banks(id) on delete restrict,
 action text not null,
 entity_type text not null,
 entity_id uuid,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists bank_audit_date_idx on public.bank_audit_logs(created_at desc);

create or replace function public.is_bank_member(p_bank_id uuid,p_permission text default null)
returns boolean language sql stable security definer set search_path=public,auth as $function$
 select auth.uid() is not null and exists(
  select 1 from public.bank_members m join public.profiles p on p.id=m.profile_id
  where m.bank_id=p_bank_id and m.profile_id=auth.uid() and m.status='active'
   and coalesce(p.account_status,'active')='active' and p.registration_status='active'
   and (p_permission is null or p_permission=any(m.permissions) or 'bank.manage'=any(m.permissions))
 );
$function$;

alter table public.commercial_banks enable row level security;
alter table public.bank_branches enable row level security;
alter table public.bank_members enable row level security;
alter table public.bank_accounts enable row level security;
alter table public.bank_transactions enable row level security;
alter table public.bank_transfers enable row level security;
alter table public.bank_fees enable row level security;
alter table public.bank_limits enable row level security;
alter table public.loan_applications enable row level security;
alter table public.bank_loans enable row level security;
alter table public.loan_installments enable row level security;
alter table public.bank_audit_logs enable row level security;

drop policy if exists commercial_banks_read on public.commercial_banks;
create policy commercial_banks_read on public.commercial_banks for select to authenticated
using(status='active' or public.is_world_admin() or public.is_bank_member(id));
drop policy if exists bank_branches_read on public.bank_branches;
create policy bank_branches_read on public.bank_branches for select to authenticated
using(exists(select 1 from public.commercial_banks b where b.id=bank_id and b.status='active') or public.is_world_admin() or public.is_bank_member(bank_id));
drop policy if exists bank_accounts_read on public.bank_accounts;
create policy bank_accounts_read on public.bank_accounts for select to authenticated
using(owner_profile_id=auth.uid() or public.is_world_admin() or public.is_bank_member(bank_id,'account.read'));
drop policy if exists bank_transactions_read on public.bank_transactions;
create policy bank_transactions_read on public.bank_transactions for select to authenticated
using(exists(select 1 from public.bank_accounts a where a.id=account_id and a.owner_profile_id=auth.uid()) or public.is_world_admin() or exists(select 1 from public.bank_accounts a where a.id=account_id and public.is_bank_member(a.bank_id,'transaction.read')));
drop policy if exists bank_transfers_read on public.bank_transfers;
create policy bank_transfers_read on public.bank_transfers for select to authenticated
using(initiated_by=auth.uid() or public.is_world_admin() or public.is_bank_member((select bank_id from public.bank_accounts where id=from_account_id),'transaction.read'));
drop policy if exists bank_fees_read on public.bank_fees;
create policy bank_fees_read on public.bank_fees for select to authenticated using(active or public.is_world_admin() or public.is_bank_member(bank_id));
drop policy if exists bank_limits_read on public.bank_limits;
create policy bank_limits_read on public.bank_limits for select to authenticated using(public.is_world_admin() or public.is_bank_member(bank_id,'bank.manage'));
drop policy if exists loan_applications_read on public.loan_applications;
create policy loan_applications_read on public.loan_applications for select to authenticated using(applicant_profile_id=auth.uid() or public.is_world_admin() or public.is_bank_member(bank_id,'loan.review'));
drop policy if exists bank_loans_read on public.bank_loans;
create policy bank_loans_read on public.bank_loans for select to authenticated using(borrower_profile_id=auth.uid() or public.is_world_admin() or public.is_bank_member(bank_id,'loan.read'));
drop policy if exists loan_installments_read on public.loan_installments;
create policy loan_installments_read on public.loan_installments for select to authenticated using(exists(select 1 from public.bank_loans l where l.id=loan_id and (l.borrower_profile_id=auth.uid() or public.is_world_admin() or public.is_bank_member(l.bank_id,'loan.read'))));
drop policy if exists bank_audit_admin_read on public.bank_audit_logs;
create policy bank_audit_admin_read on public.bank_audit_logs for select to authenticated using(public.is_world_admin() or public.is_bank_member(bank_id,'audit.read'));

revoke all on public.commercial_banks,public.bank_branches,public.bank_members,public.bank_accounts,public.bank_transactions,
 public.bank_transfers,public.bank_fees,public.bank_limits,public.loan_applications,public.bank_loans,public.loan_installments,public.bank_audit_logs
 from public,anon,authenticated;
grant select on public.commercial_banks,public.bank_branches,public.bank_accounts,public.bank_transactions,public.bank_transfers,
 public.bank_fees,public.bank_limits,public.loan_applications,public.bank_loans,public.loan_installments to authenticated;
grant select on public.bank_members,public.bank_audit_logs to authenticated;

create or replace function public.bank_audit(p_bank uuid,p_action text,p_type text,p_id uuid,p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path=public,auth as $function$
 insert into public.bank_audit_logs(actor_id,bank_id,action,entity_type,entity_id,details)
 values(auth.uid(),p_bank,p_action,p_type,p_id,coalesce(p_details,'{}'::jsonb));
$function$;
revoke all on function public.bank_audit(uuid,text,text,uuid,jsonb) from public,anon,authenticated;

create or replace function public.admin_create_commercial_bank(
 p_country_id uuid,p_name text,p_identifier text,p_type text,p_owner text default null,p_logo text default null,p_director uuid default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode cadastrar bancos.'; end if;
 if not exists(select 1 from public.countries where id=p_country_id and is_active) then raise exception 'País inexistente ou inativo.'; end if;
 if length(trim(coalesce(p_name,'')))<3 or upper(trim(coalesce(p_identifier,''))) !~ '^[A-Z0-9][A-Z0-9._-]{2,39}$' or p_type not in ('public','private') then raise exception 'Dados do banco inválidos.'; end if;
 insert into public.commercial_banks(country_id,name,bank_identifier,bank_type,owner_description,logo_url,director_profile_id,created_by)
 values(p_country_id,trim(p_name),upper(trim(p_identifier)),p_type,nullif(trim(p_owner),''),nullif(trim(p_logo),''),p_director,auth.uid()) returning id into v_id;
 perform public.bank_audit(v_id,'bank_created','commercial_bank',v_id,jsonb_build_object('status','pending','country_id',p_country_id));
 return v_id;
end;
$function$;

create or replace function public.admin_review_commercial_bank(p_bank_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare b public.commercial_banks%rowtype;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode revisar bancos.'; end if;
 if p_status not in ('active','suspended','closed') then raise exception 'Situação inválida.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id for update;
 if not found then raise exception 'Banco não encontrado.'; end if;
 update public.commercial_banks set status=p_status,approved_by=case when p_status='active' then auth.uid() else approved_by end,approved_at=case when p_status='active' then now() else approved_at end,updated_at=now() where id=b.id;
 perform public.bank_audit(b.id,'bank_status_changed','commercial_bank',b.id,jsonb_build_object('from',b.status,'to',p_status,'note',p_note));
end;
$function$;

create or replace function public.admin_set_bank_member(p_bank_id uuid,p_profile_id uuid,p_position text,p_permissions text[],p_status text default 'active')
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode nomear funcionários.'; end if;
 if p_status not in ('active','suspended','removed') or length(trim(coalesce(p_position,'')))<2 then raise exception 'Dados do funcionário inválidos.'; end if;
 if not exists(select 1 from public.commercial_banks where id=p_bank_id and status='active') then raise exception 'Banco não está ativo.'; end if;
 insert into public.bank_members(bank_id,profile_id,position,permissions,status,appointed_by)
 values(p_bank_id,p_profile_id,trim(p_position),coalesce(p_permissions,'{}'),p_status,auth.uid())
 on conflict(bank_id,profile_id) do update set position=excluded.position,permissions=excluded.permissions,status=excluded.status
 returning id into v_id;
 perform public.bank_audit(p_bank_id,'member_updated','bank_member',v_id,jsonb_build_object('profile_id',p_profile_id,'status',p_status));
 return v_id;
end;
$function$;

create or replace function public.open_bank_account(p_bank_id uuid,p_currency_id uuid,p_account_type text default 'checking',p_branch_id uuid default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare b public.commercial_banks%rowtype; p public.profiles%rowtype; v_number text; v_id uuid; v_country_currency uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into p from public.profiles where id=auth.uid() for update;
 if not found or p.registration_status<>'active' or coalesce(p.account_status,'active')<>'active' then raise exception 'Perfil não elegível para abrir conta.'; end if;
 if p_account_type not in ('checking','savings') then raise exception 'Nesta etapa, contas empresariais e institucionais aguardam o módulo de empresas/instituições.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id and status='active';
 if not found or p.country_id is distinct from b.country_id then raise exception 'Banco indisponível para o país do cidadão.'; end if;
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
end;
$function$;

create or replace function public.bank_transfer(p_from_account uuid,p_to_account uuid,p_amount numeric,p_idempotency_key text,p_description text default null)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.bank_accounts%rowtype; b public.bank_accounts%rowtype; v_id uuid; v_rate numeric:=1; v_rate_id uuid; v_received numeric; v_fee numeric:=0; v_lock uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 if p_amount is null or p_amount<=0 or p_amount>999999999999999999999999::numeric or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Valor ou chave de idempotência inválidos.'; end if;
 if exists(select 1 from public.bank_transfers where idempotency_key=p_idempotency_key) then select id into v_id from public.bank_transfers where idempotency_key=p_idempotency_key; return v_id; end if;
 select * into a from public.bank_accounts where id=p_from_account for update;
 if not found or a.owner_profile_id<>auth.uid() then raise exception 'Conta de origem não encontrada ou não pertence ao usuário.'; end if;
 select * into b from public.bank_accounts where id=p_to_account;
 if not found then raise exception 'Conta de destino não encontrada.'; end if;
 if a.id=b.id or a.status<>'active' or b.status<>'active' then raise exception 'Contas iguais ou indisponíveis.'; end if;
 if a.country_id<>b.country_id then raise exception 'Transferência internacional ainda requer autorização internacional configurada; operação bloqueada.'; end if;
 if a.currency_id<>b.currency_id then
  select r.id,r.rate into v_rate_id,v_rate from public.exchange_rates r
  where r.from_currency_id=a.currency_id and r.to_currency_id=b.currency_id and r.status='active'
   and r.effective_from<=now() and (r.effective_until is null or r.effective_until>now())
  order by r.effective_from desc limit 1;
  if v_rate_id is null then raise exception 'Não existe cotação vigente para este par de moedas.'; end if;
 end if;
 v_received:=round(p_amount*v_rate,6);
 if a.balance<p_amount then raise exception 'Saldo insuficiente.'; end if;
 perform 1 from public.bank_accounts where id in (a.id,b.id) order by id for update;
 update public.bank_accounts set balance=balance-p_amount where id=a.id returning * into a;
 update public.bank_accounts set balance=balance+v_received where id=b.id returning * into b;
 insert into public.bank_transfers(from_account_id,to_account_id,amount_sent,from_currency_id,amount_received,to_currency_id,exchange_rate_id,exchange_rate,fee_amount,idempotency_key,initiated_by,description)
 values(a.id,b.id,p_amount,a.currency_id,v_received,b.currency_id,v_rate_id,v_rate,0,p_idempotency_key,auth.uid(),p_description) returning id into v_id;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'transfer_out',p_amount,a.currency_id,a.balance,coalesce(p_description,'Transferência enviada'),v_id,p_idempotency_key||':out',auth.uid()),
       (b.id,'transfer_in',v_received,b.currency_id,b.balance,coalesce(p_description,'Transferência recebida'),v_id,p_idempotency_key||':in',auth.uid());
 perform public.bank_audit(a.bank_id,'transfer_sent','bank_transfer',v_id,jsonb_build_object('to_account',b.id,'amount',p_amount));
 return v_id;
end;
$function$;

create or replace function public.get_my_bank_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare v jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select jsonb_build_object(
  'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'bank_id',a.bank_id,'bank_name',b.name,'bank_identifier',b.bank_identifier,'account_number',a.account_number,'account_type',a.account_type,'status',a.status,'balance',a.balance,'currency_id',a.currency_id,'currency_code',c.internal_code,'currency_symbol',c.symbol,'country_id',a.country_id) order by a.created_at desc)
   from public.bank_accounts a join public.commercial_banks b on b.id=a.bank_id join public.currencies c on c.id=a.currency_id where a.owner_profile_id=auth.uid()),'[]'::jsonb),
  'banks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'identifier',b.bank_identifier,'country_id',b.country_id,'country_name',co.name,'type',b.bank_type) order by b.name)
   from public.commercial_banks b join public.countries co on co.id=b.country_id where b.status='active'
   and exists(select 1 from public.profiles p where p.id=auth.uid() and p.country_id=b.country_id)),'[]'::jsonb),
  'transactions',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'account_id',t.account_id,'type',t.transaction_type,'amount',t.amount,'currency_id',t.currency_id,'balance_after',t.balance_after,'description',t.description,'created_at',t.created_at,'status',t.status) order by t.created_at desc)
   from public.bank_transactions t join public.bank_accounts a on a.id=t.account_id where a.owner_profile_id=auth.uid()),'[]'::jsonb)
 ) into v;
 return v;
end;
$function$;

create or replace function public.admin_get_banking_overview()
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode consultar o panorama bancário.'; end if;
 return jsonb_build_object(
  'banks',(select count(*) from public.commercial_banks),
  'active_banks',(select count(*) from public.commercial_banks where status='active'),
  'accounts',(select count(*) from public.bank_accounts),
  'active_accounts',(select count(*) from public.bank_accounts where status='active'),
  'deposits',(select count(*) from public.bank_transactions where transaction_type='deposit'),
  'withdrawals',(select count(*) from public.bank_transactions where transaction_type='withdrawal'),
  'transfers',(select count(*) from public.bank_transfers),
  'loans',(select count(*) from public.bank_loans),
  'pending_banks',coalesce((select jsonb_agg(to_jsonb(b)) from public.commercial_banks b where status='pending'),'[]'::jsonb)
 );
end;
$function$;

create or replace function public.request_bank_loan(p_account_id uuid,p_amount numeric,p_term_months integer,p_rate numeric,p_purpose text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.bank_accounts%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into a from public.bank_accounts where id=p_account_id and owner_profile_id=auth.uid() and status='active';
 if not found then raise exception 'Conta de crédito inválida.'; end if;
 if p_amount<=0 or p_term_months not between 1 and 360 or p_rate not between 0 and 10000 or length(trim(coalesce(p_purpose,'')))<5 then raise exception 'Dados de crédito inválidos.'; end if;
 insert into public.loan_applications(bank_id,applicant_profile_id,account_id,amount,currency_id,term_months,annual_interest_rate,installments_count,purpose)
 values(a.bank_id,auth.uid(),a.id,p_amount,a.currency_id,p_term_months,p_rate,p_term_months,p_purpose) returning id into v_id;
 perform public.bank_audit(a.bank_id,'loan_requested','loan_application',v_id,jsonb_build_object('amount',p_amount,'term',p_term_months));
 return v_id;
end;
$function$;

create or replace function public.admin_review_bank_loan(p_application_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare x public.loan_applications%rowtype; a public.bank_accounts%rowtype; v_loan uuid; v_total numeric; v_monthly numeric; i integer;
begin
 select * into x from public.loan_applications where id=p_application_id for update;
 if not found or not (public.is_world_admin() or public.is_bank_member(x.bank_id,'loan.review')) then raise exception 'Sem permissão ou solicitação inexistente.'; end if;
 if x.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'Solicitação já revisada ou decisão inválida.'; end if;
 update public.loan_applications set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now() where id=x.id;
 if p_decision='rejected' then return null; end if;
 select * into a from public.bank_accounts where id=x.account_id for update;
 if a.status<>'active' then raise exception 'Conta de destino indisponível.'; end if;
 v_total:=round(x.amount*(1+(x.annual_interest_rate/100)*(x.term_months::numeric/12)),6);
 v_monthly:=round(v_total/x.installments_count,6);
 insert into public.bank_loans(application_id,bank_id,borrower_profile_id,account_id,principal,total_due,currency_id,annual_interest_rate,installments_count)
 values(x.id,x.bank_id,x.applicant_profile_id,x.account_id,x.amount,v_total,x.currency_id,x.annual_interest_rate,x.installments_count) returning id into v_loan;
 update public.bank_accounts set balance=balance+x.amount where id=a.id returning * into a;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'loan_disbursement',x.amount,a.currency_id,a.balance,'Crédito de empréstimo aprovado',v_loan,'loan:'||v_loan,auth.uid());
 for i in 1..x.installments_count loop
  insert into public.loan_installments(loan_id,installment_number,due_date,amount_due)
  values(v_loan,i,(current_date+(i||' month')::interval)::date,case when i=x.installments_count then v_total-v_monthly*(x.installments_count-1) else v_monthly end);
 end loop;
 perform public.bank_audit(x.bank_id,'loan_approved','bank_loan',v_loan,jsonb_build_object('principal',x.amount,'total_due',v_total));
 return v_loan;
end;
$function$;

create or replace function public.pay_bank_loan_installment(p_installment_id uuid,p_from_account uuid,p_idempotency_key text)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare ins public.loan_installments%rowtype; l public.bank_loans%rowtype; a public.bank_accounts%rowtype; v_due numeric;
begin
 select * into ins from public.loan_installments where id=p_installment_id for update;
 if not found then raise exception 'Parcela inexistente.'; end if;
 select * into l from public.bank_loans where id=ins.loan_id;
 if l.borrower_profile_id<>auth.uid() then raise exception 'Parcela não pertence ao usuário.'; end if;
 if ins.status='paid' then return; end if;
 select * into a from public.bank_accounts where id=p_from_account and owner_profile_id=auth.uid() and status='active' for update;
 if not found or a.currency_id<>l.currency_id then raise exception 'Conta de pagamento inválida.'; end if;
 v_due:=ins.amount_due-ins.amount_paid;
 if a.balance<v_due then raise exception 'Saldo insuficiente.'; end if;
 update public.bank_accounts set balance=balance-v_due where id=a.id returning * into a;
 update public.loan_installments set amount_paid=amount_due,paid_at=now(),status='paid' where id=ins.id;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'loan_payment',v_due,a.currency_id,a.balance,'Pagamento de parcela de empréstimo',l.id,p_idempotency_key,auth.uid());
 if not exists(select 1 from public.loan_installments where loan_id=l.id and status<>'paid') then update public.bank_loans set status='paid' where id=l.id; end if;
end;
$function$;

revoke all on function public.is_bank_member(uuid,text) from public,anon;
revoke all on function public.admin_create_commercial_bank(uuid,text,text,text,text,text,uuid) from public,anon;
revoke all on function public.admin_review_commercial_bank(uuid,text,text) from public,anon;
revoke all on function public.admin_set_bank_member(uuid,uuid,text,text[],text) from public,anon;
revoke all on function public.open_bank_account(uuid,uuid,text,uuid) from public,anon;
revoke all on function public.bank_transfer(uuid,uuid,numeric,text,text) from public,anon;
revoke all on function public.get_my_bank_dashboard() from public,anon;
revoke all on function public.admin_get_banking_overview() from public,anon;
revoke all on function public.request_bank_loan(uuid,numeric,integer,numeric,text) from public,anon;
revoke all on function public.admin_review_bank_loan(uuid,text) from public,anon;
revoke all on function public.pay_bank_loan_installment(uuid,uuid,text) from public,anon;
grant execute on function public.admin_create_commercial_bank(uuid,text,text,text,text,text,uuid) to authenticated;
grant execute on function public.admin_review_commercial_bank(uuid,text,text) to authenticated;
grant execute on function public.admin_set_bank_member(uuid,uuid,text,text[],text) to authenticated;
grant execute on function public.open_bank_account(uuid,uuid,text,uuid) to authenticated;
grant execute on function public.bank_transfer(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.get_my_bank_dashboard() to authenticated;
grant execute on function public.admin_get_banking_overview() to authenticated;
grant execute on function public.request_bank_loan(uuid,numeric,integer,numeric,text) to authenticated;
grant execute on function public.admin_review_bank_loan(uuid,text) to authenticated;
grant execute on function public.pay_bank_loan_installment(uuid,uuid,text) to authenticated;

commit;
