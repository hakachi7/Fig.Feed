-- Fig.Feed v6 — Segurança e Excluir minha conta.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v6_conta_seguranca). Só acrescenta funções.

-- 1) Aparelhos conectados: as sessões de login da própria pessoa
create or replace function public.my_sessions()
returns table(id uuid, user_agent text, created_at timestamptz, last_seen timestamptz, is_current boolean)
language sql stable security definer set search_path = public, auth as $$
  select s.id, coalesce(s.user_agent, ''), s.created_at,
         coalesce(s.refreshed_at::timestamptz, s.updated_at, s.created_at),
         s.id::text = coalesce(auth.jwt() ->> 'session_id', '')
    from auth.sessions s
   where s.user_id = auth.uid()
   order by 5 desc nulls last, 4 desc;
$$;
revoke execute on function public.my_sessions() from public, anon;
grant execute on function public.my_sessions() to authenticated;

-- 2) Excluir a própria conta. Contas de clientes, posts e fotos cadastradas saem junto (cascata).
--    As fotos enviadas (Storage) são apagadas pelo app antes de chamar esta função.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Entre na sua conta para excluí-la'; end if;
  if (select role from public.profiles where id = me) = 'gm'
     and (select count(*) from public.profiles where role = 'gm') <= 1 then
    raise exception 'Você é o único GM. Passe a função de GM para outra pessoa antes de excluir sua conta.';
  end if;
  delete from auth.users where id = me;
end $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- 3) Lista das fotos guardadas da própria pessoa (para a Biblioteca e para excluir a conta)
create or replace function public.my_files()
returns table(name text, size bigint, created_at timestamptz)
language sql stable security definer set search_path = public, storage as $$
  select o.name, coalesce((o.metadata->>'size')::bigint, 0), o.created_at
    from storage.objects o
   where o.bucket_id = 'fotos' and (storage.foldername(o.name))[1] = auth.uid()::text
   order by o.created_at desc;
$$;
revoke execute on function public.my_files() from public, anon;
grant execute on function public.my_files() to authenticated;

-- 4) Ajustes do app. "manutencao" liga a tela "Estamos fazendo uma atualização" (só o GM muda).
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now()
);
alter table public.app_settings enable row level security;
drop policy if exists "todos leem ajustes" on public.app_settings;
create policy "todos leem ajustes" on public.app_settings for select to anon, authenticated using (true);
drop policy if exists "gm altera ajustes" on public.app_settings;
create policy "gm altera ajustes" on public.app_settings for all to authenticated
  using ((select public.is_gm())) with check ((select public.is_gm()));
insert into public.app_settings (key, value) values ('manutencao', '{"ativo": false}'::jsonb)
  on conflict (key) do nothing;

-- 5) Checagem antes de excluir (para o app não apagar as fotos se a exclusão for bloqueada)
create or replace function public.can_delete_my_account()
returns text language sql stable security definer set search_path = public as $$
  select case
    when auth.uid() is null then 'Entre na sua conta para excluí-la'
    when (select role from public.profiles where id = auth.uid()) = 'gm'
         and (select count(*) from public.profiles where role = 'gm') <= 1
      then 'Você é o único GM. Passe a função de GM para outra pessoa antes de excluir sua conta.'
    else null end
$$;
revoke execute on function public.can_delete_my_account() from public, anon;
grant execute on function public.can_delete_my_account() to authenticated;
