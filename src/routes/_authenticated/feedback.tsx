import { useState } from "react";
import { createFileRoute, Link, useRouteContext } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronLeft, MessageSquareText, Bug, Lightbulb, Heart, EyeOff } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import { sendAnonymousFeedback } from "@/lib/feedback.functions";


export const Route = createFileRoute("/_authenticated/feedback")({
  head: () => ({
    meta: [
      { title: "Send feedback — REX" },
      { name: "description", content: "Tell the REX team what to fix, build or improve next." },
      { property: "og:title", content: "Send feedback — REX" },
      { property: "og:description", content: "Tell the REX team what to fix, build or improve next." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: FeedbackPage,
});

const KINDS = [
  { key: "idea", label: "Idea", icon: Lightbulb },
  { key: "bug", label: "Bug", icon: Bug },
  { key: "love", label: "Love it", icon: Heart },
] as const;

function FeedbackPage() {
  const { user } = useRouteContext({ from: "/_authenticated" });
  const qc = useQueryClient();
  const [kind, setKind] = useState<string>("idea");
  const [message, setMessage] = useState("");
  const [anonymous, setAnonymous] = useState(false);
  const sendAnon = useServerFn(sendAnonymousFeedback);

  const { data: mine = [] } = useQuery({
    queryKey: ["feedback", user.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("feedback")
        .select("id, kind, message, status, created_at")
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      return data ?? [];
    },
  });

  const send = useMutation({
    mutationFn: async () => {
      const page = typeof window !== "undefined" ? window.location.pathname : null;
      if (anonymous) {
        await sendAnon({ data: { kind: kind as "idea" | "bug" | "love", message: message.trim(), page } });
        return;
      }
      const { error } = await supabase.from("feedback").insert({
        user_id: user.id,
        kind,
        message: message.trim(),
        page,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      setMessage("");
      toast.success(anonymous ? "Sent anonymously — thank you 🦖" : "Thanks — feedback sent 🦖");
      qc.invalidateQueries({ queryKey: ["feedback", user.id] });
    },
    onError: () => toast.error("Couldn't send that, try again"),
  });


  return (
    <div className="px-4 pb-24 pt-20">
      <div className="mb-4 flex items-center gap-2">
        <Link to="/feed" className="flex h-9 w-9 items-center justify-center rounded-full bg-card" aria-label="Back">
          <ChevronLeft className="h-5 w-5" />
        </Link>
        <h1 className="text-2xl font-bold">Feedback</h1>
      </div>

      <p className="mb-4 text-sm text-muted-foreground">
        Spotted a bug or got an idea for REX? Tell us here — we read everything.
      </p>

      <div className="mb-3 flex gap-2">
        {KINDS.map(({ key, label, icon: Icon }) => (
          <button
            key={key}
            type="button"
            onClick={() => setKind(key)}
            className={cn(
              "flex flex-1 items-center justify-center gap-1.5 rounded-xl border px-3 py-2 text-sm font-medium transition-colors",
              kind === key
                ? "border-primary bg-primary text-primary-foreground"
                : "border-border bg-card text-muted-foreground",
            )}
          >
            <Icon className="h-4 w-4" />
            {label}
          </button>
        ))}
      </div>

      <Textarea
        value={message}
        onChange={(e) => setMessage(e.target.value)}
        rows={5}
        maxLength={2000}
        placeholder="What's on your mind?"
        className="mb-3"
      />

      <div className="mb-3 flex items-start gap-3 rounded-xl border border-border bg-card p-3">
        <EyeOff className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div className="min-w-0 flex-1">
          <label htmlFor="anon" className="text-sm font-medium">
            Send anonymously
          </label>
          <p className="text-xs text-muted-foreground">
            {anonymous
              ? "Your name won't be stored with this message — it also won't appear in your feedback list below."
              : "Your name is attached so we can follow up."}
          </p>
        </div>
        <Switch id="anon" checked={anonymous} onCheckedChange={setAnonymous} />
      </div>

      <Button
        className="w-full"
        disabled={!message.trim() || send.isPending}
        onClick={() => send.mutate()}
      >
        <MessageSquarePlus className="mr-2 h-4 w-4" />
        {send.isPending ? "Sending…" : anonymous ? "Send anonymously" : "Send feedback"}
      </Button>


      {mine.length > 0 && (
        <section className="mt-8">
          <h2 className="mb-2 text-sm font-semibold text-muted-foreground">Your feedback</h2>
          <ul className="space-y-2">
            {mine.map((f) => (
              <li key={f.id} className="rounded-xl border border-border bg-card p-3">
                <div className="mb-1 flex items-center justify-between text-[11px] uppercase tracking-wide text-muted-foreground">
                  <span>{f.kind}</span>
                  <span>{f.status}</span>
                </div>
                <p className="text-sm">{f.message}</p>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
