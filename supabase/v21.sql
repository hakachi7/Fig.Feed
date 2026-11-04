-- Fig.Feed v21 — fotos no Cloudflare R2
-- As fotos (pasta "fotos") passam a ficar no Cloudflare R2 (10 GB grátis, tráfego grátis).
-- O envio e a exclusão passam pela Edge Function "fotos" (só ela tem as chaves do R2).
-- A tabela fotos_r2 guarda o que existe lá (nome, dono, tamanho), para o espaço e os limites.
-- A visão fotos_objs junta o que ainda está no Supabase com o que já está no R2,
-- e todas as funções que mediam o espaço passaram a usar a visão.

create table if not exists public.fotos_r2 (
  name text primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  size bigint not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists fotos_r2_owner on public.fotos_r2(owner_id);
alter table public.fotos_r2 enable row level security;
drop policy if exists "dono ou admin vê" on public.fotos_r2;
create policy "dono ou admin vê" on public.fotos_r2 for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_admin()));
-- gravar e apagar: só o servidor (service role)

create or replace view public.fotos_objs as
  select o.name, coalesce((o.metadata->>'size')::bigint, 0) as size, o.created_at, (storage.foldername(o.name))[1] as dono
    from storage.objects o
   where o.bucket_id = 'fotos' and not exists (select 1 from public.fotos_r2 r where r.name = o.name)
  union all
  select r.name, r.size, r.created_at, r.owner_id::text from public.fotos_r2 r;
revoke all on public.fotos_objs from public, anon, authenticated;

create or replace function public.admin_user_files(target uuid)
 returns setof text language sql stable security definer set search_path to 'public', 'storage'
as $$ select name from public.fotos_objs where dono = target::text $$;

create or replace function public.my_files()
 returns table(name text, size bigint, created_at timestamp with time zone)
 language sql stable security definer set search_path to 'public', 'storage'
as $$
  select f.name, f.size, f.created_at from public.fotos_objs f
   where f.dono = auth.uid()::text order by f.created_at desc;
$$;

create or replace function public.admin_stats()
 returns json language plpgsql stable security definer set search_path to 'public', 'auth', 'storage'
