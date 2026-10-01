#!/usr/bin/env python3
"""Build the SetShot website into site/dist/.

Sources, all read from the checked-out tree:
  README.md                          overview page
  docs/documentation.md              documentation page
  SetShot/Resources/ReleaseNotes.md  release notes page
  project.yml                        minimum macOS version
  SetShot/Resources/Assets.xcassets  screenshots and app icon

From the GitHub Releases API (via `gh api`): latest version, publish date, the
download asset, and the publish date of each earlier release.

Requires: python3 (stdlib only), pandoc, gh (authenticated; GH_TOKEN in CI).
Set GITHUB_REPOSITORY (owner/name) to override the repo, otherwise gh infers it.
"""
import html
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from string import Template

SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
DIST = SITE / "dist"
ASSETS = ROOT / "SetShot/Resources/Assets.xcassets"

MACOS_NAMES = {"13": "Ventura", "14": "Sonoma", "15": "Sequoia", "26": "Tahoe", "27": "Golden Gate"}


def fail(msg):
    sys.exit(f"build.py: {msg}")


def run(*cmd, stdin=None):
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    if r.returncode:
        fail(f"{' '.join(cmd[:3])} failed:\n{r.stderr.strip()}")
    return r.stdout


def repo_slug():
    slug = os.environ.get("GITHUB_REPOSITORY")
    return slug or run("gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()


def pretty_date(iso):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).strftime("%B %-d, %Y")


def min_macos():
    m = re.search(r'MACOSX_DEPLOYMENT_TARGET:\s*"?([\d.]+)"?', (ROOT / "project.yml").read_text())
    if not m:
        fail("MACOSX_DEPLOYMENT_TARGET not found in project.yml")
    major = m.group(1).split(".")[0]
    name = MACOS_NAMES.get(major)
    return f"macOS {major} {name}" if name else f"macOS {m.group(1)}"


def pandoc(markdown):
    return run("pandoc", "-f", "gfm", "-t", "html5", "--wrap=none", stdin=markdown)


def pick_asset(assets):
    # Prefer a constant-named SetShot.dmg if releases ever ship one, then any dmg, then zip.
    for pred in (lambda n: n == "SetShot.dmg", lambda n: n.endswith(".dmg"), lambda n: n.endswith(".zip")):
        for a in assets:
            if pred(a["name"]):
                return a
    fail("latest release has no .dmg or .zip asset")


def copy_images():
    out = DIST / "images"
    out.mkdir(parents=True)
    for d in sorted(ASSETS.glob("*.imageset")):
        for png in d.glob("*.png"):
            shutil.copy(png, out / png.name)
    return out


def picturize(markdown, prefix, images_dir):
    """![alt](images/Name.png) -> <picture> with the light and dark variants."""
    def sub(m):
        alt, name = m.group(1), m.group(2)
        light, dark = f"{name}-light.png", f"{name}-dark.png"
        for f in (light, dark):
            if not (images_dir / f).exists():
                fail(f"docs reference images/{name}.png but {f} is not in the asset catalog")
        return (f'<picture><source media="(prefers-color-scheme: dark)" srcset="{prefix}images/{dark}">'
                f'<img src="{prefix}images/{light}" alt="{html.escape(alt, quote=True)}"></picture>')
    return re.sub(r"!\[([^\]]*)\]\(images/([A-Za-z0-9_-]+)\.png\)", sub, markdown)


def first_paragraph_text(markdown):
    for block in re.split(r"\n\s*\n", markdown):
        b = block.strip()
        if b and not b.startswith(("#", "*", "-", "!", "<", "**[")):
            text = re.sub(r"[*_`]|\[([^\]]*)\]\([^)]*\)", lambda m: m.group(1) or "", b)
            return " ".join(text.split())[:300]
    return "SetShot compares snapshots of your Mac's settings."


