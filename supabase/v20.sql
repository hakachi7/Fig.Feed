-- Fig.Feed v20: dados demográficos do usuário no Admin › Usuários › Abrir
create or replace function public.admin_user_demo(target uuid)
returns json language sql stable security definer set search_path = public as $$
  select case when not (select public.is_admin()) then null else (
    select json_build_object(
      'birth_date', p.birth_date,
      'idade', case when p.birth_date is null then null else extract(year from age(current_date, p.birth_date))::int end,
      'gender', p.gender, 'profession', p.profession,
      'country', p.country, 'state', p.state, 'city', p.city,
      'indicado_por', (select coalesce(nullif(r.name,''), 'Alguém') from public.profiles r where r.id = p.referred_by),
      'indicou', (select count(*) from public.profiles x where x.referred_by = p.id))
    from public.profiles p where p.id = target) end
$$;
revoke execute on function public.admin_user_demo(uuid) from public, anon;
grant execute on function public.admin_user_demo(uuid) to authenticated;