as $function$
declare r json;
begin
  if not public.is_admin() then raise exception 'Só administradores podem ver o painel'; end if;
  select json_build_object(
    'usuarios',        (select count(*) from auth.users),
    'confirmados',     (select count(*) from auth.users where email_confirmed_at is not null),
    'novos_7',         (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'novos_30',        (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'ativos_7',        (select count(*) from auth.users where last_sign_in_at > now() - interval '7 days'),
    'ativos_30',       (select count(*) from auth.users where last_sign_in_at > now() - interval '30 days'),
    'suspensos',       (select count(*) from auth.users where banned_until > now()),
    'planos',          (select coalesce(json_object_agg(pl, n), '{}'::json) from (
                          select case when plano in ('pro','agencia') and (plano_ate is null or plano_ate > now()) then plano else 'gratis' end pl, count(*) n
                          from public.profiles group by 1) x),
    'testes',          (select count(*) from public.profiles where plano in ('pro','agencia') and plano_ate > now()),
    'contas',          (select count(*) from public.accounts where deleted_at is null),
    'posts',           (select count(*) from public.posts where deleted_at is null),
    'posts_7',         (select count(*) from public.posts where created_at > now() - interval '7 days'),
    'stories',         (select count(*) from public.stories),
    'suporte_abertos', (select count(*) from public.support_tickets where status = 'aberto'),
    'ig_ok',           (select count(*) from public.ig_connections where status = 'ok'),
    'ig_atencao',      (select count(*) from public.ig_connections where status <> 'ok' or token_expires_at < now() + interval '10 days'),
    'espaco_fotos',    (select coalesce(sum(size), 0) from public.fotos_objs),
    'espaco_blog',     (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'blog'),
    'erros_7',         (select count(*) from public.app_errors where created_at > now() - interval '7 days'),
    'cadastros_dia',   (select json_agg(json_build_object('d', d::date, 'n', (select count(*) from auth.users u where u.created_at::date = d::date)) order by d)
                          from generate_series(current_date - 29, current_date, interval '1 day') d)
  ) into r;
  return r;
end $function$;

create or replace function public.admin_list_users()
 returns table(id uuid, email text, name text, handle text, role text, confirmed boolean, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, plano text, plano_ate timestamp with time zone, plano_origem text, suspenso boolean, espaco bigint, contas bigint, posts bigint)
 language plpgsql stable security definer set search_path to 'public', 'auth', 'storage'
as $function$
begin
  if not public.is_admin() then raise exception 'Só administradores podem ver a lista de usuários'; end if;
  return query
    select u.id, u.email::text, coalesce(p.name, ''), coalesce(p.handle, ''), coalesce(p.role, 'social_media'),
           u.email_confirmed_at is not null, u.created_at, u.last_sign_in_at,
           coalesce(p.plano, 'gratis'), p.plano_ate, coalesce(p.plano_origem, ''),
           coalesce(u.banned_until > now(), false),
           (select coalesce(sum(f.size), 0) from public.fotos_objs f where f.dono = u.id::text)::bigint,
           (select count(*) from public.accounts a where a.owner_id = u.id and a.deleted_at is null),
           (select count(*) from public.posts x where x.owner_id = u.id and x.deleted_at is null)
    from auth.users u left join public.profiles p on p.id = u.id
    order by case coalesce(p.role,'') when 'gm' then 0 when 'admin' then 1 when 'social_media' then 2 else 3 end, u.created_at;
end $function$;

create or replace function public.my_storage()
 returns json language sql stable security definer set search_path to 'public', 'storage'
as $function$
  with f as (select name, size sz from public.fotos_objs where dono = (select auth.uid())::text),
  lix as (select unnest(public._paths_de(
            (select coalesce(array_agg(id), '{}') from public.accounts where owner_id = (select auth.uid()) and deleted_at is not null),
            (select coalesce(array_agg(id), '{}') from public.posts where owner_id = (select auth.uid()) and deleted_at is not null))) p)
  select json_build_object(
    'usado', (select coalesce(sum(sz), 0) from f),
    'lixeira', (select coalesce(sum(sz), 0) from f where name in (select p from lix)),
    'limite_mb', public.limite_do_plano((select auth.uid()), 'mb'),
    'plano', public.plano_de((select auth.uid())),
    'ativos', coalesce((select (value->>'limites_ativos')::boolean from public.app_settings where key = 'planos'), false))
$function$;

create or replace function public.espaco_livre()
 returns boolean language plpgsql stable security definer set search_path to 'public', 'storage'
as $function$
declare lim integer; usado bigint;
begin
  lim := public.limite_do_plano((select auth.uid()), 'mb');
  if lim is null then return true; end if;
  select coalesce(sum(size), 0) into usado from public.fotos_objs where dono = (select auth.uid())::text;
  return usado < lim::bigint * 1048576;
end $function$;

create or replace function public.foto_existe(p_name text)
 returns boolean language sql stable security definer set search_path to 'public', 'storage'
as $$
  select exists (select 1 from public.fotos_objs where name = p_name and dono = (select auth.uid())::text)
$$;

-- usado pela Edge Function "fotos" antes de cada envio (só o servidor chama)
create or replace function public.fotos_pode_enviar(p_user uuid, p_name text)
 returns boolean language plpgsql stable security definer set search_path to 'public', 'storage'
as $function$
declare lim integer; usado bigint;
begin
  if exists (select 1 from public.fotos_objs where name = p_name and dono = p_user::text) then return true; end if; -- trocar uma foto que já existe
  lim := public.limite_do_plano(p_user, 'mb');
  if lim is null then return true; end if;
  select coalesce(sum(size), 0) into usado from public.fotos_objs where dono = p_user::text;
  return usado < lim::bigint * 1048576;
end $function$;
revoke execute on function public.fotos_pode_enviar(uuid, text) from public, anon, authenticated;

-- fotos que ainda estão só no Supabase (para a mudança para o R2; só o servidor chama)
create or replace function public.fotos_pendentes(n integer default 20)
 returns table(name text, size bigint)
 language sql stable security definer set search_path to 'public', 'storage'
as $$
  select o.name, coalesce((o.metadata->>'size')::bigint, 0) from storage.objects o
   where o.bucket_id = 'fotos' and o.name !~ '/\.emptyFolderPlaceholder$'
     and not exists (select 1 from public.fotos_r2 r where r.name = o.name)
   order by o.created_at limit n
$$;
-- fotos que já foram copiadas para o R2 e ainda estão no Supabase (para apagar de lá)
create or replace function public.fotos_copiadas(n integer default 100)
 returns setof text
 language sql stable security definer set search_path to 'public', 'storage'
as $$
  select o.name from storage.objects o
   where o.bucket_id = 'fotos' and exists (select 1 from public.fotos_r2 r where r.name = o.name)
   limit n
$$;
revoke execute on function public.fotos_pendentes(integer) from public, anon, authenticated;
revoke execute on function public.fotos_copiadas(integer) from public, anon, authenticated;

create or replace function public.admin_infra()
 returns json language plpgsql stable security definer set search_path to 'public', 'storage', 'auth'
as $function$
begin
  if not public.is_admin() then raise exception 'só administradores'; end if;
  return json_build_object(
    'db_bytes', pg_database_size(current_database()),
    'storage_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects),
    'storage_arquivos', (select count(*) from storage.objects),
    'r2_bytes', (select coalesce(sum(size), 0) from public.fotos_r2),
    'r2_arquivos', (select count(*) from public.fotos_r2),
    'fotos_bytes', (select coalesce(sum(size), 0) from public.fotos_objs),
    'fotos_grandes', (select count(*) from public.fotos_objs where size > 350000 and name !~ '/instagram/'),
    'fotos_grandes_bytes', (select coalesce(sum(size), 0) from public.fotos_objs where size > 350000 and name !~ '/instagram/'),
    'mau', (select count(*) from auth.users where last_sign_in_at >= date_trunc('month', now())),
    'ultimo_acesso', (select max(last_sign_in_at) from auth.users));
end $function$;
