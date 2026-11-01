// Nov 1 — Amazon's Product Advertising API, once the three qualifying sales
// unlocked it.
//
// WHY THIS IS A FUNCTION AND NOT IN THE APP
//
// PA-API requests are signed with AWS SigV4, which needs the secret key to do
// the signing. A secret in the app is a secret in the binary, and anybody can
// read a binary. The Google key in Info.plist is already as far down that road
// as we should go, and this is worse than that one: a Google key spends money,
// an Associates secret key acts as the account. So it lives here, as a
// Supabase secret, and the app asks this function instead.
//
// WHAT IT UNLOCKS
//
// Three things the app currently fakes:
//
//   * A pasted Amazon link fills itself in. Amazon serves apps a bot page, so
//     RexSearch falls back to reading the product name out of the URL — which
//     works for a browser link with words in the path and not at all for the
//     amzn.eu short link Amazon's own share button produces. GetItems by ASIN
//     answers properly: real title, real author, real photograph.
//   * "Find on Amazon" becomes a product link rather than a search. A search
//     link lands somebody on a results page and hopes; a product link lands
//     them on the thing.
//   * A basket. The add-to-cart URL takes ASINs, which is why "buy all my
//     want-to-reads" was not possible before this.
//
// RATE LIMITS, WHICH ARE A REAL CONSTRAINT
//
// PA-API starts at one request per second and 8,640 a day, and the allowance
// grows with revenue rather than with need. It is also withdrawn after 30 days
// without a qualifying sale. So this is cached by the caller wherever possible
// and is not something to call on every keystroke.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

const ACCESS_KEY = Deno.env.get("AMAZON_PA_ACCESS_KEY") ?? "";
const SECRET_KEY = Deno.env.get("AMAZON_PA_SECRET_KEY") ?? "";
const PARTNER_TAG = Deno.env.get("AMAZON_PARTNER_TAG") ?? "findrex-21";

// The UK marketplace. Each marketplace is its own host, region and partner
// tag — a .co.uk tag is not valid against .com, so changing one of these
// means changing all three.
const HOST = "webservices.amazon.co.uk";
const REGION = "eu-west-1";
const SERVICE = "ProductAdvertisingAPI";
const MARKETPLACE = "www.amazon.co.uk";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

// What we ask Amazon for. Deliberately short: every resource is more payload
// and more to go wrong, and the app shows a title, a line under it, a picture
// and sometimes a price.
const RESOURCES = [
  "ItemInfo.Title",
  "ItemInfo.ByLineInfo",
  "Images.Primary.Large",
  "Offers.Listings.Price",
];

// ───────────────────────────────────────────────────────── SigV4

const encoder = new TextEncoder();

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function hmac(key: ArrayBuffer | Uint8Array, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key as BufferSource,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message));
}

/// The four-step derivation AWS requires: date, region, service, then the
/// literal "aws4_request". Each HMAC takes the previous result as its key.
async function signingKey(date: string): Promise<ArrayBuffer> {
  let key: ArrayBuffer | Uint8Array = encoder.encode(`AWS4${SECRET_KEY}`);
  for (const part of [date, REGION, SERVICE, "aws4_request"]) {
    key = await hmac(key, part);
  }
  return key as ArrayBuffer;
}

async function signedHeaders(target: string, body: string): Promise<Record<string, string>> {
  // 20261101T120000Z and 20261101 — AWS wants both forms.
  const now = new Date().toISOString().replace(/[:-]|\.\d{3}/g, "");
  const amzDate = `${now.slice(0, 15)}Z`;
  const date = amzDate.slice(0, 8);
  const path = `/paapi5/${target.toLowerCase()}`;
  const amzTarget = `com.amazon.paapi5.v1.ProductAdvertisingAPIv1.${target}`;

  // Canonical headers must be lowercase, sorted, and exactly the ones listed
  // in signedHeaders — a mismatch here is the usual cause of a signature
  // error, and Amazon's message for it says nothing useful.
  const canonicalHeaders =
    `content-encoding:amz-1.0\n` +
    `content-type:application/json; charset=utf-8\n` +
    `host:${HOST}\n` +
    `x-amz-date:${amzDate}\n` +
    `x-amz-target:${amzTarget}\n`;
  const signed = "content-encoding;content-type;host;x-amz-date;x-amz-target";

  const canonicalRequest = [
    "POST",
    path,
    "",
    canonicalHeaders,
    signed,
    await sha256Hex(body),
  ].join("\n");

  const scope = `${date}/${REGION}/${SERVICE}/aws4_request`;
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join("\n");

  const signature = [...new Uint8Array(await hmac(await signingKey(date), stringToSign))]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return {
    "content-encoding": "amz-1.0",
    "content-type": "application/json; charset=utf-8",
    host: HOST,
    "x-amz-date": amzDate,
    "x-amz-target": amzTarget,
    Authorization:
      `AWS4-HMAC-SHA256 Credential=${ACCESS_KEY}/${scope}, ` +
      `SignedHeaders=${signed}, Signature=${signature}`,
  };
}

