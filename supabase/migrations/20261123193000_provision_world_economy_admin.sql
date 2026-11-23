-- WORLD ECONOMY — provisionar Super Admin por identidade autenticada.
-- Não define nem altera senha. O usuário precisa existir e ter e-mail confirmado.
begin;

update public.profiles p
set role = 'super_admin',
    registration_status = 'active',
    country_id = null
from auth.users u
where u.id = p.id
  and lower(u.email) = lower('weslleyviegas1@gmail.com')
  and u.email_confirmed_at is not null;

commit;
