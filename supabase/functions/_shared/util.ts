// Utilidades compartidas por las Edge Functions. Sin dependencias salvo supabase-js.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const URL_ = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; // solo existe en el servidor
const PEPPER = Deno.env.get("HASH_PEPPER") ?? "";
const ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);

export class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allow = ORIGINS.length === 0 ? "*" : (ORIGINS.includes(origin) ? origin : ORIGINS[0]);
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function reply(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const opts = { auth: { persistSession: false, autoRefreshToken: false } };
export const adminClient = () => createClient(URL_, SERVICE, opts);
export const anonClient = (authHeader?: string) =>
  createClient(URL_, ANON, { ...opts, global: authHeader ? { headers: { Authorization: authHeader } } : undefined });

export async function sha256(value: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(PEPPER + value));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, "0")).join("");
}

const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;
export function cleanEmail(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const e = v.trim().toLowerCase();
  return e.length <= 254 && EMAIL_RE.test(e) ? e : null;
}

// Valida el JWT del llamador Y su permiso en el servidor. Devuelve su id o null.
export async function requirePermission(req: Request, code: string): Promise<string | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const client = anonClient(auth);
  const { data, error } = await client.auth.getUser(auth.slice(7));
  if (error || !data.user) return null;
  const { data: ok } = await client.rpc("has_permission", { p_code: code });
  return ok === true ? data.user.id : null;
}
