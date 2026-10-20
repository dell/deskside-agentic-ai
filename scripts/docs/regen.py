#!/usr/bin/env python3
"""Regenerate the GitHub Pages site (docs/**/index.html) from the Markdown sources.

Each page is the existing HTML shell with its <article> replaced by the rendered Markdown (links rewritten
to site-relative URLs, relative links to files outside the site are unlinked). New pages are created from
the sizing page shell and linked in every sidebar. Usage:
    python3 scripts/docs/regen.py            # rewrite pages
    python3 scripts/docs/regen.py --check    # exit 1 if any page is stale (CI / tests)
The internal template-standard and design-system pages are intentionally NOT generated (kept local, gitignored).
"""
import sys
import re, os, posixpath, markdown

MD_TO_HTML = {
    "docs/glossary.md": "docs/glossary/index.html",
    "docs/changelog.md": "docs/changelog/index.html",
    "docs/personas.md": "docs/personas/index.html",
    "docs/sizing.md": "docs/sizing/index.html",
    "docs/stack.md": "docs/stack/index.html",
    "docs/stack-composition.md": "docs/stack-composition/index.html",
    "solutions/openclaw-on-nemoclaw/landscape-fleet-deploy.md": "docs/solutions/openclaw-on-nemoclaw/landscape-fleet-deploy/index.html",
    "solutions/hermes-on-nemoclaw/landscape-fleet-deploy.md": "docs/solutions/hermes-on-nemoclaw/landscape-fleet-deploy/index.html",
    "solutions/agentic-vss/landscape-fleet-deploy.md": "docs/solutions/agentic-vss/landscape-fleet-deploy/index.html",
    "solutions/higher-ed-ai-lab/landscape-fleet-deploy.md": "docs/solutions/higher-ed-ai-lab/landscape-fleet-deploy/index.html",
    "docs/scope.md": "docs/scope/index.html",
    "docs/operations.md": "docs/operations/index.html",
    "docs/topology.md": "docs/topology/index.html",
    "monitoring/README.md": "docs/monitoring/index.html",
    "recipes/README.md": "docs/recipes/index.html",
    "solutions/README.md": "docs/solutions/index.html",
    "solutions/agentic-coding/README.md": "docs/solutions/agentic-coding/index.html",
    "solutions/agentic-coding/it-admin-guide.md": "docs/solutions/agentic-coding/it-admin-guide/index.html",
    "solutions/agentic-coding/ide-integration.md": "docs/solutions/agentic-coding/ide-integration/index.html",
    "solutions/agentic-coding/landscape-fleet-deploy.md": "docs/solutions/agentic-coding/landscape-fleet-deploy/index.html",
    "solutions/agentic-vss/README.md": "docs/solutions/agentic-vss/index.html",
    "solutions/agentic-vss/it-admin-guide.md": "docs/solutions/agentic-vss/it-admin-guide/index.html",
    "solutions/agentic-vss/deploy-guide-dev.md": "docs/solutions/agentic-vss/deploy-guide-dev/index.html",
    "solutions/openclaw-on-nemoclaw/README.md": "docs/solutions/openclaw-on-nemoclaw/index.html",
    "solutions/openclaw-on-nemoclaw/it-admin-guide.md": "docs/solutions/openclaw-on-nemoclaw/it-admin-guide/index.html",
    "solutions/openclaw-on-nemoclaw/deploy-guide-dev.md": "docs/solutions/openclaw-on-nemoclaw/deploy-guide-dev/index.html",
    "solutions/hermes-on-nemoclaw/README.md": "docs/solutions/hermes-on-nemoclaw/index.html",
    "solutions/hermes-on-nemoclaw/it-admin-guide.md": "docs/solutions/hermes-on-nemoclaw/it-admin-guide/index.html",
    "solutions/hermes-on-nemoclaw/deploy-guide-dev.md": "docs/solutions/hermes-on-nemoclaw/deploy-guide-dev/index.html",
    "solutions/higher-ed-ai-lab/README.md": "docs/solutions/higher-ed-ai-lab/index.html",
    "solutions/higher-ed-ai-lab/it-admin-guide.md": "docs/solutions/higher-ed-ai-lab/it-admin-guide/index.html",
    "solutions/higher-ed-ai-lab/deploy-guide-dev.md": "docs/solutions/higher-ed-ai-lab/deploy-guide-dev/index.html",
}
PAGE_MAP = {
    "docs/glossary.md": "/glossary/",
    "docs/changelog.md": "/changelog/",
    "docs/personas.md": "/personas/",
    "docs/sizing.md": "/sizing/",
    "docs/stack.md": "/stack/",
    "docs/stack-composition.md": "/stack-composition/",
    "solutions/openclaw-on-nemoclaw/landscape-fleet-deploy.md": "/solutions/openclaw-on-nemoclaw/landscape-fleet-deploy/",
    "solutions/hermes-on-nemoclaw/landscape-fleet-deploy.md": "/solutions/hermes-on-nemoclaw/landscape-fleet-deploy/",
    "solutions/agentic-vss/landscape-fleet-deploy.md": "/solutions/agentic-vss/landscape-fleet-deploy/",
    "solutions/higher-ed-ai-lab/landscape-fleet-deploy.md": "/solutions/higher-ed-ai-lab/landscape-fleet-deploy/",
    "docs/scope.md": "/scope/",
    "docs/operations.md": "/operations/",
    "docs/topology.md": "/topology/",
    "monitoring/README.md": "/monitoring/",
    "recipes/README.md": "/recipes/",
    "solutions/README.md": "/solutions/",
    "solutions/agentic-coding/README.md": "/solutions/agentic-coding/",
    "solutions/agentic-coding/it-admin-guide.md": "/solutions/agentic-coding/it-admin-guide/",
    "solutions/agentic-coding/ide-integration.md": "/solutions/agentic-coding/ide-integration/",
    "solutions/agentic-coding/landscape-fleet-deploy.md": "/solutions/agentic-coding/landscape-fleet-deploy/",
    "solutions/agentic-vss/README.md": "/solutions/agentic-vss/",
    "solutions/agentic-vss/it-admin-guide.md": "/solutions/agentic-vss/it-admin-guide/",
    "solutions/agentic-vss/deploy-guide-dev.md": "/solutions/agentic-vss/deploy-guide-dev/",
    "solutions/openclaw-on-nemoclaw/README.md": "/solutions/openclaw-on-nemoclaw/",
    "solutions/openclaw-on-nemoclaw/it-admin-guide.md": "/solutions/openclaw-on-nemoclaw/it-admin-guide/",
    "solutions/openclaw-on-nemoclaw/deploy-guide-dev.md": "/solutions/openclaw-on-nemoclaw/deploy-guide-dev/",
    "solutions/hermes-on-nemoclaw/README.md": "/solutions/hermes-on-nemoclaw/",
    "solutions/hermes-on-nemoclaw/it-admin-guide.md": "/solutions/hermes-on-nemoclaw/it-admin-guide/",
    "solutions/hermes-on-nemoclaw/deploy-guide-dev.md": "/solutions/hermes-on-nemoclaw/deploy-guide-dev/",
    "solutions/higher-ed-ai-lab/README.md": "/solutions/higher-ed-ai-lab/",
    "solutions/higher-ed-ai-lab/it-admin-guide.md": "/solutions/higher-ed-ai-lab/it-admin-guide/",
    "solutions/higher-ed-ai-lab/deploy-guide-dev.md": "/solutions/higher-ed-ai-lab/deploy-guide-dev/",
    "README.md": "/",
}

