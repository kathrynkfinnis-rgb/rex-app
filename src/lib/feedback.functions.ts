import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const schema = z.object({
  kind: z.enum(["idea", "bug", "love"]),
  message: z.string().trim().min(1).max(2000),
  page: z.string().trim().max(200).nullable().optional(),
});

/**
 * Submits feedback with NO link back to the sender.
 * Auth is required (to stop spam) but the user id is deliberately never stored.
 */
export const sendAnonymousFeedback = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((data: unknown) => schema.parse(data))
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.from("feedback").insert({
      user_id: null,
      is_anonymous: true,
      kind: data.kind,
      message: data.message,
      page: data.page ?? null,
    });
    if (error) throw new Error(error.message);
    return { ok: true };
  });
