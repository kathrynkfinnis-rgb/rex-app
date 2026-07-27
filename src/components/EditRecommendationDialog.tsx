import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
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
import { CrownRatingInput } from "@/components/CrownRating";
import { Loader2, Trash2 } from "lucide-react";
import { toast } from "sonner";

export function EditRecommendationDialog({
  open,
  onOpenChange,
  recommendation,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  recommendation: { id: string; rating: number; note: string | null };
}) {
  const qc = useQueryClient();
  const [rating, setRating] = useState(recommendation.rating);
  const [note, setNote] = useState(recommendation.note ?? "");
  const [confirmDelete, setConfirmDelete] = useState(false);

  const save = useMutation({
    mutationFn: async () => {
      const { error } = await supabase
        .from("recommendations")
        .update({ rating, note: note.trim() ? note.trim() : null })
        .eq("id", recommendation.id);
      if (error) throw error;
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
            <div>
              <label className="mb-2 block text-sm font-medium">Note</label>
              <Textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={4}
                placeholder="What did you think?"
              />
            </div>
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
