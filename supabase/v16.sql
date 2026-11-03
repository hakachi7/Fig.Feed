-- Fig.Feed v16 — menus editáveis pelos admins e cores das etiquetas no Cronograma.
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v16_menus_cores). Só acrescenta.
create policy "admins editam menus" on public.app_settings for insert to authenticated
  with check (key = 'menus' and (select public.is_admin()));
create policy "admins atualizam menus" on public.app_settings for update to authenticated
  using (key = 'menus' and (select public.is_admin())) with check (key = 'menus' and (select public.is_admin()));
-- Cor da etiqueta de cada conta (vazio = cor automática)
alter table public.accounts add column if not exists cor text check (cor is null or cor ~ '^#[0-9a-fA-F]{6}$');
-- Cores dos status (rascunho, pronto, agendado, publicado) escolhidas por cada pessoa
alter table public.profiles add column if not exists status_cores jsonb not null default '{}'::jsonb check (jsonb_typeof(status_cores) = 'object');
