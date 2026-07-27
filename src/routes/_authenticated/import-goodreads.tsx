import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import { ArrowLeft, Upload, Loader2, CheckCircle2 } from "lucide-react";
import { useServerFn } from "@tanstack/react-start";
import { searchBooks } from "@/lib/search.functions";

export const Route = createFileRoute("/_authenticated/import-goodreads")({
  head: () => ({
    meta: [
      { title: "Import from Goodreads — REX" },
      { name: "description", content: "Bring your Goodreads library into REX." },
    ],
  }),
  component: ImportGoodreads,
});

type Row = {
  title: string;
  author: string;
  myRating: number; // 0-5 from goodreads
  review: string;
  status: string;
};

// Minimal CSV parser that handles quoted fields with commas and escaped quotes.
function parseCSV(text: string): string[][] {
  const rows: string[][] = [];
  let field = "";
  let row: string[] = [];
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else { inQuotes = false; }
      } else field += c;
    } else {
      if (c === '"') inQuotes = true;
      else if (c === ",") { row.push(field); field = ""; }
      else if (c === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
      else if (c === "\r") { /* skip */ }
      else field += c;
    }
  }
  if (field.length || row.length) { row.push(field); rows.push(row); }
  return rows;
}

function ImportGoodreads() {
  const navigate = useNavigate();
  const [rows, setRows] = useState<Row[]>([]);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [importing, setImporting] = useState(false);
  const [progress, setProgress] = useState(0);
  const [done, setDone] = useState(0);
  const bookSearch = useServerFn(searchBooks);

  function onFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    const reader = new FileReader();
    reader.onload = () => {
      const text = String(reader.result ?? "");
      const parsed = parseCSV(text);
      if (parsed.length < 2) { toast.error("Empty CSV"); return; }
      const headers = parsed[0].map((h) => h.trim());
      const idx = (name: string) => headers.findIndex((h) => h.toLowerCase() === name.toLowerCase());
      const iTitle = idx("Title");
      const iAuthor = idx("Author");
      const iRating = idx("My Rating");
      const iReview = idx("My Review");
      const iShelf = idx("Exclusive Shelf");
      if (iTitle < 0) { toast.error("Doesn't look like a Goodreads export"); return; }
      const out: Row[] = [];
      for (let i = 1; i < parsed.length; i++) {
        const r = parsed[i];
        if (!r[iTitle]) continue;
        out.push({
          title: r[iTitle] ?? "",
          author: iAuthor >= 0 ? r[iAuthor] ?? "" : "",
          myRating: iRating >= 0 ? parseInt(r[iRating] || "0", 10) || 0 : 0,
          review: iReview >= 0 ? r[iReview] ?? "" : "",
          status: iShelf >= 0 ? r[iShelf] ?? "" : "",
        });
      }
      setRows(out);
      // Default: only select "read" books with a rating
      const initial = new Set<number>();
      out.forEach((r, i) => { if (r.status === "read" && r.myRating > 0) initial.add(i); });
      setSelected(initial);
      toast.success(`Loaded ${out.length} books — ${initial.size} pre-selected`);
    };
    reader.readAsText(f);
  }

  function toggle(i: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(i)) next.delete(i); else next.add(i);
      return next;
    });
  }

  async function runImport() {
    const { data: userRes } = await supabase.auth.getUser();
    const uid = userRes.user?.id;
    if (!uid) { toast.error("Not signed in"); return; }
    const ids = Array.from(selected);
    if (ids.length === 0) { toast.error("Select at least one book"); return; }
    setImporting(true);
    setProgress(0);
    setDone(0);
    let count = 0;
    for (const i of ids) {
      const r = rows[i];
      try {
        // Try to enrich via Google Books
        let externalId: string | null = null;
        let imageUrl: string | null = null;
        let title = r.title;
        let author = r.author;
        try {
          const hits = await bookSearch({ data: { q: `${r.title} ${r.author}`.slice(0, 100) } });
          const hit = hits[0];
          if (hit) {
            externalId = hit.external_id;
            imageUrl = hit.image_url;
            title = hit.title || title;
            author = hit.subtitle || author;
          }
        } catch { /* ignore, fall back to raw csv row */ }

        let itemId: string | undefined;
        if (externalId) {
          const { data: existing } = await supabase
            .from("items").select("id")
            .eq("external_source", "google_books").eq("external_id", externalId).maybeSingle();
          itemId = existing?.id;
        }
        if (!itemId) {
          const { data: item, error } = await supabase.from("items").insert({
            type: "book",
            title,
            subtitle: author || null,
            image_url: imageUrl,
            external_id: externalId,
            external_source: externalId ? "google_books" : null,
          }).select("id").single();
          if (error) throw error;
          itemId = item.id;
        }
        // Goodreads rating is 1-5; scale to 1-10. If 0 (unrated), default to 8.
        const rating = r.myRating > 0 ? r.myRating * 2 : 8;
        await supabase.from("recommendations").insert({
          user_id: uid,
          item_id: itemId,
          rating,
          note: r.review?.trim() ? r.review.trim().slice(0, 2000) : null,
        });
        count++;
        setDone(count);
      } catch (err) {
        console.error("import row failed", r.title, err);
      }
      setProgress(Math.round(((count) / ids.length) * 100));
    }
    setImporting(false);
    toast.success(`Imported ${count} of ${ids.length} books`);
    setTimeout(() => navigate({ to: "/me" }), 800);
  }

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button
          onClick={() => navigate({ to: "/me" })}
          className="flex items-center gap-2 text-sm text-muted-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Back
        </button>
        <h1 className="mt-3 font-display text-3xl">Import from Goodreads</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Export your library at{" "}
          <a
            href="https://www.goodreads.com/review/import"
            target="_blank"
            rel="noreferrer"
            className="underline"
          >
            goodreads.com/review/import
          </a>{" "}
          — then upload the CSV here.
        </p>
      </header>

      <div className="space-y-5 p-5">
        {rows.length === 0 && (
          <label className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-3xl border-2 border-dashed border-border bg-card p-10 text-center transition-colors hover:bg-muted/40">
            <Upload className="h-8 w-8 text-muted-foreground" />
            <div className="font-medium">Choose Goodreads CSV</div>
            <div className="text-xs text-muted-foreground">We only read it in your browser</div>
            <input type="file" accept=".csv,text/csv" className="hidden" onChange={onFile} />
          </label>
        )}

        {rows.length > 0 && !importing && (
          <>
            <div className="flex items-center justify-between text-sm">
              <span className="text-muted-foreground">{selected.size} of {rows.length} selected</span>
              <div className="flex gap-3">
                <button
                  className="text-primary underline"
                  onClick={() => setSelected(new Set(rows.map((_, i) => i)))}
                >
                  Select all
                </button>
                <button
                  className="text-muted-foreground underline"
                  onClick={() => setSelected(new Set())}
                >
                  Clear
                </button>
              </div>
            </div>

            <ul className="divide-y divide-border overflow-hidden rounded-2xl bg-card ring-1 ring-border">
              {rows.map((r, i) => (
                <li key={i}>
                  <button
                    type="button"
                    onClick={() => toggle(i)}
                    className="flex w-full items-center gap-3 p-3 text-left"
                  >
                    <input
                      type="checkbox"
                      readOnly
                      checked={selected.has(i)}
                      className="h-5 w-5 flex-none accent-primary"
                    />
                    <div className="min-w-0 flex-1">
                      <div className="truncate font-medium">{r.title}</div>
                      <div className="truncate text-sm text-muted-foreground">
                        {r.author}
                        {r.myRating > 0 && <> · {r.myRating}/5 ★</>}
                        {r.status && <> · {r.status}</>}
                      </div>
                    </div>
                  </button>
                </li>
              ))}
            </ul>

            <Button
              onClick={runImport}
              disabled={selected.size === 0}
              className="h-14 w-full rounded-full text-base font-semibold shadow-lg shadow-primary/30"
            >
              Import {selected.size} book{selected.size === 1 ? "" : "s"}
            </Button>
          </>
        )}

        {importing && (
          <div className="flex flex-col items-center gap-4 rounded-2xl bg-card p-8 ring-1 ring-border">
            <Loader2 className="h-8 w-8 animate-spin text-primary" />
            <div className="text-sm text-muted-foreground">Importing {done} of {selected.size}…</div>
            <div className="h-2 w-full overflow-hidden rounded-full bg-muted">
              <div
                className="h-full bg-primary transition-all"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>
        )}

        {!importing && done > 0 && (
          <div className="flex items-center gap-2 rounded-xl bg-primary/10 p-3 text-sm text-primary">
            <CheckCircle2 className="h-4 w-4" /> Imported {done} books
          </div>
        )}
      </div>
    </div>
  );
}
