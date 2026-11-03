-- Fig.Feed v9 — Planejamento do mês: objetivo, pilares, formato, horário e chamada para ação.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v9_planejamento). Só acrescenta.

-- 1) Campos novos do post
alter table public.posts add column if not exists pilar   text not null default '';
alter table public.posts add column if not exists formato text check (formato in ('foto','carrossel','reels')); -- vazio = automático pelo nº de fotos
alter table public.posts add column if not exists hora    time;
alter table public.posts add column if not exists cta     text not null default '' check (char_length(cta) <= 120);

-- 2) Tipo de cada story
alter table public.stories add column if not exists tipo text not null default 'imagem'
  check (tipo in ('imagem','enquete','caixinha','link','contagem','video'));

-- 3) Pilares de conteúdo da conta: [{"name":"Produto","meta":40}, …] (meta = % desejado no mês)
alter table public.accounts add column if not exists pilares jsonb not null default '[]'::jsonb;

-- 4) Planejamento de cada conta em cada mês (objetivo)
create table if not exists public.plans (
  account_id uuid not null references public.accounts (id) on delete cascade,
  month      text not null check (month ~ '^\d{4}-\d{2}$'),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  objetivo   text not null default '' check (char_length(objetivo) <= 400),
  updated_at timestamptz not null default now(),
  primary key (account_id, month)
);
alter table public.plans enable row level security;
drop policy if exists "planos próprios" on public.plans;
create policy "planos próprios" on public.plans
  for all to authenticated using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid())
    and exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid())));
