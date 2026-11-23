-- WORLD ECONOMY — promover a conta administrativa de forma persistente.
-- Funciona se a conta já existir ou se for criada/confirmada depois da migração.
begin;

create or replace function public.promote_world_economy_admin_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if lower(coalesce(new.email, '')) = lower('weslleyviegas1@gmail.com')
     and new.email_confirmed_at is not null then
    update public.profiles
       set role = 'super_admin',
           registration_status = 'active',
           country_id = null
     where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists promote_world_economy_admin_from_auth on auth.users;
create trigger promote_world_economy_admin_from_auth
after insert or update of email, email_confirmed_at on auth.users
for each row execute function public.promote_world_economy_admin_from_auth();

create or replace function public.promote_world_economy_admin_from_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if exists (
    select 1 from auth.users u
     where u.id = new.id
       and lower(coalesce(u.email, '')) = lower('weslleyviegas1@gmail.com')
       and u.email_confirmed_at is not null
  ) then
    update public.profiles
       set role = 'super_admin',
           registration_status = 'active',
           country_id = null
     where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists promote_world_economy_admin_from_profile on public.profiles;
create trigger promote_world_economy_admin_from_profile
after insert on public.profiles
for each row execute function public.promote_world_economy_admin_from_profile();

revoke all on function public.promote_world_economy_admin_from_auth() from public, anon, authenticated;
revoke all on function public.promote_world_economy_admin_from_profile() from public, anon, authenticated;

-- Também promove a conta se o perfil já existir e o e-mail já estiver confirmado.
update public.profiles p
   set role = 'super_admin',
       registration_status = 'active',
       country_id = null
  from auth.users u
 where u.id = p.id
   and lower(coalesce(u.email, '')) = lower('weslleyviegas1@gmail.com')
   and u.email_confirmed_at is not null;

commit;
