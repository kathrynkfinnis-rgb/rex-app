// Sept 22 — the KPI dashboard, moved off Lovable.
//
// Deliberately one static file with no build step and no server: it signs in
// against Supabase directly and calls the same three admin functions the old
// page did. Those functions are SECURITY DEFINER and start with a has_role
// check, so being an admin is enforced in the database. This page hiding its
// own contents is a courtesy, not the security — a non-admin who read the
// source and called the functions themselves would still be refused.
const SUPABASE_URL = "https://uhpzkbkwxcgqfxmlyktj.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVocHprYmt3eGNncWZ4bWx5a3RqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4Mzk2NDMsImV4cCI6MjEwMTQxNTY0M30.IvQ8byDwHErLhuJI1Pg3bRcb4AKK4sb9Bm6cr_6sHbI";
const STORE = "rex.admin.session";

const root = document.getElementById("root");
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const num = (v) => (v === null || v === undefined ? "—" : Number(v).toLocaleString("en-GB"));
const pct = (a, b) => (!b ? "—" : Math.round((a / b) * 100) + "%");

function session(next) {
  try {
    if (next === undefined) return JSON.parse(localStorage.getItem(STORE) || "null");
    if (next === null) localStorage.removeItem(STORE);
    else localStorage.setItem(STORE, JSON.stringify(next));
  } catch { return null; }
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
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: "{}",
  });
  if (response.status === 401) throw new Error("expired");
  const data = await response.json();
  // The functions raise 'forbidden' for anyone without the admin role.
  if (!response.ok) throw new Error(data.message === "forbidden" ? "forbidden" : (data.message || "Couldn't load"));
  return data;
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
    .map((p) => `<div style="height:${Math.max(2, (p.count / max) * 100)}%" title="${esc(p.week)}: ${p.count}"></div>`)
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

function render(users, content, engagement, email) {
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
      ${(engagement.top_contributors || []).map((row) =>
        `<tr><td>${esc(row.display_name || row.username)}</td><td>${num(row.count)}</td></tr>`).join("")}
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
    const [users, content, engagement] = await Promise.all([
      rpc("admin_kpis_users", current.token),
      rpc("admin_kpis_content", current.token),
      rpc("admin_kpis_engagement", current.token),
    ]);
    render(users, content, engagement, current.email);
  } catch (error) {
    session(null);
    if (error.message === "forbidden") {
      root.innerHTML = `<h2 style="margin-top:0">Admin only</h2>
        <p class="muted">That account isn't an admin. Ask Kathryn if you think it should be.</p>`;
      return;
    }
    renderSignIn(error.message === "expired" ? "That session has expired — sign in again." : error.message);
  }
}

load();
