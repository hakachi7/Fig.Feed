// Fig.Feed — conexão com o Instagram (API do Instagram com LOGIN UNIFICADO — apps Meta criados a partir de out/2026)
// O cliente entra com o Instagram OU com o Facebook. A chave (token de usuário do sistema da empresa) não vence.
// Rotas:
//   GET  ?go=<link>            → abre o login da Meta para aquele link de conexão
//   GET  ?code=…&state=<link>  → volta da Meta: guarda a chave e busca os números
//   POST {action:'sync', account_id}       → "Atualizar agora" (usuário logado, dono da conta)
//   POST {action:'disconnect', account_id} → desconectar (usuário logado, dono da conta)
//   POST {action:'cron_sync'|'cron_stories', account_id, full?} + header x-cron-secret → agendamento
//   POST {action:'feedon', account_id, username} → Feed On: feed público de um perfil profissional (Business Discovery)
//   POST {action:'feedon_viewer', account_id} → admin escolhe a conta do Fig.Feed (a chave que busca perfis para todo mundo)
// Segredos: IG_APP_ID (= ID do app da Meta), IG_APP_SECRET (= chave secreta do app da Meta), IG_CONFIG_ID (opcional)
// A configuração de login precisa de instagram_basic, instagram_manage_insights e business_management.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const APP_ID = Deno.env.get("IG_APP_ID") ?? "";
const APP_SECRET = Deno.env.get("IG_APP_SECRET") ?? "";
const CONFIG_ID = Deno.env.get("IG_CONFIG_ID") ?? "1136611732178374";
const SITE = Deno.env.get("SITE_URL") ?? "https://hakachi7.github.io/Fig.Feed/";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SELF = `${SB_URL}/functions/v1/instagram`;
const GV = "v26.0";
const G = `https://graph.facebook.com/${GV}`;
const db = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const back = (hash: string) => new Response(null, { status: 302, headers: { Location: `${SITE}#${hash}` } });

class IgError extends Error { constructor(public code: number, msg: string) { super(msg); } }
async function ig(path: string, token: string, params: Record<string, string> = {}) {
  const u = new URL(path.startsWith("http") ? path : G + path);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  u.searchParams.set("access_token", token);
  const r = await fetch(u);
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) throw new IgError(j?.error?.code ?? r.status, j?.error?.message ?? `HTTP ${r.status}`);
  return j;
}
const ins = (data: any[]) => {
  const o: Record<string, number> = {};
  for (const m of data ?? []) {
    if (m.total_value?.breakdowns?.length) {
      for (const r of m.total_value.breakdowns[0].results ?? []) o[`${m.name}:${r.dimension_values?.[0]}`] = r.value;
    } else o[m.name] = m.total_value?.value ?? m.values?.[0]?.value ?? 0;
  }
  return o;
};
const PROFILE_FIELDS = "id,username,name,profile_picture_url,followers_count,media_count";

