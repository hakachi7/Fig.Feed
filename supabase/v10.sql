-- Fig.Feed v10 — Admin completo: Templates, Blog, Suporte e Assinaturas (planos e cupons).
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v10_admin). Só acrescenta.
-- Depende de supabase/admin.sql (v5): is_admin(), is_gm(), activity_log, protect_profile_role().

-- ===================== 1) Templates de feed =====================
create table if not exists public.feed_templates (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 60),
  tipo       text not null default 'feed' check (tipo in ('feed','carrossel')),
  formato    text not null default '4:5' check (formato in ('4:5','1:1','9:16')),
  slots      jsonb not null default '[]'::jsonb check (jsonb_typeof(slots) = 'array' and jsonb_array_length(slots) <= 12),
  descricao  text not null default '' check (char_length(descricao) <= 200),
  quem       text not null default 'todos' check (quem in ('todos','pro','admins')),
  status     text not null default 'rascunho' check (status in ('rascunho','publicado')),
  position   integer not null default 0,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists feed_templates_created_by_idx on public.feed_templates (created_by);
alter table public.feed_templates enable row level security;
create policy "templates visíveis" on public.feed_templates
  for select to authenticated using ((status = 'publicado' and quem <> 'admins') or (select public.is_admin()));
create policy "admins criam templates" on public.feed_templates
  for insert to authenticated with check ((select public.is_admin()));
create policy "admins editam templates" on public.feed_templates
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam templates" on public.feed_templates
  for delete to authenticated using ((select public.is_admin()));

-- ===================== 2) Blog =====================
create table if not exists public.blog_posts (
  id           uuid primary key default gen_random_uuid(),
  slug         text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 80),
  title        text not null default '' check (char_length(title) <= 140),
  subtitle     text not null default '' check (char_length(subtitle) <= 240),
  categoria    text not null default 'Dicas' check (categoria in ('Dicas','Novidades','Tutorial')),
  cover_path   text,
  cover_format text not null default '16:9' check (cover_format in ('16:9','4:5','1:1','9:16')),
  blocks       jsonb not null default '[]'::jsonb check (jsonb_typeof(blocks) = 'array'),
  resumo       text not null default '' check (char_length(resumo) <= 300),
  status       text not null default 'rascunho' check (status in ('rascunho','agendado','publicado')),
  publish_at   timestamptz,
  visibilidade text not null default 'todos' check (visibilidade in ('todos','logados')),
  em_novidades boolean not null default false,
  author_id    uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
create index if not exists blog_posts_pub_idx on public.blog_posts (status, publish_at desc);
create index if not exists blog_posts_author_idx on public.blog_posts (author_id);
alter table public.blog_posts enable row level security;
-- quem não tem conta vê só o que está no ar e é para todos
create policy "blog público" on public.blog_posts
  for select to anon using (deleted_at is null and visibilidade = 'todos'
    and (status = 'publicado' or (status = 'agendado' and publish_at <= now())));
-- quem tem conta vê o que está no ar; admins veem tudo (rascunhos e lixeira)
create policy "blog para quem entrou" on public.blog_posts
  for select to authenticated using ((deleted_at is null
    and (status = 'publicado' or (status = 'agendado' and publish_at <= now()))) or (select public.is_admin()));
create policy "admins criam posts do blog" on public.blog_posts
  for insert to authenticated with check ((select public.is_admin()));
create policy "admins editam posts do blog" on public.blog_posts
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam posts do blog" on public.blog_posts
  for delete to authenticated using ((select public.is_admin()));

-- Fotos do blog: pasta pública (qualquer um vê pelo link), só admins enviam
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('blog', 'blog', true, 10485760, array['image/jpeg','image/png','image/gif','image/webp'])
on conflict (id) do nothing;
create policy "admins enviam fotos do blog" on storage.objects
  for insert to authenticated with check (bucket_id = 'blog' and (select public.is_admin()));
create policy "admins trocam fotos do blog" on storage.objects
  for update to authenticated using (bucket_id = 'blog' and (select public.is_admin()));
create policy "admins apagam fotos do blog" on storage.objects
  for delete to authenticated using (bucket_id = 'blog' and (select public.is_admin()));

-- ===================== 3) Suporte =====================
create table if not exists public.support_tickets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  subject     text not null check (char_length(subject) between 1 and 120),
  category    text not null default 'duvida' check (category in ('duvida','problema','planos','pagamento','sugestao','privacidade')),
  status      text not null default 'aberto' check (status in ('aberto','respondido','resolvido')),
  unread_user boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists support_tickets_user_idx on public.support_tickets (user_id);
