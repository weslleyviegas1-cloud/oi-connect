-- Etapa 11 — leitura administrativa limitada ao país competente
begin;
drop policy if exists citizen_documents_read_own on public.citizen_documents;
create policy citizen_documents_read_own on public.citizen_documents for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or (country_id is not null and (public.is_country_president(country_id) or public.has_government_permission(country_id,'documents.read',null,null))));
drop policy if exists citizen_passports_read_own on public.citizen_passports;
create policy citizen_passports_read_own on public.citizen_passports for select to authenticated
using(profile_id=auth.uid() or public.is_world_admin() or (country_id is not null and (public.is_country_president(country_id) or public.has_government_permission(country_id,'documents.read',null,null))));
commit;