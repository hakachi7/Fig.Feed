# Versões do Fig.Feed

A versão no ar é sempre a da branch **main**: https://hakachi7.github.io/Fig.Feed/

Cada versão também tem uma branch própria, com o código exatamente como estava naquela versão. Elas servem só para consulta: o site não muda por causa delas.

| Versão | Nome | O que trouxe | Branch | Commit |
| --- | --- | --- | --- | --- |
| v22 | Editar capa | Pop-up "Editar capa" (arrastar, zoom, pinça, rodinha) para a capa do post na grade 3:4, sem cortar a foto; vale no Feed, Prévia, Feed On, PNGs e PDF; coluna posts.capa (supabase/v22.sql) | [versao-22-editar-capa](https://github.com/hakachi7/Fig.Feed/tree/versao-22-editar-capa) | fd228f6 |
| v21.1 | Envio mais rápido | Até 4 fotos sobem ao mesmo tempo (feed, post, stories, Biblioteca); a função fotos faz menos consultas por foto | [versao-21-fotos-r2](https://github.com/hakachi7/Fig.Feed/tree/versao-21-fotos-r2) | (veja a branch) |
| v21 | Fotos no R2 | Fotos do app e miniaturas do Instagram passam a ficar no Cloudflare R2 (10 GB grátis, tráfego grátis); envio e exclusão pela Edge Function `fotos` (supabase/functions/fotos), espaço medido pela tabela fotos_r2 (supabase/v21.sql); Admin › Visão geral mostra o R2 | [versao-21-fotos-r2](https://github.com/hakachi7/Fig.Feed/tree/versao-21-fotos-r2) | (veja a branch) |
| v20.1 | Quadro verde | Quadro de constância do Perfil em tons de verde (estilo GitHub); agendados com contorno verde | [versao-20-1-quadro-verde](https://github.com/hakachi7/Fig.Feed/tree/versao-20-1-quadro-verde) |
| v20 | Créditos e dados demográficos | Página #creditos (rodapé do menu: "Fig.Feed v20 · Créditos", sem a palavra Novidades); Admin › Usuários › Abrir mostra nascimento/idade, gênero, profissão, país, cidade/estado e indicações (função admin_user_demo, supabase/v20.sql) | [versao-20-creditos](https://github.com/hakachi7/Fig.Feed/tree/versao-20-creditos) |
| v19.3 | Chave do Feed On | Feed On busca sempre com o Instagram do Fig.Feed (nunca com a conexão de um usuário); botão "Conectar o Instagram do Fig.Feed" em Admin › Beta; a 1ª conexão de um admin vira a chave sozinha | [versao-19-3-chave-feed-on](https://github.com/hakachi7/Fig.Feed/tree/versao-19-3-chave-feed-on) |
| v19.2 | Feed On só com o link | Quem não tem Instagram conectado usa a conta do Fig.Feed (Admin › Beta); a mensagem não pede mais para conectar | [versao-19-2-feed-on-link](https://github.com/hakachi7/Fig.Feed/tree/versao-19-2-feed-on-link) |
| v19.1 | Ordem de publicação | Na grade com datas e tipo, o número em cada foto passa a ser a ordem de publicação (1 = o primeiro a postar) | [versao-19-1-ordem-publicacao](https://github.com/hakachi7/Fig.Feed/tree/versao-19-1-ordem-publicacao) |
| v19 | Feed On | Na Prévia, o feed que está no ar no Instagram (pelo link ou @ de um perfil profissional), travado; Com planejamento; Antes × depois no computador; Baixar PNG | [versao-19-feed-on](https://github.com/hakachi7/Fig.Feed/tree/versao-19-feed-on) | (veja a branch) |
| v18.2 | Servidor na Visão geral | Admin › Visão geral mostra o uso do Supabase (fotos, banco, pessoas ativas, quantos usuários do Grátis cabem, fotos para otimizar) e avisa quando um plano promete mais espaço do que existe | [versao-18-cadastro-espaco-indicacoes](https://github.com/hakachi7/Fig.Feed/tree/versao-18-cadastro-espaco-indicacoes) | (veja a branch) |
| v18.1 | Fotos menores e limites | Fotos reduzidas no envio (1080 px, ~300 KB), Otimizar fotos já enviadas, plano Grátis com 3 contas e 15 MB e limites ligados (também no servidor), barra de espaço em Admin › Usuários | [versao-18-cadastro-espaco-indicacoes](https://github.com/hakachi7/Fig.Feed/tree/versao-18-cadastro-espaco-indicacoes) | (veja a branch) |
| v18 | Cadastro, espaço e indicações | Cadastro em 2 passos com mais dados, círculo de espaço e Liberar espaço, plano Grátis com 3 contas, grade com datas e tipo, indique amigos, formulário da beta | [versao-18-cadastro-espaco-indicacoes](https://github.com/hakachi7/Fig.Feed/tree/versao-18-cadastro-espaco-indicacoes) | (veja a branch) |
| v17.2 | Feed de uma vez | “+ Criar → Adicionar posts” importa várias fotos e cada uma vira um post; conta nova com “Monte seu primeiro feed” e feed de exemplo; botão Salvar na página do post | (main) | (veja a main) |
| v17.1 | Conectar Instagram | Login unificado da Meta (Instagram ou Facebook, conexão que não vence), mensagens prontas para o cliente (WhatsApp, e-mail, lembrete, reconectar), passo a passo e dúvidas na página do cliente, erros mais claros | (main) | (veja a main) |
| v17 | Admin completo 2 | Visão geral, Planos editáveis com limites, ações sobre usuários, Textos do site, Avisos (sininho), Configurações, Saúde e planilha de usuários | [versao-17-admin-completo-2](https://github.com/hakachi7/Fig.Feed/tree/versao-17-admin-completo-2) | (veja a branch) |
| v16 | Menus e cores | Admin › Menus (ordem, tirar e adicionar botões nos 3 menus) e cores das etiquetas de contas e status no Cronograma | [versao-16-menus-e-cores](https://github.com/hakachi7/Fig.Feed/tree/versao-16-menus-e-cores) | (veja a branch) |
| v15.5 | Imagens da landing | A landing troca as próprias imagens (foto do meio e 3 grades) em vez de ganhar banners por cima | (main) | (veja a main) |
| v15.4 | Prévia e aleatório | Prévia dos pop-ups corrigida; opção de banner/imagem aleatória com fundos de bolinhas | (main) | (veja a main) |
| v15.3 | Landing na lista | A página inicial (landing page) aparece em Admin › Páginas, separada do Início do app | (main) | (veja a main) |
| v15.2 | Foto de perfil inicial | Toda conta nova nasce com uma foto de perfil de bolinhas (uma das 9, sorteada) | (main) | (veja a main) |
| v15.1 | Fundo do menu | Menu do ícone volta para a foto desfocada de antes (com crédito); o layout novo continua | (main) | (veja a main) |
| v15 | Páginas e pop-ups | Menu novo com fundo de bolinhas; Admin › Páginas (nome, link, quem vê, ligar/desligar com aviso desfocado, banners, modelos de páginas) e Admin › Pop-ups | [versao-15-paginas-e-popups](https://github.com/hakachi7/Fig.Feed/tree/versao-15-paginas-e-popups) | (veja a branch) |
| v14 | Resultados do Instagram | Aba Resultados com os números do Instagram (API da Meta), link para o cliente conectar, coleta automática diária e PDFs Resultados e Completo | [versao-14-resultados-instagram](https://github.com/hakachi7/Fig.Feed/tree/versao-14-resultados-instagram) | (veja a branch) |
| v13 | Apagar e planejamento novo | Apagar vários posts no modo Selecionar, tutorial com Selecionar e Planejamento, PDF do planejamento com capa, Mood do feed e Mood dos stories | [versao-13-apagar-e-planejamento](https://github.com/hakachi7/Fig.Feed/tree/versao-13-apagar-e-planejamento) | (veja a branch) |
| v12 | Prévia do perfil | Trocar a foto de perfil na prévia, destaques em círculos com “+ Novo” (nome e capa fáceis de trocar) e baixar a prévia em PNG | [versao-12-previa-do-perfil](https://github.com/hakachi7/Fig.Feed/tree/versao-12-previa-do-perfil) | (veja a branch) |
| v11 | Selecionar e exportar | No feed da conta: botão Selecionar, marcar posts com ✓ e exportar só eles em fotos (.zip), grade (PNG) ou legendas (.txt) | [versao-11-selecionar-e-exportar](https://github.com/hakachi7/Fig.Feed/tree/versao-11-selecionar-e-exportar) | (veja a branch) |
| v10 | Admin completo | Templates de feed, Blog, Fale com a gente (suporte) e Assinaturas com planos, testes grátis e cupons | [versao-10-admin-completo](https://github.com/hakachi7/Fig.Feed/tree/versao-10-admin-completo) | (veja a branch) |
| v9 | Planejamento | PDF do planejamento do mês para o cliente aprovar; objetivo, pilares, formato com Reels, horário, chamada e tipo de story | [versao-9-planejamento](https://github.com/hakachi7/Fig.Feed/tree/versao-9-planejamento) | (veja a branch) |
| v8 | Conteúdo do cliente | Abas Feed, Stories, Prévia e Relatório em cada conta; relatório com PDF e link de 30 dias | [versao-8-stories-previa-relatorio](https://github.com/hakachi7/Fig.Feed/tree/versao-8-stories-previa-relatorio) | [461a3c1](https://github.com/hakachi7/Fig.Feed/commit/461a3c14a1cc698f5caac5ef79803aba529816c0) |
| v7 | Organização | Lixeira de 30 dias, Biblioteca de fotos, página inicial pública, Planos | [versao-7-lixeira-e-biblioteca](https://github.com/hakachi7/Fig.Feed/tree/versao-7-lixeira-e-biblioteca) | [621cc5e](https://github.com/hakachi7/Fig.Feed/commit/621cc5e2ab29943b7b667715e8b19ee46979bf14) |
| v6 | Conta e avisos | 404 nova, sem internet, erro, modo atualização; Segurança, Excluir conta, Ajuda, Novidades, Termos, Privacidade | [versao-6-conta-e-avisos](https://github.com/hakachi7/Fig.Feed/tree/versao-6-conta-e-avisos) | [879476f](https://github.com/hakachi7/Fig.Feed/commit/879476f9ac07ff7413a8e674d987721bd9eb1ce9) |
| v5 | Administração | Aba Admin para GM e administradores: usuários, funções e atividade | [versao-5-admin](https://github.com/hakachi7/Fig.Feed/tree/versao-5-admin) | [8266c17](https://github.com/hakachi7/Fig.Feed/commit/8266c17ddb5f1ad2597934b1e820591424478721) |
| v4 | Primeiro acesso | Login revisado, e-mail confirmado, tutorial de boas-vindas, tela de carregamento | [versao-4-login-e-tutorial](https://github.com/hakachi7/Fig.Feed/tree/versao-4-login-e-tutorial) | [7de9158](https://github.com/hakachi7/Fig.Feed/commit/7de915820bdc668716c722b9f20e0d8f03f70b6c) |
| v3 | Navegação | Menu no ícone de grade, página 404, aviso de sem internet | [versao-3-menu-e-404](https://github.com/hakachi7/Fig.Feed/tree/versao-3-menu-e-404) | [6d69443](https://github.com/hakachi7/Fig.Feed/commit/6d6944392256c494bd21297003b1b95d7842f3d1) |
| v2 | Nuvem | Login, dados no Supabase, carrossel, cronograma, download, app instalável | [versao-1-e-2-prototipo-e-nuvem](https://github.com/hakachi7/Fig.Feed/tree/versao-1-e-2-prototipo-e-nuvem) | [9e684e6](https://github.com/hakachi7/Fig.Feed/commit/9e684e6140829d1a2b9d809384b49987d4053cca) |
| v1 | Protótipo | Feed com arrastar e soltar, salvo só no navegador (arquivo `prototipo-v1.html`) | [versao-1-e-2-prototipo-e-nuvem](https://github.com/hakachi7/Fig.Feed/tree/versao-1-e-2-prototipo-e-nuvem) | [9e684e6](https://github.com/hakachi7/Fig.Feed/commit/9e684e6140829d1a2b9d809384b49987d4053cca) |

A v1 e a v2 foram enviadas juntas, por isso dividem a mesma branch.

## Banco de dados de cada versão

As mudanças do Supabase ficam na pasta `supabase/`: `schema.sql` (v2), `admin.sql` (v5), `v6.sql`, `v7.sql`, `v8.sql`, `v9.sql` e `v10.sql`. Todas já estão aplicadas no projeto Fig-Free.

## Ao lançar uma versão nova

1. Subir `VERSAO` no `index.html` e o `CACHE` no `sw.js`.
2. Acrescentar a versão no topo da lista `NOVIDADES` (no `index.html`) e nesta tabela.
3. Criar a branch da versão: `versao-10-<nome-curto>`.
