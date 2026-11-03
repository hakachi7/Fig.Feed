// Fig.Feed — ações do admin que precisam do servidor
//   POST {action:'delete_user', target}  → apaga as fotos da pessoa e a conta (só admin; admin não apaga admin/GM; ninguém apaga a si mesmo)
import { createClient } from "jsr:@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const svc = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método não aceito" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Entre na sua conta" }, 401);
  // Cliente com a chave de quem chamou: as checagens rodam com as permissões dessa pessoa
  const me = createClient(SB_URL, ANON, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: u } = await me.auth.getUser();
  if (!u?.user) return json({ error: "Entre na sua conta" }, 401);
  let body: any = {};
  try { body = await req.json(); } catch { return json({ error: "Pedido inválido" }, 400); }

  if (body.action === "delete_user") {
    const target = String(body.target ?? "");
    if (!/^[0-9a-f-]{36}$/i.test(target)) return json({ error: "Usuário inválido" }, 400);
    const { data: ok, error: e1 } = await me.rpc("admin_can_manage", { target });
    if (e1 || !ok) return json({ error: "Você não pode excluir esta conta" }, 403);
    const { data: alvo } = await svc.from("profiles").select("role,name").eq("id", target).maybeSingle();
    if (alvo?.role === "gm") {
      const { count } = await svc.from("profiles").select("id", { count: "exact", head: true }).eq("role", "gm");
      if ((count ?? 0) <= 1) return json({ error: "Esta é a única conta GM" }, 403);
    }
    const { data: tu } = await svc.auth.admin.getUserById(target);
    const email = tu?.user?.email ?? "";
    // 1) fotos
    const { data: files, error: e2 } = await svc.rpc("admin_user_files", { target });
    if (e2) return json({ error: "Não deu para listar as fotos: " + e2.message }, 500);
    const names: string[] = (files ?? []).map((x: any) => typeof x === "string" ? x : x.admin_user_files);
    for (let i = 0; i < names.length; i += 100) {
      const { error } = await svc.storage.from("fotos").remove(names.slice(i, i + 100));
      if (error) return json({ error: "Não deu para apagar as fotos: " + error.message }, 500);
    }
    // 2) registro (antes, para guardar o e-mail) e 3) conta
    await svc.from("activity_log").insert({ actor_id: u.user.id, category: "usuarios", action: "excluiu a conta", target_user: null, details: { email, fotos: names.length } });
    const { error: e3 } = await svc.auth.admin.deleteUser(target);
    if (e3) return json({ error: "Não deu para excluir a conta: " + e3.message }, 500);
    return json({ ok: true, fotos: names.length });
  }
  return json({ error: "Ação desconhecida" }, 400);
});
