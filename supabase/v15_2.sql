-- Fig.Feed v15.2 — cada conta nova já nasce com uma foto de perfil de bolinhas (uma das 9 imagens img/tutorial/bolinhas-N.jpg do site).
-- Já aplicado no projeto Supabase "Fig-Free" (migração figfeed_v15_2_avatar_bolinhas).
-- O app entende avatar_path = 'bolinhas:N' como imagem do próprio site (não fica no Storage). A pessoa pode trocar pela própria foto quando quiser.
alter table public.profiles alter column avatar_path set default ('bolinhas:' || (1 + floor(random() * 9))::int);
