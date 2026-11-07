-- WORLD ECONOMY: perfis de jogadores e fotos
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 3 and 24),
  avatar_url text,
  created_at timestamptz not null default now()
);
grant select on public.profiles to anon;
grant select, insert, update on public.profiles to authenticated;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;
create policy "Perfis visíveis a todos" on public.profiles for select using (true);
create policy "Inserir o próprio perfil" on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy "Editar o próprio perfil" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'username',''), 'jogador_' || substr(new.id::text,1,8)));
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

insert into storage.buckets (id, name, public) values ('avatars','avatars',true) on conflict (id) do nothing;
create policy "Fotos públicas" on storage.objects for select using (bucket_id = 'avatars');
create policy "Enviar a própria foto" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Trocar a própria foto" on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
