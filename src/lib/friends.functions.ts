import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

export const searchProfiles = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data) =>
    z.object({ query: z.string().min(2).max(100), limit: z.number().int().min(1).max(25).optional() }).parse(data),
  )
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: rows, error } = await supabaseAdmin.rpc("search_profiles_for", {
      _caller: context.userId,
      _query: data.query,
      _limit: data.limit ?? 10,
    });
    if (error) throw error;
    return rows ?? [];
  });

export const suggestedFriends = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data) =>
    z.object({ limit: z.number().int().min(1).max(50).optional() }).parse(data ?? {}),
  )
  .handler(async ({ data, context }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: rows, error } = await supabaseAdmin.rpc("suggested_friends_for", {
      _caller: context.userId,
      _limit: data.limit ?? 20,
    });
    if (error) throw error;
    return rows ?? [];
  });
