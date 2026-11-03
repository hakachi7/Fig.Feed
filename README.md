# Fig.Feed

Aplicação web para social medias montarem e organizarem feeds, carrosséis e cronogramas de forma visual: arraste um post e a grade se reorganiza sozinha, como o auto layout do Figma.

## Arquivos

- `index.html` — o app (v5): login, contas, feed, carrossel, legenda, painel do post, cronograma (semana e quadro), perfil com quadro de constância e download. Salva tudo no Supabase.
- `404.html` — página que aparece quando alguém abre um link errado do site.
- `manifest.webmanifest`, `sw.js` e `icons/` — deixam o Fig.Feed instalável no celular como app.
- `supabase/schema.sql` — estrutura do banco de dados (tabelas, segurança e funções).
- `supabase/admin.sql` — funções de usuário (GM, admin, social media, cliente), convites e registro de atividades (v5).
- `prototipo-v1.html` — primeiro protótipo (salva só no navegador).
- `prototipo-v2-local.html` — protótipo com os layouts do Figma (salva só no navegador).

## Como abrir

Abra o `index.html` no navegador, crie uma conta e entre. As fotos de exemplo vêm do Unsplash (via Lorem Picsum).

## Novidades da v3

- O ícone de grade no topo agora abre um menu: Início, Contas, Cronograma, Downloads, atalhos para suas contas, Perfil, Configuração e Sair.
- Página "não encontrada" (404) dentro do app e no site, para links errados ou posts e contas excluídos.
- Aviso quando a internet cai, para você saber que as mudanças podem não ser salvas.

## Novidades da v4

- Login revisado: aviso para reenviar o e-mail de confirmação, "repita a senha" ao criar uma senha nova e mensagem clara quando o link do e-mail expira.
- Depois de clicar no link de confirmação do e-mail, abre a tela "E-mail confirmado".
- Tutorial de boas-vindas (3 passos) na primeira vez que a pessoa entra. Dá para rever em Configuração.
- Nova tela de carregamento: "Montando seu feed…".

## Novidades da v5

- Aba **Admin**, que só aparece para quem é GM ou administrador (no celular, fica no menu do ícone de grade).
- **Usuários e funções:** lista de quem usa o Fig.Feed, com e-mail, função e último acesso. Dá para mudar a função de alguém ou dar uma função por e-mail — se a pessoa ainda não tem conta, vale quando ela se cadastrar.
- Regras: só o GM cria ou remove administradores; admins mexem só em social media e clientes; o GM não consegue tirar o próprio acesso; ninguém muda a própria função.
- **Atividade:** registro de tudo que os administradores fazem, separado por dia e por tipo, com download em planilha (.csv). Não pode ser editado nem apagado.
- Templates, Blog, Suporte e Assinaturas aparecem como "em breve".

