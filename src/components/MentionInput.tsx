import { useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { UserAvatar } from "@/components/UserAvatar";
import { cn } from "@/lib/utils";

export type MentionProfile = {
  id: string;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
};

/** Friends (accepted) of the signed-in user — the pool you can tag in a comment. */
export function useTaggableFriends() {
  return useQuery({
    queryKey: ["taggable-friends"],
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<MentionProfile[]> => {
      const uid = (await supabase.auth.getUser()).data.user?.id;
      if (!uid) return [];
      const { data: fs, error } = await supabase
        .from("friendships")
        .select("requester_id, addressee_id")
        .eq("status", "accepted")
        .or(`requester_id.eq.${uid},addressee_id.eq.${uid}`);
      if (error) throw error;
      const ids = (fs ?? []).map((f) => (f.requester_id === uid ? f.addressee_id : f.requester_id));
      if (ids.length === 0) return [];
      const { data: profiles, error: pErr } = await supabase
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", ids);
      if (pErr) throw pErr;
      return (profiles ?? []) as MentionProfile[];
    },
  });
}

function activeMentionQuery(value: string, caret: number): { query: string; start: number } | null {
  const upto = value.slice(0, caret);
  const match = /(^|\s)@([A-Za-z0-9_]{0,30})$/.exec(upto);
  if (!match) return null;
  return { query: match[2].toLowerCase(), start: caret - match[2].length - 1 };
}

/**
 * Text field with @friend autocomplete. Renders an <input> or <textarea>.
 */
export function MentionInput({
  value,
  onChange,
  placeholder,
  multiline = false,
  rows = 2,
  maxLength = 1000,
  className,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  multiline?: boolean;
  rows?: number;
  maxLength?: number;
  className?: string;
}) {
  const { data: friends = [] } = useTaggableFriends();
  const ref = useRef<HTMLInputElement | HTMLTextAreaElement | null>(null);
  const [mention, setMention] = useState<{ query: string; start: number } | null>(null);

  const matches = useMemo(() => {
    if (!mention) return [];
    const q = mention.query;
    return friends
      .filter(
        (f) =>
          !q ||
          f.username.toLowerCase().includes(q) ||
          (f.display_name ?? "").toLowerCase().includes(q),
      )
      .slice(0, 6);
  }, [friends, mention]);

  function handleChange(e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) {
    const next = e.target.value;
    onChange(next);
    setMention(activeMentionQuery(next, e.target.selectionStart ?? next.length));
  }

  function pick(p: MentionProfile) {
    if (!mention) return;
    const end = mention.start + 1 + mention.query.length;
    const next = `${value.slice(0, mention.start)}@${p.username} ${value.slice(end)}`;
    onChange(next);
    setMention(null);
    requestAnimationFrame(() => {
      const el = ref.current;
      if (!el) return;
      el.focus();
      const pos = mention.start + p.username.length + 2;
      el.setSelectionRange(pos, pos);
    });
  }

  const shared = {
    value,
    onChange: handleChange,
    placeholder,
    maxLength,
    onBlur: () => setTimeout(() => setMention(null), 120),
    onKeyDown: (e: React.KeyboardEvent) => {
      if (e.key === "Escape" && mention) {
        e.stopPropagation();
        setMention(null);
      }
    },
  };

  return (
    <div className="relative min-w-0 flex-1">
      {mention && matches.length > 0 && (
        <div className="absolute bottom-full left-0 z-50 mb-2 w-full max-w-xs overflow-hidden rounded-xl border border-border bg-popover shadow-[0_8px_24px_rgba(0,0,0,0.08)]">
          {matches.map((p) => (
            <button
              key={p.id}
              type="button"
              onMouseDown={(e) => {
                e.preventDefault();
                pick(p);
              }}
              className="flex w-full items-center gap-2 px-3 py-2 text-left hover:bg-secondary"
            >
              <UserAvatar url={p.avatar_url} name={p.display_name || p.username} size="xs" />
              <span className="min-w-0 flex-1 truncate text-sm font-medium">
                {p.display_name || p.username}
              </span>
              <span className="truncate text-xs text-muted-foreground">@{p.username}</span>
            </button>
          ))}
        </div>
      )}
      {multiline ? (
        <textarea
          {...shared}
          ref={ref as React.RefObject<HTMLTextAreaElement>}
          rows={rows}
          className={cn(
            "w-full resize-none rounded-2xl border border-border bg-background px-4 py-2 text-sm outline-none focus:border-primary",
            className,
          )}
        />
      ) : (
        <input
          {...shared}
          ref={ref as React.RefObject<HTMLInputElement>}
          className={cn(
            "w-full rounded-full border border-border bg-background px-4 py-2 text-sm outline-none focus:border-primary",
            className,
          )}
        />
      )}
    </div>
  );
}

/** Renders comment text with @mentions linked to profiles. */
export function CommentText({ text, className }: { text: string; className?: string }) {
  const parts = text.split(/(@[A-Za-z0-9_]{2,30})/g);
  return (
    <p className={cn("whitespace-pre-wrap break-words", className)}>
      {parts.map((part, i) =>
        part.startsWith("@") ? (
          <Link
            key={i}
            to="/profile/$username"
            params={{ username: part.slice(1) }}
            onClick={(e) => e.stopPropagation()}
            className="font-semibold text-primary hover:underline"
          >
            {part}
          </Link>
        ) : (
          <span key={i}>{part}</span>
        ),
      )}
    </p>
  );
}
