-- Fig.Feed v8 — Stories, Prévia estilo Instagram e Relatório do mês.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v8_stories_previa_relatorio). Só acrescenta.

-- 1) Stories de cada conta, por dia
create table if not exists public.stories (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  account_id   uuid not null references public.accounts (id) on delete cascade,
  story_date   date not null default current_date,
  storage_path text not null,
  credit       text,
  position     integer not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists stories_account_day_idx on public.stories (account_id, story_date, position);
alter table public.stories enable row level security;
drop policy if exists "stories próprios" on public.stories;
create policy "stories próprios" on public.stories
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid())
    and exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid())));

-- 2) Dados do perfil da conta para a Prévia (como aparece no Instagram)
alter table public.accounts add column if not exists display_name text not null default '';
alter table public.accounts add column if not exists bio          text not null default '' check (char_length(bio) <= 150);
alter table public.accounts add column if not exists followers    integer check (followers >= 0);
alter table public.accounts add column if not exists following    integer check (following >= 0);
alter table public.accounts add column if not exists highlights   jsonb not null default '[]'::jsonb;

-- 3) Links do relatório do mês: o cliente abre sem login, por 30 dias.
--    Guarda uma "foto" do relatório no momento em que o link é criado.
create table if not exists public.report_links (
  token      text primary key default replace(gen_random_uuid()::text, '-', ''),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  account_id uuid not null references public.accounts (id) on delete cascade,
  month      text not null check (month ~ '^\d{4}-\d{2}$'),
  payload    jsonb not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days'
);
alter table public.report_links enable row level security;
drop policy if exists "links próprios" on public.report_links;
create policy "links próprios" on public.report_links
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid())
    and exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid())));

-- Leitura pública só pelo token exato, e só enquanto o link vale
create or replace function public.get_shared_report(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select payload from public.report_links where token = p_token and expires_at > now()
$$;
revoke execute on function public.get_shared_report(text) from public;
grant execute on function public.get_shared_report(text) to anon, authenticated;
