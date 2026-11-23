-- WORLD ECONOMY: completar registro de jogador com o nickname Minecraft.
-- A função anterior register_player_v3 era chamada pelo frontend, mas não existia
-- nas migrações versionadas. Esta RPC delega a validação de país/presidência à
-- função register_player já existente e grava o nickname de forma atômica.

begin;

create or replace function public.register_player_v3(
  p_type text,
  p_country_id uuid,
  p_minecraft_username text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
  v_nickname text := nullif(trim(p_minecraft_username), '');
begin
  if v_uid is null then
    raise exception 'É necessário entrar na conta para concluir o cadastro.';
  end if;

  if v_nickname is null or char_length(v_nickname) < 3 or char_length(v_nickname) > 32 then
    raise exception 'O nickname do Minecraft deve ter entre 3 e 32 caracteres.';
  end if;

  if v_nickname !~ '^[A-Za-z0-9_]+$' then
    raise exception 'O nickname do Minecraft contém caracteres inválidos.';
  end if;

  if exists (
    select 1
    from public.profiles p
    where lower(p.minecraft_username) = lower(v_nickname)
      and p.id <> v_uid
  ) then
    raise exception 'Este nickname do Minecraft já está vinculado a outra conta.';
  end if;

  v_result := public.register_player(p_type, p_country_id);

  update public.profiles
     set minecraft_username = v_nickname
   where id = v_uid;

  if not found then
    raise exception 'Não foi possível localizar o perfil criado para concluir o cadastro.';
  end if;

  return v_result;
end;
$$;

revoke all on function public.register_player_v3(text, uuid, text) from public, anon;
grant execute on function public.register_player_v3(text, uuid, text) to authenticated;

commit;
