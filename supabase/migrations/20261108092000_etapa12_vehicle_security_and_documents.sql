begin;
-- A emissão gratuita de veículos foi removida: veículos novos só entram por venda autenticada.
drop function if exists public.vehicle_register_initial(uuid,text);

create or replace function public.vehicle_admin_upsert_category(p_id uuid,p_code text,p_name text,p_active boolean)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v uuid;
begin
 if not public.is_world_admin() then raise exception 'Somente Super Admin pode administrar categorias.'; end if;
 if length(trim(coalesce(p_code,'')))<2 or length(trim(coalesce(p_name,'')))<2 then raise exception 'Categoria inválida.'; end if;
 if p_id is null then insert into public.vehicle_categories(code,name,is_active) values(lower(trim(p_code)),trim(p_name),p_active) returning id into v;
 else update public.vehicle_categories set code=lower(trim(p_code)),name=trim(p_name),is_active=p_active where id=p_id returning id into v; end if;
 if v is null then raise exception 'Categoria não encontrada.'; end if;
 perform public.vehicle_audit(null,'vehicle_category',v,'category_upserted',jsonb_build_object('code',p_code,'name',p_name,'active',p_active)); return v;
end; $$;
grant execute on function public.vehicle_admin_upsert_category(uuid,text,text,boolean) to authenticated;

create or replace function public.vehicle_private_transfer(p_vehicle uuid,p_buyer_profile uuid,p_buyer_company uuid,p_seller_account uuid,p_buyer_account uuid,p_amount numeric,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v public.vehicles%rowtype; sa public.bank_accounts%rowtype; ba public.bank_accounts%rowtype; sale uuid; oldp uuid; oldc uuid;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency,'')))<12 or p_amount<=0 or ((p_buyer_profile is not null)::integer+(p_buyer_company is not null)::integer<>1) then raise exception 'Dados da transferência inválidos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select id into sale from public.vehicle_sales where idempotency_key=p_idempotency; if sale is not null then return sale; end if;
 select * into v from public.vehicles where id=p_vehicle and status in ('active','for_sale') for update;
 if not found or (v.owner_profile_id<>auth.uid() and not (v.owner_company_id is not null and public.is_company_member(v.owner_company_id,'fleet.manage'))) then raise exception 'Veículo não pertence ao vendedor ou está indisponível.'; end if;
 oldp:=v.owner_profile_id; oldc:=v.owner_company_id;
 if p_buyer_profile is not null and not exists(select 1 from public.profiles where id=p_buyer_profile and role='citizen' and registration_status='active' and country_id=v.country_id) then raise exception 'O comprador deve ser cidadão ativo do país de registro.'; end if;
 if p_buyer_company is not null and not exists(select 1 from public.companies where id=p_buyer_company and status='active' and country_id=v.country_id) then raise exception 'A empresa compradora deve estar ativa no país do veículo.'; end if;
 select * into sa from public.bank_accounts where id=p_seller_account and status='active' and country_id=v.country_id and ((owner_profile_id=auth.uid()) or (owner_company_id=oldc and public.is_company_member(oldc,'finance.manage'))) for update;
 select * into ba from public.bank_accounts where id=p_buyer_account and status='active' and country_id=v.country_id and ((owner_profile_id=p_buyer_profile) or (owner_company_id=p_buyer_company and public.is_company_member(p_buyer_company,'finance.manage'))) for update;
 if sa.id is null or ba.id is null or sa.currency_id<>ba.currency_id or sa.currency_id is distinct from (select currency_id from public.vehicle_catalog where id=v.catalog_id) then raise exception 'Contas ou moeda incompatíveis.'; end if;
 if ba.balance<p_amount then raise exception 'Saldo insuficiente do comprador.'; end if;
 update public.bank_accounts set balance=balance-p_amount where id=ba.id returning * into ba;
 update public.bank_accounts set balance=balance+p_amount where id=sa.id returning * into sa;
 insert into public.vehicle_sales(vehicle_id,seller_profile_id,seller_company_id,buyer_profile_id,buyer_company_id,seller_account_id,buyer_account_id,amount,currency_id,idempotency_key)
 values(v.id,oldp,oldc,p_buyer_profile,p_buyer_company,p_seller_account,p_buyer_account,p_amount,sa.currency_id,p_idempotency) returning id into sale;
 update public.vehicles set owner_profile_id=p_buyer_profile,owner_company_id=p_buyer_company,status='active',document_status='regular',updated_at=now() where id=v.id;
 insert into public.vehicle_ownership_history(vehicle_id,previous_profile_id,previous_company_id,new_profile_id,new_company_id,transfer_value,currency_id,transfer_type,sale_id,actor_id)
 values(v.id,oldp,oldc,p_buyer_profile,p_buyer_company,p_amount,sa.currency_id,'private_sale',sale,auth.uid());
 insert into public.vehicle_documents(vehicle_id,document_number,document_type,issuer_country_id,issued_by,payload)
 values(v.id,'OWN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),'ownership',v.country_id,auth.uid(),jsonb_build_object('fictional',true,'sale_id',sale));
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,reference_id,idempotency_key,actor_id)
 values(ba.id,'vehicle_purchase',p_amount,ba.currency_id,ba.balance,'Compra particular de veículo',sale,'veh-buyer-'||p_idempotency,auth.uid()),
 (sa.id,'vehicle_sale',p_amount,sa.currency_id,sa.balance,'Venda particular de veículo',sale,'veh-seller-'||p_idempotency,auth.uid());
 perform public.vehicle_audit(v.country_id,'vehicle',v.id,'ownership_transferred',jsonb_build_object('sale_id',sale)); return sale;
