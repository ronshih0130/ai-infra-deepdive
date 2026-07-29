#!/usr/bin/env python3
"""Archive backfill + index regeneration for the public ai-infra-deepdive site.

Invoked only by `publish.sh --index-refresh`, which supplies the same
one-time current-task confirmation the single-slug publisher requires.

What it does, in order:

  1. Copies every dated report from the Obsidian vault's "04 Reports/" into
     archive/, skipping anything matched by .publishignore. Nothing is ever
     silently dropped: a skip is printed with the pattern that caused it.
  2. Regenerates archive/index.html from whatever is actually in archive/,
     newest first, taking each row's title from the file's own <title>.
  3. Regenerates the ROTATION-ROWS block in index.html from index-rows.tsv.
     The date stamp is NOT taken from the TSV — it is resolved by hashing the
     live slug and finding the archive file with the same content, so the
     landing page can never claim a date the published file doesn't have.

The script never touches git; publish.sh owns staging, commit and push.
"""

from __future__ import annotations

import fnmatch
import hashlib
import html
import os
import re
import shutil
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent
ARCHIVE = SITE / "archive"
VAULT = Path.home() / "Documents" / "My Obsidian" / "04 Reports"

DATE_RE = re.compile(r"(20\d{2}-\d{2}-\d{2})")
TITLE_RE = re.compile(r"<title[^>]*>(.*?)</title>", re.I | re.S)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_publishignore() -> list[str]:
    pats: list[str] = []
    pi = SITE / ".publishignore"
    if not pi.exists():
        return pats
    for line in pi.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            pats.append(line)
    return pats


def ignored(name: str, patterns: list[str]) -> str | None:
    for pat in patterns:
        if fnmatch.fnmatch(name, pat):
            return pat
    return None


def title_of(path: Path) -> str:
    m = TITLE_RE.search(path.read_text(errors="replace")[:20000])
    if not m:
        return path.stem.replace("_", " ")
    # Collapse whitespace and unescape once; we re-escape on output.
    return html.unescape(" ".join(m.group(1).split()))


def date_of(name: str) -> str:
    m = DATE_RE.search(name)
    return m.group(1) if m else "0000-00-00"


# ---------------------------------------------------------------- step 1


def backfill_archive() -> tuple[int, int]:
    patterns = load_publishignore()
    ARCHIVE.mkdir(exist_ok=True)
    added = skipped = 0
    if not VAULT.is_dir():
        print(f"WARNING: vault reports dir not found: {VAULT}", file=sys.stderr)
        return 0, 0
    for src in sorted(VAULT.glob("*.html")):
        pat = ignored(src.name, patterns)
        if pat:
            print(f"  skip  {src.name}  (.publishignore: {pat})")
            skipped += 1
            continue
        if not DATE_RE.search(src.name):
            print(f"  skip  {src.name}  (undated — archive holds dated reports only)")
            skipped += 1
            continue
        dest = ARCHIVE / src.name
        if dest.exists() and sha256(dest) == sha256(src):
            continue
        shutil.copy2(src, dest)
        print(f"  add   {src.name}")
        added += 1
    return added, skipped


# ---------------------------------------------------------------- step 2

ARCHIVE_HEAD = """<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"/>\
<meta name="viewport" content="width=device-width,initial-scale=1"/>\
<title>AI-Infra Deep-Dive — Full Report Archive</title><style>\
:root{--bg:#0e1116;--line:#2a323d;--ink:#e6edf3;--muted:#9aa7b4;--faint:#8692a0;--accent2:#3fb6a8;\
--mono:ui-monospace,Menlo,Consolas,monospace;\
--sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}\
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);line-height:1.5}\
.wrap{max-width:1040px;margin:0 auto;padding:30px 28px 70px}a{color:var(--accent2);text-decoration:none}\
h1{font-size:26px;margin:0 0 4px}.sub{color:var(--muted);max-width:74ch}\
.eyebrow{font-family:var(--mono);font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--faint)}\
.row{display:grid;grid-template-columns:104px 1fr;gap:2px 16px;padding:11px 12px;border-bottom:1px solid var(--line);align-items:baseline}\
.row:hover{background:#11161d}.d{font-family:var(--mono);font-size:12px;color:var(--faint)}\
.t{font-size:14px;color:var(--ink)}.f{grid-column:2;font-family:var(--mono);font-size:10.5px;color:var(--faint)}\
</style></head><body><nav style="background:#0e1117;border-bottom:1px solid #2a3040;padding:10px 22px;font-size:12px;\
display:flex;gap:16px;align-items:center;position:sticky;top:0">\
<a href="../index.html" style="color:#2dd4bf;font-weight:700">&larr; AI-Infra Deep-Dive</a>\
<span style="color:#5a6377;margin-left:auto">Full archive · personal research, not investment advice</span></nav>\
<div class="wrap"><div class="eyebrow">Complete archive · auto-generated every publish</div>\
<h1>Full Report Archive</h1><p class="sub">Every dated report ever produced — rotation layers, the weekly \
engines, and one-off teardowns — newest first. The curated landing page shows the latest of each family; \
this is the complete history.</p><div style="margin-top:22px">"""