async function callAmazon(target: string, payload: Record<string, unknown>) {
  const body = JSON.stringify({
    ...payload,
    PartnerTag: PARTNER_TAG,
    PartnerType: "Associates",
    Marketplace: MARKETPLACE,
    Resources: RESOURCES,
  });
  const response = await fetch(`https://${HOST}/paapi5/${target.toLowerCase()}`, {
    method: "POST",
    headers: await signedHeaders(target, body),
    body,
  });
  const text = await response.text();
  if (!response.ok) {
    return { ok: false as const, status: response.status, detail: text.slice(0, 400) };
  }
  return { ok: true as const, json: JSON.parse(text) };
}

/// Amazon's shape, flattened to the four things a REX card needs. Their reply
/// nests every field behind a DisplayValue, and half of them are absent on any
/// given product, so this is defensive throughout rather than trusting it.
// deno-lint-ignore no-explicit-any
function normalise(item: any) {
  const asin = item?.ASIN;
  if (!asin) return null;
  const title = item?.ItemInfo?.Title?.DisplayValue;
  if (!title) return null;
  const byline =
    item?.ItemInfo?.ByLineInfo?.Contributors?.[0]?.Name ??
    item?.ItemInfo?.ByLineInfo?.Brand?.DisplayValue ??
    item?.ItemInfo?.ByLineInfo?.Manufacturer?.DisplayValue ??
    null;
  return {
    asin,
    title,
    subtitle: byline,
    imageURL: item?.Images?.Primary?.Large?.URL ?? null,
    price: item?.Offers?.Listings?.[0]?.Price?.DisplayAmount ?? null,
    // Amazon returns a tagged DetailPageURL already, but it is built from the
    // tag we sent — so this is our link either way, and the canonical form is
    // tidier than the one they return with its tracking parameters.
    url: `https://www.amazon.co.uk/dp/${asin}?tag=${PARTNER_TAG}`,
  };
}

// ───────────────────────────────────────────────────────── handler

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // Signed-in REX users only. This spends a rate limit that is not easily
  // replaced — PA-API grants are tied to sales and withdrawn after 30 days
  // without one — so it is not something to leave open.
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization) {
    return new Response(JSON.stringify({ error: "Not signed in." }), { status: 401, headers: CORS });
  }
  const asUser = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: auth, error: authError } = await asUser.auth.getUser();
  if (authError || !auth?.user) {
    return new Response(JSON.stringify({ error: "Not signed in." }), { status: 401, headers: CORS });
  }

  if (!ACCESS_KEY || !SECRET_KEY) {
    // Said plainly rather than as a failure, because the app's fallback to
    // search links is a reasonable outcome and should not look like a bug.
    return new Response(
      JSON.stringify({ error: "not_configured", items: [] }),
      { status: 200, headers: CORS },
    );
  }

  let payload: { asin?: string; asins?: string[]; keywords?: string };
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Bad request." }), { status: 400, headers: CORS });
  }

  const asins = payload.asins ?? (payload.asin ? [payload.asin] : []);
  const result = asins.length
    // Up to ten at a time is Amazon's limit, and ten is also a wish list.
    ? await callAmazon("GetItems", { ItemIds: asins.slice(0, 10) })
    : payload.keywords?.trim()
    ? await callAmazon("SearchItems", { Keywords: payload.keywords.trim(), ItemCount: 6 })
    : null;

  if (!result) {
    return new Response(JSON.stringify({ error: "Nothing asked for." }), { status: 400, headers: CORS });
  }
  if (!result.ok) {
    console.log(`[amazon-lookup] ${result.status}: ${result.detail}`);
    // A 429 here is the one-per-second limit, which a retry a moment later
    // fixes; anything else is ours to look at. Either way the app falls back
    // to a search link, so the person is not stuck.
    return new Response(
      JSON.stringify({ error: result.status === 429 ? "rate_limited" : "amazon_error", items: [] }),
      { status: 200, headers: CORS },
    );
  }

  const raw = result.json?.ItemsResult?.Items ?? result.json?.SearchResult?.Items ?? [];
  // deno-lint-ignore no-explicit-any
  const items = (raw as any[]).map(normalise).filter(Boolean);
  return new Response(JSON.stringify({ items }), { status: 200, headers: CORS });
});
