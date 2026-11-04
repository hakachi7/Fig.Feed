-- Fig.Feed v18: cadastro completo, indicações, beta do Instagram e liberar espaço

-- ===================== 1) Dados do cadastro =====================
alter table public.profiles
  add column if not exists birth_date date,
  add column if not exists gender text,
  add column if not exists profession text,
  add column if not exists country text,
  add column if not exists state text,
  add column if not exists city text,
  add column if not exists referral_code text unique,
  add column if not exists referred_by uuid references auth.users(id) on delete set null;
grant update (birth_date, gender, profession, country, state, city) on public.profiles to authenticated;

-- código de indicação para quem já tem conta
update public.profiles set referral_code = substr(md5(id::text || random()::text), 1, 8) where referral_code is null;

-- novo usuário: copia os dados do formulário e liga a quem indicou
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb); bd date; ref uuid; code text;
begin
  begin bd := nullif(m->>'birth_date','')::date; exception when others then bd := null; end;
  if bd is not null and (bd > current_date or bd < date '1900-01-01') then bd := null; end if;
  select id into ref from public.profiles where referral_code = nullif(lower(m->>'ref'),'') limit 1;
  loop
    code := substr(md5(new.id::text || random()::text), 1, 8);
    exit when not exists (select 1 from public.profiles where referral_code = code);
  end loop;
  insert into public.profiles (id, name, birth_date, gender, profession, country, state, city, referral_code, referred_by)
  values (new.id, left(coalesce(m->>'name', ''), 120), bd,
          left(nullif(m->>'gender',''), 40), left(nullif(m->>'profession',''), 60),
          left(nullif(m->>'country',''), 2), left(nullif(m->>'state',''), 2), left(nullif(m->>'city',''), 80),
          code, ref);
  return new;
end $$;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- o usuário não pode trocar o próprio código nem quem o indicou
create or replace function public.protect_profile_role()
returns trigger language plpgsql set search_path = public as $$
begin
  if (select auth.uid()) is not null
     and coalesce(current_setting('figfeed.allow_role', true), '') <> 'on' then
    if tg_op = 'INSERT' then
      new.role := 'social_media';
      new.plano := 'gratis'; new.plano_ate := null; new.plano_origem := '';
      new.referred_by := null;
    else
      new.role := old.role;
      new.plano := old.plano; new.plano_ate := old.plano_ate; new.plano_origem := old.plano_origem;
      new.referral_code := old.referral_code; new.referred_by := old.referred_by;
    end if;
  end if;
  return new;
end $$;

-- ===================== 2) Indicações =====================
create or replace function public.my_referrals()
returns table(name text, created_at timestamptz, confirmed boolean)
language sql stable security definer set search_path = public as $$
  select coalesce(nullif(split_part(p.name, ' ', 1), ''), 'Alguém'), p.created_at, u.email_confirmed_at is not null
    from public.profiles p join auth.users u on u.id = p.id
   where p.referred_by = (select auth.uid())
   order by p.created_at desc
$$;
revoke execute on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;

-- ===================== 3) Beta do Instagram =====================
create table if not exists public.beta_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null check (length(name) between 1 and 120),
  email text not null check (length(email) between 3 and 200),
  instagram text not null check (length(instagram) between 2 and 60),
  contato text check (length(contato) <= 120),
  status text not null default 'novo' check (status in ('novo','adicionado','recusado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.beta_requests enable row level security;
create policy "pedir a beta" on public.beta_requests for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'novo');
create policy "ver o próprio pedido" on public.beta_requests for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "admins atualizam pedidos" on public.beta_requests for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admins apagam pedidos" on public.beta_requests for delete to authenticated
  using ((select public.is_admin()));
create index if not exists beta_requests_user on public.beta_requests(user_id);

-- ===================== 4) Liberar espaço =====================
-- Dos caminhos informados, devolve só os que nada mais usa (para apagar os arquivos)
create or replace function public._paths_sem_uso(cands text[])
returns setof text language sql stable security definer set search_path = public as $$
  select distinct c from unnest(cands) c
   where c is not null and c not like 'picsum:%' and c like (select auth.uid())::text || '/%'
     and not exists (select 1 from public.slides s where s.storage_path = c)
     and not exists (select 1 from public.stories s where s.storage_path = c)
     and not exists (select 1 from public.accounts a where a.avatar_path = c)
     and not exists (select 1 from public.accounts a where a.highlights @> jsonb_build_array(jsonb_build_object('path', c)))
     and not exists (select 1 from public.profiles p where p.avatar_path = c)
     and not exists (select 1 from public.ig_media m where m.thumb_url = c)
