-- v25: mapa de usuários na Visão geral do Admin (só números agrupados, nada de nome ou e-mail)
create or replace function public.admin_geo()
returns json language plpgsql stable security definer
set search_path to 'public','auth'
as $$
declare r json;
begin
  if not public.is_admin() then raise exception 'Só administradores podem ver o mapa'; end if;
  select coalesce(json_agg(x), '[]'::json) into r from (
    select coalesce(nullif(p.country,''),'') c, coalesce(nullif(p.state,''),'') s, coalesce(nullif(trim(p.city),''),'') ci,
           count(*) n,
           count(*) filter (where u.last_sign_in_at >= date_trunc('month', now())) a,
           count(*) filter (where p.plano in ('pro','agencia') and p.plano_ate is null) p
    from auth.users u left join public.profiles p on p.id = u.id
    group by 1,2,3) x;
  return r;
end $$;
revoke all on function public.admin_geo() from public, anon;
grant execute on function public.admin_geo() to authenticated;
