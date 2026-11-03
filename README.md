# Fig.Feed

Aplicação web para social medias montarem e organizarem feeds, carrosséis e cronogramas de forma visual: arraste um post e a grade se reorganiza sozinha, como o auto layout do Figma.

## Versões

A lista de todas as versões, com o código de cada uma, está em [VERSOES.md](VERSOES.md).

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


## Novidades da v6

- Telas novas: página não encontrada (404), sem internet, erro ("Ops.") e em atualização.
- Páginas da conta: Segurança (trocar e-mail e senha, aparelhos conectados) e Excluir minha conta.
- Páginas Ajuda, Novidades, Termos de uso e Política de privacidade (abrem também sem login).
- Modo atualização: o GM liga em Configuração. Só GM e admins continuam entrando.
- Banco: `supabase/v6.sql` (já aplicado no Fig-Free).

## Novidades da v7

- Lixeira: posts e contas apagados ficam 30 dias e podem ser restaurados (depois somem sozinhos).
- Biblioteca: todas as fotos enviadas, espaço usado, filtro por conta e "Sem uso"; dá para usar uma foto num post novo.
- Página inicial para quem ainda não tem conta, com rodapé (Termos, Privacidade, Ajuda, Planos).
- Página de Planos (só a tela; a cobrança ainda não está ligada).
- Banco: `supabase/v7.sql` (já aplicado no Fig-Free).

## Novidades da v8

- Cada conta ganhou abas: Feed, Stories, Prévia e Relatório.
- Stories: escolha o dia, envie as artes (ou use exemplos), destaque e arraste para ordenar.
- Prévia estilo Instagram, com nome, bio, seguidores, seguindo e destaques (editáveis só para a prévia).
- Relatório do mês: números, gráfico por semana, feed do mês, Baixar PDF e Copiar link (o cliente abre sem login por 30 dias).
- Banco: `supabase/v8.sql` (já aplicado no Fig-Free).

## Novidades da v9

- Planejamento do mês em PDF (Downloads → Baixar planejamento): visão do mês com objetivo e pilares, calendário, posts e legendas com chamada, stories e espaço para a aprovação do cliente.
- No painel do post: formato (foto, carrossel ou Reels), horário, pilar e chamada para ação.
- Tipo de cada story: imagem, vídeo, enquete, caixinha, link ou contagem regressiva.
- Banco: `supabase/v9.sql` (já aplicado no Fig-Free).

## Novidades da v10 — Admin completo

- **Templates:** o admin monta grades prontas (Foto, Texto ou Vazio em cada quadrado, formato 4:5, 1:1 ou 9:16) e escolhe quem pode usar. O usuário aplica numa conta em "+ Criar → Usar um template" e os posts entram no topo do feed como rascunho.
- **Blog:** editor por blocos (título, texto, foto, galeria, GIF, vídeo do YouTube/Vimeo, link, botão com link, citação, divisor e espaço), com capa, rascunho, agendamento, lixeira e opção de aparecer em Novidades. Páginas públicas em `#blog`.
- **Suporte:** o usuário abre um pedido em Ajuda → "Fale com a gente" e vê as respostas no app; o admin responde, usa respostas prontas e marca como resolvido.
- **Assinaturas:** plano de cada pessoa (Grátis, Pro, Agência), com ou sem prazo, testes grátis e cupons. O usuário vê o próprio plano e usa cupons na página Planos. A cobrança automática e os limites dos planos ainda não estão ligados.
- Banco: `supabase/v10.sql` (já aplicado).

## Novidades da v11 — Selecionar e exportar

- No feed de uma conta, o botão **Selecionar** mostra um círculo em cada post. Marque os que quiser (ou "Selecionar todos"); arrastar fica pausado enquanto seleciona. Esc ou "Cancelar" saem do modo.
- A barra de baixo exporta só os selecionados: **Fotos (.zip)** com uma pasta por post (fotos + legenda) e um `legendas.txt` geral, **Grade (PNG)** e **Legendas (.txt)**.
- O .zip é montado no próprio navegador com a biblioteca JSZip (carregada só na hora de exportar).

