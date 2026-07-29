import { useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Camera, Loader2, X } from "lucide-react";
import { toast } from "sonner";

const SIGNED_URL_TTL_SECONDS = 60 * 60 * 24 * 365 * 5; // 5 years
const MAX_PHOTOS = 6;

export function PhotoUploader({
  userId,
  value,
  onChange,
}: {
  userId: string;
  value: string[];
  onChange: (urls: string[]) => void;
}) {
  const fileRef = useRef<HTMLInputElement | null>(null);
  const [uploading, setUploading] = useState(false);

  async function handleFiles(files: FileList) {
    const remaining = MAX_PHOTOS - value.length;
    if (remaining <= 0) {
      toast.error(`Max ${MAX_PHOTOS} photos`);
      return;
    }
    const list = Array.from(files).slice(0, remaining);
    setUploading(true);
    const uploaded: string[] = [];
    try {
      for (const file of list) {
        if (!file.type.startsWith("image/")) {
          toast.error(`${file.name} isn't an image`);
          continue;
        }
        if (file.size > 8 * 1024 * 1024) {
          toast.error(`${file.name} is over 8MB`);
          continue;
        }
        const ext = (file.name.split(".").pop() || "jpg").toLowerCase();
        const path = `${userId}/${crypto.randomUUID()}.${ext}`;
        const { error: upErr } = await supabase.storage
          .from("rec-photos")
          .upload(path, file, { contentType: file.type });
        if (upErr) throw upErr;
        const { data: signed, error: signErr } = await supabase.storage
          .from("rec-photos")
          .createSignedUrl(path, SIGNED_URL_TTL_SECONDS);
        if (signErr || !signed?.signedUrl) throw signErr ?? new Error("Couldn't sign URL");
        uploaded.push(signed.signedUrl);
      }
      if (uploaded.length) onChange([...value, ...uploaded]);
    } catch (e: any) {
      toast.error(e.message ?? "Upload failed");
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  }

  function remove(idx: number) {
    onChange(value.filter((_, i) => i !== idx));
  }

  return (
    <div>
      <div className="flex flex-wrap gap-2">
        {value.map((url, i) => (
          <div
            key={url}
            className="relative h-20 w-20 overflow-hidden rounded-xl ring-1 ring-border"
          >
            <img src={url} alt="" className="h-full w-full object-cover" />
            <button
              type="button"
              onClick={() => remove(i)}
              aria-label="Remove photo"
              className="absolute right-1 top-1 flex h-6 w-6 items-center justify-center rounded-full bg-background/80 text-foreground shadow-sm ring-1 ring-border hover:bg-background"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}
        {value.length < MAX_PHOTOS && (
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            disabled={uploading}
            className="flex h-20 w-20 flex-col items-center justify-center gap-1 rounded-xl border-2 border-dashed border-border bg-muted/40 text-xs text-muted-foreground hover:bg-muted disabled:opacity-70"
          >
            {uploading ? (
              <Loader2 className="h-5 w-5 animate-spin" />
            ) : (
              <>
                <Camera className="h-5 w-5" />
                <span>Add photo</span>
              </>
            )}
          </button>
        )}
      </div>
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        multiple
        className="hidden"
        onChange={(e) => {
          if (e.target.files?.length) handleFiles(e.target.files);
        }}
      />
      <p className="mt-1.5 text-[11px] text-muted-foreground">
        Up to {MAX_PHOTOS} photos, 8MB each
      </p>
    </div>
  );
}
