export type ParsedRecipe = {
  ingredients: string[];
  method: string[];
  legacy?: string; // free-text fallback when no structured sections found
};

const ING_RE = /^\s*(?:##+\s*)?ingredients?\s*:?\s*$/i;
const METHOD_RE = /^\s*(?:##+\s*)?(?:method|instructions?|steps?|directions?|preparation)\s*:?\s*$/i;

function stripBullet(line: string): string {
  return line.replace(/^\s*(?:[-*•·]|\d+[.)])\s+/, "").trim();
}

export function parseRecipe(text: string | null | undefined): ParsedRecipe {
  const src = (text ?? "").replace(/\r\n/g, "\n").trim();
  if (!src) return { ingredients: [], method: [] };

  const lines = src.split("\n");
  let section: "ing" | "method" | null = null;
  const ing: string[] = [];
  const method: string[] = [];
  let sawHeading = false;

  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) continue;
    if (ING_RE.test(line)) { section = "ing"; sawHeading = true; continue; }
    if (METHOD_RE.test(line)) { section = "method"; sawHeading = true; continue; }
    const clean = stripBullet(line);
    if (!clean) continue;
    if (section === "ing") ing.push(clean);
    else if (section === "method") method.push(clean);
  }

  if (!sawHeading) return { ingredients: [], method: [], legacy: src };
  return { ingredients: ing, method };
}

export function serializeRecipe(ingredients: string[], method: string[]): string {
  const ing = ingredients.map((s) => s.trim()).filter(Boolean);
  const met = method.map((s) => s.trim()).filter(Boolean);
  const parts: string[] = [];
  if (ing.length) {
    parts.push("## Ingredients");
    parts.push(...ing.map((s) => `- ${s}`));
  }
  if (met.length) {
    if (parts.length) parts.push("");
    parts.push("## Method");
    parts.push(...met.map((s, i) => `${i + 1}. ${s}`));
  }
  return parts.join("\n");
}
