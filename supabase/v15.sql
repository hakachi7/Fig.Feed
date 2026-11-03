-- Fig.Feed v15 — Páginas do site (liga/desliga, nome, link, aviso, banners, páginas criadas a partir de modelos) e Pop-ups.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v15_paginas_popups). Só acrescenta.
-- Depende de admin.sql (is_admin) e v10.sql (pasta pública "blog" para as imagens).

-- ===================== 1) Páginas =====================
-- key: a rota da página (ex.: 'down', 'planos') ou o endereço de uma página criada por modelo (custom = true).
create table if not exists public.site_pages (
  key          text primary key check (key ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(key) <= 60),
  custom       boolean not null default false,
  nome         text not null default '' check (char_length(nome) <= 60),
  slug         text unique check (slug is null or (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 60)),
  ativo        boolean not null default true,
  quem         text not null default 'todos' check (quem in ('todos','logados','pro','admins')),
  aviso_titulo text not null default '' check (char_length(aviso_titulo) <= 80),
  aviso_texto  text not null default '' check (char_length(aviso_texto) <= 300),
  aviso_volta  timestamptz,
  aviso_botao  text not null default 'inicio' check (aviso_botao in ('inicio','novidades','suporte','nenhum')),
  auto_ligar   boolean not null default false,
  modelo       text not null default '',
  cover_path   text,
  blocks       jsonb not null default '[]'::jsonb check (jsonb_typeof(blocks) = 'array'),
  banners      jsonb not null default '{}'::jsonb check (jsonb_typeof(banners) = 'object'),
  updated_by   uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists site_pages_updated_by_idx on public.site_pages (updated_by);
alter table public.site_pages enable row level security;

-- Páginas prontas do app: todos leem a configuração (para saber se estão no ar, o nome, o aviso e os banners).
-- Páginas criadas por modelo: o conteúdo só aparece quando está no ar e para o público certo.
create policy "visitantes leem páginas" on public.site_pages for select to anon
  using (not custom or (quem = 'todos' and (ativo or (auto_ligar and aviso_volta <= now()))));
create policy "usuários leem páginas" on public.site_pages for select to authenticated
  using (not custom or (quem <> 'admins' and (ativo or (auto_ligar and aviso_volta <= now()))) or (select public.is_admin()));
create policy "admins criam páginas" on public.site_pages for insert to authenticated with check ((select public.is_admin()));
create policy "admins editam páginas" on public.site_pages for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam páginas" on public.site_pages for delete to authenticated using ((select public.is_admin()) and custom);

-- ===================== 2) Pop-ups =====================
create table if not exists public.popups (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null default '' check (char_length(nome) <= 80),
  ordem        integer not null default 0,
  ativo        boolean not null default false,
  formato      text not null default 'central' check (formato in ('central','canto','barra')),
  image_path   text,
  titulo       text not null default '' check (char_length(titulo) <= 100),
  texto        text not null default '' check (char_length(texto) <= 300),
  botao_texto  text not null default '' check (char_length(botao_texto) <= 40),
  botao_link   text not null default '' check (char_length(botao_link) <= 300),
  paginas      text[] not null default '{}',          -- vazio = todas as páginas
  momento      text not null default 'abrir' check (momento in ('abrir','segundos','rolar','sair')),
  segundos     integer not null default 5 check (segundos between 1 and 120),
  frequencia   text not null default 'uma' check (frequencia in ('uma','dia','30dias','sempre')),
  publico      text[] not null default '{todos}',     -- todos, sem_conta, logados, gratis, pro, agencia
  inicio       timestamptz,
  fim          timestamptz,
  vistos       integer not null default 0,
  cliques      integer not null default 0,
  fechados     integer not null default 0,
  created_by   uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists popups_ordem_idx on public.popups (ordem);
create index if not exists popups_created_by_idx on public.popups (created_by);
alter table public.popups enable row level security;
create policy "visitantes veem pop-ups no ar" on public.popups for select to anon
  using (ativo and (inicio is null or inicio <= now()) and (fim is null or fim > now()));
create policy "usuários veem pop-ups no ar" on public.popups for select to authenticated
  using ((ativo and (inicio is null or inicio <= now()) and (fim is null or fim > now())) or (select public.is_admin()));
create policy "admins criam pop-ups" on public.popups for insert to authenticated with check ((select public.is_admin()));
create policy "admins editam pop-ups" on public.popups for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam pop-ups" on public.popups for delete to authenticated using ((select public.is_admin()));

-- Contador: quantas vezes apareceu, quantos clicaram no botão e quantos fecharam
create or replace function public.popup_event(p_id uuid, p_kind text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_kind not in ('visto','clique','fechou') then return; end if;
  update public.popups
     set vistos   = vistos   + (p_kind = 'visto')::int,
         cliques  = cliques  + (p_kind = 'clique')::int,
         fechados = fechados + (p_kind = 'fechou')::int
   where id = p_id and ativo;
end $$;
revoke execute on function public.popup_event(uuid, text) from public;
grant execute on function public.popup_event(uuid, text) to anon, authenticated;

-- Aviso de uma página criada por modelo (o conteúdo continua protegido; só o aviso aparece)
create or replace function public.site_page_aviso(p_key text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object('key', key, 'nome', nome, 'quem', quem, 'ativo', ativo, 'aviso_titulo', aviso_titulo,
         'aviso_texto', aviso_texto, 'aviso_volta', aviso_volta, 'aviso_botao', aviso_botao, 'auto_ligar', auto_ligar)
    from public.site_pages where key = p_key and custom
$$;
revoke execute on function public.site_page_aviso(text) from public;
grant execute on function public.site_page_aviso(text) to anon, authenticated;
