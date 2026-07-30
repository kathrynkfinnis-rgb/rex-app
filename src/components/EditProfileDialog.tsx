import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog";
import { toast } from "sonner";
import { Pencil } from "lucide-react";

export function EditProfileDialog({
  userId,
  username,
  displayName,
}: {
  userId: string;
  username: string;
  displayName?: string | null;
}) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);
  const [uname, setUname] = useState(username);
  const [dname, setDname] = useState(displayName ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const clean = uname.trim().toLowerCase();
  const valid = /^[a-z0-9_]{3,30}$/.test(clean);

  async function save() {
    setError(null);
    if (!valid) {
      setError("Username must be 3–30 characters: lowercase letters, numbers or underscores.");
      return;
    }
    if (dname.trim().length > 50) {
      setError("Display name must be 50 characters or fewer.");
      return;
    }
    setSaving(true);
    const { error: err } = await supabase
      .from("profiles")
      .update({ username: clean, display_name: dname.trim() || clean })
      .eq("id", userId);
    setSaving(false);
    if (err) {
      setError(
        err.code === "23505" || /duplicate|unique/i.test(err.message)
          ? "That username is already taken."
          : err.message,
      );
      return;
    }
    toast.success("Profile updated");
    setOpen(false);
    qc.invalidateQueries();
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm" className="gap-1.5">
          <Pencil className="h-3.5 w-3.5" /> Edit
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit profile</DialogTitle>
        </DialogHeader>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <Label htmlFor="edit-username">Username</Label>
            <div className="flex items-center gap-2">
              <span className="text-muted-foreground">@</span>
              <Input
                id="edit-username"
                value={uname}
                maxLength={30}
                autoCapitalize="none"
                onChange={(e) => setUname(e.target.value)}
              />
            </div>
            <p className="text-xs text-muted-foreground">
              Lowercase letters, numbers and underscores. Friends find you by this.
            </p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="edit-display">Display name</Label>
            <Input
              id="edit-display"
              value={dname}
              maxLength={50}
              onChange={(e) => setDname(e.target.value)}
              placeholder="How your name shows up"
            />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={save} disabled={saving}>{saving ? "Saving…" : "Save"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
