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

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "POST only" }), { status: 405 });
  }

  // Supabase's edge runtime verifies the JWT in the Authorization header
  // before this handler even runs (verify_jwt defaults to true on deploy) -
  // reaching this line already means the caller has a valid session.

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
