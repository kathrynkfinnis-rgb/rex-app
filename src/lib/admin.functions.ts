import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { z } from "zod";

async function assertAdmin(context: { supabase: any; userId: string }) {
  const { data, error } = await context.supabase.rpc("has_role", {
    _user_id: context.userId,
    _role: "admin",
  });
  if (error || !data) throw new Error("Forbidden");
}

type AdminRow = {
  id: string;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  since: string | null;
};

/** List everyone with the admin role (admin-only). */
export const listAdmins = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<AdminRow[]> => {
    await assertAdmin(context as any);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: roles, error } = await supabaseAdmin
      .from("user_roles")
      .select("user_id, created_at")
      .eq("role", "admin")
      .order("created_at", { ascending: true });
    if (error) throw error;
    const ids = (roles ?? []).map((r) => r.user_id);
    if (ids.length === 0) return [];

    const { data: profiles } = await supabaseAdmin
      .from("profiles")
      .select("id, username, display_name, avatar_url")
      .in("id", ids);

    return ids.map((id) => {
      const p = (profiles ?? []).find((x) => x.id === id);
      return {
        id,
        username: p?.username ?? "unknown",
        display_name: p?.display_name ?? null,
        avatar_url: p?.avatar_url ?? null,
        since: roles!.find((r) => r.user_id === id)?.created_at ?? null,
      };
    });
  });

/** Search all users by username/display name so an admin can promote them. */
export const searchUsersForAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ query: z.string().trim().max(60) }).parse(input))
  .handler(async ({ data, context }) => {
    await assertAdmin(context as any);
    if (data.query.length < 2) return [];
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const q = `%${data.query}%`;
    const { data: profiles, error } = await supabaseAdmin
      .from("profiles")
      .select("id, username, display_name, avatar_url")
      .or(`username.ilike.${q},display_name.ilike.${q}`)
      .limit(10);
    if (error) throw error;

    const ids = (profiles ?? []).map((p) => p.id);
    const { data: roles } = ids.length
      ? await supabaseAdmin.from("user_roles").select("user_id").eq("role", "admin").in("user_id", ids)
      : { data: [] as { user_id: string }[] };

    return (profiles ?? []).map((p) => ({
      ...p,
      is_admin: (roles ?? []).some((r) => r.user_id === p.id),
    }));
  });

/** Grant the admin role to a user (admin-only). */
export const grantAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ userId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    await assertAdmin(context as any);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    const { data: profile } = await supabaseAdmin
      .from("profiles").select("id").eq("id", data.userId).maybeSingle();
    if (!profile) throw new Error("That user doesn't exist");

    const { error } = await supabaseAdmin
      .from("user_roles")
      .upsert({ user_id: data.userId, role: "admin" }, { onConflict: "user_id,role" });
    if (error) throw error;
    return { ok: true };
  });

/** Remove the admin role (admin-only, cannot remove yourself or the last admin). */
export const revokeAdmin = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input) => z.object({ userId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const ctx = context as any;
    await assertAdmin(ctx);
    if (ctx.userId === data.userId) throw new Error("You can't remove your own admin access");

    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { count } = await supabaseAdmin
      .from("user_roles").select("user_id", { count: "exact", head: true }).eq("role", "admin");
    if ((count ?? 0) <= 1) throw new Error("There must be at least one admin");

    const { error } = await supabaseAdmin
      .from("user_roles").delete().eq("user_id", data.userId).eq("role", "admin");
    if (error) throw error;
    return { ok: true };
  });
