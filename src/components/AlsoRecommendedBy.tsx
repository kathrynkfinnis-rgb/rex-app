import { Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";

type Person = { username: string; display_name: string | null };

export function AlsoRecommendedBy({
  itemId,
  excludeUserId,
}: {
  itemId: string;
  excludeUserId: string;
}) {
  const { data } = useQuery({
    queryKey: ["also-recommended", itemId, excludeUserId],
    staleTime: 60 * 1000,
    queryFn: async (): Promise<Person[]> => {
      const { data, error } = await supabase
        .from("recommendations")
        .select("user_id, profiles!recommendations_user_id_fkey(username, display_name)")
        .eq("item_id", itemId)
        .neq("user_id", excludeUserId)
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) throw error;
      const seen = new Set<string>();
      const people: Person[] = [];
      for (const row of data ?? []) {
        const p = (row as any).profiles as Person | null;
        if (!p?.username || seen.has(p.username)) continue;
        seen.add(p.username);
        people.push(p);
      }
      return people;
    },
  });

  const people = data ?? [];
  if (people.length === 0) return null;

  const shown = people.slice(0, 2);
  const extra = people.length - shown.length;

  return (
    <p className="border-t border-border px-3 py-1.5 text-[11px] text-muted-foreground">
      Also recommended by{" "}
      {shown.map((p, i) => (
        <span key={p.username}>
          {i > 0 && (i === shown.length - 1 && extra === 0 ? " and " : ", ")}
          <Link
            to="/profile/$username"
            params={{ username: p.username }}
            onClick={(e) => e.stopPropagation()}
            className="font-medium text-primary hover:underline"
          >
            {p.display_name || p.username}
          </Link>
        </span>
      ))}
      {extra > 0 && (
        <>
          {" "}
          and{" "}
          <Link
            to="/item/$id"
            params={{ id: itemId }}
            className="font-medium text-primary hover:underline"
          >
            {extra} other{extra > 1 ? "s" : ""}
          </Link>
        </>
      )}
    </p>
  );
}
