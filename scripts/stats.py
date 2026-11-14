#!/usr/bin/env python3
"""SetShot usage stats: GitHub release downloads and active Macs from Cloudflare.

    scripts/stats.py            # everything since 1.0 shipped
    scripts/stats.py --days 14  # Cloudflare daily table for the last 14 days

Downloads come from `gh`. Active Macs come from Cloudflare's GraphQL analytics
for setshot.tidbits.com: distinct client networks that fetched the appcast or
the KB with a SetShot user agent. IPv6 addresses are cut to their /64 so a Mac
rotating private addresses counts once. Other update checkers that poll the
appcast (Latest, Updatest and the like) are excluded by user agent.

The Cloudflare half needs an API token with two permissions on tidbits.com:
Zone > Analytics > Read and Zone > Zone > Read. The script reads it from
$CLOUDFLARE_API_TOKEN, or else from ~/.config/setshot/cloudflare-token.
Without a token it prints the download figures only.

Betas before b33 check GitHub for updates and never reach this host, so they
are not counted. Daily figures count only Macs where SetShot ran that day.
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

REPO = "adamengst/setshot-app"
ZONE_NAME = "tidbits.com"
HOST = "setshot.tidbits.com"
PATHS = ["/appcast.xml", "/kb/version.json", "/kb/settings-kb.json"]
RELEASE_1_0 = dt.datetime(2026, 11, 3, tzinfo=dt.timezone.utc)
TOKEN_FILE = Path.home() / ".config/setshot/cloudflare-token"
API = "https://api.cloudflare.com/client/v4"


# ---------- GitHub downloads ----------

def downloads():
    out = subprocess.run(
        ["gh", "api", f"repos/{REPO}/releases", "--paginate",
         "--jq", ".[] | {tag: .tag_name, date: .published_at, assets: [.assets[] | {name, n: .download_count}]}"],
        check=True, capture_output=True, text=True).stdout
    releases = [json.loads(line) for line in out.splitlines() if line.strip()]

    def kind(tag):
        if tag.startswith("v0.9"):
            return "0.9.x"
        return "beta" if "b" in tag[1:] else "release"

    totals = {"release": 0, "beta": 0, "0.9.x": 0}
    print("Downloads (GitHub release assets)")
    for r in releases:
        n = sum(a["n"] for a in r["assets"])
        totals[kind(r["tag"])] += n
        if kind(r["tag"]) == "release":
            parts = ", ".join(f'{a["name"].rsplit(".", 1)[-1]} {a["n"]}' for a in r["assets"])
            print(f'  {r["tag"]:<10} {r["date"][:10]}  {n:>6}  ({parts})')
    print(f'  {"Releases":<22} {totals["release"]:>6}')
    print(f'  {"Betas":<22} {totals["beta"]:>6}')
    print(f'  {"0.9.x":<22} {totals["0.9.x"]:>6}')
    print(f'  {"All":<22} {sum(totals.values()):>6}')
    print("  Zip downloads include Sparkle updates, so they count updates as well as new installs.")


# ---------- Cloudflare active Macs ----------

def token():
    t = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    if not t and TOKEN_FILE.exists():
        t = TOKEN_FILE.read_text().strip()
    return t or None


def cf(tok, path, body=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"},
        method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


QUERY = """query($z:String!,$f:ZoneHttpRequestsAdaptiveGroupsFilter_InputObject){
  viewer{zones(filter:{zoneTag:$z}){
    httpRequestsAdaptiveGroups(limit:10000,filter:$f){dimensions{clientIP}}}}}"""


def networks(tok, zone, start, end):
    """Distinct client networks that ran SetShot between start and end (one day at most)."""
    f = {"clientRequestHTTPHost": HOST, "clientRequestPath_in": PATHS,
         "userAgent_like": "SetShot%",
         "datetime_geq": start.isoformat().replace("+00:00", "Z"),
         "datetime_lt": end.isoformat().replace("+00:00", "Z")}
    r = cf(tok, "/graphql", {"query": QUERY, "variables": {"z": zone, "f": f}})
    if r.get("errors"):
        raise RuntimeError("; ".join(e["message"] for e in r["errors"]))
    groups = r["data"]["viewer"]["zones"][0]["httpRequestsAdaptiveGroups"]
    if len(groups) >= 10000:
        print(f"  warning: {start:%Y-%m-%d} hit the 10,000-row limit; counts are low", file=sys.stderr)
    return {g["dimensions"]["clientIP"] for g in groups}


def net(ip):
    return ":".join(ip.split(":")[:4]) if ":" in ip else ip


def active(tok, days):
    zones = cf(tok, f"/zones?name={ZONE_NAME}")
    if not zones.get("success") or not zones["result"]:
        sys.exit(f"Cloudflare: can't look up {ZONE_NAME}; the token needs Zone > Zone > Read.")
    zone = zones["result"][0]["id"]

    now = dt.datetime.now(dt.timezone.utc)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    first_table_day = today - dt.timedelta(days=days)

    seen, ips_seen, week = set(), set(), set()
    rows, oldest = [], None
    day = RELEASE_1_0
    while day < now:
        end = min(day + dt.timedelta(days=1), now)
        try:
            ips = networks(tok, zone, day, end)
        except RuntimeError:
            # Days older than the plan keeps are refused; skip until data starts.
            if oldest is None:
                day = end
                continue
            raise
        oldest = oldest or day
        nets = {net(ip) for ip in ips}
        new = len(nets - seen)
        seen |= nets
        ips_seen |= ips
        if day >= today - dt.timedelta(days=6):  # today plus the six days before
            week |= nets
        if day >= first_table_day:
            rows.append((day, len(nets), new))
        day = end

    print()
    print(f"Active Macs (Cloudflare, {HOST}, distinct networks)")
    print(f"  {'Day':<12} {'Networks':>8} {'New':>5}")
    for d, n, new in rows:
        label = f"{d:%Y-%m-%d}" + ("*" if d == today else "")
        print(f"  {label:<12} {n:>8} {new:>5}")
    print(f"  {'Last 7 days':<12} {len(week):>8}")
    print(f"  {'Since ' + (oldest or RELEASE_1_0).strftime('%b %-d'):<12} {len(seen):>8}  ({len(ips_seen)} raw addresses)")
    print("  * today so far. A laptop on several networks counts more than once;")
    print("    Macs behind one router count once.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--days", type=int, default=10, help="days in the Cloudflare daily table (default 10)")
    args = ap.parse_args()

    downloads()
    tok = token()
    if not tok:
        print(f"\nNo Cloudflare token in $CLOUDFLARE_API_TOKEN or {TOKEN_FILE}; skipping active Macs.")
        return
    active(tok, args.days)


if __name__ == "__main__":
    main()
