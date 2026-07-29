import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { CrownRatingInput } from "@/components/CrownRating";
import { Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { subcategoriesFor, categoryMeta, type ItemType } from "@/lib/categories";
import { cn } from "@/lib/utils";
import { RecipeEditor } from "@/components/RecipeEditor";
import { PhotoUploader } from "@/components/PhotoUploader";
import { TagsInput } from "@/components/TagsInput";

export function EditRecommendationDialog({
  open,
  onOpenChange,
  recommendation,
  item,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  recommendation: { id: string; rating: number; note: string | null; photo_url?: string | null; photo_urls?: string[] | null; tags?: string[] | null };
  item?: { id: string; type: ItemType; genre: string | null; recipe_text?: string | null } | null;
}) {
  const qc = useQueryClient();
  const [rating, setRating] = useState(recommendation.rating);
  const [note, setNote] = useState(recommendation.note ?? "");
  const initialPhotos = (recommendation.photo_urls && recommendation.photo_urls.length
    ? recommendation.photo_urls
    : recommendation.photo_url
    ? [recommendation.photo_url]
    : []) as string[];
  const [photos, setPhotos] = useState<string[]>(initialPhotos);
  const [tags, setTags] = useState<string[]>(recommendation.tags ?? []);
  const subOptions = item ? subcategoriesFor(item.type) : [];
  const [placeSub, setPlaceSub] = useState<string>(
    item && (subOptions as readonly string[]).includes(item.genre ?? "") ? (item.genre as string) : "",
  );
  const [recipeText, setRecipeText] = useState(item?.recipe_text ?? "");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const isPlace = item?.type === "place";
  const isRecipe = item?.type === "recipe";
  const { data: uid } = useQuery({
    queryKey: ["current-user-id"],
    queryFn: async () => (await supabase.auth.getUser()).data.user?.id ?? null,
    staleTime: 5 * 60 * 1000,
  });

  useEffect(() => {
    if (!open || !isRecipe || !item?.id) return;
    if (item.recipe_text != null) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("items")
        .select("recipe_text" as never)
        .eq("id", item.id)
        .maybeSingle();
      if (!cancelled && data && (data as any).recipe_text != null) {
        setRecipeText((data as any).recipe_text ?? "");
      }
    })();
    return () => { cancelled = true; };
  }, [open, isRecipe, item?.id, item?.recipe_text]);

  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from("recommendations")
        .update({
          rating,
          note: note.trim() ? note.trim() : null,
          photo_url: photos[0] ?? null,
          photo_urls: photos,
          tags,
        } as never)
        .eq("id", recommendation.id);
      if (error) throw error;
      if (item && subOptions.length > 0) {
        const nextGenre = placeSub || null;
        if ((item.genre ?? null) !== nextGenre) {
          const { error: itemErr } = await supabase
            .from("items")
            .update({ genre: nextGenre })
            .eq("id", item.id);
          if (itemErr) throw itemErr;
        }
      }
      if (isRecipe && item) {
        const nextRecipe = recipeText.trim() ? recipeText : null;
        if ((item.recipe_text ?? null) !== nextRecipe) {
          const { error: itemErr } = await supabase
            .from("items")
            .update({ recipe_text: nextRecipe } as never)
            .eq("id", item.id);
          if (itemErr) throw itemErr;
        }
      }
    },
    onSuccess: () => {
      toast.success("Post updated");
      qc.invalidateQueries();
      onOpenChange(false);
    },
    onError: (e: any) => toast.error(e.message ?? "Couldn't update"),
  });

  const del = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from("recommendations")
        .delete()
        .eq("id", recommendation.id);
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Post deleted");
      qc.invalidateQueries();
      setConfirmDelete(false);
      onOpenChange(false);
    },
    onError: (e: any) => toast.error(e.message ?? "Couldn't delete"),
  });

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Edit post</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <label className="mb-2 block text-sm font-medium">Rating</label>
              <CrownRatingInput value={rating} onChange={setRating} size="md" />
            </div>
            {item && subOptions.length > 0 && (
              <div className="space-y-1.5">
                <Label>{isPlace ? "Type of place" : `Type of ${categoryMeta(item.type).label.toLowerCase()}`}</Label>
                <div className="flex flex-wrap gap-2">
                  {subOptions.map((s) => {
                    const active = placeSub === s;
                    return (
                      <button
                        key={s}
                        type="button"
                        onClick={() => setPlaceSub(active ? "" : s)}
                        className={cn(
                          "rounded-full px-3 py-1.5 text-sm ring-1 transition-colors",
                          active
                            ? "bg-primary text-primary-foreground ring-primary"
                            : "bg-card text-foreground ring-border hover:bg-muted",
                        )}
                      >
                        {s}
                      </button>
                    );
                  })}
                </div>
                <p className="text-xs text-muted-foreground">
                  Changing this updates the tag for everyone who saved it.
                </p>
              </div>
            )}
            {isRecipe && (
              <div className="space-y-1.5">
                <RecipeEditor value={recipeText} onChange={setRecipeText} />
                <p className="text-xs text-muted-foreground">
                  Saved on the recipe so everyone who opens it can read it.
                </p>
              </div>
            )}

            <div>
              <label className="mb-2 block text-sm font-medium">Note</label>
              <Textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={4}
                placeholder="What did you think?"
              />
            </div>

            {uid && (
              <div className="space-y-1.5">
                <Label>Photos</Label>
                <PhotoUploader userId={uid} value={photos} onChange={setPhotos} />
              </div>
            )}
          </div>
          <DialogFooter className="flex-row justify-between sm:justify-between">
            <Button
              type="button"
              variant="ghost"
              className="text-destructive hover:text-destructive"
              onClick={() => setConfirmDelete(true)}
            >
              <Trash2 className="mr-1.5 h-4 w-4" /> Delete
            </Button>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => onOpenChange(false)}>
                Cancel
              </Button>
              <Button onClick={() => save.mutate()} disabled={save.isPending}>
                {save.isPending && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
                Save
              </Button>
            </div>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete this post?</AlertDialogTitle>
            <AlertDialogDescription>
              This will permanently remove your recommendation. This can't be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              onClick={(e) => {
                e.preventDefault();
                del.mutate();
              }}
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
            >
              {del.isPending ? "Deleting…" : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  );
}
