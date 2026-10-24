#!/usr/bin/env python3
"""Catalog link checker for XToolBox.

Checks every checkable URL in ``assets/asset_list.json`` — install-method
download/web links and entry homepages — and reports which ones are dead,
moved, blocked by anti-bot measures, or erroring. Distro ISO entries whose
URLs still contain ``%TOKEN%`` placeholders are skipped: the app resolves
those templates against each distro's own site at runtime and
existence-checks the candidates itself (see DistroResolver), so the raw
template is not a real URL.

Usage:
    python3 tool/check_catalog_links.py [--catalog PATH] [--output FILE]
                                        [--timeout SECONDS] [--workers N]

Exit code is 1 when at least one URL is classified dead (a definitive
404/410 or an unresolvable host), otherwise 0 — so CI can fail, or open
an issue, on real rot without crying wolf over anti-bot blocks or
transient server errors.

Only the Python standard library is used; Python 3.9+ is enough.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from urllib.parse import urlparse

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/130.0.0.0 Safari/537.36 XToolBoxLinkCheck/1.0"
)

# Hosts that serve release assets through signed, short-lived redirect
# targets. A redirect landing there is normal delivery, not a move.
CDN_HOST_SUFFIXES = (".githubusercontent.com",)
SIGNED_QUERY_MARKERS = ("x-amz-signature", "sig=", "token=", "expires=")


@dataclass
class Entry:
    """One catalog reference to a URL."""

    asset: str
    role: str  # "download" for install-method URLs, "homepage" otherwise
    label: str
    url: str


@dataclass
class Result:
    entry: Entry
    status: str  # ok | moved | blocked | dead | error | skipped
    detail: str
    final_url: str = ""


@dataclass
class Chain:
    """The outcome of following one URL."""

    code: int | None = None
    final_url: str = ""
    permanent_redirect: bool = False
    error: str = ""


class _RecordingRedirectHandler(urllib.request.HTTPRedirectHandler):
    def __init__(self) -> None:
        self.permanent = False

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: N802
        if code in (301, 308):
            self.permanent = True
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _fetch(url: str, method: str, timeout: float) -> Chain:
    handler = _RecordingRedirectHandler()
    opener = urllib.request.build_opener(handler)
    headers = {"User-Agent": USER_AGENT}
    if method == "GET":
        headers["Range"] = "bytes=0-0"
    req = urllib.request.Request(url, headers=headers, method=method)
    try:
        with opener.open(req, timeout=timeout) as resp:
            return Chain(
                code=resp.status,
                final_url=resp.geturl(),
                permanent_redirect=handler.permanent,
            )
    except urllib.error.HTTPError as e:
        return Chain(
            code=e.code,
            final_url=e.geturl() or url,
            permanent_redirect=handler.permanent,
        )
    except urllib.error.URLError as e:
        reason = e.reason
        if isinstance(reason, socket.gaierror):
            return Chain(error="dns")
        return Chain(error=f"{type(reason).__name__}: {reason}")
    except (TimeoutError, socket.timeout):
        return Chain(error="timeout")
    except Exception as e:  # a checker must report, never crash, on a bad URL
        return Chain(error=f"{type(e).__name__}: {e}")


def _same_target(original: str, final: str) -> bool:
    """True when *final* is the same document as *original*.

    Ignores the query string, a trailing slash, and an http->https
    upgrade, none of which mean the catalog entry has moved.
    """
    a, b = urlparse(original), urlparse(final)
    return (
        a.hostname == b.hostname
        and a.path.rstrip("/") == b.path.rstrip("/")
    )


def _is_cdn_delivery(final: str) -> bool:
    parsed = urlparse(final)
    host = parsed.hostname or ""
    if any(host.endswith(suffix) for suffix in CDN_HOST_SUFFIXES):
        return True
    query = parsed.query.lower()
    return any(marker in query for marker in SIGNED_QUERY_MARKERS)


def classify(entry: Entry, timeout: float) -> Result:
    """Check one entry, retrying once on transient-looking failures."""
    if "%" in entry.url:
        return Result(entry, "skipped", "runtime-resolved template URL")
    chain = _fetch(entry.url, "HEAD", timeout)
    # Many hosts refuse HEAD or gate it behind anti-bot rules while
    # serving GET happily; always confirm a non-200 HEAD with a GET.
    if chain.code is None or chain.code not in (200, 404, 410):
        get = _fetch(entry.url, "GET", timeout)
        if get.code is not None:
            chain = get
    if chain.code is None and chain.error not in ("dns",):
        retry = _fetch(entry.url, "GET", timeout)
        if retry.code is not None or retry.error == "dns":
            chain = retry

    if chain.error == "dns":
        return Result(entry, "dead", "host does not resolve")
    if chain.code is None:
        return Result(entry, "error", f"no response ({chain.error or 'unknown'})")
    if chain.code in (404, 410):
        return Result(entry, "dead", f"HTTP {chain.code}")
    if 200 <= chain.code < 300:
        if chain.final_url and not _same_target(entry.url, chain.final_url):
            if chain.permanent_redirect and not _is_cdn_delivery(chain.final_url):
                return Result(
                    entry, "moved", "permanent redirect", chain.final_url
                )
        return Result(entry, "ok", f"HTTP {chain.code}", chain.final_url)
    if chain.code in (401, 403, 405, 429):
        return Result(
            entry,
            "blocked",
            f"HTTP {chain.code} (anti-bot or method block; "
            "verify from a residential connection)",
        )
    if chain.code >= 500:
        return Result(entry, "error", f"HTTP {chain.code} (server error)")
    return Result(entry, "error", f"HTTP {chain.code}")


def collect_entries(catalog: list) -> list[Entry]:
    entries: list[Entry] = []
    for asset in catalog:
        name = asset.get("name") or asset.get("id") or "?"
        homepage = asset.get("homepage")
        if isinstance(homepage, str) and homepage.startswith("http"):
            entries.append(Entry(name, "homepage", "Homepage", homepage))
        for method in asset.get("install_methods", []):
            url = method.get("url")
            if isinstance(url, str) and url.startswith("http"):
                label = method.get("label") or method.get("type") or "Download"
                entries.append(Entry(name, "download", label, url))
    return entries


def run(catalog_path: str, timeout: float, workers: int) -> list[Result]:
    with open(catalog_path, encoding="utf-8") as f:
        catalog = json.load(f)
    entries = collect_entries(catalog)
    # Check each distinct URL once; entries sharing a URL share a result.
    unique: dict[str, Entry] = {}
    for e in entries:
        unique.setdefault(e.url, e)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        checked = {
            url: result
            for url, result in zip(
                unique.keys(), pool.map(lambda e: classify(e, timeout), unique.values())
            )
        }
    results: list[Result] = []
    for e in entries:
        base = checked[e.url]
        results.append(Result(e, base.status, base.detail, base.final_url))
    return results


def render_report(results: list[Result]) -> str:
    by_status: dict[str, list[Result]] = {}
    for r in results:
        by_status.setdefault(r.status, []).append(r)
    order = ["dead", "error", "blocked", "moved", "ok", "skipped"]
    lines = ["# Catalog link check", ""]
    lines.append(
        "Checked {} references: ".format(len(results))
        + ", ".join(
            f"{len(by_status.get(s, []))} {s}" for s in order if by_status.get(s)
        )
        + "."
    )
    titles = {
        "dead": "Dead — fix or remove these entries",
        "error": "Errors — transient or server-side; re-check before acting",
        "blocked": "Blocked — anti-bot/method blocks; verify manually",
        "moved": "Moved — permanent redirects worth updating in the catalog",
        "ok": "OK",
        "skipped": "Skipped — resolved by the app at runtime",
    }
    for status in order:
        group = by_status.get(status)
        if not group:
            continue
        lines += ["", f"## {titles[status]} ({len(group)})", ""]
        for r in sorted(group, key=lambda r: (r.entry.asset, r.entry.url)):
            line = (
                f"- **{r.entry.asset}** ({r.entry.role}, {r.entry.label}) — "
                f"{r.entry.url} → {r.detail}"
            )
            if r.final_url and status == "moved":
                line += f" → {r.final_url}"
            lines.append(line)
    lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--catalog", default="assets/asset_list.json")
    parser.add_argument("--output", help="also write the report to this file")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--workers", type=int, default=16)
    args = parser.parse_args(argv)

    results = run(args.catalog, args.timeout, args.workers)
    report = render_report(results)
    print(report)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(report)
    dead = [r for r in results if r.status == "dead"]
    return 1 if dead else 0


if __name__ == "__main__":
    sys.exit(main())
