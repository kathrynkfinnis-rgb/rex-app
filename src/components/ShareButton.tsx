import { useState } from "react";
import { toast } from "sonner";
import { Share2, MessageCircle, Copy, Check } from "lucide-react";
import { cn } from "@/lib/utils";

type Props = {
  url: string;
  text: string;
  label?: string;
  className?: string;
  variant?: "primary" | "ghost" | "icon";
};

/**
 * Share button optimised for WhatsApp forwarding.
 * - Native share sheet where supported (mobile Safari/Chrome).
 * - Otherwise pops a compact menu with WhatsApp deep-link + copy-link.
 */
export function ShareButton({
  url,
  text,
  label = "Share",
  className,
  variant = "ghost",
}: Props) {
  const [open, setOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  const full = `${text}\n${url}`;
  const waHref = `https://wa.me/?text=${encodeURIComponent(full)}`;

  async function handleClick(e: React.MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    // Try native share first (mobile)
    if (typeof navigator !== "undefined" && (navigator as any).share) {
      try {
        await (navigator as any).share({ title: "REX 🦖", text, url });
        return;
      } catch (err: any) {
        if (err?.name === "AbortError") return;
      }
    }
    setOpen((v) => !v);
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(full);
      setCopied(true);
      toast.success("Link copied");
      setTimeout(() => setCopied(false), 1500);
    } catch {
      toast.error("Couldn't copy — long-press the link instead");
    }
  }

  const btnBase =
    variant === "primary"
      ? "inline-flex items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground shadow-sm active:scale-[0.99]"
      : variant === "icon"
        ? "inline-flex h-8 w-8 items-center justify-center rounded-full text-muted-foreground hover:text-foreground"
        : "inline-flex items-center gap-1.5 rounded-full border border-border bg-background px-3 py-1.5 text-xs font-medium text-foreground hover:bg-muted";

  return (
    <div className={cn("relative", className)}>
      <button type="button" onClick={handleClick} className={btnBase} aria-label={label}>
        <Share2 className={variant === "icon" ? "h-4 w-4" : "h-3.5 w-3.5"} />
        {variant !== "icon" && <span>{label}</span>}
      </button>

      {open && (
        <>
          {/* backdrop */}
          <button
            type="button"
            aria-label="Close share menu"
            className="fixed inset-0 z-40 cursor-default"
            onClick={(e) => {
              e.preventDefault();
              e.stopPropagation();
              setOpen(false);
            }}
          />
          <div className="absolute right-0 top-full z-50 mt-2 w-56 overflow-hidden rounded-2xl bg-popover shadow-lg ring-1 ring-border">
            <a
              href={waHref}
              target="_blank"
              rel="noopener noreferrer"
              onClick={(e) => {
                e.stopPropagation();
                setOpen(false);
              }}
              className="flex items-center gap-3 px-4 py-3 text-sm hover:bg-muted"
            >
              <MessageCircle className="h-4 w-4 text-[#25D366]" />
              <span className="font-medium">Send on WhatsApp</span>
            </a>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                copy();
                setOpen(false);
              }}
              className="flex w-full items-center gap-3 border-t border-border px-4 py-3 text-left text-sm hover:bg-muted"
            >
              {copied ? <Check className="h-4 w-4 text-primary" /> : <Copy className="h-4 w-4 text-muted-foreground" />}
              <span className="font-medium">Copy link</span>
            </button>
          </div>
        </>
      )}
    </div>
  );
}
