-- Fig.Feed v18.1: plano Grátis com 3 contas e 15 MB, limites ligados e trava de espaço no servidor
insert into public.app_settings(key, value, updated_by, updated_at)
values ('planos', jsonb_build_object(
  'limites_ativos', true, 'sub', '',
  'planos', jsonb_build_array(
    jsonb_build_object('id','gratis','contas',3,'mb',15,'it',jsonb_build_array('Até 3 contas de clientes','Feed, carrossel e cronograma','15 MB de fotos (cerca de 50 posts)')),
    jsonb_build_object('id','pro','contas','','mb',10240),
    jsonb_build_object('id','agencia','contas','','mb',51200))),
  (select id from auth.users where email='gb20scc@gmail.com'), now())
on conflict (key) do update set value=excluded.value, updated_by=excluded.updated_by, updated_at=now();

-- Ainda há espaço no plano? (sem limite = sim)
create or replace function public.espaco_livre()
returns boolean language plpgsql stable security definer set search_path = public, storage as $$
declare lim integer; usado bigint;
begin
  lim := public.limite_do_plano((select auth.uid()), 'mb');
  if lim is null then return true; end if;
  select coalesce(sum((metadata->>'size')::bigint), 0) into usado from storage.objects
   where bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text;
  return usado < lim::bigint * 1048576;
end $$;
revoke execute on function public.espaco_livre() from public, anon;
grant execute on function public.espaco_livre() to authenticated;

-- Trocar uma foto que já existe (Otimizar fotos) sempre pode, mesmo com o espaço cheio
create or replace function public.foto_existe(p_name text)
returns boolean language sql stable security definer set search_path = storage as $$
  select exists (select 1 from storage.objects where bucket_id = 'fotos' and name = p_name
                  and (storage.foldername(p_name))[1] = (select auth.uid())::text)
$$;
revoke execute on function public.foto_existe(text) from public, anon;
grant execute on function public.foto_existe(text) to authenticated;

drop policy if exists "limite de espaço do plano" on storage.objects;
create policy "limite de espaço do plano" on storage.objects as restrictive for insert to authenticated
  with check (bucket_id <> 'fotos' or (select public.espaco_livre()) or public.foto_existe(name));

-- v18.2: uso do Supabase para a Visão geral do Admin (só admins)
create or replace function public.admin_infra()
returns json language plpgsql stable security definer set search_path = public, storage, auth as $$
begin
  if not public.is_admin() then raise exception 'só administradores'; end if;
  return json_build_object(
    'db_bytes', pg_database_size(current_database()),
    'storage_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects),
    'storage_arquivos', (select count(*) from storage.objects),
    'fotos_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'fotos'),
    'fotos_grandes', (select count(*) from storage.objects where bucket_id = 'fotos' and coalesce((metadata->>'size')::bigint, 0) > 350000),
    'fotos_grandes_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'fotos' and coalesce((metadata->>'size')::bigint, 0) > 350000),
    'mau', (select count(*) from auth.users where last_sign_in_at >= date_trunc('month', now())),
    'ultimo_acesso', (select max(last_sign_in_at) from auth.users));
end $$;
revoke execute on function public.admin_infra() from public, anon;
grant execute on function public.admin_infra() to authenticated;
