-- OI CONNECT: fotos de perfil privadas. Não apaga arquivos nem dados.
-- 1) O bucket deixa de servir links públicos; o app usa links assinados temporários.
update storage.buckets
   set public = false,
       file_size_limit = 2097152,
       allowed_mime_types = array['image/webp','image/jpeg','image/png']
 where id = 'avatars';

-- 2) Remove apenas a regra que deixava qualquer pessoa ler qualquer foto.
drop policy if exists "Fotos públicas" on storage.objects;

-- 3) Cada usuário autenticado lê, envia, troca e apaga só a própria pasta (<user_id>/...).
drop policy if exists "Ler a própria foto" on storage.objects;
create policy "Ler a própria foto" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "Apagar a própria foto" on storage.objects;
create policy "Apagar a própria foto" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
