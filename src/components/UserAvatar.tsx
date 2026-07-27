import { cn } from "@/lib/utils";

type Size = "xs" | "sm" | "md" | "lg" | "xl";

const sizeMap: Record<Size, string> = {
  xs: "h-6 w-6 text-[11px]",
  sm: "h-8 w-8 text-xs",
  md: "h-9 w-9 text-sm",
  lg: "h-16 w-16 text-2xl",
  xl: "h-24 w-24 text-3xl",
};

export function UserAvatar({
  url,
  name,
  size = "md",
  className,
}: {
  url?: string | null;
  name?: string | null;
  size?: Size;
  className?: string;
}) {
  const initial = (name || "?").slice(0, 1).toUpperCase();
  return (
    <div
      className={cn(
        "flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-secondary font-semibold text-secondary-foreground",
        sizeMap[size],
        className,
      )}
    >
      {url ? (
        <img src={url} alt="" className="h-full w-full object-cover" loading="lazy" />
      ) : (
        initial
      )}
    </div>
  );
}
