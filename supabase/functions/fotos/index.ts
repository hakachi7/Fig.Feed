// Fig.Feed v21 — fotos no Cloudflare R2
// Só esta função tem as chaves do R2. O app manda as fotos para cá e ela grava no R2.
// Rotas (POST):
//   multipart/form-data { path, file }               → enviar (path sempre começa com o id de quem envia)
//   { action:'remove', paths:[...] }                  → apagar (só as próprias; admin apaga qualquer uma)
//   { action:'migrate', n?, keep? }                   → admin: copia fotos que ainda estão no Supabase para o R2 (keep = não apaga de lá)
//   { action:'cleanup' }                              → admin: apaga do Supabase o que já está no R2
//   { action:'selftest' }                             → admin: grava, lê e apaga um arquivo de teste
// Admin = usuário GM/admin logado, ou o agendamento com o header x-cron-secret.
// Segredos: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET, R2_PUBLIC_URL
import { createClient } from "jsr:@supabase/supabase-js@2";
import { AwsClient } from "npm:aws4fetch@1.0.20";

const env = (k: string) => (Deno.env.get(k) ?? "").trim();
const ACC = env("R2_ACCOUNT_ID"), BUCKET = env("R2_BUCKET") || "figfeed-fotos";
const PUB = env("R2_PUBLIC_URL").replace(/\/+$/, "");
const r2 = new AwsClient({ accessKeyId: env("R2_ACCESS_KEY_ID"), secretAccessKey: env("R2_SECRET_ACCESS_KEY"), service: "s3", region: "auto" });
const keyUrl = (k: string) => `https://${ACC}.r2.cloudflarestorage.com/${BUCKET}/${k.split("/").map(encodeURIComponent).join("/")}`;
const pubUrl = (k: string) => `${PUB}/${k.split("/").map(encodeURIComponent).join("/")}`;
async function r2Put(k: string, body: Blob | ArrayBuffer, type: string) {
  const r = await r2.fetch(keyUrl(k), { method: "PUT", body, headers: { "Content-Type": type, "Cache-Control": "public, max-age=31536000" } });
  if (!r.ok) throw new Error(`R2 ${r.status}: ${(await r.text()).slice(0, 300)}`);
}
async function r2Del(k: string) {
  const r = await r2.fetch(keyUrl(k), { method: "DELETE" });
  if (!r.ok && r.status !== 404) throw new Error(`R2 ${r.status}`);
}

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });
const MAX = 10 * 1048576;
const PATH_OK = /^[0-9a-f-]{36}\/[A-Za-z0-9._\/-]{1,300}$/;

async function userOf(req: Request) {
  const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  if (!jwt) return null;
  const { data } = await db.auth.getUser(jwt);
  return data.user ?? null;
}
async function isAdmin(uid?: string) {
  if (!uid) return false;
  const { data } = await db.from("profiles").select("role").eq("id", uid).maybeSingle();
  return ["gm", "admin"].includes(data?.role);
}
async function cronOk(req: Request) {
  const h = req.headers.get("x-cron-secret");
  if (!h) return false;
  const { data } = await db.from("ig_settings").select("value").eq("key", "cron_secret").maybeSingle();
  return !!data && data.value === h;
}

async function removeAll(paths: string[]) {
  let n = 0;
  for (let i = 0; i < paths.length; i += 20) {
    const part = paths.slice(i, i + 20);
    await Promise.all(part.map((p) => r2Del(p)));
    await db.from("fotos_r2").delete().in("name", part);
    // o que ainda estiver no Supabase (de antes da mudança) também sai
    await db.storage.from("fotos").remove(part).catch(() => {});
    n += part.length;
  }
  return n;
}

