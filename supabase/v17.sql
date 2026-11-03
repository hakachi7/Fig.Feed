-- Fig.Feed v17 — Admin completo 2: painel de números, planos editáveis com limites, ações sobre usuários,
-- textos e configurações do site, avisos (sininho), registro de erros e Instagram para vencer.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v17_admin). Só acrescenta.
-- Depende de admin.sql (is_admin, is_gm, activity_log), v6.sql (app_settings), v10.sql (planos), v14.sql (Instagram), v16.sql.

-- ===================== Ajustes do site que os admins podem salvar =====================
-- menus, textos (landing, ajuda, termos, privacidade) e config (contato, redes, título).
-- 'planos' e 'manutencao' continuam só com o GM (política "gm altera ajustes").
drop policy if exists "admins editam menus" on public.app_settings;
drop policy if exists "admins atualizam menus" on public.app_settings;
create policy "admins criam ajustes do site" on public.app_settings for insert to authenticated
  with check (key in ('menus','textos','config') and (select public.is_admin()));
create policy "admins atualizam ajustes do site" on public.app_settings for update to authenticated
  using (key in ('menus','textos','config') and (select public.is_admin()))
  with check (key in ('menus','textos','config') and (select public.is_admin()));

-- ===================== 8) Erros que as pessoas encontraram =====================
create table if not exists public.app_errors (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id    uuid default auth.uid() references auth.users (id) on delete set null,
  codigo     text not null default '' check (char_length(codigo) <= 20),
  mensagem   text not null default '' check (char_length(mensagem) <= 500),
  rota       text not null default '' check (char_length(rota) <= 200),
  navegador  text not null default '' check (char_length(navegador) <= 200),
  versao     text not null default '' check (char_length(versao) <= 20)
);
create index if not exists app_errors_created_idx on public.app_errors (created_at desc);
create index if not exists app_errors_user_idx on public.app_errors (user_id);
alter table public.app_errors enable row level security;
create policy "qualquer um registra erro" on public.app_errors for insert to anon, authenticated
  with check (user_id is null or user_id = (select auth.uid()));
create policy "admins veem erros" on public.app_errors for select to authenticated using ((select public.is_admin()));
create policy "admins limpam erros" on public.app_errors for delete to authenticated using ((select public.is_admin()));

-- ===================== 1) Painel de números =====================
create or replace function public.admin_stats()
returns json language plpgsql stable security definer set search_path = public, auth, storage as $$
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
    'espaco_fotos',    (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'fotos'),
    'espaco_blog',     (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'blog'),
    'erros_7',         (select count(*) from public.app_errors where created_at > now() - interval '7 days'),
    'cadastros_dia',   (select json_agg(json_build_object('d', d::date, 'n', (select count(*) from auth.users u where u.created_at::date = d::date)) order by d)
                          from generate_series(current_date - 29, current_date, interval '1 day') d)
  ) into r;
  return r;
end $$;
revoke execute on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

-- ===================== 2) Planos: limites (só valem com a chave ligada) =====================
-- app_settings 'planos' = {"limites_ativos": bool, "planos": [{id, n, p, u, it[], b, top, contas, mb}]}
create or replace function public.plano_de(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when plano in ('pro','agencia') and (plano_ate is null or plano_ate > now()) then plano else 'gratis' end
  from public.profiles where id = uid
$$;
revoke execute on function public.plano_de(uuid) from public, anon;
grant execute on function public.plano_de(uuid) to authenticated;

create or replace function public.limite_do_plano(uid uuid, campo text)
returns integer language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb; lim integer;
begin
  select value into cfg from public.app_settings where key = 'planos';
  if cfg is null or not coalesce((cfg->>'limites_ativos')::boolean, false) then return null; end if;
  if (select role from public.profiles where id = uid) in ('gm','admin') then return null; end if;
  select nullif(x->>campo, '')::integer into lim from jsonb_array_elements(cfg->'planos') x where x->>'id' = public.plano_de(uid);
  return lim;
end $$;
revoke execute on function public.limite_do_plano(uuid, text) from public, anon, authenticated;

create or replace function public.enforce_account_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim integer;
begin
  lim := public.limite_do_plano(new.owner_id, 'contas');
  if lim is not null and (select count(*) from public.accounts where owner_id = new.owner_id and deleted_at is null) >= lim then
    raise exception 'limite de contas: seu plano permite % contas de clientes', lim;
  end if;
  return new;
end $$;
revoke execute on function public.enforce_account_limit() from public, anon, authenticated;
drop trigger if exists accounts_limit on public.accounts;
create trigger accounts_limit before insert on public.accounts for each row execute function public.enforce_account_limit();

-- Quanto espaço eu uso e qual o meu limite (MB; nulo = sem limite)
create or replace function public.my_storage()
returns json language sql stable security definer set search_path = public, storage as $$
  select json_build_object(
    'usado', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects
              where bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text),
    'limite_mb', public.limite_do_plano((select auth.uid()), 'mb'))
$$;
revoke execute on function public.my_storage() from public, anon;
grant execute on function public.my_storage() to authenticated;

-- ===================== 3) Usuários =====================
drop function if exists public.admin_list_users();
create or replace function public.admin_list_users()
returns table(id uuid, email text, name text, handle text, role text, confirmed boolean, created_at timestamptz, last_sign_in_at timestamptz,
              plano text, plano_ate timestamptz, plano_origem text, suspenso boolean, espaco bigint, contas bigint, posts bigint)