end; $$;
grant execute on function public.vehicle_private_transfer(uuid,uuid,uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.vehicle_pay_fee(p_fee uuid,p_account uuid,p_idempotency text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare f public.vehicle_fees%rowtype; a public.bank_accounts%rowtype; tx uuid; treasury public.national_treasuries%rowtype; code text; doc text;
begin
 if auth.uid() is null or length(trim(coalesce(p_idempotency,'')))<12 then raise exception 'Chave inválida.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_idempotency,0));
 select * into f from public.vehicle_fees where id=p_fee for update;
 if not found or f.status<>'pending' then raise exception 'Taxa não disponível.'; end if;
 if f.owner_profile_id is distinct from auth.uid() and not (f.owner_company_id is not null and public.is_company_member(f.owner_company_id,'finance.manage')) then raise exception 'Taxa não pertence ao pagador.'; end if;
 select * into a from public.bank_accounts where id=p_account and status='active' and currency_id=f.currency_id and ((owner_profile_id=auth.uid()) or (owner_company_id=f.owner_company_id and public.is_company_member(f.owner_company_id,'finance.manage'))) for update;
 if not found or a.balance<f.amount then raise exception 'Conta inválida ou saldo insuficiente.'; end if;
 select * into treasury from public.national_treasuries where country_id=f.country_id for update;
 if not found then raise exception 'Tesouro Nacional não cadastrado.'; end if;
 select internal_code into code from public.currencies where id=f.currency_id;
 if treasury.currency_code is distinct from code then raise exception 'Moeda da taxa diverge da moeda do Tesouro.'; end if;
 update public.bank_accounts set balance=balance-f.amount where id=a.id returning * into a;
 insert into public.bank_transactions(account_id,transaction_type,amount,currency_id,balance_after,description,idempotency_key,actor_id)
 values(a.id,'vehicle_fee',f.amount,a.currency_id,a.balance,'Taxa veicular ao Tesouro',p_idempotency,auth.uid()) returning id into tx;
 insert into public.treasury_ledger_entries(country_id,entry_type,category,description,amount,currency_code_snapshot,signed_amount,source_type,source_id,idempotency_key,created_by)
 values(f.country_id,'revenue','vehicle_fee','Taxa veicular '||f.id,f.amount,code,f.amount,'vehicle_fee',f.id,'vehicle-fee:'||p_idempotency,auth.uid());
 update public.vehicle_fees set status='paid',paid_at=now(),bank_transaction_id=tx,idempotency_key=p_idempotency where id=f.id;
 update public.vehicles set document_status='regular',updated_at=now() where id=f.vehicle_id;
 doc:='LIC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
 insert into public.vehicle_documents(vehicle_id,document_number,document_type,issuer_country_id,issued_by,valid_until,payload)
 values(f.vehicle_id,doc,'license',f.country_id,auth.uid(),(current_date+365)::timestamptz,jsonb_build_object('fictional',true,'fee_id',f.id,'bank_transaction_id',tx));
 perform public.vehicle_audit(f.country_id,'vehicle_fee',f.id,'paid',jsonb_build_object('transaction_id',tx,'license_document',doc)); return tx;
end; $$;
grant execute on function public.vehicle_pay_fee(uuid,uuid,text) to authenticated;
commit;