async function migrate(n: number, keep: boolean) {
  const { data: list, error } = await db.rpc("fotos_pendentes", { n });
  if (error) throw error;
  let ok = 0; const falhas: string[] = [];
  for (const f of list ?? []) {
    try {
      const owner = f.name.split("/")[0];
      const { data: blob, error: e1 } = await db.storage.from("fotos").download(f.name);
      if (e1 || !blob) throw e1 ?? new Error("sem arquivo");
      await r2Put(f.name, blob, blob.type || "image/jpeg");
      const { error: e2 } = await db.from("fotos_r2").upsert({ name: f.name, owner_id: owner, size: blob.size });
      if (e2) throw e2;
      const chk = await fetch(pubUrl(f.name), { method: "HEAD" });
      if (!chk.ok) throw new Error(`não abriu no endereço público (${chk.status})`);
      if (!keep) await db.storage.from("fotos").remove([f.name]);
      ok++;
    } catch (e) { falhas.push(`${f.name}: ${(e as Error).message}`.slice(0, 200)); }
  }
  const { data: rest } = await db.rpc("fotos_pendentes", { n: 1000 });
  return { ok, falhas, faltam: (rest ?? []).length };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "use POST" }, 405);
  if (!ACC || !PUB) return json({ error: "Fotos sem configuração no servidor (R2)" }, 500);
  try {
    const ct = req.headers.get("content-type") ?? "";

    // ---- enviar ---- (v21.1: menos idas ao banco; login e leitura da foto ao mesmo tempo)
    if (ct.includes("multipart/form-data")) {
      const [user, fd] = await Promise.all([userOf(req), req.formData()]);
      if (!user) return json({ error: "Entre na sua conta de novo" }, 401);
      const path = String(fd.get("path") ?? "");
      const file = fd.get("file");
      if (!(file instanceof File) && !(file instanceof Blob)) return json({ error: "Nenhuma foto recebida" }, 400);
      const own = path.startsWith(user.id + "/");
      if (!PATH_OK.test(path) || path.includes("..") || (!own && !(await isAdmin(user.id)))) return json({ error: "Caminho de foto inválido" }, 400);
      if (file.size > MAX) return json({ error: "Foto grande demais (máximo de 10 MB)" }, 413);
      const owner = path.split("/")[0];
      const { data: pode, error: e0 } = await db.rpc("fotos_pode_enviar", { p_user: owner, p_name: path });
      if (e0) throw e0;
      if (!pode) return json({ error: "Seu espaço acabou. Libere espaço ou veja os Planos." }, 403);
      const type = String(fd.get("type") || file.type || "image/jpeg");
      await r2Put(path, file, type);
      const { error: e1 } = await db.from("fotos_r2").upsert({ name: path, owner_id: owner, size: file.size, created_at: new Date().toISOString() });
      if (e1) throw e1;
      return json({ path, url: pubUrl(path), size: file.size });
    }
    const user = await userOf(req);

    const body = await req.json().catch(() => ({}));
    if (body.action === "remove") {
      if (!user) return json({ error: "Entre na sua conta de novo" }, 401);
      const admin = await isAdmin(user.id);
      const paths = (Array.isArray(body.paths) ? body.paths : []).map(String)
        .filter((p: string) => PATH_OK.test(p) && !p.includes("..") && (admin || p.startsWith(user.id + "/")));
      return json({ removed: await removeAll(paths) });
    }
    const adm = (await cronOk(req)) || (await isAdmin(user?.id));
    if (!adm) return json({ error: "só administradores" }, 403);
    if (body.action === "migrate") return json(await migrate(Math.min(50, Math.max(1, Number(body.n) || 20)), !!body.keep));
    if (body.action === "cleanup") {
      // apaga do Supabase as fotos que já estão no R2
      const { data: names, error } = await db.rpc("fotos_copiadas", { n: 100 });
      if (error) throw error;
      const list = (names ?? []).map((x: any) => typeof x === "string" ? x : x.fotos_copiadas);
      if (list.length) await db.storage.from("fotos").remove(list);
      const { data: rest } = await db.rpc("fotos_copiadas", { n: 1000 });
      return json({ apagadas: list.length, faltam: (rest ?? []).length });
    }
    if (body.action === "selftest") {
      const k = `00000000-0000-0000-0000-000000000000/teste/${crypto.randomUUID()}.txt`;
      const out: Record<string, unknown> = { conta: ACC.slice(0, 6) + "…", bucket: BUCKET, publico: PUB };
      const t0 = Date.now();
      try { await r2Put(k, new Blob(["ok"]), "text/plain"); out.gravar = "ok"; out.gravar_ms = Date.now() - t0; } catch (e) { out.gravar = (e as Error).message; return json(out); }
      try { const r = await fetch(pubUrl(k), { headers: { Origin: "https://jvpereira.cc" } }); out.ler_publico = r.status; out.cors = r.headers.get("access-control-allow-origin"); out.vary = r.headers.get("vary"); } catch (e) { out.ler_publico = (e as Error).message; }
      try { await r2Del(k); out.apagar = "ok"; } catch (e) { out.apagar = (e as Error).message; }
      return json(out);
    }
    return json({ error: "ação desconhecida" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message ?? "erro" }, 500);
  }
});