// ---------- Coleta ----------
// v21: miniaturas vão para o Cloudflare R2 (mesmo lugar das fotos do app)
const R2E = (k: string) => (Deno.env.get(k) ?? "").trim();
const r2 = new AwsClient({ accessKeyId: R2E("R2_ACCESS_KEY_ID"), secretAccessKey: R2E("R2_SECRET_ACCESS_KEY"), service: "s3", region: "auto" });
const r2Url = (k: string) => `https://${R2E("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com/${R2E("R2_BUCKET") || "figfeed-fotos"}/${k.split("/").map(encodeURIComponent).join("/")}`;
async function saveThumb(owner: string, mediaId: string, url?: string) {
  if (!url) return null;
  const path = `${owner}/instagram/${mediaId}.jpg`;
  try {
    const r = await fetch(url); if (!r.ok) return null;
    const blob = await r.blob();
    const p = await r2.fetch(r2Url(path), { method: "PUT", body: blob, headers: { "Content-Type": r.headers.get("content-type") ?? "image/jpeg", "Cache-Control": "public, max-age=31536000" } });
    if (!p.ok) { console.error(`[thumb] R2 ${p.status}`); return null; }
    const { error } = await db.from("fotos_r2").upsert({ name: path, owner_id: owner, size: blob.size });
    return error ? null : path;
  } catch { return null; }
}
const kindOf = (m: any) => m.media_product_type === "STORY" ? "story" : m.media_product_type === "REELS" ? "reels" : m.media_type === "CAROUSEL_ALBUM" ? "carrossel" : "foto";
const METRICS: Record<string, string[]> = {
  foto: ["views", "reach", "likes", "comments", "saved", "shares", "follows", "total_interactions", "profile_visits"],
  carrossel: ["views", "reach", "likes", "comments", "saved", "shares", "follows", "total_interactions", "profile_visits"],
  reels: ["views", "reach", "likes", "comments", "saved", "shares", "total_interactions"],
  story: ["views", "reach", "replies", "shares", "follows", "profile_visits", "navigation", "total_interactions"],
};
async function mediaInsights(id: string, kind: string, token: string) {
  try { return ins((await ig(`/${id}/insights`, token, { metric: METRICS[kind].join(",") })).data); }
  catch (e) {
    if (e instanceof IgError && e.code === 190) throw e;
    try { return ins((await ig(`/${id}/insights`, token, { metric: "reach,views" })).data); } catch { return {}; }
  }
}
// v23: stories — o que as pessoas fizeram (avançou, voltou, saiu, foi para outro perfil) e cliques no link
async function storyExtra(id: string, token: string) {
  const o: Record<string, number> = {};
  try {
    const r = await ig(`/${id}/insights`, token, { metric: "navigation", breakdown: "story_navigation_action_type" });
    for (const b of r.data?.[0]?.total_value?.breakdowns?.[0]?.results ?? []) o[String(b.dimension_values?.[0] ?? "").toLowerCase()] = b.value;
  } catch (e) { if (e instanceof IgError && e.code === 190) throw e; }
  try {
    const v = ins((await ig(`/${id}/insights`, token, { metric: "link_clicks" })).data);
    if (v.link_clicks != null) o.link_clicks = v.link_clicks;
  } catch (e) { if (e instanceof IgError && e.code === 190) throw e; }
  return o;
}
async function upsertMedia(acc: any, m: any, token: string, haveThumb: Set<string>) {
  const kind = kindOf(m);
  const v = await mediaInsights(m.id, kind, token);
  const row: any = {
    media_id: m.id, account_id: acc.account_id, ts: m.timestamp, kind,
    caption: m.caption ?? null, permalink: m.permalink ?? null,
    views: v.views ?? null, reach: v.reach ?? null, likes: v.likes ?? m.like_count ?? null, comments: v.comments ?? m.comments_count ?? null,
    saved: v.saved ?? null, shares: v.shares ?? null, follows: v.follows ?? null, total_interactions: v.total_interactions ?? null,
    replies: v.replies ?? null, profile_visits: v.profile_visits ?? null, navigation: v.navigation ?? null, updated_at: new Date().toISOString(),
  };
  if (kind === "story") {
    const x = await storyExtra(m.id, token);
    const NAV: Record<string, string> = { tap_forward: "nav_forward", tap_back: "nav_back", tap_exit: "nav_exit", swipe_forward: "nav_next" };
    for (const [k, col] of Object.entries(NAV)) if (x[k] != null) row[col] = x[k];
    if (Object.keys(x).some((k) => NAV[k])) for (const col of Object.values(NAV)) row[col] ??= 0;
    if (x.link_clicks != null) row.link_clicks = x.link_clicks;
  }
  if (kind === "carrossel" && Array.isArray(m.children?.data)) row.slides = m.children.data.length;
  if (!haveThumb.has(m.id)) {
    const p = await saveThumb(acc.owner_id, m.id, m.thumbnail_url ?? m.media_url);
    if (p) row.thumb_url = p;
  }
  await db.from("ig_media").upsert(row);
}
const day = (d: Date) => d.toISOString().slice(0, 10);

