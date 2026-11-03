-- Fig.Feed v7 — Lixeira (itens apagados ficam 30 dias) e Biblioteca.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v7_lixeira). Só acrescenta colunas e funções.

-- 1) Marca de "apagado em" nas contas e nos posts (vazio = ativo)
alter table public.accounts add column if not exists deleted_at timestamptz;
alter table public.posts    add column if not exists deleted_at timestamptz;
create index if not exists accounts_deleted_idx on public.accounts (owner_id) where deleted_at is not null;
create index if not exists posts_deleted_idx    on public.posts (owner_id)    where deleted_at is not null;

-- 2) Reordenar o feed passa a ignorar os posts que estão na lixeira
create or replace function public.reorder_posts(p_account uuid, p_ids uuid[])
returns void language plpgsql set search_path = public as $$
declare
  follow boolean;
  dates  date[];
begin
  if not exists (select 1 from public.accounts where id = p_account and owner_id = auth.uid()) then
    raise exception 'Conta não encontrada';
  end if;

  update public.posts p
     set position = t.ord - 1
    from unnest(p_ids) with ordinality as t(id, ord)
   where p.id = t.id and p.account_id = p_account;

  select dates_follow into follow from public.profiles where id = auth.uid();

  if follow then
    select array_agg(publish_date order by publish_date desc) into dates
      from public.posts where account_id = p_account and deleted_at is null and publish_date is not null;

    if coalesce(array_length(dates, 1), 0) =
       (select count(*) from public.posts where account_id = p_account and deleted_at is null) then
      update public.posts p
         set publish_date = dates[p.position + 1]
       where p.account_id = p_account and p.deleted_at is null;
    end if;
  end if;
end $$;

-- 3) Esvaziar a lixeira (tudo, ou só o que passou de 30 dias).
--    Devolve os caminhos das fotos guardadas, para o app apagar os arquivos.
--    Roda com as permissões de quem chama: só alcança os próprios itens.
create or replace function public.empty_my_trash(only_expired boolean default false)
returns setof text language plpgsql security invoker set search_path = public as $$
declare lim timestamptz := case when only_expired then now() - interval '30 days' else 'infinity'::timestamptz end;
begin
  return query
    select s.storage_path from public.slides s join public.posts p on p.id = s.post_id
     where p.owner_id = auth.uid() and s.storage_path not like 'picsum:%'
       and (p.deleted_at < lim
            or p.account_id in (select id from public.accounts where owner_id = auth.uid() and deleted_at < lim))
    union
    select a.avatar_path from public.accounts a
     where a.owner_id = auth.uid() and a.deleted_at < lim and a.avatar_path is not null;

  delete from public.posts    where owner_id = auth.uid() and deleted_at < lim;
  delete from public.accounts where owner_id = auth.uid() and deleted_at < lim;
end $$;
revoke execute on function public.empty_my_trash(boolean) from public, anon;
grant execute on function public.empty_my_trash(boolean) to authenticated;
