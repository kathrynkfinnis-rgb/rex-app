import { Crown } from "lucide-react";
import { cn } from "@/lib/utils";

/** Read-only crown rating (out of 10). */
export function CrownRatingDisplay({
  value,
  size = "sm",
  showNumber = false,
  className,
}: {
  value: number;
  size?: "xs" | "sm" | "md";
  showNumber?: boolean;
  className?: string;
}) {
  const sizes = { xs: "h-3 w-3", sm: "h-3.5 w-3.5", md: "h-4 w-4" } as const;
  const rounded = Math.round(value);
  return (
    <div className={cn("flex items-center gap-1", className)}>
      <div className="flex items-center gap-0.5">
        {Array.from({ length: 10 }).map((_, i) => (
          <Crown
            key={i}
            className={cn(
              sizes[size],
              i < rounded ? "fill-primary text-primary" : "text-muted-foreground/25",
            )}
            strokeWidth={2}
          />
        ))}
      </div>
      {showNumber && (
        <span className="ml-1 text-sm font-semibold tabular-nums">
          {value.toFixed(value % 1 === 0 ? 0 : 1)}<span className="text-muted-foreground font-normal">/10</span>
        </span>
      )}
    </div>
  );
}

/** Interactive crown rating picker (1–10). */
export function CrownRatingInput({
  value,
  onChange,
  size = "lg",
}: {
  value: number;
  onChange: (v: number) => void;
  size?: "md" | "lg";
}) {
  const iconClass = size === "lg" ? "h-6 w-6" : "h-5 w-5";
  return (
    <div className="flex items-center gap-2">
      <div className="flex flex-wrap gap-1">
        {Array.from({ length: 10 }).map((_, i) => {
          const n = i + 1;
          return (
            <button
              key={n}
              type="button"
              onClick={() => onChange(n)}
              className="p-0.5 transition-transform active:scale-90"
              aria-label={`${n} crown${n > 1 ? "s" : ""}`}
            >
              <Crown
                className={cn(
                  iconClass,
                  n <= value ? "fill-primary text-primary" : "text-muted-foreground/30",
                )}
                strokeWidth={2}
              />
            </button>
          );
        })}
      </div>
      <span className="ml-1 text-lg font-bold tabular-nums text-foreground">
        {value}<span className="text-sm font-normal text-muted-foreground">/10</span>
      </span>
    </div>
  );
}
