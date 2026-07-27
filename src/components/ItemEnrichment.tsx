import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { getItemEnrichment } from "@/lib/enrichment.functions";
import { CrownRatingDisplay } from "@/components/CrownRating";
import { ExternalLink, Star, ArrowUpRight } from "lucide-react";
import { useState } from "react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";

type EnrichmentData = NonNullable<Awaited<ReturnType<typeof getItemEnrichment>>>;

export function ItemEnrichment({ itemId }: { itemId: string }) {
  const fetchFn = useServerFn(getItemEnrichment);
  const { data, isLoading } = useQuery({
    queryKey: ["enrichment", itemId],
    queryFn: () => fetchFn({ data: { itemId } }),
    staleTime: 1000 * 60 * 60,
  });

  if (isLoading) {
    return (
      <section className="border-t border-border p-5">
        <div className="h-4 w-24 animate-pulse rounded bg-muted" />
        <div className="mt-3 h-20 animate-pulse rounded-xl bg-muted" />
      </section>
    );
  }
  if (!data) return null;

  return (
    <section className="border-t border-border p-5 space-y-5">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-2xl">About</h2>
        <span className="text-[11px] uppercase tracking-wider text-muted-foreground">via {data.source}</span>
      </div>

      {data.score && (
        <div className="flex items-center gap-2 rounded-2xl bg-secondary/40 p-3 ring-1 ring-border">
          <CrownRatingDisplay value={data.score.value} size="sm" />
          <span className="text-sm font-semibold tabular-nums">
            {data.score.value.toFixed(1)}<span className="font-normal text-muted-foreground">/{data.score.scale}</span>
          </span>
          <span className="text-xs text-muted-foreground">
            {data.score.label}{data.score.count ? ` · ${formatCount(data.score.count)} ratings` : ""}
          </span>
        </div>
      )}

      {data.description && <Description text={data.description} />}

      {data.facts.length > 0 && (
        <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1.5 text-sm">
          {data.facts.map((f) => (
            <div key={f.label} className="contents">
              <dt className="text-muted-foreground">{f.label}</dt>
              <dd className="font-medium">{f.value}</dd>
            </div>
          ))}
        </dl>
      )}

      {data.extra_links && data.extra_links.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {data.extra_links.map((l) => (
            <a
              key={l.url}
              href={l.url}
              target="_blank"
              rel="noreferrer"
              className="inline-flex items-center gap-1 rounded-full bg-secondary px-3 py-1.5 text-xs font-medium hover:bg-secondary/70"
            >
              {l.label} <ExternalLink className="h-3 w-3" />
            </a>
          ))}
        </div>
      )}

      {data.reviews.length > 0 && (
        <div>
          <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
            Public reviews
          </h3>
          <div className="mt-2 space-y-3">
            {data.reviews.map((r, i) => (
              <ReviewCard key={i} r={r} />
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

function Description({ text }: { text: string }) {
  const [open, setOpen] = useState(false);
  const long = text.length > 280;
  return (
    <div className="text-sm leading-relaxed">
      <p className={!open && long ? "line-clamp-4" : undefined}>{text}</p>
      {long && (
        <button onClick={() => setOpen(!open)} className="mt-1 text-xs font-semibold text-primary">
          {open ? "Show less" : "Read more"}
        </button>
      )}
    </div>
  );
}

function ReviewCard({ r }: { r: { author: string; rating: number | null; text: string; url?: string | null; created_at?: string | null } }) {
  const [open, setOpen] = useState(false);
  const long = r.text.length > 240;
  return (
    <div className="rounded-2xl bg-card p-4 ring-1 ring-border">
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-medium">{r.author}</span>
        {r.rating != null && (
          <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
            <Star className="h-3 w-3 fill-current text-primary" /> {r.rating.toFixed(1)}/10
          </span>
        )}
      </div>
      {r.text && (
        <p className={`mt-1.5 text-sm leading-snug ${!open && long ? "line-clamp-4" : ""}`}>
          &ldquo;{r.text}&rdquo;
        </p>
      )}
      <div className="mt-1.5 flex items-center justify-between text-[11px] text-muted-foreground">
        {long ? (
          <button onClick={() => setOpen(!open)} className="font-semibold text-primary">
            {open ? "Show less" : "Read more"}
          </button>
        ) : <span />}
        {r.url && (
          <a href={r.url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1">
            Source <ExternalLink className="h-3 w-3" />
          </a>
        )}
      </div>
    </div>
  );
}

function formatCount(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + "M";
  if (n >= 1_000) return (n / 1_000).toFixed(1) + "k";
  return String(n);
}
