export type ParsedRecipe = {
  ingredients: string[];
  method: string[];
  legacy?: string; // free-text fallback when nothing structured or step-like is found
};

const ING_RE = /^\s*(?:##+\s*)?ingredients?\s*:?\s*$/i;
const METHOD_RE =
  /^\s*(?:##+\s*)?(?:method|instructions?|steps?|directions?|preparation|how\s*to\s*(?:make|cook|prepare)?|what\s*to\s*do)\s*:?\s*$/i;

// Cooking-instruction verbs that typically open a method step. Used to detect
// the ingredients→method transition even when there's no explicit heading —
// e.g. an "Ingredients" heading is present but the method heading uses a
// synonym we don't recognise, or the paste has no headings at all.
const STEP_VERB_RE =
  /^(preheat|heat|mix|add|combine|stir|whisk|pour|bake|cook|simmer|boil|fry|roast|grill|chop|slice|dice|mince|season|serve|let|cover|remove|place|transfer|reduce|drain|rest|cool|garnish|repeat|set|line|grease|sprinkle|spread|layer|roll|knead|whip|beat|melt|toss|fold|arrange|top|drizzle|spoon|divide|return|bring|turn|flip|rub|marinate|chill|freeze|warm|blend|process|pur[eé]e|strain|peel|trim|crush|squeeze|zest|coat|dust|brush|put|leave|meanwhile)\b/i;

function stripBullet(line: string): string {
  return line.replace(/^\s*(?:[-*•·]|\d+[.)])\s+/, "").trim();
}

function looksLikeStep(line: string): boolean {
  const trimmed = line.trim();
  if (/^\d+[.)]\s+/.test(trimmed)) return true; // "1. " / "2) "
  if (trimmed.length > 80) return true; // long, sentence-like instructions
  return STEP_VERB_RE.test(trimmed);
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

    // No heading matched this line. If we're not already in the method
    // section, decide whether it reads like an instruction step so mixed
    // unlabelled pastes (or a recognised "Ingredients" heading followed by
    // an unrecognised method heading) still get split sensibly.
    if (section !== "method" && looksLikeStep(line)) section = "method";
    if (section === null) section = "ing";

    const clean = stripBullet(line);
    if (!clean) continue;
    if (section === "ing") ing.push(clean);
    else method.push(clean);
  }

  // Only bail out to an unsplit blob when we found neither an explicit
  // heading nor anything that looked like a method step to split on.
  if (!sawHeading && method.length === 0) return { ingredients: [], method: [], legacy: src };
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
