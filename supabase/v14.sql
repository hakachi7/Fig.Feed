-- Fig.Feed v14: Resultados do Instagram (API do Instagram com login do Instagram)

-- Conexão de cada conta do Fig.Feed com um Instagram (o app lê isto)
create table if not exists public.ig_connections (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ig_user_id text not null,
  username text,
  name text,
  profile_picture_url text,
  followers int,
  media_count int,
  status text not null default 'ok' check (status in ('ok','erro','desconectado')),
  status_msg text,
  token_expires_at timestamptz,
  connected_at timestamptz not null default now(),
  last_sync timestamptz
);
alter table public.ig_connections enable row level security;
create policy "conexões próprias - ler" on public.ig_connections for select using (owner_id = (select auth.uid()));
create policy "conexões próprias - apagar" on public.ig_connections for delete using (owner_id = (select auth.uid()));

-- Chaves de acesso: só o servidor (Edge Functions) lê e escreve. Sem políticas = ninguém pelo app.
create table if not exists public.ig_tokens (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  access_token text not null,
  expires_at timestamptz,
  refreshed_at timestamptz not null default now()
);
alter table public.ig_tokens enable row level security;

-- Links de conexão que a social media manda para o cliente
create table if not exists public.ig_connect_links (
  token text primary key default encode(extensions.gen_random_bytes(12),'hex'),
  account_id uuid not null references public.accounts(id) on delete cascade,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_at timestamptz
);
alter table public.ig_connect_links enable row level security;
create policy "links de conexão próprios" on public.ig_connect_links for all
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()) and exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid())));

-- Página do cliente: mostra quem pediu, sem login
create or replace function public.ig_link_info(p_token text)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'handle', a.handle,
    'quem', coalesce(nullif(p.name,''), nullif(p.handle,''), 'Sua social media'),
    'valido', l.used_at is null and l.expires_at > now())
  from ig_connect_links l
  join accounts a on a.id = l.account_id
  left join profiles p on p.id = l.owner_id
  where l.token = p_token
$$;
revoke all on function public.ig_link_info(text) from public;
grant execute on function public.ig_link_info(text) to anon, authenticated;

-- Números do perfil por dia
create table if not exists public.ig_daily (
  account_id uuid not null references public.accounts(id) on delete cascade,
  day date not null,
  followers int, reach int, views int, accounts_engaged int, total_interactions int,
  likes int, comments int, saves int, shares int, profile_links_taps int, follows int, unfollows int,
  primary key (account_id, day)
);
-- Posts, Reels e stories com seus números
create table if not exists public.ig_media (
  media_id text primary key,
  account_id uuid not null references public.accounts(id) on delete cascade,
  ts timestamptz not null,
  kind text not null,                 -- foto, carrossel, reels, story
  caption text, permalink text, thumb_url text,
  views int, reach int, likes int, comments int, saved int, shares int, follows int,
  total_interactions int, replies int, profile_visits int, navigation int,
  updated_at timestamptz not null default now()
);
create index if not exists ig_media_acc_ts on public.ig_media(account_id, ts desc);
-- Público (cidade, idade, gênero)
create table if not exists public.ig_audience (
  account_id uuid not null references public.accounts(id) on delete cascade,
  kind text not null,                 -- city, age, gender, country
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (account_id, kind)
);
do $$ declare t text; begin
  foreach t in array array['ig_daily','ig_media','ig_audience'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "dados do instagram próprios" on public.%I for select using (exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid())))', t);
  end loop;
end $$;

-- Segredo interno para o agendamento chamar a coleta
create table if not exists public.ig_settings (key text primary key, value text not null);
alter table public.ig_settings enable row level security;
insert into public.ig_settings(key,value) values ('cron_secret', encode(extensions.gen_random_bytes(24),'hex')) on conflict do nothing;

-- Agendamento: coleta diária às 6h10 (Brasília) e stories a cada 4 horas
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create or replace function public.ig_cron(p_action text)
returns void language plpgsql security definer set search_path = public as $$
declare s text; c record;
begin
  select value into s from ig_settings where key = 'cron_secret';
  for c in select account_id from ig_connections where status <> 'desconectado' loop
    perform net.http_post(
      url := 'https://ftffxxugvzijkcfprgiv.supabase.co/functions/v1/instagram',
      headers := jsonb_build_object('Content-Type','application/json','x-cron-secret', s),
      body := jsonb_build_object('action', p_action, 'account_id', c.account_id),
      timeout_milliseconds := 120000);
  end loop;
end $$;
revoke all on function public.ig_cron(text) from public, anon, authenticated;
select cron.schedule('instagram-diario', '10 9 * * *', $$select public.ig_cron('cron_sync')$$);
select cron.schedule('instagram-stories', '40 */4 * * *', $$select public.ig_cron('cron_stories')$$);

-- Totais do mês (alcance sem repetir pessoas)
create table if not exists public.ig_monthly (
  account_id uuid not null references public.accounts(id) on delete cascade,
  month text not null,
  reach int, views int, accounts_engaged int, total_interactions int,
  updated_at timestamptz not null default now(),
  primary key (account_id, month)
);
alter table public.ig_monthly enable row level security;
create policy "dados do instagram próprios" on public.ig_monthly for select using (exists (select 1 from public.accounts a where a.id = account_id and a.owner_id = (select auth.uid())));