$$;
revoke execute on function public._paths_sem_uso(text[]) from public, anon, authenticated;

-- Todos os arquivos ligados a estas contas (e a estes posts)
create or replace function public._paths_de(acc_ids uuid[], post_ids uuid[])
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(p), '{}') from (
    select s.storage_path p from public.slides s join public.posts po on po.id = s.post_id
     where po.owner_id = (select auth.uid()) and (po.account_id = any(acc_ids) or po.id = any(post_ids))
    union select st.storage_path from public.stories st where st.owner_id = (select auth.uid()) and st.account_id = any(acc_ids)
    union select a.avatar_path from public.accounts a where a.owner_id = (select auth.uid()) and a.id = any(acc_ids)
    union select h->>'path' from public.accounts a, jsonb_array_elements(case when jsonb_typeof(a.highlights) = 'array' then a.highlights else '[]'::jsonb end) h
     where a.owner_id = (select auth.uid()) and a.id = any(acc_ids) and jsonb_typeof(h) = 'object'
    union select m.thumb_url from public.ig_media m join public.accounts a on a.id = m.account_id
     where a.owner_id = (select auth.uid()) and a.id = any(acc_ids)
  ) x
$$;
revoke execute on function public._paths_de(uuid[], uuid[]) from public, anon, authenticated;

-- Esvaziar a lixeira (agora também apaga stories, destaques e miniaturas do Instagram)
create or replace function public.empty_my_trash(only_expired boolean default false)
returns setof text language plpgsql security definer set search_path = public as $$
declare lim timestamptz := case when only_expired then now() - interval '30 days' else 'infinity'::timestamptz end;
  accs uuid[]; psts uuid[]; cands text[];
begin
  if (select auth.uid()) is null then return; end if;
  select coalesce(array_agg(id), '{}') into accs from public.accounts where owner_id = (select auth.uid()) and deleted_at < lim;
  select coalesce(array_agg(id), '{}') into psts from public.posts where owner_id = (select auth.uid()) and deleted_at < lim;
  cands := public._paths_de(accs, psts);
  delete from public.posts    where owner_id = (select auth.uid()) and id = any(psts);
  delete from public.accounts where owner_id = (select auth.uid()) and id = any(accs);
  return query select public._paths_sem_uso(cands);
end $$;
revoke execute on function public.empty_my_trash(boolean) from public, anon;
grant execute on function public.empty_my_trash(boolean) to authenticated;

-- Excluir contas (feeds) para sempre, sem passar pela lixeira
create or replace function public.delete_accounts_now(acc_ids uuid[])
returns setof text language plpgsql security definer set search_path = public as $$
declare accs uuid[]; cands text[];
begin
  if (select auth.uid()) is null then return; end if;
  select coalesce(array_agg(id), '{}') into accs from public.accounts where owner_id = (select auth.uid()) and id = any(acc_ids);
  cands := public._paths_de(accs, '{}');
  delete from public.accounts where owner_id = (select auth.uid()) and id = any(accs);
  return query select public._paths_sem_uso(cands);
end $$;
revoke execute on function public.delete_accounts_now(uuid[]) from public, anon;
grant execute on function public.delete_accounts_now(uuid[]) to authenticated;

-- Espaço: quanto uso, quanto ocupa a lixeira e o limite do plano (mesmo com os limites desligados)
create or replace function public.my_storage()
returns json language sql stable security definer set search_path = public, storage as $$
  with f as (select name, coalesce((metadata->>'size')::bigint, 0) sz from storage.objects
              where bucket_id = 'fotos' and (storage.foldername(name))[1] = (select auth.uid())::text),
  lix as (select unnest(public._paths_de(
            (select coalesce(array_agg(id), '{}') from public.accounts where owner_id = (select auth.uid()) and deleted_at is not null),
            (select coalesce(array_agg(id), '{}') from public.posts where owner_id = (select auth.uid()) and deleted_at is not null))) p)
  select json_build_object(
    'usado', (select coalesce(sum(sz), 0) from f),
    'lixeira', (select coalesce(sum(sz), 0) from f where name in (select p from lix)),
    'limite_mb', public.limite_do_plano((select auth.uid()), 'mb'),
    'plano', public.plano_de((select auth.uid())),
    'ativos', coalesce((select (value->>'limites_ativos')::boolean from public.app_settings where key = 'planos'), false))
$$;
revoke execute on function public.my_storage() from public, anon;
grant execute on function public.my_storage() to authenticated;
