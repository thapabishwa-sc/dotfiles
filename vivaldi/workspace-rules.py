#!/usr/bin/env python3
"""Create Vivaldi Workspaces and Workspace Rules (link routes) from the tables below,
and apply UI settings tuned for three Vivaldi windows side by side (~1100px each).

Vivaldi rewrites its Preferences file while running, so QUIT VIVALDI (Cmd-Q) first.
Re-runnable: existing workspaces are reused by name and rules already present are
skipped, so editing the table and running again only adds what's new. A timestamped
backup of Preferences is written next to it before every change.

Pref format (from Vivaldi 8.2's own code):
  vivaldi.workspaces.list         [{id: int, name: str, emoji: str}]
  vivaldi.workspaces.link_routes  [{id: uuid, type: CONTAINS|EQUALS|STARTSWITH,
                                    expression: str, workspaceId: int}]
  SETTINGS: plain vivaldi.* prefs (booleans here), set to the listed values.
  SEARCH_ENGINES: nickname search engines, written to the keywords table of
  "Web Data" (Vivaldi closed). Chromium only verifies keywords.url_hash on Windows
  (keyword_table.cc: `#if BUILDFLAG(IS_WIN)`), so rows without a hash load fine on
  macOS; the row shape mirrors a user-added engine. Existing nicknames are updated
  in place; built-in (prepopulated) ones are never touched.
The default engine is left alone (default_search_provider.guid already points at
Google; the full default is MAC-protected in Secure Preferences).

Usage:  python3 ~/.config/vivaldi/workspace-rules.py [--dry-run] [--prefs PATH]
"""
import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid

DEFAULT_PREFS = os.path.expanduser("~/Library/Application Support/Vivaldi/Default/Preferences")
WEB_DATA = "Web Data"  # sibling of Preferences

# General browsing stays in Vivaldi's built-in unassigned group (where new windows
# start), so there is no "web" workspace; these hold the routed work sites.
WORKSPACES = [  # (name, emoji) - created in this order if missing
    ("monitoring", "📈"),   # ngSaaS + PreSaaS cluster tooling
    ("dev", "💻"),          # code, tickets, inventory + reporting
]

# Old name -> new name. Renamed in place (same workspace id), so existing rules and
# tabs carry over. Workspaces dropped from the table (web, presaas, tools) are NOT
# deleted by this script - delete them in Vivaldi so it can move or close their tabs.
RENAMES = {"ngsaas": "monitoring"}

RULES = [  # (type, expression, workspace) - "If URL <type> <expression> open in <workspace>"
    # monitoring: cluster tooling behind Teleport + OCI console (ngSaaS and PreSaaS)
    ("CONTAINS", "-grafana.corp.stellarcyber.cloud", "monitoring"),
    ("CONTAINS", "-spark.corp.stellarcyber.cloud", "monitoring"),
    ("CONTAINS", "-flink.corp.stellarcyber.cloud", "monitoring"),
    ("CONTAINS", "-alertmanager.corp.stellarcyber.cloud", "monitoring"),
    ("CONTAINS", "-prometheus.corp.stellarcyber.cloud", "monitoring"),
    ("CONTAINS", "argo.corp.stellarcyber.cloud", "monitoring"),
    ("CONTAINS", "://cloud.oracle.com", "monitoring"),    # console only, not the OCI login hosts
    ("STARTSWITH", "https://t.stellarcyber.cloud", "monitoring"),  # Teleport
    # dev: code + tickets
    ("STARTSWITH", "https://github.com", "dev"),
    ("STARTSWITH", "https://bitbucket.org", "dev"),
    ("CONTAINS", ".atlassian.net", "dev"),
    # dev too: inventory + reporting (host-anchored so repo paths like /cmdb don't match)
    ("CONTAINS", "://cmdb", "dev"),
    ("CONTAINS", "://datagerry", "dev"),
    ("CONTAINS", "://metabase", "dev"),
]


# UI settings for three ~1100px windows on the ultrawide (keys/types from Vivaldi 8.2).
# Tabs stay on top (vivaldi.tabs.bar.position = 0, the default) and page zoom stays 100%.
SETTINGS = {
    "vivaldi.panels.as_overlay.enabled": True,      # side panel floats over the page, no width cost
    "vivaldi.panels.as_overlay.auto_close": True,   # ...and closes when you click back into the page
    "vivaldi.appearance.density": True,             # compact UI
    "vivaldi.workspaces.button.show_in_tabbar": True,
    "vivaldi.workspaces.button.show_name": True,    # each window shows which workspace it holds
    # Window panel lists tabs open more than once (same URL) in a "Duplicate Tabs"
    # folder, ending with a "Close All Duplicate Tabs" button.
    "vivaldi.panels.window.list.show.duplicate_tabs": True,
}


