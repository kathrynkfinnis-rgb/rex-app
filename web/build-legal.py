#!/usr/bin/env python3
"""Generates privacy.html and terms.html from the app's own copy.

Sept 17 — the website and the app must say the same thing, and the app is
where the text is edited (LegalContentView.swift, which is also what people
agree to at sign-up). This reads the two Swift string literals and renders
them, so the pages can't quietly drift out of date. Run it after editing
the policy, and commit the result:

    python3 web/build-legal.py
"""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "ios/App/App/Native/LegalContentView.swift"
OUT = ROOT / "web"

swift = SOURCE.read_text()
updated = re.search(r'lastUpdated = "([^"]+)"', swift).group(1)


def body(name: str) -> str:
    match = re.search(rf'private static let {name} = """\n(.*?)\n    """', swift, re.S)
    text = match.group(1)
    text = re.sub(r"^    ", "", text, flags=re.M)
    return text.replace("\\(lastUpdated)", updated)


def render(text: str) -> str:
    """Numbered headings become <h2>, bullet runs become <ul>, the rest <p>."""
    out, bullets = [], []

    def flush():
        if bullets:
            out.append("<ul>" + "".join(f"<li>{b}</li>" for b in bullets) + "</ul>")
            bullets.clear()

    for line in text.split("\n"):
        line = line.strip()
        if not line:
            flush()
            continue
        escaped = html.escape(line).replace("&quot;", '"')
        escaped = re.sub(r"support@find-rex\.com", '<a href="mailto:support@find-rex.com">support@find-rex.com</a>', escaped)
        if line.startswith("•"):
            bullets.append(escaped.lstrip("• ").strip())
        elif re.match(r"^\d+\. [A-Z]", line):
            flush()
            out.append(f"<h2>{escaped}</h2>")
        elif line.startswith("Last updated"):
            flush()
            out.append(f'<p class="updated">{escaped}</p>')
        else:
            flush()
            out.append(f"<p>{escaped}</p>")
    flush()
    return "\n".join(out)


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>REX — {title}</title>
<meta name="description" content="{desc}">
<link rel="stylesheet" href="https://api.fontshare.com/v2/css?f[]=switzer@400,500,600,700&f[]=sentient@400,500,700&display=swap">
<link rel="stylesheet" href="/styles.css">
<link rel="icon" href="/favicon.png">
<link rel="apple-touch-icon" href="/icon-180.png">
<meta property="og:site_name" content="REX">
<meta property="og:title" content="REX — {title}">
<meta property="og:description" content="{desc}">
</head>
<body>
<header class="site"><div class="wrap">
  <a class="brand" href="/"><img src="/wordmark.png" alt="REX"></a>
  <nav class="site">
    <a href="/privacy.html">Privacy</a>
    <a href="/terms.html">Terms</a>
    <a href="/support.html">Support</a>
  </nav>
</div></header>
<main><div class="wrap legal">
<h1>{title}</h1>
{body}
</div></main>
<footer class="site"><div class="wrap">
  <p>REX is made by Three Lines Studio Ltd.<br>
  Questions about this? <a href="mailto:support@find-rex.com">support@find-rex.com</a></p>
  <p><a href="/privacy.html">Privacy Policy</a> &middot; <a href="/terms.html">Terms of Service</a> &middot; <a href="/support.html">Support</a></p>
</div></footer>
</body>
</html>
"""

for name, title, desc, out_name in [
    ("privacyBody", "Privacy Policy", "What REX collects, why, who processes it, and your rights.", "privacy.html"),
    ("termsBody", "Terms of Service", "The agreement for using REX.", "terms.html"),
]:
    (OUT / out_name).write_text(PAGE.format(title=title, desc=desc, body=render(body(name))))
    print("wrote", out_name)
