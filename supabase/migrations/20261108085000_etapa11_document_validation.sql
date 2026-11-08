-- Etapa 11 — validação interna e auditada de documentos digitais
begin;
create or replace function public.validate_world_document(p_identification_code text)
returns jsonb language plpgsql security definer set search_path=public,auth as $function$
declare d public.citizen_documents%rowtype; p public.profiles%rowtype; v_valid boolean;
begin
  if auth.uid() is null then raise exception 'Autenticação necessária.'; end if;
  if nullif(trim(p_identification_code),'') is null then raise exception 'Informe o código de identificação.'; end if;
  select * into d from public.citizen_documents where upper(identification_code)=upper(trim(p_identification_code));
  if not found then return jsonb_build_object('valid',false,'status','not_found','message','Documento não localizado.'); end if;
  if not (d.profile_id=auth.uid() or public.is_world_admin() or public.is_country_president(d.country_id) or public.has_government_permission(d.country_id,'documents.read',null,null) or public.has_government_permission(d.country_id,'immigration.review',null,null)) then
    raise exception 'Sem autorização para consultar os dados deste documento.';
  end if;
  select * into p from public.profiles where id=d.profile_id;
  v_valid:=d.status='active' and (d.expires_at is null or d.expires_at>now());
  insert into public.document_audit_logs(actor_id,profile_id,country_id,object_type,object_id,action,reason,new_values)
  values(auth.uid(),d.profile_id,d.country_id,'digital_document',d.id,'validated','Consulta de validação documental.',jsonb_build_object('valid',v_valid,'status',d.status));
  return jsonb_build_object('valid',v_valid,'status',d.status,'document_type',d.document_type,'document_number',d.document_number,'identification_code',d.identification_code,'holder',p.username,'permanent_id',p.player_number,'country_id',d.country_id,'issued_at',d.issued_at,'expires_at',d.expires_at,'fictional',coalesce((d.metadata->>'fictional')::boolean,true));
end;$function$;
revoke all on function public.validate_world_document(text) from public,anon;
grant execute on function public.validate_world_document(text) to authenticated;
commit;