async function syncAccount(accountId: string, opts: { full?: boolean; storiesOnly?: boolean } = {}) {
  const { data: acc } = await db.from("ig_connections").select("*").eq("account_id", accountId).maybeSingle();
  const { data: tk } = await db.from("ig_tokens").select("*").eq("account_id", accountId).maybeSingle();
  if (!acc || !tk) return { ok: false, motivo: "sem conexão" };
  const token = tk.access_token as string; // login unificado: a chave não vence, não precisa renovar
  try {
    const { data: thumbs } = await db.from("ig_media").select("media_id").eq("account_id", accountId).not("thumb_url", "is", null);
    const have = new Set((thumbs ?? []).map((t: any) => t.media_id));
    const fields = "id,caption,media_type,media_product_type,permalink,timestamp,thumbnail_url,media_url,like_count,comments_count,children{id}";

    // stories: só ficam disponíveis por 24 h
    const st = await ig(`/${acc.ig_user_id}/stories`, token, { fields: fields.replace(",children{id}", "") }).catch((e) => { if (e.code === 190) throw e; return { data: [] }; });
    for (const m of st.data ?? []) await upsertMedia(acc, { ...m, media_product_type: "STORY" }, token, have);
    if (opts.storiesOnly) { await db.from("ig_connections").update({ status: "ok", status_msg: null }).eq("account_id", accountId); return { ok: true }; }

    // perfil
    const me = await ig(`/${acc.ig_user_id}`, token, { fields: PROFILE_FIELDS });
    await db.from("ig_connections").update({
      username: me.username, name: me.name ?? null, profile_picture_url: me.profile_picture_url ?? null,
      followers: me.followers_count ?? null, media_count: me.media_count ?? null,
    }).eq("account_id", accountId);
    await db.from("ig_daily").upsert({ account_id: accountId, day: day(new Date()), followers: me.followers_count ?? null }, { onConflict: "account_id,day", ignoreDuplicates: false });

    // números do perfil por dia (a Meta guarda 90 dias e atrasa até 48 h)
    const nDays = opts.full ? 30 : 4;
    for (let i = 1; i <= nDays; i++) {
      const d0 = new Date(); d0.setUTCHours(3, 0, 0, 0); d0.setUTCDate(d0.getUTCDate() - i); // dia em Brasília
      const since = Math.floor(d0.getTime() / 1000), until = since + 86400;
      const base = { period: "day", metric_type: "total_value", since: String(since), until: String(until) };
      const a = await ig(`/${acc.ig_user_id}/insights`, token, { ...base, metric: "reach,views,accounts_engaged,total_interactions,likes,comments,saves,shares,profile_links_taps" })
        .then((r) => ins(r.data)).catch((e) => { if (e.code === 190) throw e; return {} as Record<string, number>; });
      const f = await ig(`/${acc.ig_user_id}/insights`, token, { ...base, metric: "follows_and_unfollows", breakdown: "follow_type" })
        .then((r) => ins(r.data)).catch((e) => { if (e.code === 190) throw e; return {} as Record<string, number>; });
      const row: any = { account_id: accountId, day: day(new Date(d0.getTime() + 3 * 3600e3)) };
      for (const k of ["reach", "views", "accounts_engaged", "total_interactions", "likes", "comments", "saves", "shares", "profile_links_taps"]) if (a[k] != null) row[k] = a[k];
      if (f["follows_and_unfollows:FOLLOWER"] != null) row.follows = f["follows_and_unfollows:FOLLOWER"];
      if (f["follows_and_unfollows:NON_FOLLOWER"] != null) row.unfollows = f["follows_and_unfollows:NON_FOLLOWER"];
      await db.from("ig_daily").upsert(row, { onConflict: "account_id,day" });
    }

    // totais do mês atual e do anterior (alcance sem repetir pessoas)
    for (const k of [0, -1]) {
      const n = new Date(); const ini = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth() + k, 1, 3));
      const fim = new Date(Date.UTC(n.getUTCFullYear(), n.getUTCMonth() + k + 1, 1, 3));
      const ate = Math.min(fim.getTime(), Date.now(), ini.getTime() + 30 * 864e5);
      if (ate <= ini.getTime()) continue;
      const mes = `${ini.getUTCFullYear()}-${String(ini.getUTCMonth() + 1).padStart(2, "0")}`;
      const t = await ig(`/${acc.ig_user_id}/insights`, token, { period: "day", metric_type: "total_value", since: String(Math.floor(ini.getTime() / 1000)), until: String(Math.floor(ate / 1000)), metric: "reach,views,accounts_engaged,total_interactions" })
        .then((r) => ins(r.data)).catch((e) => { if (e.code === 190) throw e; return null; });
      if (t) await db.from("ig_monthly").upsert({ account_id: accountId, month: mes, reach: t.reach ?? null, views: t.views ?? null, accounts_engaged: t.accounts_engaged ?? null, total_interactions: t.total_interactions ?? null, updated_at: new Date().toISOString() });
    }

    // posts e Reels dos últimos 60 dias (na primeira vez) ou 40 dias (dia a dia)
    const limitTs = Date.now() - (opts.full ? 60 : 40) * 864e5;
    let next: string | null = `${G}/${acc.ig_user_id}/media`;
    let pages = 0;
    while (next && pages++ < 6) {
      const r: any = next.includes("access_token") ? await fetch(next).then((x) => x.json()) : await ig(next, token, { fields, limit: "50" });
      if (r.error) throw new IgError(r.error.code, r.error.message);
      let old = false;
      for (const m of r.data ?? []) {
        if (new Date(m.timestamp).getTime() < limitTs) { old = true; break; }
        await upsertMedia(acc, m, token, have);
      }
      next = old ? null : r.paging?.next ?? null;
    }

    // público (só contas com 100 seguidores ou mais) — uma vez por semana
    const { data: au } = await db.from("ig_audience").select("updated_at").eq("account_id", accountId).eq("kind", "city").maybeSingle();
    if (opts.full || !au || Date.now() - new Date(au.updated_at).getTime() > 6 * 864e5) {
      for (const b of ["city", "age", "gender"]) {
        try {
          const r = await ig(`/${acc.ig_user_id}/insights`, token, { metric: "follower_demographics", period: "lifetime", timeframe: "this_month", metric_type: "total_value", breakdown: b });
          const res = r.data?.[0]?.total_value?.breakdowns?.[0]?.results ?? [];
          if (res.length) await db.from("ig_audience").upsert({ account_id: accountId, kind: b, data: res.map((x: any) => ({ k: x.dimension_values?.[0], v: x.value })), updated_at: new Date().toISOString() });
        } catch (e) { if (e instanceof IgError && e.code === 190) throw e; }
      }
    }
    await db.from("ig_connections").update({ status: "ok", status_msg: null, last_sync: new Date().toISOString() }).eq("account_id", accountId);
    return { ok: true };
  } catch (e) {
    const lost = e instanceof IgError && e.code === 190;
    await db.from("ig_connections").update({ status: "erro", status_msg: lost ? "A conexão caiu. Reenvie o link para o cliente." : String((e as Error).message).slice(0, 200) }).eq("account_id", accountId);
    return { ok: false, motivo: lost ? "reconectar" : (e as Error).message };
  }
}

