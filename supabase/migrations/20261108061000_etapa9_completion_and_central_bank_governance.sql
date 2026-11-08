-- WORLD ECONOMY — COMPLEMENTO DA ETAPA 9 + GOVERNANÇA DO BANCO CENTRAL
-- Migration aditiva: corrige fluxos bancários, cria carteira de dinheiro emitido
-- e formaliza solicitação presidencial / aprovação global do Banco Central.
begin;

-- ---------------------------------------------------------------------------
-- GOVERNANÇA DO BANCO CENTRAL: o país solicita; o Super Admin aprova e cria.
-- O Presidente não recebe poderes monetários automaticamente.
-- ---------------------------------------------------------------------------
create table if not exists public.central_bank_creation_requests (
 id uuid primary key default gen_random_uuid(),
 country_id uuid not null references public.countries(id) on delete restrict,
 requested_by uuid not null references public.profiles(id) on delete restrict,
 proposed_name text not null check(length(trim(proposed_name)) between 3 and 160),
 proposed_identifier text not null check(proposed_identifier ~ '^[A-Z0-9][A-Z0-9._-]{2,39}$'),
 description text,
 proposed_governor_profile_id uuid references public.profiles(id) on delete restrict,
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 central_bank_id uuid references public.central_banks(id) on delete restrict,
 reviewed_by uuid references public.profiles(id) on delete restrict,
 review_note text,
 created_at timestamptz not null default now(),
 reviewed_at timestamptz,
 check((status='approved' and central_bank_id is not null) or status<>'approved')
);
create unique index if not exists central_bank_creation_one_pending_country
 on public.central_bank_creation_requests(country_id) where status='pending';
create index if not exists central_bank_creation_requests_status_idx
 on public.central_bank_creation_requests(status,created_at desc);

alter table public.central_bank_creation_requests enable row level security;
drop policy if exists central_bank_creation_requests_read on public.central_bank_creation_requests;
create policy central_bank_creation_requests_read on public.central_bank_creation_requests
 for select to authenticated
 using(requested_by=auth.uid() or public.is_world_admin() or public.is_country_president(country_id));
revoke all on public.central_bank_creation_requests from public,anon,authenticated;
grant select on public.central_bank_creation_requests to authenticated;

