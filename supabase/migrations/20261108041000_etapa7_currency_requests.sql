-- WORLD ECONOMY — ETAPA 7 complemento: solicitações de alteração de moeda nacional
begin;

create table if not exists public.currency_change_requests (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references public.countries(id) on delete restrict,
  requested_currency_id uuid not null references public.currencies(id) on delete restrict,
  requested_by uuid not null references public.profiles(id) on delete restrict,
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id) on delete restrict,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  check (length(trim(reason)) >= 5)
);
create unique index if not exists currency_change_one_pending_per_country
  on public.currency_change_requests(country_id) where status='pending';
create index if not exists currency_change_requests_country_created_idx
  on public.currency_change_requests(country_id,created_at desc);

alter table public.currency_change_requests enable row level security;
drop policy if exists currency_change_requests_read on public.currency_change_requests;
create policy currency_change_requests_read on public.currency_change_requests for select to authenticated
using (public.is_world_admin() or requested_by=auth.uid() or public.is_country_president(country_id));
revoke all on public.currency_change_requests from public,anon,authenticated;
grant select on public.currency_change_requests to authenticated;

create or replace function public.request_country_currency_change(
  p_country_id uuid,p_currency_id uuid,p_reason text
) returns uuid language plpgsql security definer set search_path=public,auth as $func$
declare v_id uuid; v_current_currency uuid;
begin
  if auth.uid() is null or not public.is_country_president(p_country_id) then
    raise exception 'Somente o presidente do próprio país pode solicitar alteração monetária.';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'Informe uma justificativa com pelo menos cinco caracteres.'; end if;
  if not exists(select 1 from public.currencies where id=p_currency_id and status='active') then
    raise exception 'A moeda solicitada não está ativa.';
  end if;
  select currency_id into v_current_currency from public.country_currency_assignments
    where country_id=p_country_id and effective_until is null;
  if v_current_currency=p_currency_id then raise exception 'Este país já utiliza a moeda selecionada.'; end if;
  insert into public.currency_change_requests(country_id,requested_currency_id,requested_by,reason)
  values(p_country_id,p_currency_id,auth.uid(),trim(p_reason)) returning id into v_id;
  perform public.currency_audit('request_national_currency_change','currency_change_request',v_id,null,
    jsonb_build_object('country_id',p_country_id,'requested_currency_id',p_currency_id,'reason',p_reason),p_reason);
  return v_id;
end;
$func$;

create or replace function public.admin_review_currency_change_request(
  p_request_id uuid,p_decision text,p_note text default null
) returns void language plpgsql security definer set search_path=public,auth as $func$
declare r public.currency_change_requests%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Somente o Super Admin pode revisar solicitações monetárias.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;
  select * into r from public.currency_change_requests where id=p_request_id for update;
  if not found or r.status<>'pending' then raise exception 'Solicitação inexistente ou já analisada.'; end if;
  if p_decision='approved' then
    perform public.admin_assign_country_currency(r.country_id,r.requested_currency_id,now(),coalesce(nullif(trim(p_note),''),r.reason));
  end if;
  update public.currency_change_requests set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now(),
    review_note=nullif(trim(p_note),'') where id=r.id;
  perform public.currency_audit('review_currency_change_request','currency_change_request',r.id,to_jsonb(r),
    jsonb_build_object('status',p_decision,'review_note',p_note),coalesce(nullif(trim(p_note),''),r.reason));
end;
$func$;

revoke all on function public.request_country_currency_change(uuid,uuid,text) from public,anon;
revoke all on function public.admin_review_currency_change_request(uuid,text,text) from public,anon;
grant execute on function public.request_country_currency_change(uuid,uuid,text) to authenticated;
grant execute on function public.admin_review_currency_change_request(uuid,text,text) to authenticated;

commit;
