import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

/** Your private "top friends" — only ever visible to you. */
export function useTopFriends() {
  return useQuery({
    queryKey: ["top-friends"],
    queryFn: async () => {
      const { data, error } = await supabase.from("top_friends").select("friend_id");
      if (error) throw error;
      return new Set((data ?? []).map((r: any) => r.friend_id as string));
    },
  });
}

export function useToggleTopFriend() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ friendId, isTop }: { friendId: string; isTop: boolean }) => {
      if (isTop) {
        const { error } = await supabase.from("top_friends").delete().eq("friend_id", friendId);
        if (error) throw error;
        return false;
      }
      const { data: auth } = await supabase.auth.getUser();
      const uid = auth.user?.id;
      if (!uid) throw new Error("Not signed in");
      const { error } = await supabase.from("top_friends").insert({ user_id: uid, friend_id: friendId });
      if (error) throw error;
      return true;
    },
    onSuccess: (added) => {
      qc.invalidateQueries({ queryKey: ["top-friends"] });
      toast.success(added ? "Added to your top friends" : "Removed from your top friends");
    },
    onError: (e: any) => toast.error(e.message ?? "Couldn't update top friends"),
  });
}
