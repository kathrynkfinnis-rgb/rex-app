export type NotificationType =
  | "rec_like"
  | "rec_comment"
  | "friend_request"
  | "friend_accepted"
  | "blast_new"
  | "blast_comment"
  | "friend_new_rec";

export type NotificationRow = {
  id: string;
  user_id: string;
  actor_id: string | null;
  type: NotificationType;
  entity_type: string | null;
  entity_id: string | null;
  data: Record<string, any>;
  read_at: string | null;
  created_at: string;
  actor?: { username: string | null; display_name: string | null; avatar_url: string | null } | null;
};

export function notifCopy(n: NotificationRow): string {
  const who = n.actor?.display_name || n.actor?.username || "Someone";
  switch (n.type) {
    case "rec_like":
      return `${who} liked your recommendation`;
    case "rec_comment":
      return `${who} commented: "${(n.data?.preview as string) || ""}"`;
    case "friend_request":
      return `${who} sent you a friend request`;
    case "friend_accepted":
      return `${who} accepted your friend request`;
    case "blast_new":
      return `${who} put out a blast: "${n.data?.title || ""}"`;
    case "blast_comment":
      return n.data?.has_suggestion
        ? `${who} suggested something on your blast "${n.data?.title || ""}"`
        : `${who} replied to your blast: "${(n.data?.preview as string) || ""}"`;
    case "friend_new_rec":
      return `${who} recommended ${n.data?.title || "something new"}`;
    default:
      return "New activity";
  }
}

export function notifHref(n: NotificationRow): string {
  if (n.entity_type === "recommendation" && n.entity_id) return `/item/${n.entity_id}`;
  if (n.entity_type === "request" && n.entity_id) return `/ask/${n.entity_id}`;
  if (n.entity_type === "friendship") return `/friends`;
  return `/notifications`;
}

export const PREF_LABELS: Record<
  Exclude<keyof PrefRow, "user_id" | "created_at" | "updated_at" | "email_enabled">,
  { label: string; description: string }
> = {
  rec_comment: { label: "Comments on my recommendations", description: "When someone replies to a rec you posted" },
  rec_like: { label: "Likes on my recommendations", description: "When someone likes a rec you posted" },
  friend_request: { label: "New friend requests", description: "When someone wants to connect" },
  friend_accepted: { label: "Friend requests accepted", description: "When someone accepts your request" },
  blast_new: { label: "New blasts from friends", description: "When a friend posts a want-a-rec" },
  blast_comment: { label: "Replies to my blasts", description: "Comments or suggestions on blasts you posted" },
  friend_new_rec: { label: "New recs from friends", description: "Every time a friend posts a recommendation (can be noisy)" },
};

export type PrefRow = {
  user_id: string;
  rec_like: boolean;
  rec_comment: boolean;
  friend_request: boolean;
  friend_accepted: boolean;
  blast_new: boolean;
  blast_comment: boolean;
  friend_new_rec: boolean;
  email_enabled: boolean;
  created_at?: string;
  updated_at?: string;
};

export const DEFAULT_PREFS: Omit<PrefRow, "user_id" | "created_at" | "updated_at"> = {
  rec_like: true,
  rec_comment: true,
  friend_request: true,
  friend_accepted: true,
  blast_new: true,
  blast_comment: true,
  friend_new_rec: false,
  email_enabled: false,
};
