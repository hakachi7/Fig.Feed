// Fig.Feed — conexão com o Instagram (API do Instagram com login do Instagram)
// Rotas:
//   GET  ?go=<link>            → abre o login do Instagram para aquele link de conexão
//   GET  ?code=…&state=<link>  → volta da Meta: guarda a chave e busca os números
//   POST {action:'sync', account_id}       → "Atualizar agora" (usuário logado, dono da conta)
//   POST {action:'disconnect', account_id} → desconectar (usuário logado, dono da conta)
//   POST {action:'cron_sync'|'cron_stories', account_id} + header x-cron-secret → agendamento
import { createClient } from "jsr:@supabase/supabase-js@2";

const APP_ID = Deno.env.get("IG_APP_ID") ?? "";
const APP_SECRET = Deno.env.get("IG_APP_SECRET") ?? "";
const SITE = Deno.env.get("SITE_URL") ?? "https://hakachi7.github.io/Fig.Feed/";
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SELF = `${SB_URL}/functions/v1/instagram`;
const GV = "v26.0";
const G = `https://graph.instagram.com/${GV}`;
const SCOPES = "instagram_business_basic,instagram_business_manage_insights";
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

// ---------- Coleta ----------
async function saveThumb(owner: string, mediaId: string, url?: string) {
  if (!url) return null;
  const path = `${owner}/instagram/${mediaId}.jpg`;
  try {
    const r = await fetch(url); if (!r.ok) return null;
    const { error } = await db.storage.from("fotos").upload(path, await r.blob(), { contentType: r.headers.get("content-type") ?? "image/jpeg", upsert: true });
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
    // alguma métrica não aceita para este post: tenta o básico
    try { return ins((await ig(`/${id}/insights`, token, { metric: "reach,views" })).data); } catch { return {}; }
  }
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
  let token = tk.access_token as string;
  try {
    // renova a chave quando faltar menos de 20 dias (e tiver mais de 1 dia)
    const exp = tk.expires_at ? new Date(tk.expires_at).getTime() : 0;
    if (exp - Date.now() < 20 * 864e5 && Date.now() - new Date(tk.refreshed_at).getTime() > 864e5) {
      const r = await ig("https://graph.instagram.com/refresh_access_token", token, { grant_type: "ig_refresh_token" });
      token = r.access_token;
      const ex = new Date(Date.now() + (r.expires_in ?? 5184000) * 1000).toISOString();
      await db.from("ig_tokens").update({ access_token: token, expires_at: ex, refreshed_at: new Date().toISOString() }).eq("account_id", accountId);
      await db.from("ig_connections").update({ token_expires_at: ex }).eq("account_id", accountId);
    }
    const { data: thumbs } = await db.from("ig_media").select("media_id").eq("account_id", accountId).not("thumb_url", "is", null);
    const have = new Set((thumbs ?? []).map((t: any) => t.media_id));
    const fields = "id,caption,media_type,media_product_type,permalink,timestamp,thumbnail_url,media_url,like_count,comments_count";

    // stories: só ficam disponíveis por 24 h
    const st = await ig(`/${acc.ig_user_id}/stories`, token, { fields }).catch((e) => { if (e.code === 190) throw e; return { data: [] }; });
    for (const m of st.data ?? []) await upsertMedia(acc, { ...m, media_product_type: "STORY" }, token, have);
    if (opts.storiesOnly) { await db.from("ig_connections").update({ status: "ok", status_msg: null }).eq("account_id", accountId); return { ok: true }; }

    // perfil
    const me = await ig(`/me`, token, { fields: "user_id,username,name,profile_picture_url,followers_count,media_count" });
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
      const a = new URL("https://www.instagram.com/oauth/authorize");
      a.searchParams.set("client_id", APP_ID);
      a.searchParams.set("redirect_uri", SELF);
      a.searchParams.set("response_type", "code");
      a.searchParams.set("scope", SCOPES);
      a.searchParams.set("enable_fb_login", "false");
      a.searchParams.set("state", go);
      return new Response(null, { status: 302, headers: { Location: a.toString() } });
    }
    const state = url.searchParams.get("state") ?? "";
    if (url.searchParams.get("error")) return back(`conectar-erro/negado/${state}`);
    const code = (url.searchParams.get("code") ?? "").replace(/#_$/, "");
    if (!code || !state) return back("conectar-erro/link");
    const { data: l } = await db.from("ig_connect_links").select("*").eq("token", state).maybeSingle();
    if (!l || l.used_at || new Date(l.expires_at) < new Date()) return back("conectar-erro/link");
    try {
      // 1) código → chave curta
      const f = new FormData();
      f.set("client_id", APP_ID); f.set("client_secret", APP_SECRET); f.set("grant_type", "authorization_code");
      f.set("redirect_uri", SELF); f.set("code", code);
      const r1 = await fetch("https://api.instagram.com/oauth/access_token", { method: "POST", body: f }).then((r) => r.json());
      const short = r1.access_token ?? r1.data?.[0]?.access_token;
      if (!short) throw new Error(r1.error_message ?? "sem chave");
      // 2) chave curta → chave de 60 dias
      const r2 = await ig("https://graph.instagram.com/access_token", short, { grant_type: "ig_exchange_token", client_secret: APP_SECRET });
      const token = r2.access_token as string;
      const ex = new Date(Date.now() + (r2.expires_in ?? 5184000) * 1000).toISOString();
      // 3) quem é
      const me = await ig("/me", token, { fields: "user_id,username,name,account_type,profile_picture_url,followers_count,media_count" });
      if (me.account_type && !["BUSINESS", "MEDIA_CREATOR", "CREATOR"].includes(String(me.account_type).toUpperCase())) return back(`conectar-erro/pessoal/${state}`);
      await db.from("ig_tokens").upsert({ account_id: l.account_id, access_token: token, expires_at: ex, refreshed_at: new Date().toISOString() });
      await db.from("ig_connections").upsert({
        account_id: l.account_id, owner_id: l.owner_id, ig_user_id: String(me.user_id ?? me.id), username: me.username, name: me.name ?? null,
        profile_picture_url: me.profile_picture_url ?? null, followers: me.followers_count ?? null, media_count: me.media_count ?? null,
        status: "ok", status_msg: "Buscando os últimos 30 dias…", token_expires_at: ex, connected_at: new Date().toISOString(),
      });
      await db.from("ig_connect_links").update({ used_at: new Date().toISOString() }).eq("token", state);
      // primeira coleta em segundo plano
      // @ts-ignore EdgeRuntime existe no Supabase
      EdgeRuntime.waitUntil(syncAccount(l.account_id, { full: true }));
      return back(`conectado/${encodeURIComponent(me.username ?? "")}`);
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
    return json(await syncAccount(accountId, { storiesOnly: body.action === "cron_stories" }));
  }
  const user = await userOf(req);
  if (!user || !accountId || !(await ownsAccount(user.id, accountId))) return json({ erro: "não autorizado" }, 401);
  if (body.action === "sync") return json(await syncAccount(accountId, { full: !!body.full }));
  if (body.action === "disconnect") {
    await db.from("ig_tokens").delete().eq("account_id", accountId);
    await db.from("ig_connections").delete().eq("account_id", accountId);
    return json({ ok: true });
  }
  return json({ erro: "ação desconhecida" }, 400);
});
