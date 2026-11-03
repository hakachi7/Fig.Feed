-- Fig.Feed v5 — Painel Admin: funções (GM, admin, social media, cliente),
-- convites por e-mail e registro de atividades.
-- Já aplicado no projeto Supabase "Fig-Free". Este arquivo serve de registro e para recriar o banco.
-- Observação: quem é o GM NÃO fica aqui (é um dado, não estrutura). Para definir o GM num banco novo,
-- rode no SQL Editor:  insert into public.role_invites (email, role) values ('seu@email.com', 'gm');

-- 1) Função de cada usuário
alter table public.profiles
  add column if not exists role text not null default 'social_media'
  check (role in ('gm','admin','social_media','cliente'));

-- 2) Funções de apoio (leem a função de quem está logado)
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = (select auth.uid())
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role in ('gm','admin') from public.profiles where id = (select auth.uid())), false)
$$;

create or replace function public.is_gm()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'gm' from public.profiles where id = (select auth.uid())), false)
$$;

-- 3) Ninguém muda a própria função pelo app: só pelas funções oficiais abaixo
create or replace function public.protect_profile_role()
returns trigger language plpgsql set search_path = public as $$
begin
  if (select auth.uid()) is not null
     and coalesce(current_setting('figfeed.allow_role', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      new.role := 'social_media';
    else
      new.role := old.role;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists profiles_protect_role on public.profiles;
create trigger profiles_protect_role
  before insert or update on public.profiles
  for each row execute function public.protect_profile_role();

-- 4) Admins podem ver todos os perfis
drop policy if exists "admins veem perfis" on public.profiles;
create policy "admins veem perfis" on public.profiles
  for select to authenticated using ((select public.is_admin()));

-- 5) Registro de atividades (não pode ser editado nem apagado)
create table if not exists public.activity_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null default auth.uid(),
  category text not null check (category in ('funcoes','usuarios','conteudo','pagamentos','seguranca','ver_como_usuario')),
  action text not null,
  target_user uuid references auth.users(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists activity_log_created_idx on public.activity_log (created_at desc);
create index if not exists activity_log_actor_idx on public.activity_log (actor_id);
create index if not exists activity_log_target_idx on public.activity_log (target_user);
alter table public.activity_log enable row level security;

create policy "admins leem atividade" on public.activity_log
  for select to authenticated using ((select public.is_admin()));
create policy "admins registram atividade" on public.activity_log
  for insert to authenticated
  with check ((select public.is_admin()) and actor_id = (select auth.uid()));
revoke update, delete, truncate on public.activity_log from anon, authenticated;

-- 6) Convites de função por e-mail (para quem ainda não tem conta)
create table if not exists public.role_invites (
  email text primary key check (email = lower(email)),
  role text not null check (role in ('gm','admin','social_media','cliente')),
  invited_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists role_invites_invited_by_idx on public.role_invites (invited_by);
alter table public.role_invites enable row level security;
create policy "admins veem convites" on public.role_invites
  for select to authenticated using ((select public.is_admin()));
revoke insert, update, delete, truncate on public.role_invites from anon, authenticated;

-- 7) Mudar a função de alguém (regras: só o GM mexe em admins; o GM não tira o próprio acesso)
create or replace function public.set_user_role(target uuid, new_role text)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  my text := public.my_role();
  old_role text;
begin
  if my is null or my not in ('gm','admin') then
    raise exception 'Só administradores podem mudar funções';
  end if;
  if new_role not in ('gm','admin','social_media','cliente') then
    raise exception 'Função inválida';
  end if;
  select role into old_role from public.profiles where id = target;
  if old_role is null then
    raise exception 'Usuário não encontrado';
  end if;
  if my <> 'gm' and (new_role in ('gm','admin') or old_role in ('gm','admin')) then
    raise exception 'Só o GM pode criar ou alterar administradores';
  end if;
  if target = me and old_role = 'gm' and new_role <> 'gm' then
    raise exception 'O GM não pode tirar o próprio acesso';
  end if;

  perform set_config('figfeed.allow_role', 'on', true);
  update public.profiles set role = new_role where id = target;
  perform set_config('figfeed.allow_role', '', true);

  insert into public.activity_log (actor_id, category, action, target_user, details)
  values (me, 'funcoes', 'mudou a função', target,
          jsonb_build_object('de', old_role, 'para', new_role));
end $$;