create or replace function public.request_central_bank_creation(
 p_country_id uuid,p_name text,p_identifier text,p_description text default null,
 p_proposed_governor_profile_id uuid default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_profile public.profiles%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into v_profile from public.profiles where id=auth.uid();
 if not found or v_profile.role<>'president' or v_profile.country_id is distinct from p_country_id
   or not public.is_country_president(p_country_id) then
  raise exception 'Somente o Presidente ativo do país pode solicitar a criação do Banco Central.';
 end if;
 if length(trim(coalesce(p_name,'')))<3 or upper(trim(coalesce(p_identifier,''))) !~ '^[A-Z0-9][A-Z0-9._-]{2,39}$' then
  raise exception 'Nome ou identificador institucional inválido.';
 end if;
 if exists(select 1 from public.central_banks where country_id=p_country_id and is_primary) then
  raise exception 'Este país já possui um Banco Central principal.';
 end if;
 if p_proposed_governor_profile_id is not null and not exists(
   select 1 from public.profiles p where p.id=p_proposed_governor_profile_id
    and p.country_id=p_country_id and p.registration_status='active'
    and coalesce(p.account_status,'active')='active'
 ) then raise exception 'O indicado para Governador precisa ser um cidadão ativo do país.'; end if;
 insert into public.central_bank_creation_requests(country_id,requested_by,proposed_name,proposed_identifier,description,proposed_governor_profile_id)
 values(p_country_id,auth.uid(),trim(p_name),upper(trim(p_identifier)),nullif(trim(p_description),''),p_proposed_governor_profile_id)
 returning id into v_id;
 return v_id;
end;
$function$;

create or replace function public.admin_review_central_bank_creation_request(
 p_request_id uuid,p_approve boolean,p_note text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare r public.central_bank_creation_requests%rowtype; v_bank uuid; v_governor uuid;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode revisar a criação do Banco Central.'; end if;
 select * into r from public.central_bank_creation_requests where id=p_request_id for update;
 if not found or r.status<>'pending' then raise exception 'Solicitação inexistente ou já revisada.'; end if;
 perform 1 from public.countries where id=r.country_id for update;
 if p_approve then
  if exists(select 1 from public.central_banks where country_id=r.country_id and is_primary) then
   raise exception 'O país já possui um Banco Central principal; revise a solicitação como rejeitada.';
  end if;
  v_bank:=public.admin_create_central_bank(r.country_id,r.proposed_name,r.proposed_identifier,r.description,true);
  if r.proposed_governor_profile_id is not null then
   v_governor:=r.proposed_governor_profile_id;
   perform public.admin_set_central_bank_member(
    v_bank,v_governor,'Governador do Banco Central',
    array['dashboard.manage','issuance.request','withdrawal.request','reserves.manage','interest.manage','policy.manage','targets.manage','decisions.manage','audit.read'],
    'active'
   );
  end if;
  update public.central_bank_creation_requests set status='approved',central_bank_id=v_bank,
   reviewed_by=auth.uid(),review_note=p_note,reviewed_at=now() where id=r.id;
 else
  update public.central_bank_creation_requests set status='rejected',reviewed_by=auth.uid(),
   review_note=p_note,reviewed_at=now() where id=r.id;
 end if;
 return v_bank;
end;
$function$;

revoke all on function public.request_central_bank_creation(uuid,text,text,text,uuid) from public,anon;
revoke all on function public.admin_review_central_bank_creation_request(uuid,boolean,text) from public,anon;
grant execute on function public.request_central_bank_creation(uuid,text,text,text,uuid) to authenticated;
grant execute on function public.admin_review_central_bank_creation_request(uuid,boolean,text) to authenticated;

-- ---------------------------------------------------------------------------
-- DINHEIRO EM ESPÉCIE / CARTEIRA: cada crédito deve vir de emissão aprovada.
-- Depósitos e saques movem saldo; não criam moeda.
-- ---------------------------------------------------------------------------
create table if not exists public.bank_cash_wallets (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references public.profiles(id) on delete restrict,
 country_id uuid not null references public.countries(id) on delete restrict,
 currency_id uuid not null references public.currencies(id) on delete restrict,
 balance numeric(30,6) not null default 0 check(balance>=0),
 updated_at timestamptz not null default now(),
 unique(profile_id,country_id,currency_id),
 unique(id,currency_id)
);
create table if not exists public.bank_cash_wallet_transactions (
 id uuid primary key default gen_random_uuid(),
 wallet_id uuid not null references public.bank_cash_wallets(id) on delete restrict,
 transaction_type text not null check(transaction_type in ('issuance_allocation','deposit','withdrawal')),
 amount numeric(30,6) not null check(amount>0),
 balance_after numeric(30,6) not null check(balance_after>=0),
 reference_id uuid,
 idempotency_key text not null unique,
 description text not null,
 actor_id uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now()
);
create index if not exists bank_cash_wallet_transactions_date_idx
 on public.bank_cash_wallet_transactions(wallet_id,created_at desc);
alter table public.bank_cash_wallets enable row level security;
alter table public.bank_cash_wallet_transactions enable row level security;
drop policy if exists bank_cash_wallets_read on public.bank_cash_wallets;
create policy bank_cash_wallets_read on public.bank_cash_wallets for select to authenticated
 using(profile_id=auth.uid() or public.is_world_admin());
drop policy if exists bank_cash_wallet_transactions_read on public.bank_cash_wallet_transactions;
create policy bank_cash_wallet_transactions_read on public.bank_cash_wallet_transactions for select to authenticated
 using(public.is_world_admin() or exists(select 1 from public.bank_cash_wallets w where w.id=wallet_id and w.profile_id=auth.uid()));
revoke all on public.bank_cash_wallets,public.bank_cash_wallet_transactions from public,anon,authenticated;
grant select on public.bank_cash_wallets,public.bank_cash_wallet_transactions to authenticated;

create or replace function public.admin_allocate_issued_money_to_wallet(
 p_profile_id uuid,p_amount numeric,p_reason text
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare p public.profiles%rowtype; v_currency uuid; v_wallet uuid; v_balance numeric; v_issued numeric; v_committed numeric; v_key text;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode distribuir moeda emitida.'; end if;
 if p_amount is null or p_amount<=0 or length(trim(coalesce(p_reason,'')))<5 then raise exception 'Valor ou justificativa inválidos.'; end if;
 select * into p from public.profiles where id=p_profile_id for update;
 if not found or p.country_id is null then raise exception 'Cidadão sem país associado.'; end if;
 select c.id into v_currency from public.currencies c join public.country_currency_assignments a on a.currency_id=c.id
 where a.country_id=p.country_id and a.effective_until is null and c.status='active' order by a.effective_from desc limit 1;
 if v_currency is null then raise exception 'O país não possui moeda nacional ativa.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p.country_id::text||':'||v_currency::text,0));
 select coalesce(sum(case when operation_type='issuance' then amount else -amount end),0)
 into v_issued from public.money_supply_records where country_id=p.country_id and currency_id=v_currency;
 select
  coalesce((select sum(balance) from public.bank_accounts where country_id=p.country_id and currency_id=v_currency),0)
 +coalesce((select sum(l.balance) from public.bank_liquidity l join public.commercial_banks b on b.id=l.bank_id where b.country_id=p.country_id and l.currency_id=v_currency),0)
 +coalesce((select sum(balance) from public.bank_cash_wallets where country_id=p.country_id and currency_id=v_currency),0)
 into v_committed;
 if v_issued-v_committed<p_amount then
  raise exception 'Oferta monetária disponível insuficiente. Emissão líquida: %, já distribuído ou depositado: %, solicitado: %.',v_issued,v_committed,p_amount;
 end if;
 insert into public.bank_cash_wallets(profile_id,country_id,currency_id,balance)
 values(p.id,p.country_id,v_currency,p_amount)
 on conflict(profile_id,country_id,currency_id) do update set balance=bank_cash_wallets.balance+excluded.balance,updated_at=now()
 returning id,balance into v_wallet,v_balance;
 v_key:='issuance-wallet:'||gen_random_uuid()::text;
 insert into public.bank_cash_wallet_transactions(wallet_id,transaction_type,amount,balance_after,idempotency_key,description,actor_id)
 values(v_wallet,'issuance_allocation',p_amount,v_balance,v_key,trim(p_reason),auth.uid());
 return v_wallet;
end;
$function$;

create or replace function public.bank_deposit(
 p_account_id uuid,p_amount numeric,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.bank_accounts%rowtype; w public.bank_cash_wallets%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 if p_amount is null or p_amount<=0 or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Valor ou chave de idempotência inválidos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 select id into v_id from public.bank_transactions where idempotency_key=p_idempotency_key;
 if v_id is not null then return v_id; end if;
 select * into a from public.bank_accounts where id=p_account_id for update;
 if not found or a.owner_profile_id<>auth.uid() or a.status<>'active' then raise exception 'Conta de destino inválida.'; end if;
 if not exists(select 1 from public.commercial_banks b where b.id=a.bank_id and b.status='active') then raise exception 'Banco indisponível.'; end if;
 select * into w from public.bank_cash_wallets where profile_id=auth.uid() and country_id=a.country_id and currency_id=a.currency_id for update;
 if not found or w.balance<p_amount then raise exception 'Saldo em dinheiro insuficiente para o depósito.'; end if;
 update public.bank_cash_wallets set balance=balance-p_amount,updated_at=now() where id=w.id returning * into w;
 update public.bank_accounts set balance=balance+p_amount where id=a.id returning * into a;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,idempotency_key,actor_id)
 values(a.id,'deposit',p_amount,a.currency_id,a.balance,'Depósito de dinheiro em carteira',p_idempotency_key,auth.uid()) returning id into v_id;
 insert into public.bank_cash_wallet_transactions(wallet_id,transaction_type,amount,balance_after,reference_id,idempotency_key,description,actor_id)
 values(w.id,'deposit',p_amount,w.balance,v_id,p_idempotency_key||':wallet','Depósito em conta bancária',auth.uid());
 perform public.bank_audit(a.bank_id,'cash_deposit','bank_account',a.id,jsonb_build_object('amount',p_amount,'currency_id',a.currency_id));
 return v_id;
end;
$function$;

create or replace function public.bank_withdraw(
 p_account_id uuid,p_amount numeric,p_idempotency_key text
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.bank_accounts%rowtype; w public.bank_cash_wallets%rowtype; v_fee numeric:=0; v_limit numeric; v_id uuid; v_after numeric;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 if p_amount is null or p_amount<=0 or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Valor ou chave de idempotência inválidos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 select id into v_id from public.bank_transactions where idempotency_key=p_idempotency_key;
 if v_id is not null then return v_id; end if;
 select * into a from public.bank_accounts where id=p_account_id for update;
 if not found or a.owner_profile_id<>auth.uid() or a.status<>'active' then raise exception 'Conta de origem inválida.'; end if;
 if not exists(select 1 from public.commercial_banks b where b.id=a.bank_id and b.status='active') then raise exception 'Banco indisponível.'; end if;
 select coalesce(amount,0) into v_fee from public.bank_fees where bank_id=a.bank_id and fee_type='withdrawal' and active and (currency_id is null or currency_id=a.currency_id) order by currency_id nulls last limit 1;
 v_fee:=coalesce(v_fee,0);
 select daily_limit into v_limit from public.bank_limits where bank_id=a.bank_id and operation_type='withdrawal' and currency_id=a.currency_id;
 if v_limit is not null and coalesce((select sum(amount) from public.bank_transactions where account_id=a.id and transaction_type='withdrawal' and created_at>=date_trunc('day',now())),0)+p_amount>v_limit then raise exception 'Limite diário de saque excedido.'; end if;
 if a.balance<p_amount+v_fee then raise exception 'Saldo insuficiente para saque e tarifa.'; end if;
 insert into public.bank_cash_wallets(profile_id,country_id,currency_id,balance)
 values(auth.uid(),a.country_id,a.currency_id,0) on conflict(profile_id,country_id,currency_id) do nothing;
 select * into w from public.bank_cash_wallets where profile_id=auth.uid() and country_id=a.country_id and currency_id=a.currency_id for update;
 update public.bank_accounts set balance=balance-p_amount-v_fee where id=a.id returning balance into v_after;
 update public.bank_cash_wallets set balance=balance+p_amount,updated_at=now() where id=w.id returning * into w;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,idempotency_key,actor_id)
 values(a.id,'withdrawal',p_amount,a.currency_id,v_after+v_fee,'Saque para carteira em dinheiro',p_idempotency_key,auth.uid()) returning id into v_id;
 if v_fee>0 then
  insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,idempotency_key,actor_id)
  values(a.id,'fee',v_fee,a.currency_id,v_after,'Tarifa de saque',p_idempotency_key||':fee',auth.uid());
  insert into public.bank_liquidity(bank_id,currency_id,balance) values(a.bank_id,a.currency_id,v_fee)
   on conflict(bank_id,currency_id) do update set balance=bank_liquidity.balance+excluded.balance,updated_at=now();
 end if;
 insert into public.bank_cash_wallet_transactions(wallet_id,transaction_type,amount,balance_after,reference_id,idempotency_key,description,actor_id)
 values(w.id,'withdrawal',p_amount,w.balance,v_id,p_idempotency_key||':wallet','Saque de conta bancária',auth.uid());
 perform public.bank_audit(a.bank_id,'cash_withdrawal','bank_account',a.id,jsonb_build_object('amount',p_amount,'fee',v_fee));
 return v_id;
end;
$function$;

create or replace function public.bank_transfer(
 p_from_account uuid,p_to_account uuid,p_amount numeric,p_idempotency_key text,p_description text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.bank_accounts%rowtype; b public.bank_accounts%rowtype; v_id uuid; v_rate numeric:=1; v_rate_id uuid; v_received numeric; v_fee numeric:=0; v_limit numeric;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 if p_amount is null or p_amount<=0 or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Valor ou chave de idempotência inválidos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 select id into v_id from public.bank_transfers where idempotency_key=p_idempotency_key;
 if v_id is not null then return v_id; end if;
 if p_from_account=p_to_account then raise exception 'A origem e o destino devem ser contas diferentes.'; end if;
 perform 1 from public.bank_accounts where id in (p_from_account,p_to_account) order by id for update;
 select * into a from public.bank_accounts where id=p_from_account;
 select * into b from public.bank_accounts where id=p_to_account;
 if a.id is null or a.owner_profile_id<>auth.uid() then raise exception 'Conta de origem não encontrada ou não pertence ao usuário.'; end if;
 if b.id is null then raise exception 'Conta de destino não encontrada.'; end if;
 if a.status<>'active' or b.status<>'active' then raise exception 'Uma das contas está indisponível.'; end if;
 if not exists(select 1 from public.commercial_banks x where x.id=a.bank_id and x.status='active')
  or not exists(select 1 from public.commercial_banks x where x.id=b.bank_id and x.status='active') then raise exception 'Um dos bancos está suspenso ou encerrado.'; end if;
 if a.country_id<>b.country_id then raise exception 'Transferências internacionais estão bloqueadas até existir liquidação internacional autorizada.'; end if;
 if a.currency_id<>b.currency_id then
  select r.id,r.rate into v_rate_id,v_rate from public.exchange_rates r
  where r.from_currency_id=a.currency_id and r.to_currency_id=b.currency_id and r.status='active'
   and r.effective_from<=now() and (r.effective_until is null or r.effective_until>now())
  order by r.effective_from desc limit 1;
  if v_rate_id is null then raise exception 'Não existe cotação vigente para este par de moedas.'; end if;
 end if;
 select coalesce(amount,0) into v_fee from public.bank_fees where bank_id=a.bank_id and fee_type='transfer' and active and (currency_id is null or currency_id=a.currency_id) order by currency_id nulls last limit 1;
 v_fee:=coalesce(v_fee,0);
 select daily_limit into v_limit from public.bank_limits where bank_id=a.bank_id and operation_type='transfer' and currency_id=a.currency_id;
 if v_limit is not null and coalesce((select sum(amount) from public.bank_transactions where account_id=a.id and transaction_type='transfer_out' and created_at>=date_trunc('day',now())),0)+p_amount>v_limit then raise exception 'Limite diário de transferências excedido.'; end if;
 if a.balance<p_amount+v_fee then raise exception 'Saldo insuficiente para transferência e tarifa.'; end if;
 v_received:=round(p_amount*v_rate,6);
 update public.bank_accounts set balance=balance-p_amount-v_fee where id=a.id returning * into a;
 update public.bank_accounts set balance=balance+v_received where id=b.id returning * into b;
 insert into public.bank_transfers(from_account_id,to_account_id,amount_sent,from_currency_id,amount_received,to_currency_id,exchange_rate_id,exchange_rate,fee_amount,idempotency_key,initiated_by,description)
 values(a.id,b.id,p_amount,(select currency_id from public.bank_accounts where id=a.id),v_received,(select currency_id from public.bank_accounts where id=b.id),v_rate_id,v_rate,v_fee,p_idempotency_key,auth.uid(),p_description) returning id into v_id;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'transfer_out',p_amount,(select currency_id from public.bank_accounts where id=a.id),a.balance+v_fee,coalesce(p_description,'Transferência enviada'),v_id,p_idempotency_key||':out',auth.uid()),
       (b.id,'transfer_in',v_received,b.currency_id,b.balance,coalesce(p_description,'Transferência recebida'),v_id,p_idempotency_key||':in',auth.uid());
 if v_fee>0 then
  insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
  values(a.id,'fee',v_fee,a.currency_id,a.balance,'Tarifa de transferência',v_id,p_idempotency_key||':fee',auth.uid());
  insert into public.bank_liquidity(bank_id,currency_id,balance) values(a.bank_id,a.currency_id,v_fee)
   on conflict(bank_id,currency_id) do update set balance=bank_liquidity.balance+excluded.balance,updated_at=now();
 end if;
 perform public.bank_audit(a.bank_id,'transfer_sent','bank_transfer',v_id,jsonb_build_object('to_account',b.id,'amount',p_amount,'fee',v_fee));
 return v_id;
end;
$function$;

create or replace function public.bank_transfer_to_account(
 p_from_account uuid,p_bank_identifier text,p_account_number text,p_amount numeric,p_idempotency_key text,p_description text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_to_account uuid; v_id uuid; v_country uuid;
begin
 select country_id into v_country from public.bank_accounts where id=p_from_account and owner_profile_id=auth.uid() and status='active';
 if v_country is null then raise exception 'Conta de origem inválida.'; end if;
 select a.id into v_to_account from public.bank_accounts a join public.commercial_banks b on b.id=a.bank_id
 where b.bank_identifier=upper(trim(p_bank_identifier)) and a.account_number=trim(p_account_number)
  and a.country_id=v_country and a.status='active' and b.status='active';
 if v_to_account is null then raise exception 'Banco ou conta destinatária não encontrados neste país.'; end if;
 v_id:=public.bank_transfer(p_from_account,v_to_account,p_amount,p_idempotency_key,p_description);
 return v_id;
end;
$function$;

-- Gestão de agências, tarifas, limites e equipe pelo administrador da instituição.
create or replace function public.bank_manage_branch(
 p_bank_id uuid,p_branch_id uuid,p_name text,p_region text,p_city text,p_code text,p_status text default 'active'
) returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare v_id uuid;
begin
 if not (public.is_world_admin() or public.is_bank_member(p_bank_id,'bank.manage')) then raise exception 'Sem permissão para administrar agências.'; end if;
 if length(trim(coalesce(p_name,'')))<2 or length(trim(coalesce(p_code,'')))<2 or p_status not in ('active','suspended','closed') then raise exception 'Dados da agência inválidos.'; end if;
 if not exists(select 1 from public.commercial_banks where id=p_bank_id and status='active') then raise exception 'Banco indisponível.'; end if;
 if p_branch_id is null then
  insert into public.bank_branches(bank_id,name,region,city,branch_code,status)
  values(p_bank_id,trim(p_name),nullif(trim(p_region),''),nullif(trim(p_city),''),upper(trim(p_code)),p_status) returning id into v_id;
 else
  update public.bank_branches set name=trim(p_name),region=nullif(trim(p_region),''),city=nullif(trim(p_city),''),branch_code=upper(trim(p_code)),status=p_status
  where id=p_branch_id and bank_id=p_bank_id returning id into v_id;
  if v_id is null then raise exception 'Agência não encontrada.'; end if;
 end if;
 perform public.bank_audit(p_bank_id,'branch_saved','bank_branch',v_id,jsonb_build_object('status',p_status));
 return v_id;
end;
$function$;

create or replace function public.bank_set_fee(
 p_bank_id uuid,p_fee_type text,p_amount numeric,p_currency_id uuid,p_active boolean default true
) returns void language plpgsql security definer set search_path=public,auth as $function$
begin
 if not (public.is_world_admin() or public.is_bank_member(p_bank_id,'bank.manage')) then raise exception 'Sem permissão para configurar tarifas.'; end if;
 if p_fee_type not in ('maintenance','transfer','international','withdrawal') or p_amount is null or p_amount<0 then raise exception 'Tarifa inválida.'; end if;
 insert into public.bank_fees(bank_id,fee_type,amount,currency_id,active)
 values(p_bank_id,p_fee_type,p_amount,p_currency_id,p_active)
 on conflict(bank_id,fee_type) do update set amount=excluded.amount,currency_id=excluded.currency_id,active=excluded.active;
 perform public.bank_audit(p_bank_id,'fee_changed','bank_fee',null,jsonb_build_object('fee_type',p_fee_type,'amount',p_amount,'active',p_active));
end;
$function$;

create or replace function public.bank_set_daily_limit(
 p_bank_id uuid,p_operation_type text,p_daily_limit numeric,p_currency_id uuid
) returns void language plpgsql security definer set search_path=public,auth as $function$
begin
 if not (public.is_world_admin() or public.is_bank_member(p_bank_id,'bank.manage')) then raise exception 'Sem permissão para configurar limites.'; end if;
 if p_operation_type not in ('withdrawal','transfer') or p_daily_limit is null or p_daily_limit<=0 then raise exception 'Limite inválido.'; end if;
 insert into public.bank_limits(bank_id,operation_type,daily_limit,currency_id,updated_by)
 values(p_bank_id,p_operation_type,p_daily_limit,p_currency_id,auth.uid())
 on conflict(bank_id,operation_type,currency_id) do update set daily_limit=excluded.daily_limit,updated_by=auth.uid(),updated_at=now();
 perform public.bank_audit(p_bank_id,'daily_limit_changed','bank_limit',null,jsonb_build_object('operation_type',p_operation_type,'daily_limit',p_daily_limit));
end;
$function$;

create table if not exists public.bank_credit_policies (
 bank_id uuid primary key references public.commercial_banks(id) on delete restrict,
 annual_interest_rate numeric(12,6) not null default 12 check(annual_interest_rate between 0 and 10000),
 max_term_months integer not null default 60 check(max_term_months between 1 and 360),
 enabled boolean not null default true,
 updated_by uuid references public.profiles(id) on delete restrict,
 updated_at timestamptz not null default now()
);
alter table public.bank_credit_policies enable row level security;
drop policy if exists bank_credit_policies_read on public.bank_credit_policies;
create policy bank_credit_policies_read on public.bank_credit_policies for select to authenticated
 using(public.is_world_admin() or public.is_bank_member(bank_id,'loan.review') or exists(select 1 from public.commercial_banks b where b.id=bank_id and b.status='active'));
revoke all on public.bank_credit_policies from public,anon,authenticated;
grant select on public.bank_credit_policies to authenticated;

create or replace function public.bank_set_credit_policy(
 p_bank_id uuid,p_annual_rate numeric,p_max_term_months integer,p_enabled boolean
) returns void language plpgsql security definer set search_path=public,auth as $function$
begin
 if not (public.is_world_admin() or public.is_bank_member(p_bank_id,'bank.manage')) then raise exception 'Sem permissão para configurar crédito.'; end if;
 if p_annual_rate is null or p_annual_rate not between 0 and 10000 or p_max_term_months not between 1 and 360 then raise exception 'Política de crédito inválida.'; end if;
 insert into public.bank_credit_policies(bank_id,annual_interest_rate,max_term_months,enabled,updated_by)
 values(p_bank_id,p_annual_rate,p_max_term_months,p_enabled,auth.uid())
 on conflict(bank_id) do update set annual_interest_rate=excluded.annual_interest_rate,max_term_months=excluded.max_term_months,enabled=excluded.enabled,updated_by=auth.uid(),updated_at=now();
 perform public.bank_audit(p_bank_id,'credit_policy_changed','bank_credit_policy',p_bank_id,jsonb_build_object('annual_rate',p_annual_rate,'max_term_months',p_max_term_months,'enabled',p_enabled));
end;
$function$;

create or replace function public.request_bank_loan(p_account_id uuid,p_amount numeric,p_term_months integer,p_rate numeric,p_purpose text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare a public.bank_accounts%rowtype; v_policy public.bank_credit_policies%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select * into a from public.bank_accounts where id=p_account_id and owner_profile_id=auth.uid() and status='active';
 if not found or not exists(select 1 from public.commercial_banks b where b.id=a.bank_id and b.status='active') then raise exception 'Conta de crédito inválida ou banco indisponível.'; end if;
 select * into v_policy from public.bank_credit_policies where bank_id=a.bank_id;
 if not found then v_policy.annual_interest_rate:=12; v_policy.max_term_months:=60; v_policy.enabled:=true; end if;
 if not v_policy.enabled then raise exception 'Este banco não está aceitando solicitações de crédito.'; end if;
 if p_amount is null or p_amount<=0 or p_term_months not between 1 and v_policy.max_term_months or length(trim(coalesce(p_purpose,'')))<5 then raise exception 'Dados de crédito inválidos.'; end if;
 insert into public.loan_applications(bank_id,applicant_profile_id,account_id,amount,currency_id,term_months,annual_interest_rate,installments_count,purpose)
 values(a.bank_id,auth.uid(),a.id,p_amount,a.currency_id,p_term_months,v_policy.annual_interest_rate,p_term_months,trim(p_purpose)) returning id into v_id;
 perform public.bank_audit(a.bank_id,'loan_requested','loan_application',v_id,jsonb_build_object('amount',p_amount,'term',p_term_months,'annual_rate',v_policy.annual_interest_rate));
 return v_id;
end;
$function$;

create or replace function public.admin_review_bank_loan(p_application_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path=public,auth as $function$
declare x public.loan_applications%rowtype; a public.bank_accounts%rowtype; v_loan uuid; v_total numeric; v_monthly numeric; i integer; v_liquidity numeric;
begin
 select * into x from public.loan_applications where id=p_application_id for update;
 if not found or not (public.is_world_admin() or public.is_bank_member(x.bank_id,'loan.review')) then raise exception 'Sem permissão ou solicitação inexistente.'; end if;
 if x.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'Solicitação já revisada ou decisão inválida.'; end if;
 if p_decision='rejected' then
  update public.loan_applications set status='rejected',reviewed_by=auth.uid(),reviewed_at=now() where id=x.id;
  perform public.bank_audit(x.bank_id,'loan_rejected','loan_application',x.id,'{}'::jsonb);
  return null;
 end if;
 perform 1 from public.commercial_banks where id=x.bank_id and status='active' for update;
 if not found then raise exception 'Banco suspenso ou indisponível.'; end if;
 select * into a from public.bank_accounts where id=x.account_id for update;
 if not found or a.status<>'active' or a.currency_id<>x.currency_id then raise exception 'Conta de destino indisponível.'; end if;
 select balance into v_liquidity from public.bank_liquidity where bank_id=x.bank_id and currency_id=x.currency_id for update;
 if coalesce(v_liquidity,0)<x.amount then raise exception 'Liquidez bancária insuficiente. Capitalize o banco com recursos existentes antes de aprovar.'; end if;
 v_total:=round(x.amount*(1+(x.annual_interest_rate/100)*(x.term_months::numeric/12)),6);
 v_monthly:=round(v_total/x.installments_count,6);
 insert into public.bank_loans(application_id,bank_id,borrower_profile_id,account_id,principal,total_due,currency_id,annual_interest_rate,installments_count)
 values(x.id,x.bank_id,x.applicant_profile_id,x.account_id,x.amount,v_total,x.currency_id,x.annual_interest_rate,x.installments_count) returning id into v_loan;
 update public.bank_liquidity set balance=balance-x.amount,updated_at=now() where bank_id=x.bank_id and currency_id=x.currency_id;
 update public.bank_accounts set balance=balance+x.amount where id=a.id returning * into a;
 update public.loan_applications set status='approved',reviewed_by=auth.uid(),reviewed_at=now() where id=x.id;
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
declare ins public.loan_installments%rowtype; l public.bank_loans%rowtype; a public.bank_accounts%rowtype; v_due numeric; v_id uuid;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency_key,'')))<12 then raise exception 'Autenticação ou chave de idempotência inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency_key,0));
 if exists(select 1 from public.bank_transactions where idempotency_key=p_idempotency_key) then return; end if;
 select * into ins from public.loan_installments where id=p_installment_id for update;
 if not found then raise exception 'Parcela inexistente.'; end if;
 select * into l from public.bank_loans where id=ins.loan_id for update;
 if l.borrower_profile_id<>auth.uid() or l.status<>'active' then raise exception 'Parcela não pertence ao usuário ou empréstimo inativo.'; end if;
 select * into a from public.bank_accounts where id=p_from_account and owner_profile_id=auth.uid() and status='active' for update;
 if not found or a.currency_id<>l.currency_id or a.balance<ins.amount_due-ins.amount_paid then raise exception 'Conta de pagamento inválida ou saldo insuficiente.'; end if;
 v_due:=ins.amount_due-ins.amount_paid;
 update public.bank_accounts set balance=balance-v_due where id=a.id returning * into a;
 update public.loan_installments set amount_paid=amount_due,paid_at=now(),status='paid' where id=ins.id;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(a.id,'loan_payment',v_due,a.currency_id,a.balance,'Pagamento de parcela de empréstimo',l.id,p_idempotency_key,auth.uid()) returning id into v_id;
 insert into public.bank_liquidity(bank_id,currency_id,balance) values(l.bank_id,l.currency_id,v_due)
 on conflict(bank_id,currency_id) do update set balance=bank_liquidity.balance+excluded.balance,updated_at=now();
 if not exists(select 1 from public.loan_installments where loan_id=l.id and status<>'paid') then update public.bank_loans set status='paid' where id=l.id; end if;
 perform public.bank_audit(l.bank_id,'loan_installment_paid','bank_loan',l.id,jsonb_build_object('installment_id',ins.id,'amount',v_due));
end;
$function$;

-- Dashboard único para o portal: carteira, contas, extratos, solicitações e pagamentos.
create or replace function public.get_my_bank_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare v jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
 select jsonb_build_object(
  'cash_wallets',coalesce((select jsonb_agg(jsonb_build_object('id',w.id,'country_id',w.country_id,'currency_id',w.currency_id,'currency_code',c.internal_code,'currency_name',c.name,'symbol',c.symbol,'balance',w.balance) order by c.name)
   from public.bank_cash_wallets w join public.currencies c on c.id=w.currency_id where w.profile_id=auth.uid()),'[]'::jsonb),
  'wallet_transactions',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'type',t.transaction_type,'amount',t.amount,'balance_after',t.balance_after,'description',t.description,'created_at',t.created_at) order by t.created_at desc)
   from public.bank_cash_wallet_transactions t join public.bank_cash_wallets w on w.id=t.wallet_id where w.profile_id=auth.uid()),'[]'::jsonb),
  'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'bank_id',a.bank_id,'bank_name',b.name,'bank_identifier',b.bank_identifier,'account_number',a.account_number,'account_type',a.account_type,'status',a.status,'balance',a.balance,'currency_id',a.currency_id,'currency_code',c.internal_code,'currency_symbol',c.symbol,'country_id',a.country_id) order by a.created_at desc)
   from public.bank_accounts a join public.commercial_banks b on b.id=a.bank_id join public.currencies c on c.id=a.currency_id where a.owner_profile_id=auth.uid()),'[]'::jsonb),
  'banks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'identifier',b.bank_identifier,'country_id',b.country_id,'country_name',co.name,'type',b.bank_type,'status',b.status) order by b.name)
   from public.commercial_banks b join public.countries co on co.id=b.country_id where (b.status='active' or public.is_world_admin())
   and (public.is_world_admin() or exists(select 1 from public.profiles p where p.id=auth.uid() and p.country_id=b.country_id))),'[]'::jsonb),
  'countries',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.countries c where c.is_active and public.is_world_admin()),'[]'::jsonb),
  'transactions',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'account_id',t.account_id,'type',t.transaction_type,'amount',t.amount,'currency_id',t.currency_id,'balance_after',t.balance_after,'description',t.description,'created_at',t.created_at,'status',t.status) order by t.created_at desc)
   from public.bank_transactions t join public.bank_accounts a on a.id=t.account_id where a.owner_profile_id=auth.uid()),'[]'::jsonb),
  'loan_applications',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'bank_id',x.bank_id,'bank_name',b.name,'account_id',x.account_id,'amount',x.amount,'currency_id',x.currency_id,'currency_code',c.internal_code,'term_months',x.term_months,'annual_interest_rate',x.annual_interest_rate,'status',x.status,'purpose',x.purpose,'created_at',x.created_at) order by x.created_at desc)
   from public.loan_applications x join public.commercial_banks b on b.id=x.bank_id join public.currencies c on c.id=x.currency_id
   where x.applicant_profile_id=auth.uid() or public.is_world_admin() or public.is_bank_member(x.bank_id,'loan.review')),'[]'::jsonb),
  'installments',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'loan_id',i.loan_id,'installment_number',i.installment_number,'due_date',i.due_date,'amount_due',i.amount_due,'amount_paid',i.amount_paid,'status',i.status,'bank_name',b.name,'currency_code',c.internal_code) order by i.due_date)
   from public.loan_installments i join public.bank_loans l on l.id=i.loan_id join public.commercial_banks b on b.id=l.bank_id join public.currencies c on c.id=l.currency_id
   where l.borrower_profile_id=auth.uid() or public.is_world_admin() or public.is_bank_member(l.bank_id,'loan.review')),'[]'::jsonb),
  'bank_overview',case when public.is_world_admin() then public.admin_get_banking_overview() else null end
 ) into v;
 return v;