def resolve_link(target, md_src):
    """Rewrite a relative md link to the site URL, depth-relative. None = unlink target."""
    if target.startswith(("http://", "https://", "#", "mailto:")):
        return target
    frag = ""
    if "#" in target:
        target, f = target.split("#", 1); frag = "#" + f
    base = posixpath.dirname(md_src)
    repo = posixpath.normpath(posixpath.join(base, target))
    url = None
    if repo in PAGE_MAP:
        url = PAGE_MAP[repo]
    elif repo.endswith(".md"):
        if repo.startswith("docs/"):
            url = "/" + repo
    else:
        mirrored = posixpath.join("docs", repo)
        if os.path.exists(mirrored):
            url = "/" + mirrored
    if url is None:
        return None
    page_html = MD_TO_HTML[md_src]
    page_dir = posixpath.dirname(page_html)
    u = url.lstrip("/")
    if not u.startswith("docs/"):
        u = posixpath.join("docs", u)
    if u.endswith("index.html"):
        u = u[: -len("index.html")]
    trailing = u.endswith("/")
    rel = posixpath.relpath(u.rstrip("/"), page_dir)
    if trailing and not rel.endswith("/"):
        rel += "/"
    if rel == "":
        rel = "./"
    return rel + frag


def md_to_html(md_text, md_src):
    md_text = re.sub(r"\A---\n.*?\n---\n", "", md_text, flags=re.S)
    def md_repl(m):
        label, target = m.group(2), m.group(3)
        r = resolve_link(target, md_src)
        if r is None:
            return label
        return f"{m.group(1)}[{label}]({r})"
    md_text = re.sub(r"(!?)\[([^\]]*)\]\(([^)\s]+)\)", md_repl, md_text)
    html = markdown.markdown(md_text, extensions=["fenced_code", "tables", "toc"])
    html = html.replace("<hr />", "").replace("<hr>", "")
    html = re.sub(r"(<pre><code[^>]*>)(.*?)(</code></pre>)", lambda m: m.group(1) + m.group(2).replace('"', "&quot;") + m.group(3), html, flags=re.S)
    return html

