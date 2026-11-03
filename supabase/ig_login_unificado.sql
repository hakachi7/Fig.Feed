-- Instagram com login unificado (03/11/2026): primeira coleta completa numa chamada própria,
-- para o Supabase não cortar o robô no meio. Usado pela Edge Function instagram logo após conectar.
create or replace function public.ig_sync_now(p_account uuid, p_full boolean default false)
returns void language plpgsql security definer set search_path to 'public' as $$
declare s text;
begin
  select value into s from ig_settings where key = 'cron_secret';
  perform net.http_post(
    url := 'https://ftffxxugvzijkcfprgiv.supabase.co/functions/v1/instagram',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret', s),
    body := jsonb_build_object('action','cron_sync','account_id', p_account, 'full', p_full),
    timeout_milliseconds := 150000);
end $$;
revoke all on function public.ig_sync_now(uuid, boolean) from public, anon, authenticated;
grant execute on function public.ig_sync_now(uuid, boolean) to service_role;
