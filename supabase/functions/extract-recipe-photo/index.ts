// #21 — photo-to-recipe import. Same reasoning as extract-recommendations
// (see that function's header comment): the native app has no server of
// its own to hold ANTHROPIC_API_KEY, so the one step that needs it lives
// here. Everything else (uploading the photo to storage, creating the
// item/recommendation) happens directly from the app via ordinary
// authenticated REST calls, same as the rest of the native app.
//
// Deliberately returns transcribed recipe TEXT, not structured
// ingredients/method arrays — RexRecipe.parse() in the native app (and
// src/lib/recipe.ts on the web) already splits free text into ingredients
// and method with a local heuristic parser, used today for "paste whole
// recipe". Reusing that instead of asking the model for structured output
// keeps this function simple and keeps photo-import and paste-import
// behaving identically once the text exists.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const TRANSCRIBE_TOOL = {
  name: "transcribe_recipe",
  description: "Return the recipe transcribed from the photo.",
  input_schema: {
    type: "object",
    required: ["text"],
    properties: {
      title: {
        type: ["string", "null"],
        description: "The recipe's name/title, if visible in the photo. Null if not shown.",
      },
      text: {
        type: "string",
        description:
          "The recipe transcribed as plain text, ingredients then method, one item per line, headings kept if present (e.g. 'Ingredients' / 'Method'). Transcribe exactly what's written - don't invent quantities or steps that aren't in the photo.",
      },
    },
  },
} as const;

const PROMPT = `You transcribe recipes from photos - cookbook pages, handwritten cards, screenshots of a recipe site or app, whatever's in the image.

Read the photo and transcribe the recipe faithfully: the title if one is visible, then the ingredients list, then the method/steps, in that order. Keep quantities exactly as written. If the photo isn't a recipe, or nothing is legible, return an empty text field rather than guessing.`;


// Sept 21, security review — the comment this replaces said that reaching the
// handler meant the caller held a valid session. It didn't. Supabase's
// verify_jwt accepts ANY valid JWT for this project, and that includes the
// public anon key, which ships inside the app binary and sits in the website's
// source. So this function was callable by anyone who looked.
//
// The role claim is what actually distinguishes them. It is signed by Supabase
// and can't be edited without the JWT secret, so reading it without verifying
// the signature is safe HERE — the runtime has already checked the signature;
// all that's left is to look at who it says this is.
function callerRole(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const token = header.replace(/^[Bb]earer\s+/, "");
  const payload = token.split(".")[1];
  if (!payload) return null;
  try {
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return (JSON.parse(json) as { role?: string }).role ?? null;
  } catch {
    return null;
  }
}

function rejectUnlessAuthenticated(req: Request): Response | null {
  if (callerRole(req) === "authenticated") return null;
  return new Response(JSON.stringify({ error: "Not allowed" }), {
    status: 403,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }

  // A signed-in person, not the anon key — these calls cost real money at
  // Anthropic, and the anon key is public by design.
  const denied = rejectUnlessAuthenticated(req);
  if (denied) return denied;

  let body: { imageBase64?: string; mediaType?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), { status: 400 });
  }

  const imageBase64 = body.imageBase64 ?? "";
  const mediaType = body.mediaType ?? "image/jpeg";
  if (!imageBase64) {
    return new Response(JSON.stringify({ error: "imageBase64 is required" }), { status: 400 });
  }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) {
    return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not configured" }), { status: 500 });
  }

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 2048,
      system: PROMPT,
      messages: [
        {
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mediaType, data: imageBase64 } },
            { type: "text", text: "Transcribe this recipe." },
          ],
        },
      ],
      tools: [TRANSCRIBE_TOOL],
      tool_choice: { type: "tool", name: "transcribe_recipe" },
    }),
  });

  if (!res.ok) {
    const errBody = await res.text();
    return new Response(
      JSON.stringify({ error: `Recipe transcription failed [${res.status}]: ${errBody.slice(0, 300)}` }),
      { status: 502 },
    );
  }

  const json = await res.json();
  const toolUse = json.content?.find(
    (b: { type: string; name?: string }) => b.type === "tool_use" && b.name === "transcribe_recipe",
  );
  const title = typeof toolUse?.input?.title === "string" ? toolUse.input.title : null;
  const text = typeof toolUse?.input?.text === "string" ? toolUse.input.text : "";

  return new Response(JSON.stringify({ title, text }), {
    headers: { "Content-Type": "application/json" },
  });
});