SOLUTION_NAMES = {'openclaw-on-nemoclaw': 'OpenClaw on NemoClaw', 'hermes-on-nemoclaw': 'Hermes on NemoClaw', 'agentic-vss': 'Agentic Video Search & Summarization', 'higher-ed-ai-lab': 'Higher Education AI Lab'}
TITLES = {**{"docs/solutions/%s/landscape-fleet-deploy/index.html" % k: "%s — Fleet Deploy via Landscape" % v for k, v in SOLUTION_NAMES.items()}, "docs/scope/index.html": "Scope", "docs/operations/index.html": "Operations", "docs/topology/index.html": "Topology",
          "docs/monitoring/index.html": "Tokenomics monitoring", "docs/changelog/index.html": "Changelog"}
NAV_NEW = [("scope", "Scope &amp; Backlog"), ("operations", "Operations"), ("topology", "Topology (TP vs DP)"),
           ("monitoring", "Tokenomics Monitoring"), ("changelog", "Changelog")]

def make_shell(html_path):
    """Create a new page shell by cloning the sizing page and fixing depth-relative paths."""
    parts = html_path.split("/")
    if parts[1] == "solutions" and len(parts) == 5:       # solution sub-page: clone its IT-admin page (same depth and nav)
        s = open("docs/solutions/%s/it-admin-guide/index.html" % parts[2]).read()
        s = re.sub(r"<title>.*?</title>", "<title>%s — Dell Deskside Agentic AI Solutions for NVIDIA</title>" % TITLES[html_path], s)
        s = s.replace('class="sub active"', 'class="sub"')
        s = s.replace('/ it-admin-guide</div>', '/ landscape-fleet-deploy</div>')
        return s
    s = open("docs/sizing/index.html").read()
    name = html_path.split("/")[1]
    s = re.sub(r"<title>.*?</title>", "<title>%s — Dell Deskside Agentic AI Solutions for NVIDIA</title>" % TITLES[html_path], s)
    s = s.replace('<a href="../sizing/" class="active">', '<a href="../sizing/">')
    s = s.replace('<div class="topbar"><a href="../index.html">Home</a> / sizing</div>', '<div class="topbar"><a href="../index.html">Home</a> / %s</div>' % name)
    return s

