-- Fig.Feed v22: capa do post (posição e zoom da 1ª foto na grade, quadro 3:4). A foto não é cortada.
alter table public.posts add column if not exists capa jsonb;
alter table public.posts drop constraint if exists posts_capa_check;
alter table public.posts add constraint posts_capa_check check (capa is null or (jsonb_typeof(capa) = 'object' and pg_column_size(capa) < 600));
comment on column public.posts.capa is 'v22: recorte da capa na grade (quadro 3:4): {p: caminho da 1a foto, x, y: posição em %, z: zoom, r: largura/altura da foto}';
