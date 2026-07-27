import { createFileRoute } from "@tanstack/react-router";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import { Mic, UserPlus, UserCheck } from "lucide-react";

type Creator = {
  id: string;
  slug: string;
  name: string;
  color: string;
  emoji: string | null;
  rec_count: number;
};

export const Route = createFileRoute("/_authenticated/creators")({
  head: () => ({
    meta: [
      { title: "Creators — REX" },
      { name: "description", content: "Follow podcast creators on REX." },
    ],
  }),
  component: CreatorsPage,
});

function CreatorsPage() {
  const qc = useQueryClient();

  const { data: creators, isLoading } = useQuery({
    queryKey: ["creators"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("creators")
        .select("id, slug, name, color, emoji, recommendations!creator_id(count)")
        .order("name", { ascending: true })
        .returns<Creator[]>();
      if (error) throw error;
      return (data ?? []).map((c: any) => ({
        id: c.id,
        slug: c.slug,
        name: c.name,
        color: c.color,
        emoji: c.emoji,
        rec_count: c.recommendations?.[0]?.count ?? 0,
      })) as Creator[];
    },
  });

  const { data: follows } = useQuery({
    queryKey: ["creator-follows"],
    queryFn: async () => {
      const { data, error } = await supabase.from("creator_follows").select("creator_id");
      if (error) throw error;
      return new Set((data ?? []).map((f: any) => f.creator_id));
    },
  });

  const follow = useMutation({
    mutationFn: async (creatorId: string) => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error("Not signed in");
      const { error } = await supabase.from("creator_follows").insert({ user_id: user.id, creator_id: creatorId });
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["creator-follows"] });
      qc.invalidateQueries({ queryKey: ["feed"] });
      toast.success("Following creator");
    },
    onError: (e: any) => toast.error(e.message),
  });

  const unfollow = useMutation({
    mutationFn: async (creatorId: string) => {
      const { error } = await supabase.from("creator_follows").delete().eq("creator_id", creatorId);
      if (error) throw error;
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["creator-follows"] });
      qc.invalidateQueries({ queryKey: ["feed"] });
      toast.success("Unfollowed creator");
    },
    onError: (e: any) => toast.error(e.message),
  });

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <h1 className="font-display text-3xl">Creators</h1>
        <p className="mt-1 text-sm text-muted-foreground">Follow podcasts to see their picks in your feed.</p>
      </header>

      <div className="p-5">
        {isLoading && (
          <div className="space-y-3">
            <Skeleton />
            <Skeleton />
            <Skeleton />
          </div>
        )}

        {!isLoading && (creators?.length ?? 0) === 0 && (
          <p className="text-sm text-muted-foreground">No creators available yet.</p>
        )}

        <div className="space-y-3">
          {creators?.map((creator) => {
            const isFollowing = follows?.has(creator.id);
            return (
              <div
                key={creator.id}
                className="flex items-center justify-between rounded-2xl bg-card p-4 ring-1 ring-border"
                style={{ borderLeft: `4px solid ${creator.color}` }}
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div
                    className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-lg"
                    style={{ backgroundColor: `${creator.color}22` }}
                  >
                    {creator.emoji ?? "🎙️"}
                  </div>
                  <div className="min-w-0">
                    <p className="font-medium truncate">{creator.name}</p>
                    <p className="text-xs text-muted-foreground truncate">
                      @{creator.slug}
                      {creator.rec_count > 0 && ` · ${creator.rec_count} recommendation${creator.rec_count === 1 ? "" : "s"}`}
                    </p>
                  </div>
                </div>
                <Button
                  size="sm"
                  variant={isFollowing ? "outline" : "default"}
                  className="rounded-full shrink-0"
                  onClick={() => (isFollowing ? unfollow.mutate(creator.id) : follow.mutate(creator.id))}
                  disabled={follow.isPending || unfollow.isPending}
                >
                  {isFollowing ? (
                    <><UserCheck className="mr-1 h-3.5 w-3.5" /> Following</>
                  ) : (
                    <><UserPlus className="mr-1 h-3.5 w-3.5" /> Follow</>
                  )}
                </Button>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

function Skeleton() {
  return <div className="h-[76px] animate-pulse rounded-2xl bg-muted" />;
}
