import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useState } from "react";
import { useServerFn } from "@tanstack/react-start";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import {
  ArrowLeft,
  FileSpreadsheet,
  FileText,
  Upload,
  Loader2,
  Check,
  X,
  Sparkles,
  Search,
  MapPin,
  Film,
} from "lucide-react";
import mammoth from "mammoth";
import {
  extractFromText,
  fetchSheetCsv,
  fetchGoogleMapsList,
  importGoogleMapsPlaces,
  importImdbTitles,
  resolveStagingRow,
  approveStagingRow,
} from "@/lib/import.functions";


export const Route = createFileRoute("/_authenticated/import")({
  head: () => ({
    meta: [
      { title: "Import Rex — REX" },
      { name: "description", content: "Bring Rex from Google Sheets or Word docs into REX." },
    ],
  }),
  component: ImportPage,
});

type Tab = "sheet" | "docx" | "paste" | "gmaps" | "imdb";

function ImportPage() {
  const navigate = useNavigate();
  const qc = useQueryClient();
  const [tab, setTab] = useState<Tab>("sheet");
  const [sheetUrl, setSheetUrl] = useState("");
  const [pasted, setPasted] = useState("");
  const [gmapsUrl, setGmapsUrl] = useState("");
  const [loading, setLoading] = useState(false);

  const fetchSheet = useServerFn(fetchSheetCsv);
  const extract = useServerFn(extractFromText);
  const fetchGmaps = useServerFn(fetchGoogleMapsList);
  const importGmaps = useServerFn(importGoogleMapsPlaces);
  const importImdb = useServerFn(importImdbTitles);
  const resolve = useServerFn(resolveStagingRow);
  const approve = useServerFn(approveStagingRow);


  const { data: staging } = useQuery({
    queryKey: ["import-staging"],
    queryFn: async () => {
      const { data } = await supabase
        .from("import_staging")
        .select("*")
        .eq("status", "pending")
        .order("created_at", { ascending: false });
      return data ?? [];
    },
  });

  async function runExtract(text: string, source: string) {
    if (!text.trim()) {
      toast.error("Nothing to import");
      return;
    }
    setLoading(true);
    try {
      const { inserted } = await extract({ data: { text, source } });
      if (inserted === 0) {
        toast.error("Couldn't find any Rex in that");
      } else {
        toast.success(`Extracted ${inserted} candidate${inserted === 1 ? "" : "s"} — review below`);
        setPasted("");
        setSheetUrl("");
        qc.invalidateQueries({ queryKey: ["import-staging"] });
      }
    } catch (e: any) {
      toast.error(e.message ?? "Extraction failed");
    } finally {
      setLoading(false);
    }
  }

  async function onSheetImport() {
    if (!sheetUrl.trim()) return;
    setLoading(true);
    try {
      const { csv } = await fetchSheet({ data: { url: sheetUrl.trim() } });
      await runExtract(csv, "google_sheet");
    } catch (e: any) {
      setLoading(false);
      toast.error(e.message ?? "Couldn't read the sheet");
    }
  }

  async function onDocxFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setLoading(true);
    try {
      const buf = await f.arrayBuffer();
      const result = await mammoth.extractRawText({ arrayBuffer: buf });
      await runExtract(result.value, `docx:${f.name}`);
    } catch (err: any) {
      setLoading(false);
      toast.error(err.message ?? "Couldn't read that file");
    }
  }

  function parseCsvLine(line: string): string[] {
    const out: string[] = [];
    let cur = "";
    let inQ = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inQ) {
        if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
        else if (c === '"') inQ = false;
        else cur += c;
      } else {
        if (c === ",") { out.push(cur); cur = ""; }
        else if (c === '"') inQ = true;
        else cur += c;
      }
    }
    out.push(cur);
    return out.map((s) => s.trim());
  }

  function extractPlaceNameFromMapsUrl(url: string): string | null {
    try {
      const u = new URL(url);
      const q = u.searchParams.get("q");
      if (q) {
        // Google Takeout saved-place URLs use q=Name, Address, City...
        return decodeURIComponent(q.split(",")[0]).trim() || null;
      }
      const m = u.pathname.match(/\/maps\/place\/([^/]+)/);
      if (m) return decodeURIComponent(m[1].replace(/\+/g, " ")).trim();
    } catch {}
    return null;
  }

  async function onGmapsFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setLoading(true);
    try {
      const text = await f.text();
      const places: { title: string; address?: string | null; note?: string | null }[] = [];
      if (f.name.toLowerCase().endsWith(".json") || text.trim().startsWith("{")) {
        // GeoJSON export from Takeout
        const json = JSON.parse(text);
        const features: any[] = json.features ?? [];
        for (const ft of features) {
          const props = ft.properties ?? {};
          const loc = props.location ?? {};
          const title = loc.name || props.name || props.title;
          if (!title) continue;
          places.push({
            title: String(title),
            address: loc.address ?? null,
            note: props.Comment ?? props.comment ?? null,
          });
        }
      } else {
        // CSV: Title,Note,URL  (Google Takeout "Saved Places" / lists)
        const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
        if (!lines.length) throw new Error("Empty file");
        const header = parseCsvLine(lines[0]).map((h) => h.toLowerCase());
        const idxTitle = header.findIndex((h) => h === "title" || h === "name");
        const idxNote = header.findIndex((h) => h === "note" || h === "comment");
        const idxUrl = header.findIndex((h) => h === "url" || h === "link");
        for (let i = 1; i < lines.length; i++) {
          const cells = parseCsvLine(lines[i]);
          let title = idxTitle >= 0 ? cells[idxTitle] : cells[0];
          const note = idxNote >= 0 ? cells[idxNote] : null;
          const url = idxUrl >= 0 ? cells[idxUrl] : null;
          if ((!title || title.toLowerCase() === "url" || /^https?:/i.test(title)) && url) {
            title = extractPlaceNameFromMapsUrl(url) ?? title;
          }
          if (!title) continue;
          places.push({ title, address: null, note: note || null });
        }
      }
      if (!places.length) throw new Error("No places found in that file");
      const { inserted } = await importGmaps({ data: { source: `google_maps:${f.name}`, places: places.slice(0, 500) } });
      toast.success(`Imported ${inserted} place${inserted === 1 ? "" : "s"} — review below`);
      qc.invalidateQueries({ queryKey: ["import-staging"] });
    } catch (err: any) {
      toast.error(err.message ?? "Couldn't read that file");
    } finally {
      setLoading(false);
    }
  }

  async function onGmapsUrl() {
    if (!gmapsUrl.trim()) return;
    setLoading(true);
    try {
      const { titles } = await fetchGmaps({ data: { url: gmapsUrl.trim() } });
      if (!titles.length) {
        toast.error("Couldn't read that list — Google may be blocking it. Try Takeout export.");
        return;
      }
      const { inserted } = await importGmaps({
        data: {
          source: "google_maps_url",
          places: titles.map((t) => ({ title: t })),
        },
      });
      toast.success(`Imported ${inserted} place${inserted === 1 ? "" : "s"} — review below`);
      setGmapsUrl("");
      qc.invalidateQueries({ queryKey: ["import-staging"] });
    } catch (e: any) {
      toast.error(e.message ?? "Couldn't read that list");
    } finally {
      setLoading(false);
    }
  }

  function imdbTitleType(raw: string): "movie" | "tv" | null {
    const t = raw.toLowerCase().trim();
    if (!t) return null;
    if (t.includes("tv") || t.includes("series") || t.includes("mini")) return "tv";
    if (t === "movie" || t.includes("movie") || t === "video" || t === "short") return "movie";
    return null;
  }

  async function onImdbFile(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (!f) return;
    setLoading(true);
    try {
      const text = await f.text();
      const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
      if (lines.length < 2) throw new Error("File looks empty");
      const header = parseCsvLine(lines[0]).map((h) => h.toLowerCase().replace(/^"|"$/g, "").trim());
      const idxTitle = header.findIndex((h) => h === "title" || h === "original title" || h === "primary title");
      const idxType = header.findIndex((h) => h === "title type" || h === "titletype");
      const idxYear = header.findIndex((h) => h === "year");
      const idxYourRating = header.findIndex((h) => h === "your rating");
      if (idxTitle < 0) throw new Error("Couldn't find a Title column — is this the IMDb CSV export?");
      const titles: {
        title: string;
        type: "movie" | "tv";
        year?: string | null;
        rating?: number | null;
      }[] = [];
      for (let i = 1; i < lines.length; i++) {
        const cells = parseCsvLine(lines[i]);
        const title = cells[idxTitle];
        if (!title) continue;
        const type = imdbTitleType(idxType >= 0 ? cells[idxType] ?? "" : "movie") ?? "movie";
        const year = idxYear >= 0 ? cells[idxYear] || null : null;
        const ratingStr = idxYourRating >= 0 ? cells[idxYourRating] : "";
        const ratingNum = ratingStr ? Number(ratingStr) : NaN;
        titles.push({
          title: title.replace(/^"|"$/g, ""),
          type,
          year,
          rating: Number.isFinite(ratingNum) && ratingNum > 0 ? ratingNum : null,
        });
      }
      if (!titles.length) throw new Error("No titles found in that file");
      const { inserted } = await importImdb({
        data: { source: `imdb:${f.name}`, titles: titles.slice(0, 1000) },
      });
      toast.success(`Imported ${inserted} title${inserted === 1 ? "" : "s"} — review below`);
      qc.invalidateQueries({ queryKey: ["import-staging"] });
    } catch (err: any) {
      toast.error(err.message ?? "Couldn't read that file");
    } finally {
      setLoading(false);
    }
  }



  async function onResolve(id: string) {
    try {
      const { matched } = await resolve({ data: { id } });
      toast[matched ? "success" : "message"](matched ? "Matched" : "No match found");
      qc.invalidateQueries({ queryKey: ["import-staging"] });
    } catch (e: any) {
      toast.error(e.message ?? "Match failed");
    }
  }

  async function onApprove(row: any) {
    try {
      await approve({ data: { id: row.id, rating: row.raw_rating ?? null, note: row.raw_note ?? null } });
      toast.success("Added to your feed");
      qc.invalidateQueries({ queryKey: ["import-staging"] });
    } catch (e: any) {
      toast.error(e.message ?? "Failed");
    }
  }

  async function onReject(id: string) {
    await supabase.from("import_staging").update({ status: "rejected" }).eq("id", id);
    qc.invalidateQueries({ queryKey: ["import-staging"] });
  }

  const TABS: { id: Tab; label: string; icon: typeof FileSpreadsheet }[] = [
    { id: "sheet", label: "Sheet", icon: FileSpreadsheet },
    { id: "gmaps", label: "Maps", icon: MapPin },
    { id: "imdb", label: "IMDb", icon: Film },
    { id: "docx", label: ".docx", icon: FileText },
    { id: "paste", label: "Paste", icon: Sparkles },
  ];

  return (
    <div>
      <header className="border-b border-border bg-background px-5 pb-4 pt-[calc(env(safe-area-inset-top)+1rem)]">
        <button
          onClick={() => navigate({ to: "/me" })}
          className="flex items-center gap-2 text-sm text-muted-foreground"
        >
          <ArrowLeft className="h-4 w-4" /> Back
        </button>
        <h1 className="mt-3 font-display text-3xl">Import Rex</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Bring in a batch from a spreadsheet, doc, or pasted list. We'll extract each one and let you review before it hits your feed.
        </p>
      </header>

      <div className="space-y-5 p-5">
        <div className="grid grid-cols-5 gap-2 rounded-full bg-muted p-1">

          {TABS.map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`flex items-center justify-center gap-1.5 rounded-full px-3 py-2 text-xs font-semibold transition-colors ${
                tab === t.id ? "bg-background shadow-sm" : "text-muted-foreground"
              }`}
            >
              <t.icon className="h-3.5 w-3.5" /> {t.label}
            </button>
          ))}
        </div>

        {tab === "sheet" && (
          <div className="space-y-3 rounded-2xl bg-card p-4 ring-1 ring-border">
            <label className="text-sm font-medium">Google Sheets URL</label>
            <Input
              value={sheetUrl}
              onChange={(e) => setSheetUrl(e.target.value)}
              placeholder="https://docs.google.com/spreadsheets/d/…"
              className="h-11"
            />
            <p className="text-xs text-muted-foreground">
              Share the sheet as <em>Anyone with the link</em> so we can read it. Any layout works — mixed columns and freeform notes are fine.
            </p>
            <Button
              onClick={onSheetImport}
              disabled={loading || !sheetUrl.trim()}
              className="h-11 w-full rounded-full"
            >
              {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
              Extract Rex
            </Button>
          </div>
        )}

        {tab === "gmaps" && (
          <div className="space-y-4">
            <label className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-border bg-card p-6 text-center transition-colors hover:bg-muted/40">
              {loading ? (
                <Loader2 className="h-8 w-8 animate-spin text-primary" />
              ) : (
                <Upload className="h-8 w-8 text-muted-foreground" />
              )}
              <div className="font-medium">Upload a Google Maps export</div>
              <div className="text-xs text-muted-foreground">
                CSV or JSON from{" "}
                <a
                  href="https://takeout.google.com/settings/takeout/custom/maps_your_places"
                  target="_blank"
                  rel="noreferrer"
                  className="underline"
                >
                  Google Takeout → Saved Places / Lists
                </a>
              </div>
              <input
                type="file"
                accept=".csv,.json,.geojson,text/csv,application/json"
                className="hidden"
                onChange={onGmapsFile}
                disabled={loading}
              />
            </label>

            <div className="space-y-3 rounded-2xl bg-card p-4 ring-1 ring-border">
              <label className="text-sm font-medium">Or paste a shared Maps list link</label>
              <Input
                value={gmapsUrl}
                onChange={(e) => setGmapsUrl(e.target.value)}
                placeholder="https://maps.app.goo.gl/… or https://www.google.com/maps/…"
                className="h-11"
              />
              <p className="text-xs text-muted-foreground">
                Best-effort — Google sometimes blocks scraping. If it fails, use the Takeout export above.
              </p>
              <Button
                onClick={onGmapsUrl}
                disabled={loading || !gmapsUrl.trim()}
                className="h-11 w-full rounded-full"
              >
                {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                Import from link
              </Button>
            </div>

            <p className="text-xs text-muted-foreground">
              Each place lands in the review queue. Hit <em>Match</em> to link it to Google Places (adds address, photo, and pin on the map), then <em>Add</em> to post it.
            </p>
          </div>
        )}

        {tab === "imdb" && (
          <div className="space-y-4">
            <label className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-border bg-card p-6 text-center transition-colors hover:bg-muted/40">
              {loading ? (
                <Loader2 className="h-8 w-8 animate-spin text-primary" />
              ) : (
                <Upload className="h-8 w-8 text-muted-foreground" />
              )}
              <div className="font-medium">Upload your IMDb ratings CSV</div>
              <div className="text-xs text-muted-foreground">
                Export from{" "}
                <a
                  href="https://www.imdb.com/list/ratings"
                  target="_blank"
                  rel="noreferrer"
                  className="underline"
                >
                  IMDb → Your Ratings
                </a>{" "}
                (or any IMDb list) — click <em>Export</em>, then upload the CSV here.
              </div>
              <input
                type="file"
                accept=".csv,text/csv"
                className="hidden"
                onChange={onImdbFile}
                disabled={loading}
              />
            </label>
            <p className="text-xs text-muted-foreground">
              Movies and TV shows are auto-detected from the <em>Title Type</em> column, and your 1–10 IMDb rating carries straight over as crowns. Everything drops into the review queue — hit <em>Match</em> to pull in poster art and details before adding.
            </p>
          </div>
        )}



        {tab === "docx" && (
          <label className="flex cursor-pointer flex-col items-center justify-center gap-3 rounded-2xl border-2 border-dashed border-border bg-card p-8 text-center transition-colors hover:bg-muted/40">
            {loading ? (
              <Loader2 className="h-8 w-8 animate-spin text-primary" />
            ) : (
              <Upload className="h-8 w-8 text-muted-foreground" />
            )}
            <div className="font-medium">Choose a .docx file</div>
            <div className="text-xs text-muted-foreground">Word or Google Docs exported as .docx</div>
            <input
              type="file"
              accept=".docx"
              className="hidden"
              onChange={onDocxFile}
              disabled={loading}
            />
          </label>
        )}

        {tab === "paste" && (
          <div className="space-y-3 rounded-2xl bg-card p-4 ring-1 ring-border">
            <label className="text-sm font-medium">Paste your list</label>
            <Textarea
              value={pasted}
              onChange={(e) => setPasted(e.target.value)}
              placeholder={"e.g.\nWolf Hall by Hilary Mantel — brilliant, 9/10\nOppenheimer — Nolan doing what he does best\nRochelle Canteen, London — best lunch spot 8/10"}
              className="min-h-[180px]"
            />
            <Button
              onClick={() => runExtract(pasted, "paste")}
              disabled={loading || !pasted.trim()}
              className="h-11 w-full rounded-full"
            >
              {loading ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
              Extract Rex
            </Button>
          </div>
        )}

        <section>
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-widest text-muted-foreground">
            Review queue {staging && staging.length > 0 ? `(${staging.length})` : ""}
          </h2>
          {!staging || staging.length === 0 ? (
            <div className="rounded-2xl bg-muted/40 p-6 text-center text-sm text-muted-foreground">
              Nothing to review yet.
            </div>
          ) : (
            <ul className="space-y-3">
              {staging.map((row) => (
                <li
                  key={row.id}
                  className="flex gap-3 rounded-2xl bg-card p-3 ring-1 ring-border"
                >
                  {row.resolved_image_url ? (
                    <img
                      src={row.resolved_image_url}
                      alt=""
                      className="h-16 w-16 flex-none rounded-lg object-cover"
                    />
                  ) : (
                    <div className="flex h-16 w-16 flex-none items-center justify-center rounded-lg bg-muted text-xs text-muted-foreground">
                      {row.suggested_type ?? "?"}
                    </div>
                  )}
                  <div className="min-w-0 flex-1 space-y-1">
                    <div className="truncate font-medium">{row.raw_title}</div>
                    <div className="truncate text-xs text-muted-foreground">
                      {row.suggested_type ?? "unknown"}
                      {row.resolved_subtitle ? ` · ${row.resolved_subtitle}` : row.raw_creator ? ` · ${row.raw_creator}` : ""}
                      {typeof row.raw_rating === "number" ? ` · ${row.raw_rating}/10` : ""}
                    </div>
                    {row.raw_note && (
                      <p className="line-clamp-2 text-xs text-muted-foreground">{row.raw_note}</p>
                    )}
                    <div className="flex gap-1.5 pt-1">
                      {!row.resolved_external_id && (
                        <button
                          onClick={() => onResolve(row.id)}
                          className="flex items-center gap-1 rounded-full bg-muted px-2.5 py-1 text-xs font-medium"
                        >
                          <Search className="h-3 w-3" /> Match
                        </button>
                      )}
                      <button
                        onClick={() => onApprove(row)}
                        className="flex items-center gap-1 rounded-full bg-primary px-2.5 py-1 text-xs font-semibold text-primary-foreground"
                      >
                        <Check className="h-3 w-3" /> Add
                      </button>
                      <button
                        onClick={() => onReject(row.id)}
                        className="flex items-center gap-1 rounded-full bg-muted px-2.5 py-1 text-xs font-medium text-muted-foreground"
                      >
                        <X className="h-3 w-3" /> Skip
                      </button>
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>

        <div className="pt-2 text-center text-xs text-muted-foreground">
          Just books? <Link to="/import-goodreads" className="underline">Use the Goodreads importer</Link>
        </div>
      </div>
    </div>
  );
}