def render(template, out_path, root, title, description, nav, content, repo_url):
    page = template.substitute(
        title=html.escape(title), description=html.escape(description, quote=True), root=root,
        nav_home=' aria-current="page"' if nav == "home" else "",
        nav_docs=' aria-current="page"' if nav == "docs" else "",
        nav_notes=' aria-current="page"' if nav == "notes" else "",
        content=content, repo_url=repo_url)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(page)


def main():
    for tool in ("pandoc", "gh"):
        if not shutil.which(tool):
            fail(f"{tool} is not installed")
    slug = repo_slug()
    repo_url = f"https://github.com/{slug}"

    latest = json.loads(run("gh", "api", f"repos/{slug}/releases/latest"))
    version = latest["tag_name"].lstrip("v")
    published = pretty_date(latest["published_at"])
    asset = pick_asset(latest["assets"])
    size_mb = round(asset["size"] / 1_000_000, 1)
    macos = min_macos()

    lines = run("gh", "api", "--paginate", f"repos/{slug}/releases",
                "--jq", ".[] | select(.draft|not) | {tag_name, published_at}")
    dates = {}
    for line in lines.splitlines():
        r = json.loads(line)
        dates[r["tag_name"].lstrip("v")] = pretty_date(r["published_at"])

    template = Template((SITE / "template.html").read_text())
    if DIST.exists():
        shutil.rmtree(DIST)
    DIST.mkdir()
    shutil.copytree(SITE / "static", DIST / "static")
    images_dir = copy_images()

    # Overview: README, with its H1 and download line replaced by the hero block.
    readme = (ROOT / "README.md").read_text()
    h1 = re.match(r"# (.+)\n", readme)
    if not h1:
        fail("README.md does not start with an H1")
    body = readme[h1.end():]
    body, n = re.subn(r"^\*\*\[Download[^\n]*\n", "", body, flags=re.M)
    if n != 1:
        print("warning: README download line not found; nothing removed", file=sys.stderr)
    hero = f"""<section class="hero">
<h1>{html.escape(h1.group(1))}</h1>
<p class="lede">See what changed in your Mac's settings, in plain English.</p>
<p class="download"><a class="button" href="{html.escape(asset['browser_download_url'])}">Download SetShot {html.escape(version)}</a></p>
<p class="meta">Version {html.escape(version)}, released {published} &middot; {size_mb} MB &middot; requires {html.escape(macos)} or later &middot;
<a href="release-notes/">Release notes</a></p>
</section>
"""
    render(template, DIST / "index.html", "", "SetShot: see what changed in your Mac's settings",
           first_paragraph_text(body), "home", hero + pandoc(body), repo_url)

    # Documentation
    doc = picturize((ROOT / "docs/documentation.md").read_text(), "../", images_dir)
    render(template, DIST / "docs/index.html", "../", "SetShot Documentation",
           first_paragraph_text(doc.split("\n", 1)[1]), "docs", pandoc(doc), repo_url)

    # Release notes, each version heading dated from the Releases API.
    notes_html = pandoc((ROOT / "SetShot/Resources/ReleaseNotes.md").read_text())

    def add_date(m):
        d = dates.get(m.group(2).strip())
        span = f' <span class="date">{d}</span>' if d else ""
        return f"{m.group(1)}{m.group(2)}{span}</h2>"
    notes_html = re.sub(r'(<h2 id="[^"]*">)([^<]+)</h2>', add_date, notes_html)
    intro = (f'<h1>Release Notes</h1>\n<p class="release-meta">The latest release is '
             f'<a href="{html.escape(asset["browser_download_url"])}">SetShot {html.escape(version)}</a>, '
             f'published {published}.</p>\n')
    render(template, DIST / "release-notes/index.html", "../", "SetShot Release Notes",
           f"What changed in each SetShot release, latest is {version}.", "notes", intro + notes_html, repo_url)

    print(f"Built {DIST} for {slug}: version {version}, {asset['name']} ({size_mb} MB), {macos}")


if __name__ == "__main__":
    main()