def inject_subnav(s, sol):
    """Add 'Fleet Deploy via Landscape' to a solution's sidebar sub-links (after the last one)."""
    if not sol or ('solutions/%s/landscape-fleet-deploy/"' % sol) in s: return s
    subs = list(re.finditer(r'<a class="sub[^"]*" href="([^"]*)solutions/%s/[^"]*">[^<]*</a>' % re.escape(sol), s))
    if not subs: return s
    last = subs[-1]
    link = '\n<a class="sub" href="%ssolutions/%s/landscape-fleet-deploy/">Fleet Deploy via Landscape</a>' % (last.group(1), sol)
    return s[:last.end()] + link + s[last.end():]

def inject_nav(s, name):
    """Add the new reference pages after the Glossary link (same relative prefix), mark the active one.
    The anchor must tolerate class="active" — on the glossary's own page that link carries it, and an
    earlier version of this regex matched only the plain form, so nav injections silently skipped it."""
    m = re.search(r'<a href="((?:\.\./)*)glossary/"(?: class="active")?>Glossary</a>', s)
    if not m: return s
    pre = m.group(1)
    add = ""
    for slug, label in NAV_NEW:
        nav = re.search(r'<nav class="nav">.*?</nav>', s, re.S)
        if nav and ('<a href="%s%s/"' % (pre, slug)) in nav.group(0): continue
        add += "\n" + '<a href="%s%s/"%s>%s</a>' % (pre, slug, ' class="active"' if slug == name else "", label)
    return s.replace(m.group(0), m.group(0) + add, 1) if add else s

def ensure_scripts(s):
    """highlight.js on every page (before tabs/picker, which depend on it)."""
    m = re.search(r'href="((?:\.\./)*)assets/dell\.css"', s)
    if not m: return s
    pre = m.group(1)
    for name in ("highlight", "anchors"):
        tag = '<script src="%sassets/%s.js" defer></script>' % (pre, name)
        if tag in s: continue
        first = re.search(r'<script src="[^"]*assets/(?:tabs|picker)\.js"', s)
        s = (s[:first.start()] + tag + "\n" + s[first.start():]) if first else s.replace("</body>", tag + "\n</body>", 1)
    return s

PICKER_PAGES = {m for m in MD_TO_HTML if m.startswith("solutions/") and m.rsplit("/", 1)[-1] in
                ("deploy-guide-dev.md", "it-admin-guide.md", "landscape-fleet-deploy.md", "ide-integration.md")}

def ensure_picker(s):
    s = re.sub(r'<article class="article"( data-picker)?>', '<article class="article" data-picker>', s, count=1)
    m = re.search(r'href="((?:\.\./)*)assets/dell\.css"', s)
    tag = '<script src="%sassets/picker.js" defer></script>' % m.group(1)
    return s if tag in s else s.replace("</body>", tag + "\n</body>", 1)

check = "--check" in sys.argv
changed = []
for md_src, html_path in MD_TO_HTML.items():
    if not os.path.exists(md_src): continue
    new_page = not os.path.exists(html_path)
    s = make_shell(html_path) if new_page else open(html_path).read()
    body = md_to_html(open(md_src).read(), md_src)
    new = re.sub(r"(<article[^>]*>).*(</article>)", lambda m: m.group(1) + "\n" + body + "\n    " + m.group(2), s, flags=re.S)
    new = ensure_scripts(new)
    if md_src.startswith('solutions/') and md_src.split('/')[1] in SOLUTION_NAMES: new = inject_subnav(new, md_src.split('/')[1])
    if md_src in PICKER_PAGES: new = ensure_picker(new)
    new = inject_nav(new, html_path.split("/")[1] if html_path.split("/")[1] in dict(NAV_NEW) else "")
    if new != s:
        changed.append(html_path)
        if not check:
            os.makedirs(os.path.dirname(html_path), exist_ok=True); open(html_path, "w").write(new)
print("\n".join(changed))
print(len(changed), "stale" if check else "regenerated")
sys.exit(1 if (check and changed) else 0)