# Nickname search engines: type "<nickname> <terms>" in the address bar. %s = terms.
# Per-cluster tools take the cluster name, e.g. "gf prod-us-ashburn-1".
SEARCH_ENGINES = [  # (nickname, name, url)
    ("gh", "GitHub repos", "https://github.com/orgs/stellarcyber-eng/repositories?q=%s"),
    ("ghc", "GitHub code", "https://github.com/search?q=org%3Astellarcyber-eng+%s&type=code"),
    ("bb", "Bitbucket", "https://bitbucket.org/accaellatechnology/workspace/repositories/?search=%s"),
    ("j", "Jira issue", "https://accaella.atlassian.net/browse/%s"),
    ("js", "Jira search", "https://accaella.atlassian.net/issues/?jql=text%20~%20%22%s%22"),
    ("cf", "Confluence", "https://accaella.atlassian.net/wiki/search?text=%s"),
    ("gf", "Grafana", "https://%s-grafana.corp.stellarcyber.cloud/"),
    ("gfe", "Grafana Explore", "https://%s-grafana.corp.stellarcyber.cloud/explore"),
    ("sp", "Spark", "https://%s-spark.corp.stellarcyber.cloud/"),
    ("fl", "Flink", "https://%s-flink.corp.stellarcyber.cloud/"),
    ("am", "Alertmanager", "https://%s-alertmanager.corp.stellarcyber.cloud/"),
    ("pr", "Prometheus", "https://%s-prometheus.corp.stellarcyber.cloud/"),
    ("ar", "Argo CD", "https://%s-argo.corp.stellarcyber.cloud/applications"),
]


def chromium_now() -> int:
    """Microseconds since 1601-01-01 (Chromium base::Time)."""
    return int(time.time() * 1_000_000) + 11_644_473_600 * 1_000_000


def apply_search_engines(web_data: str, dry_run: bool) -> bool:
    """Insert/update nickname engines in Vivaldi's keywords table. Returns True if changed."""
    db = sqlite3.connect(web_data)
    try:
        rows = {k: (rid, url, name, prepop)
                for rid, k, url, name, prepop in db.execute(
                    "SELECT id, keyword, url, short_name, prepopulate_id FROM keywords")}
        now = chromium_now()
        changed = False
        for nickname, name, url in SEARCH_ENGINES:
            url = url.replace("%s", "{searchTerms}")  # Chromium's stored template format
            have = rows.get(nickname)
            if have is None:
                print(f"+ search {nickname:4} {name} -> {url}")
                if not dry_run:
                    db.execute(
                        "INSERT INTO keywords (short_name, keyword, favicon_url, url,"
                        " safe_for_autoreplace, originating_url, date_created, usage_count,"
                        " input_encodings, suggest_url, prepopulate_id, created_by_policy,"
                        " last_modified, sync_guid, alternate_urls, last_visited,"
                        " created_from_play_api, is_active, starter_pack_id,"
                        " enforced_by_policy, featured_by_policy)"
                        " VALUES (?, ?, '', ?, 0, '', ?, 0, '', '', 0, 0, ?, ?, '[]', 0, 0, 1, 0, 0, 0)",
                        (name, nickname, url, now, now, str(uuid.uuid4())))
                changed = True
            elif have[3]:
                print(f"! search {nickname:4} is a built-in Vivaldi engine ({have[2]}) - left alone")
            elif (have[1], have[2]) != (url, name):
                print(f"~ search {nickname:4} {name} -> {url} (updated)")
                if not dry_run:
                    db.execute("UPDATE keywords SET url=?, short_name=?, last_modified=? WHERE id=?",
                               (url, name, now, have[0]))
                changed = True
        if changed and not dry_run:
            db.commit()
        return changed
    finally:
        db.close()


def set_pref(prefs: dict, dotted: str, value) -> bool:
    node = prefs
    *parents, leaf = dotted.split(".")
    for key in parents:
        node = node.setdefault(key, {})
    if node.get(leaf) == value:
        return False
    node[leaf] = value
    return True


