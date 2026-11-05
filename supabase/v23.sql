-- Fig.Feed v23: análises de Stories e Carrosséis em Resultados
-- Stories: o que as pessoas fizeram (navigation por story_navigation_action_type) e cliques no link; carrossel: quantas fotos
alter table public.ig_media
  add column if not exists nav_forward int,
  add column if not exists nav_back int,
  add column if not exists nav_exit int,
  add column if not exists nav_next int,
  add column if not exists link_clicks int,
  add column if not exists slides int;

-- Curtidas por foto do carrossel, anotadas à mão (a Meta não libera esse número pela API)
create table if not exists public.ig_slide_likes (
  media_id text primary key references public.ig_media(media_id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  likes int[] not null check (array_length(likes, 1) between 1 and 20 and 0 <= all(likes)),
  updated_at timestamptz not null default now()
);
alter table public.ig_slide_likes enable row level security;
create policy "curtidas por foto próprias" on public.ig_slide_likes for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid())
    and exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid()))
    and exists (select 1 from public.ig_media m where m.media_id = ig_slide_likes.media_id and m.account_id = ig_slide_likes.account_id));
create index if not exists ig_slide_likes_acc on public.ig_slide_likes(account_id);
create index if not exists ig_slide_likes_owner on public.ig_slide_likes(owner_id);
