-- v26: Testar sem cadastro
-- Visitantes entram como usuários anônimos do Supabase (Authentication › Sign In / Providers › "Allow anonymous sign-ins").
-- Quem não criou a conta em 14 dias é apagado sozinho, com contas, posts e stories (as tabelas apagam em cascata).
-- Fotos que o visitante enviou para o Cloudflare R2 não são apagadas por esta limpeza.

select cron.schedule(
  'limpar-visitantes',
  '20 7 * * *',
  $$ delete from auth.users where is_anonymous is true and created_at < now() - interval '14 days' $$
);