def vivaldi_running() -> bool:
    return subprocess.run(["pgrep", "-x", "Vivaldi"], capture_output=True).returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="show changes, write nothing")
    ap.add_argument("--prefs", default=DEFAULT_PREFS)
    args = ap.parse_args()

    if not args.dry_run and args.prefs == DEFAULT_PREFS and vivaldi_running():
        print("Vivaldi is running - quit it (Cmd-Q) first, or it will overwrite these changes.")
        return 1

    with open(args.prefs, encoding="utf-8") as f:
        prefs = json.load(f)
    ws_prefs = prefs.setdefault("vivaldi", {}).setdefault("workspaces", {})
    workspaces = ws_prefs.setdefault("list", [])
    routes = ws_prefs.setdefault("link_routes", [])

    changed = False
    emoji_for = dict(WORKSPACES)
    for old, new in RENAMES.items():
        old_ws = next((w for w in workspaces if w.get("name") == old), None)
        if old_ws and not any(w.get("name") == new for w in workspaces):
            old_ws["name"] = new
            if new in emoji_for:
                old_ws["emoji"] = emoji_for[new]
            changed = True
            print(f"~ rename workspace {old} -> {emoji_for.get(new, '')} {new} (id {old_ws['id']} kept)")
    by_name = {w.get("name"): w for w in workspaces}
    next_id = int(time.time() * 1000)  # Vivaldi uses Date.now() for new workspace ids
    used_ids = {w.get("id") for w in workspaces}
    for name, emoji in WORKSPACES:
        if name in by_name:
            continue
        while next_id in used_ids:
            next_id += 1
        ws = {"id": next_id, "name": name, "emoji": emoji}
        workspaces.append(ws)
        by_name[name] = ws
        used_ids.add(next_id)
        changed = True
        print(f"+ workspace {emoji} {name} (id {next_id})")

    for rtype, expr, name in RULES:
        wid = by_name[name]["id"]
        same = [r for r in routes if (r.get("type"), r.get("expression")) == (rtype, expr)]
        if same:
            # One rule per pattern: keep the copy already aimed at the table's target
            # (else retarget the first, keeping its id) and drop any other copies.
            keep = next((r for r in same if r.get("workspaceId") == wid), same[0])
            if keep.get("workspaceId") != wid:
                keep["workspaceId"] = wid
                changed = True
                print(f"~ rule  URL {rtype.lower():10} {expr:38} -> {name} (moved)")
            for extra in (r for r in same if r is not keep):
                routes.remove(extra)
                changed = True
                print(f"- rule  URL {rtype.lower():10} {expr:38} (duplicate removed)")
            continue
        routes.append({"id": str(uuid.uuid4()), "type": rtype, "expression": expr, "workspaceId": wid})
        changed = True
        print(f"+ rule  URL {rtype.lower():10} {expr:38} -> {name}")

    if ws_prefs.get("enabled") is not True:
        ws_prefs["enabled"] = True
        changed = True

    for key, value in SETTINGS.items():
        if set_pref(prefs, key, value):
            changed = True
            print(f"~ set   {key} = {json.dumps(value)}")

    web_data = os.path.join(os.path.dirname(args.prefs), WEB_DATA)
    search_changed = False
    if os.path.exists(web_data):
        if not args.dry_run:
            backup_wd = f"{web_data}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
            shutil.copy2(web_data, backup_wd)
        search_changed = apply_search_engines(web_data, args.dry_run)
        if not args.dry_run:
            if search_changed:
                print(f"Search engines updated. Backup: {backup_wd}")
            else:
                os.remove(backup_wd)

    if not changed:
        state = "Search engines written; prefs" if search_changed and not args.dry_run else "Already up to date"
        print(f"{state}: {len(workspaces)} workspaces, {len(routes)} rules - prefs unchanged")
        return 0
    if args.dry_run:
        print(f"(dry run) {len(workspaces)} workspaces, {len(routes)} rules - nothing written")
        return 0

    backup = f"{args.prefs}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(args.prefs, backup)
    tmp = args.prefs + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(prefs, f, ensure_ascii=False, separators=(",", ":"))
    os.chmod(tmp, os.stat(args.prefs).st_mode & 0o777)
    os.replace(tmp, args.prefs)
    print(f"Wrote {len(workspaces)} workspaces, {len(routes)} rules. Backup: {backup}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