-- 8) Convidar por e-mail com uma função (se a pessoa já tem conta confirmada, aplica na hora)
create or replace function public.invite_with_role(invite_email text, new_role text)
returns text language plpgsql security definer set search_path = public, auth as $$
declare
  me uuid := (select auth.uid());
  my text := public.my_role();
  e text := lower(trim(invite_email));
  existing uuid;
begin
  if my is null or my not in ('gm','admin') then
    raise exception 'Só administradores podem convidar';
  end if;
  if new_role not in ('gm','admin','social_media','cliente') then
    raise exception 'Função inválida';
  end if;
  if my <> 'gm' and new_role in ('gm','admin') then
    raise exception 'Só o GM pode convidar administradores';
  end if;

  select id into existing from auth.users
   where lower(email) = e and email_confirmed_at is not null;

  if existing is not null then
    perform public.set_user_role(existing, new_role);
    return 'aplicado';
  end if;

  insert into public.role_invites (email, role, invited_by)
  values (e, new_role, me)
  on conflict (email) do update set role = excluded.role, invited_by = excluded.invited_by, created_at = now();

  insert into public.activity_log (actor_id, category, action, details)
  values (me, 'usuarios', 'convidou por e-mail', jsonb_build_object('email', e, 'funcao', new_role));
  return 'convite criado';
end $$;

-- 9) Quando a pessoa confirma o e-mail, o convite vira a função dela
create or replace function public.apply_role_invite()
returns trigger language plpgsql security definer set search_path = public as $$
declare inv record;
begin
  if new.email_confirmed_at is null then
    return new;
  end if;
  select * into inv from public.role_invites where email = lower(new.email);
  if not found then
    return new;
  end if;

  perform set_config('figfeed.allow_role', 'on', true);
  insert into public.profiles (id, name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''), inv.role)
  on conflict (id) do update set role = excluded.role;
  perform set_config('figfeed.allow_role', '', true);

  delete from public.role_invites where email = inv.email;
  insert into public.activity_log (actor_id, category, action, target_user, details)
  values (inv.invited_by, 'funcoes', 'convite aceito', new.id, jsonb_build_object('funcao', inv.role));
  return new;
end $$;

drop trigger if exists zz_apply_role_invite on auth.users;
create trigger zz_apply_role_invite
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.apply_role_invite();

-- 10) Lista de usuários com e-mail para o painel (só GM/admin)
create or replace function public.admin_list_users()
returns table (id uuid, email text, name text, handle text, role text, confirmed boolean, created_at timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then
    raise exception 'Só administradores podem ver a lista de usuários';
  end if;
  return query
    select u.id, u.email::text, coalesce(p.name, ''), coalesce(p.handle, ''), coalesce(p.role, 'social_media'),
           u.email_confirmed_at is not null, u.created_at, u.last_sign_in_at
    from auth.users u left join public.profiles p on p.id = u.id
    order by case coalesce(p.role,'') when 'gm' then 0 when 'admin' then 1 when 'social_media' then 2 else 3 end, u.created_at;
end $$;

-- 11) Cancelar um convite pendente
create or replace function public.cancel_invite(invite_email text)
returns void language plpgsql security definer set search_path = public as $$
declare
  my text := public.my_role();
  inv record;
begin
  select * into inv from public.role_invites where email = lower(trim(invite_email));
  if not found then return; end if;
  if my is null or my not in ('gm','admin') then
    raise exception 'Só administradores podem cancelar convites';
  end if;
  if my <> 'gm' and inv.role in ('gm','admin') then
    raise exception 'Só o GM pode cancelar convites de administrador';
  end if;
  delete from public.role_invites where email = inv.email;
  insert into public.activity_log (actor_id, category, action, details)
  values ((select auth.uid()), 'usuarios', 'cancelou convite', jsonb_build_object('email', inv.email, 'funcao', inv.role));
end $$;

-- 12) Quem pode chamar o quê
revoke execute on function public.apply_role_invite() from public, anon, authenticated;
revoke execute on function public.protect_profile_role() from public, anon, authenticated;
revoke execute on function public.set_user_role(uuid, text) from public, anon;
revoke execute on function public.invite_with_role(text, text) from public, anon;
revoke execute on function public.admin_list_users() from public, anon;
revoke execute on function public.cancel_invite(text) from public, anon;
revoke execute on function public.my_role() from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.is_gm() from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.invite_with_role(text, text) to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.cancel_invite(text) to authenticated;
grant execute on function public.my_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_gm() to authenticated;
