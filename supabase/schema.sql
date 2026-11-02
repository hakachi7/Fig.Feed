-- =====================================================================
-- Fig.Feed — estrutura do banco de dados (Supabase / Postgres)
-- Rode este arquivo uma vez no SQL Editor do Supabase.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Perfil de cada usuário (criado automaticamente no cadastro)
-- ---------------------------------------------------------------------
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  name         text not null default '',
  handle       text not null default '',
  avatar_path  text,                          -- caminho da foto no Storage
  dates_follow boolean not null default true, -- datas acompanham a ordem da grade
  created_at   timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Contas (os clientes da social media)
-- ---------------------------------------------------------------------
create table public.accounts (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  handle     text not null,
  position   integer not null default 0,   -- ordem na tela de Contas
  created_at timestamptz not null default now()
);
create index on public.accounts (owner_id, position);

-- ---------------------------------------------------------------------
-- 3. Posts do feed
--    position 0 = topo da grade (o mais recente, como no Instagram)
-- ---------------------------------------------------------------------
create table public.posts (
  id           uuid primary key default gen_random_uuid(),
  account_id   uuid not null references public.accounts (id) on delete cascade,
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title        text not null default 'Novo post',
  caption      text not null default '' check (char_length(caption) <= 2200),
  publish_date date,
  status       text not null default 'rascunho' check (status in ('rascunho', 'pronto', 'agendado')),
  position     integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on public.posts (account_id, position);
create index on public.posts (owner_id, publish_date);

-- ---------------------------------------------------------------------
-- 4. Fotos de cada post (o carrossel). A de position 0 é a capa.
-- ---------------------------------------------------------------------
create table public.slides (
  id           uuid primary key default gen_random_uuid(),
  post_id      uuid not null references public.posts (id) on delete cascade,
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  storage_path text not null,               -- ex.: <id do usuário>/<id do post>/foto.jpg
  credit       text,
  position     integer not null default 0,
  created_at   timestamptz not null default now()
);
create index on public.slides (post_id, position);
create index on public.slides (owner_id);

-- Máximo de 10 fotos por post, como no Instagram
create or replace function public.limit_slides()
returns trigger language plpgsql set search_path = public as $$
begin
  if (select count(*) from public.slides where post_id = new.post_id) >= 10 then
    raise exception 'Um post pode ter no máximo 10 fotos';
  end if;
  return new;
end $$;

create trigger slides_limit before insert on public.slides
  for each row execute function public.limit_slides();

-- Atualiza updated_at do post sempre que ele muda
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end $$;

create trigger posts_touch before update on public.posts
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- 5. Segurança: cada usuário só vê e mexe no que é dele
-- ---------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.posts    enable row level security;
alter table public.slides   enable row level security;

create policy "perfil próprio" on public.profiles
  for all to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "contas próprias" on public.accounts
  for all to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

create policy "posts próprios" on public.posts
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (
    owner_id = (select auth.uid())
    and exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid()))
  );

create policy "fotos próprias" on public.slides
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (
    owner_id = (select auth.uid())
    and exists (select 1 from public.posts p where p.id = post_id and p.owner_id = (select auth.uid()))
  );

-- ---------------------------------------------------------------------
-- 6. Funções do projeto
-- ---------------------------------------------------------------------

-- Reordenar a grade de uma conta de uma vez só (o "arrastar e soltar").
-- Recebe os ids dos posts na nova ordem, do topo para baixo.
-- Se a pessoa usa "datas acompanham a ordem", redistribui as datas.
create or replace function public.reorder_posts(p_account uuid, p_ids uuid[])
returns void language plpgsql security invoker set search_path = public as $$
declare
  follow boolean;
  dates  date[];
begin
  if not exists (select 1 from public.accounts where id = p_account and owner_id = (select auth.uid())) then
    raise exception 'Conta não encontrada';
  end if;

  update public.posts p
     set position = t.ord - 1
    from unnest(p_ids) with ordinality as t(id, ord)
   where p.id = t.id and p.account_id = p_account;

  select dates_follow into follow from public.profiles where id = (select auth.uid());

  if follow then
    select array_agg(publish_date order by publish_date desc) into dates
      from public.posts where account_id = p_account and publish_date is not null;

    if coalesce(array_length(dates, 1), 0) =
       (select count(*) from public.posts where account_id = p_account) then
      update public.posts p
         set publish_date = dates[p.position + 1]
       where p.account_id = p_account;
    end if;
  end if;
end $$;

-- Reordenar as fotos de um carrossel
create or replace function public.reorder_slides(p_post uuid, p_ids uuid[])
returns void language plpgsql security invoker set search_path = public as $$
begin
  update public.slides s
     set position = t.ord - 1
    from unnest(p_ids) with ordinality as t(id, ord)
   where s.id = t.id and s.post_id = p_post;
end $$;

revoke execute on function public.reorder_posts(uuid, uuid[]) from public, anon;
revoke execute on function public.reorder_slides(uuid, uuid[]) from public, anon;
grant execute on function public.reorder_posts(uuid, uuid[]) to authenticated;
grant execute on function public.reorder_slides(uuid, uuid[]) to authenticated;

-- Cronograma: próximas publicações de todas as contas
create or replace view public.schedule with (security_invoker = true) as
  select p.id as post_id, p.title, p.status, p.publish_date,
         a.id as account_id, a.handle,
         (select s.storage_path from public.slides s
           where s.post_id = p.id order by s.position limit 1) as cover_path,
         (select count(*) from public.slides s where s.post_id = p.id) as slide_count
    from public.posts p
    join public.accounts a on a.id = p.account_id
   where p.publish_date >= current_date
   order by p.publish_date, a.handle;

-- ---------------------------------------------------------------------
-- 7. Armazenamento das fotos (pasta "fotos", privada)
--    Cada usuário só acessa a própria pasta: fotos/<id do usuário>/...
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "ver próprias fotos" on storage.objects
  for select to authenticated using (bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "enviar próprias fotos" on storage.objects
  for insert to authenticated with check (bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "trocar próprias fotos" on storage.objects
  for update to authenticated using (bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "apagar próprias fotos" on storage.objects
  for delete to authenticated using (bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text);