create index if not exists support_tickets_status_idx on public.support_tickets (status, updated_at desc);
alter table public.support_tickets enable row level security;
create policy "ver pedidos" on public.support_tickets
  for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "abrir pedido" on public.support_tickets
  for insert to authenticated with check (user_id = (select auth.uid()) and status = 'aberto');
create policy "admins atualizam pedidos" on public.support_tickets
  for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create table if not exists public.support_messages (
  id         bigint generated always as identity primary key,
  ticket_id  uuid not null references public.support_tickets (id) on delete cascade,
  author_id  uuid default auth.uid() references auth.users (id) on delete set null,
  from_admin boolean not null default false,
  body       text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists support_messages_ticket_idx on public.support_messages (ticket_id, created_at);
create index if not exists support_messages_author_idx on public.support_messages (author_id);
alter table public.support_messages enable row level security;
create policy "ver mensagens" on public.support_messages
  for select to authenticated using (exists (select 1 from public.support_tickets t where t.id = ticket_id
    and (t.user_id = (select auth.uid()) or (select public.is_admin()))));
create policy "escrever mensagem" on public.support_messages
  for insert to authenticated with check (author_id = (select auth.uid()) and (
    (from_admin = false and exists (select 1 from public.support_tickets t where t.id = ticket_id and t.user_id = (select auth.uid())))
    or (from_admin = true and (select public.is_admin()))));

-- Cada mensagem nova muda a situação do pedido
create or replace function public.support_after_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.support_tickets
     set updated_at = now(),
         status = case when new.from_admin then 'respondido' else 'aberto' end,
         unread_user = new.from_admin
   where id = new.ticket_id;
  return new;
end $$;
drop trigger if exists support_messages_after on public.support_messages;
create trigger support_messages_after after insert on public.support_messages
  for each row execute function public.support_after_message();
revoke execute on function public.support_after_message() from public, anon, authenticated;

-- O usuário marca a resposta como lida
create or replace function public.support_mark_read(ticket uuid)
returns void language sql security definer set search_path = public as $$
  update public.support_tickets set unread_user = false where id = ticket and user_id = (select auth.uid());
$$;
revoke execute on function public.support_mark_read(uuid) from public, anon;
grant execute on function public.support_mark_read(uuid) to authenticated;

-- ===================== 4) Planos de cada usuário =====================
alter table public.profiles add column if not exists plano text not null default 'gratis' check (plano in ('gratis','pro','agencia'));
alter table public.profiles add column if not exists plano_ate timestamptz;          -- vazio = sem prazo
alter table public.profiles add column if not exists plano_origem text not null default '';  -- manual, teste, cupom