// Acha o Instagram que o cliente compartilhou (tenta vários caminhos e anota o que a Meta respondeu)
async function findIgAccount(token: string): Promise<{ id: string; username?: string } | null> {
  const log = (k: string, v: unknown) => console.log(`[ig-find] ${k}: ${JSON.stringify(v).slice(0, 600)}`);
  // 1) caminho da documentação
  try {
    const r = await ig("/me/assigned_instagram_accounts", token, { fields: "id,username" });
    log("assigned_instagram_accounts", r);
    if (r.data?.[0]?.id) return r.data[0];
  } catch (e) { log("assigned_instagram_accounts erro", (e as Error).message); }
  // 2) permissões da chave: instagram_basic traz o ID da conta em target_ids
  try {
    const d = await ig("/debug_token", `${APP_ID}|${APP_SECRET}`, { input_token: token });
    const gs = d.data?.granular_scopes ?? [];
    log("debug_token", { type: d.data?.type, scopes: d.data?.scopes, granular: gs });
    const ids: string[] = gs.find((g: any) => g.scope === "instagram_basic")?.target_ids
      ?? gs.find((g: any) => String(g.scope).startsWith("instagram_"))?.target_ids ?? [];
    for (const id of ids) {
      try { const p = await ig(`/${id}`, token, { fields: "id,username" }); if (p.username) return p; } catch (e) { log(`perfil ${id} erro`, (e as Error).message); }
    }
  } catch (e) { log("debug_token erro", (e as Error).message); }
  // 3) pela empresa do cliente
  try {
    const me = await ig("/me", token, { fields: "id,client_business_id" });
    log("me", me);
    if (me.client_business_id) {
      for (const edge of ["owned_instagram_accounts", "instagram_accounts"]) {
        try {
          const r = await ig(`/${me.client_business_id}/${edge}`, token, { fields: "id,username" });
          log(edge, r);
          if (r.data?.[0]?.id) return r.data[0];
        } catch (e) { log(`${edge} erro`, (e as Error).message); }
      }
    }
  } catch (e) { log("me erro", (e as Error).message); }
  return null;
}

