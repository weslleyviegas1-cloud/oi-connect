begin;

-- WORLD ECONOMY — ETAPA 5
-- Camada aditiva de cidadania. Reutiliza profiles.player_number, profiles e countries.
-- Nenhuma tabela de autenticação, usuário, país ou governo é recriada.

create extension if not exists pgcrypto;

create table if not exists public.citizen_profiles (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  birth_date_sim date,
  residence_city text,
  bio text,
  public_profile_enabled boolean not null default true,
  show_player_number boolean not null default false,
  show_residence_city boolean not null default false,
  show_bio boolean not null default false,
  citizen_status text not null default 'active'
    check (citizen_status in ('active','pending','inactive','suspended','under_review')),
  country_joined_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (residence_city is null or char_length(residence_city) <= 100),
  check (bio is null or char_length(bio) <= 500)
);

create table if not exists public.citizen_documents (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null check (document_type in ('national_identity','passport')),
  document_number text not null unique,
  issuing_country_id uuid references public.countries(id),
  issued_at timestamptz,
  expires_at timestamptz,
  status text not null default 'active'
    check (status in ('pending','active','expired','suspended','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, document_type)
);

create table if not exists public.citizen_passports (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  passport_number text not null unique,
  issuing_country_id uuid references public.countries(id),
  issued_at timestamptz,
  expires_at timestamptz,
  status text not null default 'not_issued'
    check (status in ('not_issued','pending','active','expired','suspended','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.nationality_change_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  from_country_id uuid references public.countries(id),
  to_country_id uuid not null references public.countries(id),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id),
  review_note text,
  constraint nationality_change_different_country check (from_country_id is distinct from to_country_id)
);

create unique index if not exists nationality_change_one_pending_per_profile_uidx
  on public.nationality_change_requests(profile_id) where status = 'pending';
create index if not exists nationality_change_status_requested_idx
  on public.nationality_change_requests(status, requested_at desc);
create index if not exists nationality_change_target_country_idx
  on public.nationality_change_requests(to_country_id, status);

create table if not exists public.citizen_nationality_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  from_country_id uuid references public.countries(id),
  to_country_id uuid references public.countries(id),
  changed_by uuid references public.profiles(id),
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.citizen_nickname_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  field_name text not null check (field_name in ('username','minecraft_username')),
  old_value text,
  new_value text,
  changed_at timestamptz not null default now()
);

create table if not exists public.citizen_history (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  description text not null,
  country_id uuid references public.countries(id),
  actor_id uuid references public.profiles(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.citizen_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  description text not null,
  object_type text,
  object_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists citizen_documents_profile_idx on public.citizen_documents(profile_id, created_at desc);
create index if not exists citizen_history_profile_created_idx on public.citizen_history(profile_id, created_at desc);
create index if not exists citizen_notifications_recipient_created_idx on public.citizen_notifications(recipient_id, created_at desc);
create index if not exists citizen_nickname_history_profile_idx on public.citizen_nickname_history(profile_id, changed_at desc);

-- O player_number já é a identidade permanente e única do WORLD ECONOMY.
-- Este gatilho impede que qualquer atualização posterior troque ou reutilize esse número.
create or replace function public.prevent_player_number_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.player_number is distinct from old.player_number then
    raise exception 'O ID permanente do jogador não pode ser alterado.';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_player_number_immutable on public.profiles;
create trigger profiles_player_number_immutable
before update of player_number on public.profiles
for each row execute function public.prevent_player_number_change();

-- Registra alterações de nickname sem alterar o ID permanente.
create or replace function public.capture_citizen_nickname_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.username is distinct from old.username then
    insert into public.citizen_nickname_history(profile_id,field_name,old_value,new_value)
    values (new.id,'username',old.username,new.username);
    insert into public.citizen_history(profile_id,event_type,title,description,actor_id)
    values (new.id,'nickname_changed','Nome de exibição atualizado',
      'O nome de exibição foi alterado de ' || coalesce(old.username,'(vazio)') || ' para ' || coalesce(new.username,'(vazio)') || '.',
      auth.uid());
  end if;
  if new.minecraft_username is distinct from old.minecraft_username then
    insert into public.citizen_nickname_history(profile_id,field_name,old_value,new_value)
    values (new.id,'minecraft_username',old.minecraft_username,new.minecraft_username);
    insert into public.citizen_history(profile_id,event_type,title,description,actor_id)
    values (new.id,'minecraft_nickname_changed','Nickname do Minecraft atualizado',
      'O nickname do Minecraft foi alterado de ' || coalesce(old.minecraft_username,'(vazio)') || ' para ' || coalesce(new.minecraft_username,'(vazio)') || '.',
      auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_capture_citizen_nickname on public.profiles;
create trigger profiles_capture_citizen_nickname
after update of username, minecraft_username on public.profiles
for each row execute function public.capture_citizen_nickname_change();

-- Inicializa as extensões dos perfis existentes sem substituir dados.
insert into public.citizen_profiles(profile_id,citizen_status,country_joined_at)
select p.id,
  case when coalesce(p.account_status,'active')='suspended' then 'suspended'
       when p.registration_status <> 'active' then 'pending' else 'active' end,
  case when p.country_id is not null then p.created_at else null end
from public.profiles p
on conflict (profile_id) do nothing;

insert into public.citizen_nationality_history(profile_id,from_country_id,to_country_id,changed_by,reason,created_at)
select p.id,null,p.country_id,null,'Vínculo nacional existente antes da Etapa 5.',p.created_at
from public.profiles p
where p.country_id is not null
  and not exists (
    select 1 from public.citizen_nationality_history h
    where h.profile_id=p.id and h.to_country_id=p.country_id
  );

insert into public.citizen_history(profile_id,event_type,title,description,country_id,created_at)
select p.id,'account_registered','Cadastro na plataforma','Conta registrada no WORLD ECONOMY.',p.country_id,p.created_at
from public.profiles p
where not exists (
  select 1 from public.citizen_history h
  where h.profile_id=p.id and h.event_type='account_registered'
);

-- Identidade Nacional digital: usa o número permanente já existente, sem criar novo ID de cidadão.
insert into public.citizen_documents(profile_id,document_type,document_number,issuing_country_id,issued_at,status)
select p.id,'national_identity','WE-ID-' || p.player_number::text,p.country_id,p.created_at,
  case when p.account_status='suspended' then 'suspended' else 'active' end
from public.profiles p
where p.player_number is not null
on conflict (profile_id,document_type) do nothing;

-- Registro do passaporte preparado, mas não emitido nesta etapa.
insert into public.citizen_passports(profile_id,passport_number,issuing_country_id,status)
select p.id,'WE-PASS-' || p.player_number::text,p.country_id,'not_issued'
from public.profiles p
where p.player_number is not null
on conflict (profile_id) do nothing;

-- Registra novos perfis criados pelo gatilho de autenticação já existente.
create or replace function public.initialize_citizen_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.citizen_profiles(profile_id,citizen_status,country_joined_at)
  values (new.id,case when new.registration_status='active' then 'active' else 'pending' end,
    case when new.country_id is not null then now() else null end)
  on conflict (profile_id) do nothing;

  if new.player_number is not null then
    insert into public.citizen_documents(profile_id,document_type,document_number,issuing_country_id,issued_at,status)
    values (new.id,'national_identity','WE-ID-' || new.player_number::text,new.country_id,now(),'active')
    on conflict (profile_id,document_type) do nothing;

    insert into public.citizen_passports(profile_id,passport_number,issuing_country_id,status)
    values (new.id,'WE-PASS-' || new.player_number::text,new.country_id,'not_issued')
    on conflict (profile_id) do nothing;
  end if;

  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
  values (new.id,'account_registered','Cadastro na plataforma','Conta registrada no WORLD ECONOMY.',new.country_id,new.id);
  return new;
end;
$$;

drop trigger if exists profiles_initialize_citizen_record on public.profiles;
create trigger profiles_initialize_citizen_record
after insert on public.profiles
for each row execute function public.initialize_citizen_record();

-- Atualiza a nacionalidade e o histórico quando um fluxo autorizado altera country_id.
create or replace function public.capture_citizen_country_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.country_id is distinct from old.country_id then
    insert into public.citizen_nationality_history(profile_id,from_country_id,to_country_id,changed_by,reason)
    values (new.id,old.country_id,new.country_id,auth.uid(),'Alteração de vínculo nacional autorizada.');
    update public.citizen_profiles
      set country_joined_at=case when new.country_id is null then null else now() end,
          updated_at=now()
      where profile_id=new.id;
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
    values (new.id,'nationality_changed','Vínculo nacional atualizado',
      'O vínculo nacional foi alterado por procedimento autorizado.',new.country_id,auth.uid());
    insert into public.citizen_notifications(recipient_id,event_type,title,description)
    values (new.id,'nationality_changed','Nacionalidade atualizada',
      'Seu vínculo nacional foi alterado por uma decisão administrativa.');
  end if;
  if new.role is distinct from old.role then
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id)
    values (new.id,
      case when new.role='president' then 'government_appointment' else 'role_changed' end,
      case when new.role='president' then 'Nomeação para presidência' else 'Cargo atualizado' end,
      'Seu cargo na plataforma foi atualizado para ' || new.role || '.',new.country_id,auth.uid());
  end if;
  if new.account_status is distinct from old.account_status then
    update public.citizen_profiles set citizen_status=case when new.account_status='suspended' then 'suspended' when citizen_status='suspended' then 'active' else citizen_status end, updated_at=now() where profile_id=new.id;
    update public.citizen_documents set status=case when new.account_status='suspended' then 'suspended' else 'active' end, updated_at=now() where profile_id=new.id and document_type='national_identity';
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
    values (new.id,'account_status_changed','Situação da conta alterada',
      'A situação global da conta foi atualizada.',new.country_id,auth.uid(),
      jsonb_build_object('old_status',old.account_status,'new_status',new.account_status));
    insert into public.citizen_notifications(recipient_id,event_type,title,description)
    values (new.id,'account_status_changed','Situação da conta atualizada',
      'A administração atualizou a situação da sua conta.');
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_capture_citizen_country_change on public.profiles;
create trigger profiles_capture_citizen_country_change
after update of country_id,role,account_status on public.profiles
for each row execute function public.capture_citizen_country_change();

-- Atualiza o perfil complementar sem permitir que o cidadão altere campos administrativos.
create or replace function public.update_my_citizen_profile(
  p_birth_date_sim date default null,
  p_residence_city text default null,
  p_bio text default null,
  p_public_profile_enabled boolean default true,
  p_show_player_number boolean default false,
  p_show_residence_city boolean default false,
  p_show_bio boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  if p_birth_date_sim is not null and p_birth_date_sim > current_date then
    raise exception 'A data fictícia de nascimento não pode estar no futuro.';
  end if;
  if char_length(coalesce(p_residence_city,'')) > 100 then raise exception 'Cidade excede 100 caracteres.'; end if;
  if char_length(coalesce(p_bio,'')) > 500 then raise exception 'Descrição excede 500 caracteres.'; end if;

  insert into public.citizen_profiles(profile_id)
  values (auth.uid()) on conflict (profile_id) do nothing;

  update public.citizen_profiles
  set birth_date_sim=p_birth_date_sim,
      residence_city=nullif(trim(p_residence_city),''),
      bio=nullif(trim(p_bio),''),
      public_profile_enabled=coalesce(p_public_profile_enabled,true),
      show_player_number=coalesce(p_show_player_number,false),
      show_residence_city=coalesce(p_show_residence_city,false),
      show_bio=coalesce(p_show_bio,false),
      updated_at=now()
  where profile_id=auth.uid();

  insert into public.citizen_history(profile_id,event_type,title,description,actor_id)
  values (auth.uid(),'profile_updated','Perfil atualizado','O cidadão atualizou as informações opcionais do perfil.',auth.uid());
end;
$$;


create or replace function public.update_my_minecraft_nickname(p_nickname text)
returns void
language plpgsql
security definer
set search_path = public
as $
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  if length(trim(coalesce(p_nickname,''))) < 3 or length(trim(p_nickname)) > 32 then
    raise exception 'O nickname deve ter entre 3 e 32 caracteres.';
  end if;
  update public.profiles
    set minecraft_username=trim(p_nickname)
    where id=auth.uid();
  if not found then raise exception 'Perfil não encontrado.'; end if;
end;
$;

create or replace function public.get_my_citizen_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  select jsonb_build_object(
    'id',p.id,
    'player_number',p.player_number,
    'username',p.username,
    'minecraft_username',p.minecraft_username,
    'avatar_url',p.avatar_url,
    'role',p.role,
    'registration_status',p.registration_status,
    'account_status',p.account_status,
    'created_at',p.created_at,
    'country_id',p.country_id,
    'country_name',c.name,
    'country_flag',c.flag,
    'country_capital',c.capital,
    'country_continent',c.continent,
    'president_username',pres.username,
    'birth_date_sim',cp.birth_date_sim,
    'residence_city',cp.residence_city,
    'bio',cp.bio,
    'public_profile_enabled',cp.public_profile_enabled,
    'show_player_number',cp.show_player_number,
    'show_residence_city',cp.show_residence_city,
    'show_bio',cp.show_bio,
    'citizen_status',cp.citizen_status,
    'country_joined_at',cp.country_joined_at
  ) into v_result
  from public.profiles p
  left join public.countries c on c.id=p.country_id
  left join public.profiles pres on pres.country_id=p.country_id and pres.role='president'
  left join public.citizen_profiles cp on cp.profile_id=p.id
  where p.id=auth.uid();

  if v_result is null then raise exception 'Perfil de cidadão não encontrado.'; end if;
  return v_result;
end;
$$;

create or replace function public.get_public_citizen_profile(p_profile_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'username',p.username,
    'minecraft_username',p.minecraft_username,
    'avatar_url',p.avatar_url,
    'role',p.role,
    'player_number',case when cp.show_player_number then p.player_number else null end,
    'country_name',c.name,
    'country_flag',c.flag,
    'residence_city',case when cp.show_residence_city then cp.residence_city else null end,
    'bio',case when cp.show_bio then cp.bio else null end,
    'public_profile_enabled',cp.public_profile_enabled
  ) into v_result
  from public.profiles p
  left join public.countries c on c.id=p.country_id
  left join public.citizen_profiles cp on cp.profile_id=p.id
  where p.id=p_profile_id
    and coalesce(p.account_status,'active')='active'
    and coalesce(cp.public_profile_enabled,true)=true;

  return v_result;
end;
$$;

create or replace function public.request_nationality_change(p_country_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_profile public.profiles%rowtype; v_country public.countries%rowtype; v_request uuid;
begin
  if auth.uid() is null then raise exception 'É necessário entrar na conta.'; end if;
  select * into v_profile from public.profiles where id=auth.uid() for update;
  if not found then raise exception 'Perfil não encontrado.'; end if;
  if coalesce(v_profile.account_status,'active') <> 'active' then raise exception 'Conta sem permissão para solicitar mudança.'; end if;
  if v_profile.country_id is null then raise exception 'Sua conta ainda não possui nacionalidade definida.'; end if;
  if v_profile.country_id=p_country_id then raise exception 'Você já possui vínculo com este país.'; end if;

  select * into v_country from public.countries
  where id=p_country_id and is_active=true and citizens_available=true for update;
  if not found then raise exception 'Este país não está aceitando novos cidadãos.'; end if;

  if exists (select 1 from public.nationality_change_requests where profile_id=auth.uid() and status='pending') then
    raise exception 'Você já possui uma solicitação de nacionalidade pendente.';
  end if;

  insert into public.nationality_change_requests(profile_id,from_country_id,to_country_id)
  values (auth.uid(),v_profile.country_id,p_country_id) returning id into v_request;

  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
  values (auth.uid(),'nationality_requested','Mudança de nacionalidade solicitada',
    'Você solicitou mudança para ' || v_country.name || '.',v_profile.country_id,auth.uid(),
    jsonb_build_object('request_id',v_request,'target_country_id',p_country_id));

  insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values (auth.uid(),'nationality_requested','Solicitação recebida',
    'Sua solicitação de mudança de nacionalidade foi registrada e aguarda análise.','nationality_change_request',v_request);

  insert into public.admin_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values (null,'nationality_change_requested','Nova solicitação de nacionalidade',
    v_profile.username || ' solicitou vínculo com ' || v_country.name || '.','nationality_change_request',v_request);

  return v_request;
end;
$$;

create or replace function public.admin_review_nationality_change(
  p_request_id uuid,
  p_decision text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_request public.nationality_change_requests%rowtype;
  v_target public.countries%rowtype;
  v_profile public.profiles%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode revisar solicitações.'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Decisão inválida.'; end if;

  select * into v_request from public.nationality_change_requests
  where id=p_request_id and status='pending' for update;
  if not found then raise exception 'Solicitação não encontrada ou já revisada.'; end if;

  select * into v_profile from public.profiles where id=v_request.profile_id for update;
  select * into v_target from public.countries where id=v_request.to_country_id for update;

  if p_decision='approved' then
    if not found or not v_target.is_active or not v_target.citizens_available then
      raise exception 'O país de destino não está mais aceitando cidadãos.';
    end if;
    if v_profile.role='president' then
      raise exception 'Encerre a presidência antes de aprovar a mudança de nacionalidade.';
    end if;
    if exists (select 1 from public.government_members gm where gm.profile_id=v_profile.id and gm.status='active') then
      raise exception 'O cidadão possui vínculo governamental ativo. Resolva esse vínculo antes da mudança.';
    end if;
    update public.profiles set country_id=v_target.id where id=v_profile.id;
    update public.citizen_documents set issuing_country_id=v_target.id,updated_at=now()
      where profile_id=v_profile.id and document_type='national_identity' and status='active';
    update public.citizen_passports set issuing_country_id=v_target.id,updated_at=now()
      where profile_id=v_profile.id and status='not_issued';
  end if;

  update public.nationality_change_requests
  set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),review_note=nullif(trim(p_note),'')
  where id=v_request.id;

  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
  values (v_profile.id,'nationality_request_reviewed',
    case when p_decision='approved' then 'Mudança de nacionalidade aprovada' else 'Mudança de nacionalidade rejeitada' end,
    coalesce(nullif(trim(p_note),''),case when p_decision='approved' then 'Sua solicitação foi aprovada.' else 'Sua solicitação foi rejeitada.' end),
    case when p_decision='approved' then v_target.id else v_profile.country_id end,auth.uid(),
    jsonb_build_object('request_id',v_request.id,'decision',p_decision));

  insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values (v_profile.id,'nationality_request_' || p_decision,
    case when p_decision='approved' then 'Mudança aprovada' else 'Mudança rejeitada' end,
    coalesce(nullif(trim(p_note),''),case when p_decision='approved' then 'Sua nacionalidade foi atualizada.' else 'Sua solicitação foi rejeitada.' end),
    'nationality_change_request',v_request.id);

  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
  values (auth.uid(),'review','nationality_change_request',v_request.id::text,
    'Solicitação de nacionalidade ' || p_decision || '.',
    jsonb_build_object('country_id',v_request.from_country_id),
    jsonb_build_object('country_id',case when p_decision='approved' then v_target.id else v_profile.country_id end,'note',p_note));

  return jsonb_build_object('status',p_decision,'request_id',v_request.id);
end;
$$;

create or replace function public.admin_set_citizen_status(
  p_profile_id uuid,
  p_status text,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_old text;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode alterar a situação global do cidadão.'; end if;
  if p_status not in ('active','pending','inactive','suspended','under_review') then raise exception 'Situação inválida.'; end if;
  if p_profile_id=auth.uid() then raise exception 'Não é permitido alterar a própria situação administrativa.'; end if;

  select citizen_status into v_old from public.citizen_profiles where profile_id=p_profile_id for update;
  if not found then raise exception 'Perfil de cidadão não encontrado.'; end if;

  update public.citizen_profiles set citizen_status=p_status,updated_at=now() where profile_id=p_profile_id;
  update public.profiles set account_status=case when p_status='suspended' then 'suspended' else 'active' end,
    suspended_at=case when p_status='suspended' then now() else null end,
    suspension_note=case when p_status='suspended' then nullif(trim(p_note),'') else null end
  where id=p_profile_id;

  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
  select p_profile_id,'citizen_status_changed','Situação do cidadão alterada',
    coalesce(nullif(trim(p_note),''),'A situação do cidadão foi atualizada pelo Super Admin.'),
    p.country_id,auth.uid(),jsonb_build_object('old_status',v_old,'new_status',p_status)
  from public.profiles p where p.id=p_profile_id;

  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,old_values,new_values)
  values (auth.uid(),'update','citizen_status',p_profile_id::text,'Situação do cidadão alterada.',
    jsonb_build_object('status',v_old),jsonb_build_object('status',p_status,'note',p_note));
end;
$$;


create or replace function public.admin_update_citizen_passport(
  p_profile_id uuid,
  p_status text,
  p_validity_days integer default 365
)
returns void
language plpgsql
security definer
set search_path = public
as $
declare v_profile public.profiles%rowtype; v_passport public.citizen_passports%rowtype;
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode administrar passaportes.'; end if;
  if p_status not in ('pending','active','expired','suspended','cancelled') then raise exception 'Situação de passaporte inválida.'; end if;
  if p_validity_days is null or p_validity_days < 1 or p_validity_days > 3650 then
    raise exception 'A validade deve estar entre 1 e 3650 dias.';
  end if;
  select * into v_profile from public.profiles where id=p_profile_id for update;
  if not found then raise exception 'Cidadão não encontrado.'; end if;
  select * into v_passport from public.citizen_passports where profile_id=p_profile_id for update;
  if not found then raise exception 'Registro inicial de passaporte não encontrado.'; end if;

  update public.citizen_passports
  set status=p_status,
      issuing_country_id=v_profile.country_id,
      issued_at=case when p_status='active' then coalesce(issued_at,now()) else issued_at end,
      expires_at=case when p_status='active' then now() + make_interval(days=>p_validity_days) else expires_at end,
      updated_at=now()
  where profile_id=p_profile_id;

  if p_status in ('active','expired','suspended','cancelled') then
    insert into public.citizen_documents(profile_id,document_type,document_number,issuing_country_id,issued_at,expires_at,status)
    values (p_profile_id,'passport',v_passport.passport_number,v_profile.country_id,now(),
      case when p_status='active' then now() + make_interval(days=>p_validity_days) else null end,p_status)
    on conflict (profile_id,document_type) do update
      set issuing_country_id=excluded.issuing_country_id,
          issued_at=coalesce(public.citizen_documents.issued_at,excluded.issued_at),
          expires_at=excluded.expires_at,status=excluded.status,updated_at=now();
  end if;

  insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
  values (p_profile_id,'passport_status_changed','Passaporte atualizado',
    'A situação do passaporte foi atualizada para ' || p_status || '.',v_profile.country_id,auth.uid(),
    jsonb_build_object('status',p_status,'validity_days',p_validity_days));
  insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
  values (p_profile_id,'passport_status_changed','Passaporte atualizado',
    'A situação do seu passaporte foi atualizada para ' || p_status || '.','citizen_passport',v_passport.id);
  insert into public.admin_audit_logs(actor_id,operation,object_type,object_id,description,new_values)
  values (auth.uid(),'update','citizen_passport',v_passport.id::text,'Situação do passaporte atualizada.',
    jsonb_build_object('status',p_status,'validity_days',p_validity_days));
end;
$;

create or replace function public.admin_list_nationality_change_requests()
returns table (
  id uuid,
  profile_id uuid,
  username text,
  minecraft_username text,
  player_number bigint,
  from_country_id uuid,
  from_country_name text,
  to_country_id uuid,
  to_country_name text,
  requested_at timestamptz,
  status text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_world_admin() then raise exception 'Apenas o Super Admin pode consultar solicitações.'; end if;
  return query
  select r.id,r.profile_id,p.username,p.minecraft_username,p.player_number,
    r.from_country_id,fc.name,r.to_country_id,tc.name,r.requested_at,r.status
  from public.nationality_change_requests r
  join public.profiles p on p.id=r.profile_id
  left join public.countries fc on fc.id=r.from_country_id
  join public.countries tc on tc.id=r.to_country_id
  where r.status='pending'
  order by r.requested_at asc;
end;
$$;

create or replace function public.get_country_citizens(p_country_id uuid,p_search text default null)
returns table (
  profile_id uuid,
  username text,
  minecraft_username text,
  player_number bigint,
  avatar_url text,
  role text,
  citizen_status text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (
    public.is_world_admin()
    or public.is_country_president(p_country_id)
    or public.has_government_permission(p_country_id,'citizen.read',null,null)
  ) then
    raise exception 'Sem permissão para consultar os cidadãos deste país.';
  end if;
  return query
  select p.id,p.username,p.minecraft_username,
    case when coalesce(cp.show_player_number,false) then p.player_number else null end,
    p.avatar_url,p.role,coalesce(cp.citizen_status,'active'),cp.country_joined_at
  from public.profiles p
  left join public.citizen_profiles cp on cp.profile_id=p.id
  where p.country_id=p_country_id
    and p.registration_status='active'
    and coalesce(p.account_status,'active')='active'
    and (coalesce(p_search,'')='' or p.username ilike '%'||p_search||'%'
      or coalesce(p.minecraft_username,'') ilike '%'||p_search||'%'
      or p.player_number::text=coalesce(p_search,''))
  order by p.username;
end;
$$;


-- Eventos de nomeação/exoneração e comunicados publicados chegam ao histórico/notificações pessoais.
create or replace function public.capture_citizen_government_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $
begin
  if tg_op='INSERT' and new.status='active' then
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
    values (new.profile_id,'government_appointment','Nomeação governamental',
      'Você foi nomeado(a) para o cargo de ' || new.position || '.',new.country_id,new.appointed_by,
      jsonb_build_object('membership_id',new.id,'position',new.position));
    insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values (new.profile_id,'government_appointment','Nomeação governamental',
      'Você foi nomeado(a) para o cargo de ' || new.position || '.','government_member',new.id);
  elsif tg_op='UPDATE' and new.status is distinct from old.status and new.status in ('inactive','exonerated') then
    insert into public.citizen_history(profile_id,event_type,title,description,country_id,actor_id,metadata)
    values (new.profile_id,'government_exoneration','Vínculo governamental encerrado',
      'Seu vínculo no cargo de ' || new.position || ' foi encerrado.',new.country_id,auth.uid(),
      jsonb_build_object('membership_id',new.id,'position',new.position,'status',new.status));
    insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
    values (new.profile_id,'government_exoneration','Vínculo governamental encerrado',
      'Seu vínculo no cargo de ' || new.position || ' foi encerrado.','government_member',new.id);
  end if;
  return new;
end;
$;

drop trigger if exists government_members_citizen_events on public.government_members;
create trigger government_members_citizen_events
after insert or update of status on public.government_members
for each row execute function public.capture_citizen_government_membership();

create or replace function public.notify_citizens_of_published_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $
begin
  if new.status='published' and (tg_op='INSERT' or old.status is distinct from 'published') then
    insert into public.citizen_notifications(recipient_id,event_type,title,description,object_type,object_id)
    select p.id,'country_announcement','Comunicado do país: ' || new.title,
      left(new.content,500),'government_announcement',new.id
    from public.profiles p
    where p.country_id=new.country_id
      and p.registration_status='active'
      and coalesce(p.account_status,'active')='active';
  end if;
  return new;
end;
$;

drop trigger if exists government_announcements_citizen_notifications on public.government_announcements;
create trigger government_announcements_citizen_notifications
after insert or update of status on public.government_announcements
for each row execute function public.notify_citizens_of_published_announcement();

-- RLS: documentos e informações privadas só podem ser consultados pelo titular ou Super Admin.
alter table public.citizen_profiles enable row level security;
alter table public.citizen_documents enable row level security;
alter table public.citizen_passports enable row level security;
alter table public.nationality_change_requests enable row level security;
alter table public.citizen_nationality_history enable row level security;
alter table public.citizen_nickname_history enable row level security;
alter table public.citizen_history enable row level security;
alter table public.citizen_notifications enable row level security;

revoke all on public.citizen_profiles,public.citizen_documents,public.citizen_passports,
  public.nationality_change_requests,public.citizen_nationality_history,public.citizen_nickname_history,
  public.citizen_history,public.citizen_notifications from public,anon,authenticated;

grant select on public.citizen_profiles,public.citizen_documents,public.citizen_passports,
  public.nationality_change_requests,public.citizen_nationality_history,public.citizen_nickname_history,
  public.citizen_history,public.citizen_notifications to authenticated;
grant update(is_read) on public.citizen_notifications to authenticated;

drop policy if exists citizen_profiles_self_or_admin_read on public.citizen_profiles;
create policy citizen_profiles_self_or_admin_read on public.citizen_profiles
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists citizen_documents_self_or_admin_read on public.citizen_documents;
create policy citizen_documents_self_or_admin_read on public.citizen_documents
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists citizen_passports_self_or_admin_read on public.citizen_passports;
create policy citizen_passports_self_or_admin_read on public.citizen_passports
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists nationality_requests_self_or_admin_read on public.nationality_change_requests;
create policy nationality_requests_self_or_admin_read on public.nationality_change_requests
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists nationality_history_self_or_admin_read on public.citizen_nationality_history;
create policy nationality_history_self_or_admin_read on public.citizen_nationality_history
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists nickname_history_self_or_admin_read on public.citizen_nickname_history;
create policy nickname_history_self_or_admin_read on public.citizen_nickname_history
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists citizen_history_self_or_admin_read on public.citizen_history;
create policy citizen_history_self_or_admin_read on public.citizen_history
for select to authenticated using (profile_id=auth.uid() or public.is_world_admin());

drop policy if exists citizen_notifications_self_read on public.citizen_notifications;
create policy citizen_notifications_self_read on public.citizen_notifications
for select to authenticated using (recipient_id=auth.uid());
drop policy if exists citizen_notifications_self_mark_read on public.citizen_notifications;
create policy citizen_notifications_self_mark_read on public.citizen_notifications
for update to authenticated using (recipient_id=auth.uid()) with check (recipient_id=auth.uid());

-- Nenhuma escrita direta em documentos, histórico, solicitações ou perfis complementares.
-- Todas as operações passam pelas funções SECURITY DEFINER acima.
revoke all on function public.prevent_player_number_change() from public,anon,authenticated;
revoke all on function public.capture_citizen_nickname_change() from public,anon,authenticated;
revoke all on function public.initialize_citizen_record() from public,anon,authenticated;
revoke all on function public.capture_citizen_country_change() from public,anon,authenticated;
revoke all on function public.capture_citizen_government_membership() from public,anon,authenticated;
revoke all on function public.notify_citizens_of_published_announcement() from public,anon,authenticated;
revoke all on function public.update_my_citizen_profile(date,text,text,boolean,boolean,boolean,boolean) from public,anon;
revoke all on function public.update_my_minecraft_nickname(text) from public,anon;
revoke all on function public.get_my_citizen_profile() from public,anon;
revoke all on function public.get_public_citizen_profile(uuid) from public,anon;
revoke all on function public.request_nationality_change(uuid) from public,anon;
revoke all on function public.admin_review_nationality_change(uuid,text,text) from public,anon;
revoke all on function public.admin_set_citizen_status(uuid,text,text) from public,anon;
revoke all on function public.admin_update_citizen_passport(uuid,text,integer) from public,anon;
revoke all on function public.admin_list_nationality_change_requests() from public,anon;
revoke all on function public.get_country_citizens(uuid,text) from public,anon;

grant execute on function public.update_my_citizen_profile(date,text,text,boolean,boolean,boolean,boolean) to authenticated;
grant execute on function public.update_my_minecraft_nickname(text) to authenticated;
grant execute on function public.get_my_citizen_profile() to authenticated;
grant execute on function public.get_public_citizen_profile(uuid) to authenticated;
grant execute on function public.request_nationality_change(uuid) to authenticated;
grant execute on function public.admin_review_nationality_change(uuid,text,text) to authenticated;
grant execute on function public.admin_set_citizen_status(uuid,text,text) to authenticated;
grant execute on function public.admin_update_citizen_passport(uuid,text,integer) to authenticated;
grant execute on function public.admin_list_nationality_change_requests() to authenticated;
grant execute on function public.get_country_citizens(uuid,text) to authenticated;

commit;