language plpgsql stable security definer set search_path = public, auth, storage as $$
begin
  if not public.is_admin() then raise exception 'Só administradores podem ver a lista de usuários'; end if;
  return query
    select u.id, u.email::text, coalesce(p.name, ''), coalesce(p.handle, ''), coalesce(p.role, 'social_media'),
           u.email_confirmed_at is not null, u.created_at, u.last_sign_in_at,
           coalesce(p.plano, 'gratis'), p.plano_ate, coalesce(p.plano_origem, ''),
           coalesce(u.banned_until > now(), false),
           (select coalesce(sum((o.metadata->>'size')::bigint), 0) from storage.objects o where o.bucket_id = 'fotos' and (storage.foldername(o.name))[1] = u.id::text)::bigint,
           (select count(*) from public.accounts a where a.owner_id = u.id and a.deleted_at is null),
           (select count(*) from public.posts x where x.owner_id = u.id and x.deleted_at is null)
    from auth.users u left join public.profiles p on p.id = u.id
    order by case coalesce(p.role,'') when 'gm' then 0 when 'admin' then 1 when 'social_media' then 2 else 3 end, u.created_at;
end $$;
revoke execute on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;

-- Quem pode mexer em quem: ninguém em si mesmo; admin não mexe em admin/GM; GM mexe em todos menos no último GM
create or replace function public.admin_can_manage(target uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare trole text;
begin
  if not public.is_admin() or target = (select auth.uid()) then return false; end if;
  select role into trole from public.profiles where id = target;
  if trole in ('gm','admin') and not public.is_gm() then return false; end if;
  return true;
end $$;
revoke execute on function public.admin_can_manage(uuid) from public, anon;
grant execute on function public.admin_can_manage(uuid) to authenticated;

-- Suspender (não consegue entrar e é desconectado em até 1 hora) ou reativar
create or replace function public.admin_set_suspended(target uuid, suspender boolean)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.admin_can_manage(target) then raise exception 'Você não pode suspender esta conta'; end if;
  update auth.users set banned_until = case when suspender then now() + interval '100 years' else null end where id = target;
  if suspender then delete from auth.sessions where user_id = target; end if;
  insert into public.activity_log (actor_id, category, action, target_user, details)
  values ((select auth.uid()), 'usuarios', case when suspender then 'suspendeu a conta' else 'reativou a conta' end, target, '{}'::jsonb);
end $$;
revoke execute on function public.admin_set_suspended(uuid, boolean) from public, anon;
grant execute on function public.admin_set_suspended(uuid, boolean) to authenticated;

-- Arquivos de um usuário (só o servidor usa, para apagar ao excluir a conta)
create or replace function public.admin_user_files(target uuid)
returns setof text language sql stable security definer set search_path = public, storage as $$
  select name from storage.objects where bucket_id = 'fotos' and (storage.foldername(name))[1] = target::text
$$;
revoke execute on function public.admin_user_files(uuid) from public, anon, authenticated;
grant execute on function public.admin_user_files(uuid) to service_role;

-- ===================== 5) Avisos (sininho) =====================
create table if not exists public.avisos (
  id         uuid primary key default gen_random_uuid(),
  titulo     text not null check (char_length(titulo) between 1 and 80),
  texto      text not null default '' check (char_length(texto) <= 400),
  link       text not null default '' check (char_length(link) <= 300),
  publico    text not null default 'todos' check (publico in ('todos','gratis','pro','agencia')),
  ativo      boolean not null default true,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists avisos_created_by_idx on public.avisos (created_by);
alter table public.avisos enable row level security;
create policy "usuários leem avisos" on public.avisos for select to authenticated
  using ((ativo and (publico = 'todos' or publico = public.plano_de((select auth.uid())))) or (select public.is_admin()));
create policy "admins criam avisos" on public.avisos for insert to authenticated with check ((select public.is_admin()));
create policy "admins editam avisos" on public.avisos for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam avisos" on public.avisos for delete to authenticated using ((select public.is_admin()));

create table if not exists public.aviso_lidos (
  user_id  uuid not null default auth.uid() references auth.users (id) on delete cascade,
  aviso_id uuid not null references public.avisos (id) on delete cascade,
  lido_em  timestamptz not null default now(),
  primary key (user_id, aviso_id)
);
create index if not exists aviso_lidos_aviso_idx on public.aviso_lidos (aviso_id);
alter table public.aviso_lidos enable row level security;
create policy "leituras próprias" on public.aviso_lidos for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "admins contam leituras" on public.aviso_lidos for select to authenticated using ((select public.is_admin()));

-- Instagram: conexões com problema ou chave perto de vencer (sem mostrar a chave)
create or replace function public.admin_ig_status()
returns table(account_id uuid, handle text, dono text, username text, status text, status_msg text, token_expires_at timestamptz, last_sync timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Só administradores'; end if;
  return query
    select c.account_id, a.handle, coalesce(nullif(p.name,''), u.email::text), c.username, c.status, coalesce(c.status_msg,''), c.token_expires_at, c.last_sync
    from public.ig_connections c
    join public.accounts a on a.id = c.account_id
    left join public.profiles p on p.id = c.owner_id
    left join auth.users u on u.id = c.owner_id
    order by (c.status <> 'ok') desc, c.token_expires_at nulls last;
end $$;
revoke execute on function public.admin_ig_status() from public, anon;
grant execute on function public.admin_ig_status() to authenticated;

-- Ajuste (migração figfeed_v17_plano_de_proprio): plano_de só responde sobre a própria pessoa (ou para admins / servidor)
create or replace function public.plano_de(uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select case when plano in ('pro','agencia') and (plano_ate is null or plano_ate > now()) then plano else 'gratis' end
  from public.profiles where id = uid and (uid = (select auth.uid()) or public.is_admin() or (select auth.uid()) is null)
$$;
