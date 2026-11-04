-- Fig.Feed v19: Feed On (feed público de um perfil profissional, guardado por conta)
create table if not exists public.feedon (
  account_id uuid primary key references public.accounts(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  username text not null,
  data jsonb not null,
  fetched_at timestamptz not null default now()
);
alter table public.feedon enable row level security;
create policy "feed on próprio - ler" on public.feedon for select to authenticated using (owner_id = (select auth.uid()));
create policy "feed on próprio - desligar" on public.feedon for delete to authenticated using (owner_id = (select auth.uid()));

-- Conexões que o admin pode escolher como "conta do Fig.Feed" (só as dele); a escolha fica em ig_settings 'feedon_viewer'
create or replace function public.feedon_viewer_info()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'atual', (select c.username from ig_settings s join ig_connections c on c.account_id::text = s.value where s.key = 'feedon_viewer'),
    'minhas', coalesce((select json_agg(json_build_object('account_id', c.account_id, 'username', c.username)) from ig_connections c
                         where c.owner_id = (select auth.uid()) and c.status = 'ok'), '[]'::json))
  where public.is_admin()
$$;
revoke execute on function public.feedon_viewer_info() from public, anon;
grant execute on function public.feedon_viewer_info() to authenticated;
