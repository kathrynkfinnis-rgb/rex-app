// Sept 22 — the KPI dashboard, moved off Lovable.
//
// Deliberately one static file with no build step and no server: it signs in
// against Supabase directly and calls the same three admin functions the old
// page did. Those functions are SECURITY DEFINER and start with a has_role
// check, so being an admin is enforced in the database. This page hiding its
// own contents is a courtesy, not the security — a non-admin who read the
// source and called the functions themselves would still be refused.
const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";
const STORE = "rex.admin.session";

const root = document.getElementById("root");
const esc = (v) =>
  String(v ?? "").replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
  );
const num = (v) => (v === null || v === undefined ? "—" : Number(v).toLocaleString("en-GB"));
const pct = (a, b) => (!b ? "—" : Math.round((a / b) * 100) + "%");

function session(next) {
  try {
    if (next === undefined) return JSON.parse(localStorage.getItem(STORE) || "null");
    if (next === null) localStorage.removeItem(STORE);
    else localStorage.setItem(STORE, JSON.stringify(next));
  } catch {
    return null;
  }
}

async function signIn(email, password) {
  const response = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error_description || data.msg || "Couldn't sign in");
  return data;
}

async function rpc(name, token) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  if (response.status === 401) throw new Error("expired");
  const data = await response.json();
  // The functions raise 'forbidden' for anyone without the admin role.
  if (!response.ok)
    throw new Error(data.message === "forbidden" ? "forbidden" : data.message || "Couldn't load");
  return data;
}

/// Oct 18 — "where is this feedback going?", asked through TestFlight, and
/// then "i haven't seen this feedback so where actually is it going?"
///
/// The in-app ! button has written to public.feedback since 30 July and
/// nothing has ever read it back: not this page, not the app. Months of it
/// has been sitting there unseen, which is exactly what the question was
/// about.
///
/// Read straight from the table rather than through an RPC like the KPIs:
/// the policy from 30 July already says an admin can select every row, so
/// there is nothing to add server-side and no migration to run.
async function table(path, token) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
  });
  if (response.status === 401) throw new Error("expired");
  if (!response.ok) return [];
  return response.json();
}

function feedbackRow(row) {
  const when = row.created_at
    ? new Date(row.created_at).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short" })
    : "";
  const who = row.is_anonymous
    ? "anonymous"
    : row.who?.display_name || row.who?.username || "someone";
  const where = row.page ? ` · ${esc(row.page)}` : "";
  return `<div class="fb">
    <p class="fb-meta">${esc(when)} · ${esc(who)}${where}</p>
    <p class="fb-body">${esc(row.message || "")}</p>
  </div>`;
}

function kpi(label, value, { sub, accent } = {}) {
  return `<div class="kpi${accent ? " accent" : ""}">
    <div class="v">${esc(value)}</div>
    <div class="l">${esc(label)}</div>
    ${sub ? `<div class="s">${esc(sub)}</div>` : ""}
  </div>`;
}

function pair(label, total, recent) {
  return `<div class="pair"><span>${esc(label)}</span>
    <span class="n">${num(total)}</span><span class="r">+${num(recent)}/7d</span></div>`;
}

function bars(points) {
  if (!points || !points.length) return "";
  const max = Math.max(...points.map((p) => p.count), 1);
  return `<div class="bars">${points
    .map(
      (p) =>
        `<div style="height:${Math.max(2, (p.count / max) * 100)}%" title="${esc(p.week)}: ${p.count}"></div>`,
    )
    .join("")}</div>`;
}

function renderSignIn(message) {
  root.innerHTML = `
    <p class="lede">Sign in with your REX account.</p>
    <form class="signin" id="f">
      <input name="email" type="email" placeholder="Email" autocomplete="username" required>
      <input name="password" type="password" placeholder="Password" autocomplete="current-password" required>
      <button class="btn" type="submit">Sign in</button>
      ${message ? `<p class="err">${esc(message)}</p>` : ""}
    </form>`;
  document.getElementById("f").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.target);
    try {
      const data = await signIn(form.get("email"), form.get("password"));
      session({ token: data.access_token, email: form.get("email") });
      load();
    } catch (error) {
      renderSignIn(error.message);
    }
  });
}

