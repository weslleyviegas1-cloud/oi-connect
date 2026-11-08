begin;
alter table public.bank_transactions drop constraint if exists bank_transactions_transaction_type_check;
alter table public.bank_transactions add constraint bank_transactions_transaction_type_check
 check(transaction_type in ('opening','deposit','withdrawal','transfer_in','transfer_out','fee','loan_disbursement','loan_payment','reversal','vehicle_purchase','vehicle_sale','vehicle_fee'));

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
 if sa.id is null or ba.id is null or sa.id=ba.id or sa.currency_id<>ba.currency_id or sa.currency_id is distinct from (select currency_id from public.vehicle_catalog where id=v.catalog_id) then raise exception 'Contas distintas ou moeda incompatíveis.'; end if;
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
commit;