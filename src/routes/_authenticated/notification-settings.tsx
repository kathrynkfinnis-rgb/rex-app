import { createFileRoute, Link, useRouteContext } from "@tanstack/react-router";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Switch } from "@/components/ui/switch";
import { ChevronLeft, Mail } from "lucide-react";
import { PREF_LABELS, DEFAULT_PREFS, type PrefRow } from "@/lib/notifications";
import { toast } from "sonner";

export const Route = createFileRoute("/_authenticated/notification-settings")({
  head: () => ({
    meta: [
      { title: "Notification settings — REX" },
      { name: "description", content: "Choose which REX activity should notify you." },
    ],
  }),
  component: NotificationSettingsPage,
});

function NotificationSettingsPage() {
  const { user } = useRouteContext({ from: "/_authenticated" });
  const qc = useQueryClient();

  const { data: prefs } = useQuery({
    queryKey: ["notif-prefs", user.id],
    queryFn: async () => {
      const { data } = await supabase
        .from("notification_preferences")
        .select("*")
        .eq("user_id", user.id)
        .maybeSingle();
      return (data ?? { user_id: user.id, ...DEFAULT_PREFS }) as PrefRow;
    },
  });

  const save = useMutation({
    mutationFn: async (patch: Partial<PrefRow>) => {
      const next = { ...(prefs ?? { user_id: user.id, ...DEFAULT_PREFS }), ...patch, user_id: user.id };
      const { error } = await supabase
        .from("notification_preferences")
        .upsert(next, { onConflict: "user_id" });
      if (error) throw error;
      return next;
    },
    onMutate: async (patch) => {
      await qc.cancelQueries({ queryKey: ["notif-prefs", user.id] });
      const prev = qc.getQueryData<PrefRow>(["notif-prefs", user.id]);
      if (prev) qc.setQueryData(["notif-prefs", user.id], { ...prev, ...patch });
      return { prev };
    },
    onError: (_e, _v, ctx) => {
      if (ctx?.prev) qc.setQueryData(["notif-prefs", user.id], ctx.prev);
      toast.error("Couldn't save preference");
    },
  });

  const keys = Object.keys(PREF_LABELS) as Array<keyof typeof PREF_LABELS>;

  return (
    <div className="px-4 pb-24 pt-20">
      <div className="mb-4 flex items-center gap-2">
        <Link
          to="/notifications"
          className="flex h-9 w-9 items-center justify-center rounded-full bg-card"
          aria-label="Back"
        >
          <ChevronLeft className="h-5 w-5" />
        </Link>
        <h1 className="text-2xl font-bold">Notifications</h1>
      </div>

      <p className="mb-4 text-sm text-muted-foreground">
        Choose what REX alerts you about. New alerts appear in your bell in real time.
      </p>

      <div className="divide-y divide-border rounded-2xl bg-card">
        {keys.map((k) => (
          <label key={k} className="flex items-start justify-between gap-3 p-4">
            <div className="min-w-0">
              <p className="text-sm font-medium">{PREF_LABELS[k].label}</p>
              <p className="text-xs text-muted-foreground">{PREF_LABELS[k].description}</p>
            </div>
            <Switch
              checked={Boolean(prefs?.[k])}
              onCheckedChange={(v) => save.mutate({ [k]: v } as Partial<PrefRow>)}
            />
          </label>
        ))}
      </div>

      <h2 className="mt-8 mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">
        Email
      </h2>
      <div className="rounded-2xl bg-card p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="flex items-center gap-2 text-sm font-medium">
              <Mail className="h-4 w-4" /> Also email me
            </p>
            <p className="text-xs text-muted-foreground">
              Send an email for the events I've enabled above. Coming soon — needs an email sender to be set up.
            </p>
          </div>
          <Switch
            checked={Boolean(prefs?.email_enabled)}
            disabled
            onCheckedChange={(v) => save.mutate({ email_enabled: v })}
          />
        </div>
      </div>
    </div>
  );
}