function render(users, content, engagement, email, feedback) {
  const ratio = (a, b) => (!b ? "—" : (a / b).toFixed(2));
  root.innerHTML = `
    <p class="who">Signed in as ${esc(email)} · <button id="out">sign out</button></p>

    <h2>Users and growth</h2>
    <div class="kpis">
      ${kpi("Total users", num(users.total_users), { accent: true })}
      ${kpi("Signups · 24h", num(users.new_24h))}
      ${kpi("Signups · 7d", num(users.new_7d))}
      ${kpi("Signups · 30d", num(users.new_30d))}
      ${kpi("DAU", num(users.dau), { sub: "posted a Rex, 24h" })}
      ${kpi("WAU", num(users.wau), { sub: "posted, 7d" })}
      ${kpi("MAU", num(users.mau), { sub: "posted, 30d" })}
      ${kpi("WAU / MAU", ratio(users.wau, users.mau), { sub: "stickiness" })}
    </div>

    <h2>Activation</h2>
    <div class="kpis">
      ${kpi("Activated", pct(engagement.activated_users, engagement.total_users), { sub: `${num(engagement.activated_users)} posted ≥1 Rex`, accent: true })}
      ${kpi("Have a friend", pct(engagement.users_with_friend, engagement.total_users), { sub: `${num(engagement.users_with_friend)} of ${num(engagement.total_users)}` })}
      ${kpi("Avg friends", num(engagement.avg_friends))}
      ${kpi("Rex per active user", num(engagement.recs_per_active_user))}
      ${kpi("Friend accept rate", pct(engagement.friendships_accepted, engagement.friendships_accepted + engagement.friendships_pending))}
      ${kpi("Avg rating", num(engagement.avg_rating))}
      ${kpi("With a photo", pct(engagement.recs_with_photo, content.recs_total))}
      ${kpi("With a note", pct(engagement.recs_with_note, content.recs_total))}
    </div>

    <h2>What's been posted</h2>
    <div class="pairs">
      ${pair("Rex", content.recs_total, content.recs_7d)}
      ${pair("Blasts", content.blasts_total, content.blasts_7d)}
      ${pair("Comments on Rex", content.rec_comments_total, content.rec_comments_7d)}
      ${pair("Comments on blasts", content.blast_comments_total, content.blast_comments_7d)}
      ${pair("Likes", content.likes_total, content.likes_7d)}
      ${pair("Saves", content.saves_total, content.saves_7d)}
    </div>

    <h2>Rex per week</h2>
    ${bars(engagement.recs_by_week)}

    <h2>Signups per week</h2>
    ${bars(engagement.signups_by_week)}

    <h2>By category</h2>
    <table class="lean"><tbody>
      ${(engagement.by_category || []).map((row) => `<tr><td>${esc(row.type)}</td><td>${num(row.count)}</td></tr>`).join("")}
    </tbody></table>

    <h2>Who's posting</h2>
    <table class="lean"><tbody>
      ${(engagement.top_contributors || [])
        .map(
          (row) =>
            `<tr><td>${esc(row.display_name || row.username)}</td><td>${num(row.count)}</td></tr>`,
        )
        .join("")}
    </tbody></table>

    <h2>The rest</h2>
    <div class="pairs">
      <div class="pair"><span>Lists</span><span class="n">${num(engagement.lists_total)}</span><span class="r">${num(engagement.lists_published)} published</span></div>
      <div class="pair"><span>Want to trys</span><span class="n">${num(engagement.wants_total)}</span></div>
      <div class="pair"><span>Things</span><span class="n">${num(engagement.items_total)}</span></div>
      <div class="pair"><span>Places on the map</span><span class="n">${num(engagement.places_geocoded)}</span><span class="r">of ${num(engagement.places_total)}</span></div>
      <div class="pair"><span>Blasts answered</span><span class="n">${num(engagement.blasts_answered)}</span><span class="r">of ${num(engagement.blasts_total)}</span></div>
      <div class="pair"><span>Document imports</span><span class="n">${num(engagement.imports_total)}</span></div>
    </div>

    <h2>Feedback from inside the app</h2>
    ${
      feedback.length
        ? `<div class="fb-list">${feedback.map(feedbackRow).join("")}</div>`
        : `<p class="muted">Nothing yet. This is the ! button in the app header, not TestFlight \u2014 those live in App Store Connect.</p>`
    }

    <p class="muted" style="margin-top:2rem;font-size:.85rem">
      DAU, WAU and MAU mean “posted a Rex”, not “opened the app” — nobody posts daily, so read them as
      contribution rather than engagement. Refreshes when you reload.
    </p>`;
  document.getElementById("out").addEventListener("click", () => {
    session(null);
    renderSignIn();
  });
}

async function load() {
  const current = session();
  if (!current) return renderSignIn();
  root.innerHTML = `<p class="muted">Loading…</p>`;
  try {
    const [users, content, engagement, feedback] = await Promise.all([
      rpc("admin_kpis_users", current.token),
      rpc("admin_kpis_content", current.token),
      rpc("admin_kpis_engagement", current.token),
      // Newest first, and a generous limit because nobody has ever read it.
      // No profiles embed: feedback.user_id references auth.users, not
      // public.profiles, so there is no foreign key for PostgREST to follow
      // and asking for one is a 400 — which would have shown an empty list
      // and read as "nobody has sent anything".
      table(
        "feedback?select=created_at,message,page,is_anonymous,user_id" +
          "&order=created_at.desc&limit=200",
        current.token,
      ),
    ]);
    // Names in a second pass. profiles.id is the same uuid as auth.users.id,
    // so the ids line up even though no foreign key joins them.
    const ids = [
      ...new Set(feedback.filter((f) => !f.is_anonymous && f.user_id).map((f) => f.user_id)),
    ];
    const people = ids.length
      ? await table(
          `profiles?select=id,username,display_name&id=in.(${ids.join(",")})`,
          current.token,
        )
      : [];
    const byId = Object.fromEntries(people.map((p) => [p.id, p]));
    for (const row of feedback) row.who = byId[row.user_id];
    render(users, content, engagement, current.email, feedback);
  } catch (error) {
    session(null);
    if (error.message === "forbidden") {
      root.innerHTML = `<h2 style="margin-top:0">Admin only</h2>
        <p class="muted">That account isn't an admin. Ask Kathryn if you think it should be.</p>`;
      return;
    }
    renderSignIn(
      error.message === "expired" ? "That session has expired — sign in again." : error.message,
    );
  }
}

load();