end;
$function$;

-- Revisão do status do banco também é registrada e bloqueia operações ao suspender.
create or replace function public.admin_review_commercial_bank(p_bank_id uuid,p_status text,p_note text default null)
returns void language plpgsql security definer set search_path=public,auth as $function$
declare b public.commercial_banks%rowtype;
begin
 if not public.is_world_admin() then raise exception 'Somente o Super Admin pode revisar bancos.'; end if;
 if p_status not in ('active','suspended','closed') then raise exception 'Situação inválida.'; end if;
 select * into b from public.commercial_banks where id=p_bank_id for update;
 if not found then raise exception 'Banco não encontrado.'; end if;
 if b.status='closed' and p_status<>'closed' then raise exception 'Banco encerrado não pode ser reativado; crie nova instituição.'; end if;
 update public.commercial_banks set status=p_status,approved_by=case when p_status='active' then auth.uid() else approved_by end,
  approved_at=case when p_status='active' then now() else approved_at end,updated_at=now() where id=b.id;
 perform public.bank_audit(b.id,'bank_status_changed','commercial_bank',b.id,jsonb_build_object('from',b.status,'to',p_status,'note',p_note));
end;
$function$;

-- Privilégios: todas as mutações passam por RPCs SECURITY DEFINER validadas.
revoke all on function public.admin_allocate_issued_money_to_wallet(uuid,numeric,text) from public,anon;
revoke all on function public.bank_deposit(uuid,numeric,text) from public,anon;
revoke all on function public.bank_withdraw(uuid,numeric,text) from public,anon;
revoke all on function public.bank_transfer(uuid,uuid,numeric,text,text) from public,anon;
revoke all on function public.bank_transfer_to_account(uuid,text,text,numeric,text,text) from public,anon;
revoke all on function public.bank_manage_branch(uuid,uuid,text,text,text,text,text) from public,anon;
revoke all on function public.bank_set_fee(uuid,text,numeric,uuid,boolean) from public,anon;
revoke all on function public.bank_set_daily_limit(uuid,text,numeric,uuid) from public,anon;
revoke all on function public.bank_set_credit_policy(uuid,numeric,integer,boolean) from public,anon;
revoke all on function public.request_bank_loan(uuid,numeric,integer,numeric,text) from public,anon;
revoke all on function public.admin_review_bank_loan(uuid,text) from public,anon;
revoke all on function public.pay_bank_loan_installment(uuid,uuid,text) from public,anon;
revoke all on function public.get_my_bank_dashboard() from public,anon;
grant execute on function public.admin_allocate_issued_money_to_wallet(uuid,numeric,text) to authenticated;
grant execute on function public.bank_deposit(uuid,numeric,text) to authenticated;
grant execute on function public.bank_withdraw(uuid,numeric,text) to authenticated;
grant execute on function public.bank_transfer(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.bank_transfer_to_account(uuid,text,text,numeric,text,text) to authenticated;
grant execute on function public.bank_manage_branch(uuid,uuid,text,text,text,text,text) to authenticated;
grant execute on function public.bank_set_fee(uuid,text,numeric,uuid,boolean) to authenticated;
grant execute on function public.bank_set_daily_limit(uuid,text,numeric,uuid) to authenticated;
grant execute on function public.bank_set_credit_policy(uuid,numeric,integer,boolean) to authenticated;
grant execute on function public.request_bank_loan(uuid,numeric,integer,numeric,text) to authenticated;
grant execute on function public.admin_review_bank_loan(uuid,text) to authenticated;
grant execute on function public.pay_bank_loan_installment(uuid,uuid,text) to authenticated;
grant execute on function public.get_my_bank_dashboard() to authenticated;

commit;