// ---------- Feed On ----------
const FO_FIELDS = "username,name,biography,website,profile_picture_url,followers_count,follows_count,media_count," +
  "media.limit(30){id,media_type,media_product_type,media_url,thumbnail_url,permalink,timestamp,like_count,comments_count}";
// Feed On: TODO mundo busca com a "chave do Fig.Feed" (um Instagram conectado por um admin), nunca com a conexão de um usuário
async function feedonViewer(_userId: string, _accountId: string) {
  const sel = "account_id,ig_user_id";
  let c: { account_id: string; ig_user_id: string } | null = null;
  const { data: s } = await db.from("ig_settings").select("value").eq("key", "feedon_viewer").maybeSingle();
  if (s?.value) ({ data: c } = await db.from("ig_connections").select(sel).eq("account_id", s.value).eq("status", "ok").maybeSingle());
  if (!c) {
    // sem escolha salva: a primeira conexão de um admin/GM vira a chave sozinha
    const { data: adm } = await db.from("profiles").select("id").in("role", ["gm", "admin"]);
    const ids = (adm ?? []).map((x: { id: string }) => x.id);
    if (ids.length) {
      ({ data: c } = await db.from("ig_connections").select(sel).in("owner_id", ids).eq("status", "ok").order("connected_at").limit(1).maybeSingle());
      if (c) await db.from("ig_settings").upsert({ key: "feedon_viewer", value: c.account_id });
    }
  }
  if (!c) return null;
  const { data: t } = await db.from("ig_tokens").select("access_token").eq("account_id", c.account_id).maybeSingle();
  return t ? { igId: c.ig_user_id as string, token: t.access_token as string } : null;
}
const FO_NAO = ["p", "reel", "reels", "stories", "explore", "tv", "accounts", "direct"];
function feedonUser(raw: string) {
  let u = String(raw ?? "").trim();
  const m = u.match(/instagram\.com\/([A-Za-z0-9._]+)/i);
  if (m) u = m[1];
  u = u.replace(/^@/, "").replace(/[/?#].*$/, "").toLowerCase();
  return /^[a-z0-9._]{1,30}$/.test(u) && !FO_NAO.includes(u) ? u : null;
}
async function feedon(userId: string, accountId: string, raw: string) {
  const username = feedonUser(raw);
  if (!username) return { ok: false, motivo: "link" };
  const v = await feedonViewer(userId, accountId);
  if (!v) return { ok: false, motivo: "sem_conta" };
  try {
    const r = await ig(`/${v.igId}`, v.token, { fields: `business_discovery.username(${username}){${FO_FIELDS}}` });
    const d = r.business_discovery;
    if (!d?.username) return { ok: false, motivo: "perfil" };
    const fetched_at = new Date().toISOString();
    await db.from("feedon").upsert({ account_id: accountId, owner_id: userId, username: d.username, data: d, fetched_at });
    return { ok: true, data: d, fetched_at };
  } catch (e) {
    const code = e instanceof IgError ? e.code : 0;
    console.log(`[feedon] ${username}: ${code} ${(e as Error).message}`);
    if ([4, 17, 32, 613].includes(code)) return { ok: false, motivo: "limite" };
    if (code === 190) return { ok: false, motivo: "conexao" };
    return { ok: false, motivo: "perfil" };
  }
}

// ---------- Rotas ----------
async function userOf(req: Request) {
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!jwt) return null;
  const { data } = await db.auth.getUser(jwt);
  return data.user ?? null;
}
async function ownsAccount(userId: string, accountId: string) {
  const { data } = await db.from("accounts").select("id").eq("id", accountId).eq("owner_id", userId).maybeSingle();
  return !!data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const url = new URL(req.url);

  if (req.method === "GET") {
    if (!APP_ID || !APP_SECRET) return back("conectar-erro/config");
    const go = url.searchParams.get("go");
    if (go) {
      const { data: l } = await db.from("ig_connect_links").select("*").eq("token", go).maybeSingle();
      if (!l || l.used_at || new Date(l.expires_at) < new Date()) return back("conectar-erro/link");
      const a = new URL(`https://www.facebook.com/${GV}/dialog/oauth`);
      a.searchParams.set("client_id", APP_ID);
      a.searchParams.set("config_id", CONFIG_ID);
      a.searchParams.set("redirect_uri", SELF);
      a.searchParams.set("response_type", "code");
      a.searchParams.set("override_default_response_type", "true");
      a.searchParams.set("prompt", "login"); // mostra as duas opções: Instagram e Facebook
      a.searchParams.set("state", go);
      return new Response(null, { status: 302, headers: { Location: a.toString() } });
    }
    const state = url.searchParams.get("state") ?? "";
    if (url.searchParams.get("error")) return back(`conectar-erro/negado/${state}`);
    const code = url.searchParams.get("code") ?? "";
    if (!code || !state) return back("conectar-erro/link");
    const { data: l } = await db.from("ig_connect_links").select("*").eq("token", state).maybeSingle();
    if (!l || l.used_at || new Date(l.expires_at) < new Date()) return back("conectar-erro/link");
    try {
      // 1) código → chave (token de usuário do sistema da empresa do cliente; não vence)
      const t = await fetch(`${G}/oauth/access_token?` + new URLSearchParams({ client_id: APP_ID, client_secret: APP_SECRET, redirect_uri: SELF, code })).then((r) => r.json());
      const token = t.access_token as string;
      if (!token) throw new Error(t?.error?.message ?? "sem chave");
      // 2) qual Instagram o cliente compartilhou
      const first = await findIgAccount(token);
      if (!first?.id) return back(`conectar-erro/pessoal/${state}`);
      // 3) perfil
      const me = await ig(`/${first.id}`, token, { fields: PROFILE_FIELDS });
      await db.from("ig_tokens").upsert({ account_id: l.account_id, access_token: token, expires_at: null, refreshed_at: new Date().toISOString() });
      await db.from("ig_connections").upsert({
        account_id: l.account_id, owner_id: l.owner_id, ig_user_id: String(me.id ?? first.id), username: me.username ?? first.username, name: me.name ?? null,
        profile_picture_url: me.profile_picture_url ?? null, followers: me.followers_count ?? null, media_count: me.media_count ?? null,
        status: "ok", status_msg: "Buscando os últimos 30 dias…", token_expires_at: null, connected_at: new Date().toISOString(),
      });
      await db.from("ig_connect_links").update({ used_at: new Date().toISOString() }).eq("token", state);
      // primeira coleta completa numa chamada própria (pelo banco), para o Supabase não cortar no meio
      const { error: rpcErr } = await db.rpc("ig_sync_now", { p_account: l.account_id, p_full: true });
      // @ts-ignore EdgeRuntime existe no Supabase
      if (rpcErr) { console.error(rpcErr); EdgeRuntime.waitUntil(syncAccount(l.account_id, { full: true })); }
      return back(`conectado/${encodeURIComponent(me.username ?? first.username ?? "")}`);
    } catch (e) {
      console.error(e);
      return back(`conectar-erro/falhou/${state}`);
    }
  }

  // POST
  const body = await req.json().catch(() => ({}));
  const accountId = body.account_id as string;
  if (String(body.action).startsWith("cron_")) {
    const { data: s } = await db.from("ig_settings").select("value").eq("key", "cron_secret").single();
    if (!s || req.headers.get("x-cron-secret") !== s.value) return json({ erro: "não autorizado" }, 401);
    return json(await syncAccount(accountId, { storiesOnly: body.action === "cron_stories", full: !!body.full }));
  }
  const user = await userOf(req);
  if (!user || !accountId || !(await ownsAccount(user.id, accountId))) return json({ erro: "não autorizado" }, 401);
  if (body.action === "sync") return json(await syncAccount(accountId, { full: !!body.full }));
  if (body.action === "feedon") return json(await feedon(user.id, accountId, body.username));
  if (body.action === "feedon_viewer") {
    const { data: p } = await db.from("profiles").select("role").eq("id", user.id).maybeSingle();
    if (!["gm", "admin"].includes(p?.role)) return json({ erro: "só administradores" }, 403);
    const { data: c } = await db.from("ig_connections").select("account_id").eq("account_id", accountId).eq("status", "ok").maybeSingle();
    if (!c) return json({ ok: false, motivo: "sem conexão" });
    await db.from("ig_settings").upsert({ key: "feedon_viewer", value: accountId });
    return json({ ok: true });
  }
  if (body.action === "disconnect") {
    await db.from("ig_tokens").delete().eq("account_id", accountId);
    await db.from("ig_connections").delete().eq("account_id", accountId);
    return json({ ok: true });
  }
  return json({ erro: "ação desconhecida" }, 400);
});
