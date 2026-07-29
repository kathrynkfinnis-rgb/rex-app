import { useState, type KeyboardEvent } from "react";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

interface Props {
  value: string[];
  onChange: (next: string[]) => void;
  placeholder?: string;
  suggestions?: string[];
}

function normalize(t: string) {
  return t.trim().replace(/^#+/, "").replace(/\s+/g, " ").slice(0, 32);
}

export function TagsInput({ value, onChange, placeholder = "Add a tag…", suggestions = [] }: Props) {
  const [draft, setDraft] = useState("");

  const add = (raw: string) => {
    const t = normalize(raw);
    if (!t) return;
    const lower = t.toLowerCase();
    if (value.some((v) => v.toLowerCase() === lower)) return;
    if (value.length >= 8) return;
    onChange([...value, t]);
    setDraft("");
  };

  const remove = (t: string) => onChange(value.filter((v) => v !== t));

  const onKey = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter" || e.key === ",") {
      e.preventDefault();
      add(draft);
    } else if (e.key === "Backspace" && !draft && value.length) {
      remove(value[value.length - 1]);
    }
  };

  const remaining = suggestions.filter(
    (s) => !value.some((v) => v.toLowerCase() === s.toLowerCase()),
  );

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-1.5 rounded-xl border bg-background p-2">
        {value.map((t) => (
          <span
            key={t}
            className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
          >
            #{t}
            <button type="button" onClick={() => remove(t)} className="opacity-70 hover:opacity-100" aria-label={`Remove ${t}`}>
              <X className="h-3 w-3" />
            </button>
          </span>
        ))}
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={onKey}
          onBlur={() => draft && add(draft)}
          placeholder={value.length ? "" : placeholder}
          className="min-w-[8ch] flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
        />
      </div>
      {remaining.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {remaining.slice(0, 8).map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => add(s)}
              className={cn(
                "rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground hover:bg-muted/70",
              )}
            >
              + {s}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