-- Ninguém muda a própria função NEM o próprio plano pelo app
create or replace function public.protect_profile_role()
returns trigger language plpgsql set search_path = public as $$
begin
  if (select auth.uid()) is not null
     and coalesce(current_setting('figfeed.allow_role', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      new.role := 'social_media';
      new.plano := 'gratis'; new.plano_ate := null; new.plano_origem := '';
    else
      new.role := old.role;
      new.plano := old.plano; new.plano_ate := old.plano_ate; new.plano_origem := old.plano_origem;
    end if;
  end if;
  return new;
end $$;

-- Admin muda o plano de alguém (dias vazio = sem prazo)
create or replace function public.admin_set_plan(target uuid, novo_plano text, dias integer default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  old_plan text;
begin
  if not public.is_admin() then
    raise exception 'Só administradores podem mudar planos';
  end if;
  if novo_plano not in ('gratis','pro','agencia') then
    raise exception 'Plano inválido';
  end if;
  if dias is not null and (dias < 1 or dias > 730) then
    raise exception 'O prazo precisa ser entre 1 e 730 dias';
  end if;
  select plano into old_plan from public.profiles where id = target;
  if old_plan is null then
    raise exception 'Usuário não encontrado';
  end if;
  perform set_config('figfeed.allow_role', 'on', true);
  update public.profiles
     set plano = novo_plano,
         plano_ate = case when novo_plano = 'gratis' or dias is null then null else now() + make_interval(days => dias) end,
         plano_origem = case when novo_plano = 'gratis' then '' when dias is null then 'manual' else 'teste' end
   where id = target;
  perform set_config('figfeed.allow_role', '', true);
  insert into public.activity_log (actor_id, category, action, target_user, details)
  values (me, 'pagamentos', 'mudou o plano', target, jsonb_build_object('de', old_plan, 'para', novo_plano, 'dias', dias));
end $$;
revoke execute on function public.admin_set_plan(uuid, text, integer) from public, anon;
grant execute on function public.admin_set_plan(uuid, text, integer) to authenticated;

-- ===================== 5) Cupons =====================
create table if not exists public.coupons (
  code       text primary key check (code ~ '^[A-Z0-9_-]{3,30}$'),
  descricao  text not null default '' check (char_length(descricao) <= 120),
  plano      text not null default 'pro' check (plano in ('pro','agencia')),
  dias       integer not null default 30 check (dias between 1 and 365),
  max_usos   integer check (max_usos is null or max_usos > 0),
  usos       integer not null default 0,
  ativo      boolean not null default true,
  expira_em  timestamptz,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists coupons_created_by_idx on public.coupons (created_by);
alter table public.coupons enable row level security;
create policy "admins veem cupons" on public.coupons for select to authenticated using ((select public.is_admin()));
create policy "admins criam cupons" on public.coupons for insert to authenticated with check ((select public.is_admin()));
create policy "admins editam cupons" on public.coupons for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam cupons" on public.coupons for delete to authenticated using ((select public.is_admin()));

create table if not exists public.coupon_redemptions (
  code       text not null references public.coupons (code) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (code, user_id)
);
create index if not exists coupon_redemptions_user_idx on public.coupon_redemptions (user_id);
alter table public.coupon_redemptions enable row level security;
create policy "admins veem usos de cupons" on public.coupon_redemptions for select to authenticated using ((select public.is_admin()));

-- O usuário usa um cupom (só uma vez cada)
create or replace function public.redeem_coupon(coupon_code text)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := (select auth.uid());
  c record;
  p record;
  base timestamptz;
begin
  if me is null then raise exception 'Entre na sua conta para usar um cupom'; end if;
  select * into c from public.coupons where code = upper(trim(coupon_code)) for update;
  if not found or not c.ativo or (c.expira_em is not null and c.expira_em < now()) then
    raise exception 'Cupom inválido ou vencido';
  end if;
  if c.max_usos is not null and c.usos >= c.max_usos then
    raise exception 'Esse cupom já foi usado o máximo de vezes';
  end if;
  if exists (select 1 from public.coupon_redemptions where code = c.code and user_id = me) then
    raise exception 'Você já usou esse cupom';
  end if;
  select plano, plano_ate into p from public.profiles where id = me;
  if p.plano <> 'gratis' and p.plano_ate is null then
    raise exception 'Seu plano já não tem prazo para acabar';
  end if;
  if p.plano = 'agencia' and c.plano = 'pro' and (p.plano_ate is null or p.plano_ate > now()) then
    raise exception 'Seu plano atual já é melhor que o deste cupom';
  end if;
  base := greatest(now(), coalesce(case when p.plano = c.plano then p.plano_ate end, now()));
  perform set_config('figfeed.allow_role', 'on', true);
  update public.profiles set plano = c.plano, plano_ate = base + make_interval(days => c.dias), plano_origem = 'cupom' where id = me;
  perform set_config('figfeed.allow_role', '', true);
  insert into public.coupon_redemptions (code, user_id) values (c.code, me);
  update public.coupons set usos = usos + 1 where code = c.code;
  insert into public.activity_log (actor_id, category, action, target_user, details)
  values (me, 'pagamentos', 'usou cupom', me, jsonb_build_object('cupom', c.code, 'plano', c.plano, 'dias', c.dias));
  return c.plano;
end $$;
revoke execute on function public.redeem_coupon(text) from public, anon;
grant execute on function public.redeem_coupon(text) to authenticated;

-- ===================== 6) Lista de usuários do Admin agora traz o plano =====================
drop function if exists public.admin_list_users();
create or replace function public.admin_list_users()
returns table (id uuid, email text, name text, handle text, role text, confirmed boolean, created_at timestamptz,
               last_sign_in_at timestamptz, plano text, plano_ate timestamptz, plano_origem text)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then
    raise exception 'Só administradores podem ver a lista de usuários';
  end if;
  return query
    select u.id, u.email::text, coalesce(p.name, ''), coalesce(p.handle, ''), coalesce(p.role, 'social_media'),
           u.email_confirmed_at is not null, u.created_at, u.last_sign_in_at,
           coalesce(p.plano, 'gratis'), p.plano_ate, coalesce(p.plano_origem, '')
    from auth.users u left join public.profiles p on p.id = u.id
    order by case coalesce(p.role,'') when 'gm' then 0 when 'admin' then 1 when 'social_media' then 2 else 3 end, u.created_at;
end $$;
revoke execute on function public.admin_list_users() from public, anon;
grant execute on function public.admin_list_users() to authenticated;
