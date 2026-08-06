import { useEffect, useMemo, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Plus, X, GripVertical, ClipboardPaste } from "lucide-react";
import { parseRecipe, serializeRecipe } from "@/lib/recipe";
import { cn } from "@/lib/utils";

type Props = {
  value: string;
  onChange: (next: string) => void;
};

export function RecipeEditor({ value, onChange }: Props) {
  // Local editable arrays; serialize back on any change.
  const initial = useMemo(() => parseRecipe(value), []); // eslint-disable-line react-hooks/exhaustive-deps
  const [ingredients, setIngredients] = useState<string[]>(
    initial.ingredients.length ? initial.ingredients : [""],
  );
  const [method, setMethod] = useState<string[]>(
    initial.method.length ? initial.method : [""],
  );
  const [legacy, setLegacy] = useState<string>(initial.legacy ?? "");
  const [showPaste, setShowPaste] = useState(false);
  const [pasteBuf, setPasteBuf] = useState("");
  const ingRefs = useRef<Array<HTMLInputElement | null>>([]);
  const stepRefs = useRef<Array<HTMLTextAreaElement | null>>([]);

  // Push structured content upstream. If user is still on legacy free-text and
  // hasn't touched structured fields, preserve the legacy string.
  useEffect(() => {
    const structured = serializeRecipe(ingredients, method);
    if (structured) onChange(structured);
    else onChange(legacy);
  }, [ingredients, method, legacy, onChange]);

  function updateIng(i: number, v: string) {
    setIngredients((arr) => arr.map((x, idx) => (idx === i ? v : x)));
  }
  function addIng(after = ingredients.length - 1) {
    setIngredients((arr) => {
      const next = [...arr];
      next.splice(after + 1, 0, "");
      return next;
    });
    requestAnimationFrame(() => ingRefs.current[after + 1]?.focus());
  }
  function removeIng(i: number) {
    setIngredients((arr) => (arr.length === 1 ? [""] : arr.filter((_, idx) => idx !== i)));
  }

  function updateStep(i: number, v: string) {
    setMethod((arr) => arr.map((x, idx) => (idx === i ? v : x)));
  }
  function addStep(after = method.length - 1) {
    setMethod((arr) => {
      const next = [...arr];
      next.splice(after + 1, 0, "");
      return next;
    });
    requestAnimationFrame(() => stepRefs.current[after + 1]?.focus());
  }
  function removeStep(i: number) {
    setMethod((arr) => (arr.length === 1 ? [""] : arr.filter((_, idx) => idx !== i)));
  }

  function applyPaste() {
    if (!pasteBuf.trim()) { setShowPaste(false); return; }
    const parsed = parseRecipe(pasteBuf);
    if (parsed.ingredients.length || parsed.method.length) {
      if (parsed.ingredients.length) setIngredients(parsed.ingredients);
      if (parsed.method.length) setMethod(parsed.method);
    } else {
      // Nothing recognisable as ingredients or steps (e.g. a single plain
      // sentence) — drop it in as one method step rather than losing it.
      setMethod([pasteBuf.trim()]);
    }
    setLegacy("");
    setPasteBuf("");
    setShowPaste(false);
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <Label className="text-base">Recipe</Label>
        <button
          type="button"
          onClick={() => setShowPaste((v) => !v)}
          className="inline-flex items-center gap-1.5 rounded-full bg-muted px-3 py-1.5 text-xs font-medium text-muted-foreground transition-colors hover:bg-muted/70"
        >
          <ClipboardPaste className="h-3.5 w-3.5" />
          Paste whole recipe
        </button>
      </div>

      {showPaste && (
        <div className="space-y-2 rounded-2xl bg-muted/40 p-3 ring-1 ring-border">
          <p className="text-xs text-muted-foreground">
            Paste from anywhere — we'll split ingredients and steps automatically.
          </p>
          <Textarea
            value={pasteBuf}
            onChange={(e) => setPasteBuf(e.target.value)}
            rows={8}
            placeholder={"Ingredients\n- 200g flour\n- 2 eggs\n\nMethod\n1. Mix the dry…"}
            className="rounded-xl font-mono text-xs"
          />
          <div className="flex justify-end gap-2">
            <Button type="button" variant="ghost" size="sm" onClick={() => { setShowPaste(false); setPasteBuf(""); }}>
              Cancel
            </Button>
            <Button type="button" size="sm" onClick={applyPaste}>
              Split it up
            </Button>
          </div>
        </div>
      )}

      <div className="space-y-2">
        <div className="flex items-baseline justify-between">
          <h3 className="font-display text-xl">Ingredients</h3>
          <span className="text-xs text-muted-foreground">{ingredients.filter((x) => x.trim()).length} items</span>
        </div>
        <ul className="space-y-1.5">
          {ingredients.map((val, i) => (
            <li key={i} className="group flex items-center gap-2">
              <GripVertical className="h-4 w-4 flex-none text-muted-foreground/40" />
              <Input
                ref={(el) => { ingRefs.current[i] = el; }}
                value={val}
                onChange={(e) => updateIng(i, e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") { e.preventDefault(); addIng(i); }
                  if (e.key === "Backspace" && !val && ingredients.length > 1) {
                    e.preventDefault();
                    removeIng(i);
                    requestAnimationFrame(() => ingRefs.current[Math.max(0, i - 1)]?.focus());
                  }
                }}
                placeholder={i === 0 ? "e.g. 200g plain flour" : "Add ingredient"}
                className="h-10 rounded-lg"
              />
              <button
                type="button"
                onClick={() => removeIng(i)}
                className={cn(
                  "flex h-8 w-8 flex-none items-center justify-center rounded-full text-muted-foreground/60 opacity-0 transition-opacity hover:bg-muted hover:text-foreground group-hover:opacity-100 focus:opacity-100",
                  ingredients.length === 1 && !val && "pointer-events-none",
                )}
                aria-label="Remove ingredient"
              >
                <X className="h-4 w-4" />
              </button>
            </li>
          ))}
        </ul>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={() => addIng()}
          className="gap-1.5 text-muted-foreground"
        >
          <Plus className="h-4 w-4" /> Add ingredient
        </Button>
      </div>

      <div className="space-y-2">
        <div className="flex items-baseline justify-between">
          <h3 className="font-display text-xl">Method</h3>
          <span className="text-xs text-muted-foreground">{method.filter((x) => x.trim()).length} steps</span>
        </div>
        <ol className="space-y-2">
          {method.map((val, i) => (
            <li key={i} className="group flex items-start gap-2">
              <div className="mt-2 flex h-7 w-7 flex-none items-center justify-center rounded-full bg-primary/15 text-xs font-semibold text-primary">
                {i + 1}
              </div>
              <Textarea
                ref={(el) => { stepRefs.current[i] = el; }}
                value={val}
                onChange={(e) => updateStep(i, e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
                    e.preventDefault();
                    addStep(i);
                  }
                  if (e.key === "Backspace" && !val && method.length > 1) {
                    e.preventDefault();
                    removeStep(i);
                    requestAnimationFrame(() => stepRefs.current[Math.max(0, i - 1)]?.focus());
                  }
                }}
                rows={2}
                placeholder={i === 0 ? "Describe the first step…" : "Next step"}
                className="min-h-11 rounded-lg text-sm"
              />
              <button
                type="button"
                onClick={() => removeStep(i)}
                className={cn(
                  "mt-2 flex h-8 w-8 flex-none items-center justify-center rounded-full text-muted-foreground/60 opacity-0 transition-opacity hover:bg-muted hover:text-foreground group-hover:opacity-100 focus:opacity-100",
                  method.length === 1 && !val && "pointer-events-none",
                )}
                aria-label="Remove step"
              >
                <X className="h-4 w-4" />
              </button>
            </li>
          ))}
        </ol>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={() => addStep()}
          className="gap-1.5 text-muted-foreground"
        >
          <Plus className="h-4 w-4" /> Add step
        </Button>
        <p className="text-xs text-muted-foreground">Tip: press ⌘/Ctrl + Enter inside a step to add another.</p>
      </div>
    </div>
  );
}