ARCHIVE_FOOT = """</div><p class="sub" style="font-size:12px;margin-top:26px;color:var(--faint)">\
{count} reports · personal research for a private knowledge base, not investment advice. Figures are \
point-in-time and decay quickly; a dated report is a snapshot of what was known that day, never a live view.\
</p></div></body></html>"""


def build_archive_index() -> int:
    files = [p for p in ARCHIVE.glob("*.html") if p.name != "index.html"]
    files.sort(key=lambda p: (date_of(p.name), p.name), reverse=True)
    rows = []
    for p in files:
        rows.append(
            '    <a class="row" href="{f}"><span class="d">{d}</span>'
            '<span class="t">{t}</span><span class="f">{f}</span></a>'.format(
                f=html.escape(p.name), d=date_of(p.name), t=html.escape(title_of(p))
            )
        )
    (ARCHIVE / "index.html").write_text(
        ARCHIVE_HEAD + "\n".join(rows) + ARCHIVE_FOOT.format(count=len(files))
    )
    return len(files)


# ---------------------------------------------------------------- step 3

ROW_TMPL = """      <tr>
        <td class="mono">{num}</td><td>{layer}</td>
        <td><span class="pill done">Done · {date}</span></td>
        <td>{chokepoint}</td>
        <td class="sev">{tightness}/20</td>
        <td><a href="{slug}">Open ↗</a> <span class="mono" style="font-size:10px;color:var(--faint)">v5</span></td>
      </tr>"""

START = "<!-- ROTATION-ROWS:START"
END = "<!-- ROTATION-ROWS:END -->"


def slug_date(slug: str, by_hash: dict[str, str], fallback_glob: str) -> str:
    """Date of the report currently living at `slug`, proven by content hash."""
    live = SITE / slug
    if live.exists():
        name = by_hash.get(sha256(live))
        if name:
            return date_of(name)
    # The live slug isn't byte-identical to anything archived (hand-patched, or
    # published before the archive was maintained). Fall back to the newest
    # archived report for this layer, and say so.
    cands = sorted(
        (p.name for p in ARCHIVE.glob("*.html") if fnmatch.fnmatch(p.name, fallback_glob)),
        key=date_of,
        reverse=True,
    )
    if cands:
        print(f"  NOTE  {slug}: no exact archive match; dating from {cands[0]}")
        return date_of(cands[0])
    print(f"  WARN  {slug}: no archive match and no glob match ({fallback_glob})")
    return "unknown"


def build_landing_rows() -> int:
    by_hash = {
        sha256(p): p.name for p in ARCHIVE.glob("*.html") if p.name != "index.html"
    }
    rows = []
    tsv = (SITE / "index-rows.tsv").read_text().splitlines()
    for line in tsv:
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 6:
            print(f"  WARN  malformed index-rows.tsv line: {line[:60]}", file=sys.stderr)
            continue
        num, layer, slug, glob_pat, chokepoint, tightness = parts[:6]
        rows.append(
            ROW_TMPL.format(
                num=num,
                layer=layer,
                date=slug_date(slug, by_hash, glob_pat),
                chokepoint=chokepoint,
                tightness=tightness,
                slug=slug,
            )
        )
    idx = SITE / "index.html"
    text = idx.read_text()
    s = text.index(START)
    s = text.index("-->", s) + 3
    e = text.index(END)
    idx.write_text(text[:s] + "\n" + "\n".join(rows) + "\n    " + text[e:])
    return len(rows)


def main() -> int:
    print("archive backfill:")
    added, skipped = backfill_archive()
    print(f"  -> {added} added, {skipped} skipped")
    print("archive index:")
    n = build_archive_index()
    print(f"  -> {n} rows")
    print("landing rotation rows:")
    r = build_landing_rows()
    print(f"  -> {r} rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
