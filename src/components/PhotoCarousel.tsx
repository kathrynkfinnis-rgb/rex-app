import { useRef, useState } from "react";
import { cn } from "@/lib/utils";

export function PhotoCarousel({ photos, className }: { photos: string[]; className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  if (!photos.length) return null;

  if (photos.length === 1) {
    return <img src={photos[0]} alt="" className={cn("max-h-56 w-full object-cover", className)} />;
  }

  function onScroll() {
    const el = ref.current;
    if (!el) return;
    const i = Math.round(el.scrollLeft / el.clientWidth);
    if (i !== active) setActive(i);
  }

  function goTo(i: number) {
    const el = ref.current;
    if (!el) return;
    el.scrollTo({ left: i * el.clientWidth, behavior: "smooth" });
  }

  return (
    <div className={cn("relative", className)}>
      <div
        ref={ref}
        onScroll={onScroll}
        className="flex snap-x snap-mandatory overflow-x-auto scroll-smooth [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {photos.map((url) => (
          <div key={url} className="h-56 w-full shrink-0 snap-center bg-muted">
            <img src={url} alt="" className="h-full w-full object-cover" draggable={false} />
          </div>
        ))}
      </div>
      <div className="pointer-events-none absolute bottom-2 left-1/2 flex -translate-x-1/2 items-center gap-1.5 rounded-full bg-black/40 px-2 py-1 backdrop-blur">
        {photos.map((url, i) => (
          <button
            key={url}
            type="button"
            aria-label={`Photo ${i + 1}`}
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              goTo(i);
            }}
            className={cn(
              "pointer-events-auto h-1.5 rounded-full bg-white/50 transition-all",
              i === active ? "w-4 bg-white" : "w-1.5",
            )}
          />
        ))}
      </div>
      <span className="pointer-events-none absolute right-2 top-2 rounded-full bg-black/50 px-2 py-0.5 text-[10px] font-medium text-white">
        {active + 1}/{photos.length}
      </span>
    </div>
  );
}
