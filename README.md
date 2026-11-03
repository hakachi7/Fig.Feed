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

## Novidades da v12 — Prévia do perfil

- Toque na foto de perfil da prévia para trocar a foto da conta.
- O painel "Editar perfil" agora se chama só **Perfil** (nome, bio, seguidores e seguindo).
- **Destaques** em círculos, até 8: o círculo **+ Novo** cria um destaque; tocar num destaque abre o painel para trocar o nome (até 15 letras) e a capa — enviando uma foto ou escolhendo uma foto dos posts —, mover para os lados ou remover. As fotos enviadas ficam em `fotos/<usuário>/destaques/` e contam como "em uso" na Biblioteca.
- **Baixar PNG**: a prévia inteira em imagem de 1080 px de largura.

## Novidades da v15 — Páginas e pop-ups

- **Menu do ícone** refeito: fundo de bolinhas (botão "↻ outro fundo"), atalhos grandes numerados (Contas, Cronograma, Downloads, Biblioteca, Lixeira) com informações ao lado, suas contas e os links da conta. Esc fecha.
- **Admin › Páginas**: lista de todas as páginas. Em cada uma dá para trocar o nome (aparece no menu e no topo), o link (o antigo continua funcionando), quem vê (todo mundo, quem tem conta, Pro/Agência, só admins) e ligar/desligar. Entrar, Termos, Privacidade, Perfil, Configuração e Segurança ficam sempre no ar.
- **Página desligada**: quem abrir vê "Estamos trabalhando nessa área" com a página desfocada por trás, a previsão de volta e um botão. Dá para mudar o texto, a data, o botão e ligar sozinha na data. Admins continuam vendo a página, com uma barra avisando que está desligada.
- **Banners** por página: principal (1920 × 640 no computador e 1080 × 1350 no celular), faixa (1440 × 160) e carrossel com até 5 (1200 × 800). Avisa quando a imagem vai cortar. Ficam na pasta pública `blog/banners/`.
- **Modelos de páginas**: Página inicial, Sobre nós, Tabela de preços, Contato, Estamos trabalhando, Lançamento em breve, Perguntas frequentes e Em branco. A página nasce desligada no endereço `/#p/<link>` e é editada com o mesmo editor de blocos do Blog (com o bloco novo "Pergunta").
- **Admin › Pop-ups**: nome, ordem (↑ ↓; se dois puderem aparecer, só o de cima aparece), ligar/desligar, formato (central, canto ou barra no topo), imagem, título, texto, botão, páginas, momento (ao abrir, depois de X segundos, ao rolar, ao tentar sair), quantas vezes, para quem e período. Conta quantas vezes apareceu, os cliques e quantos fecharam.
- Limites: "uma vez por pessoa" é contado por aparelho; "ao tentar sair" não existe no celular; o bloqueio de páginas é feito no navegador (serve para manutenção, não para esconder dados).
- Banco: `supabase/v15.sql` (tabelas `site_pages` e `popups`, funções `popup_event` e `site_page_aviso`).
- v15.1: o fundo do menu voltou a ser a foto desfocada de antes (com o crédito do fotógrafo e o botão "↻ outra foto"); as bolinhas ficaram só no layout.
- v15.2: toda conta nova nasce com uma foto de perfil de bolinhas (o banco sorteia uma das 9 imagens; `avatar_path = 'bolinhas:N'`). Arquivo: `supabase/v15_2.sql`.
- v15.3: em Admin › Páginas, a **Página inicial (landing page)** aparece separada do **Início do app**; a landing pode ter nome, banners, aviso e ser desligada (quem tem conta continua entrando). Admins veem a landing em `/#landing`.
- v15.4: prévia dos pop-ups refeita (tela de mentira com classes próprias, não muda de tamanho em telas grandes); em todo lugar de banner (principal, celular, faixa, carrossel) e na imagem do pop-up há a opção **Aleatório**, que guarda `bolinhas:aleatorio` e sorteia um dos 9 fundos de bolinhas a cada visita.
- v15.5: na **Página inicial (landing page)**, a aba Banners virou **Imagens da página**: troca a foto do meio (até 12, vão alternando) e as 6 imagens de cada uma das 3 grades, com envio ou Aleatório. Fica em `site_pages.banners.land = {hero:[...], grids:[[6],[6],[6]]}`; sem nada salvo, usa as bolinhas de sempre. A landing não mostra mais banners por cima.

## Novidades da v16 — Menus e cores

- **Admin › Menus**: três menus editáveis — Barra do topo, Menu do ícone de grade e Menu de tela cheia. Em cada um dá para mudar a ordem (↑ ↓), tirar (×) e adicionar botões: páginas do site, páginas criadas a partir de modelos ou um link (outro site ou `/#pagina`). Até 10 botões por menu; "Voltar ao padrão" refaz como era. Fica em `app_settings` (chave `menus`); admins e o GM podem salvar. Admin, "Sua conta" e Sair continuam fixos.
- **Cores das etiquetas no Cronograma**: no lado esquerdo, tocar no quadradinho de uma conta ou na bolinha de um status abre uma paleta (14 cores, "Outra" para escolher qualquer cor, e "Cor padrão"). A cor da conta fica em `accounts.cor` e vale nos cartões da semana e do quadro; as cores dos status ficam em `profiles.status_cores` e são de cada pessoa.
- Banco: `supabase/v16.sql`.

## Novidades da v17 — Admin completo 2

- **Visão geral** (primeira aba do Admin): pessoas cadastradas, ativas, sem confirmar e suspensas; quantos em cada plano e em teste; contas, posts, stories e espaço usado; suporte aberto, Instagram com problema e erros; gráfico de cadastros por dia (30 dias). Função `admin_stats`.
- **Planos**: nome, preço, itens, botão, destaque e limites (contas e MB) de cada plano, salvos em `app_settings` (`planos`, só o GM). Com "Aplicar os limites" ligado, o banco não deixa criar conta de cliente além do limite (gatilho `accounts_limit`) e o app avisa antes de enviar fotos além do espaço (`my_storage`). Admins nunca têm limite.
- **Usuários**: "Abrir" mostra plano, cadastro, último acesso, contas, posts e espaço; envia link para trocar a senha; suspende/reativa (`admin_set_suspended`, a pessoa sai em até 1 hora); exclui a conta e as fotos pela função do servidor `admin-users` (`supabase/functions/admin-users`). Botão **Baixar planilha** (CSV para Excel).
- **Textos**: página inicial (frase, botões, 3 quadros), perguntas da Ajuda e textos de Termos e Privacidade (com `##` para títulos e `-` para listas), com contador dos campos [entre colchetes] que faltam.
- **Avisos**: sininho no alto do app, por plano; marca como lido ao abrir. Tabelas `avisos` e `aviso_lidos`.
- **Configurações**: e-mail de contato, Instagram e WhatsApp (no rodapé público) e descrição para o Google. A imagem de compartilhamento no WhatsApp continua no código.
- **Saúde**: erros que as pessoas encontraram (tabela `app_errors`, agrupados) e Instagram com erro ou chave para vencer (`admin_ig_status`).
- Banco: `supabase/v17.sql`.
