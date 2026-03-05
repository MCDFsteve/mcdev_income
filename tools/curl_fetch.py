#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path
from urllib.parse import urlsplit


def _safe_name(method, url):
    parsed = urlsplit(url)
    raw = f"{parsed.netloc}{parsed.path}"
    raw = raw.strip("/").replace("/", "_")
    if not raw:
        raw = "root"
    name = f"{method.lower()}_{raw}"
    if len(name) > 120:
        digest = hashlib.sha1(name.encode("utf-8")).hexdigest()[:10]
        name = f"{name[:80]}_{digest}"
    return name


def _payload_for(entry):
    payload = entry.get("sample_request")
    if payload is None:
        return None
    if isinstance(payload, dict):
        return json.dumps(payload, ensure_ascii=True)
    if isinstance(payload, str):
        return payload
    return None


def main():
    parser = argparse.ArgumentParser(description="Fetch endpoints via curl using a session cookie.")
    parser.add_argument("--endpoints", default="docs/api_endpoints.json", help="Endpoints JSON path")
    parser.add_argument("--out", default="tools/output", help="Output directory")
    parser.add_argument(
        "--include-non-idempotent",
        action="store_true",
        help="Include POST/PUT/PATCH/DELETE (default: only GET/HEAD)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print commands without executing")
    args = parser.parse_args()

    cookie = os.environ.get("MCDEV_COOKIE")
    if not cookie:
        raise SystemExit("MCDEV_COOKIE is not set")

    endpoints = json.loads(Path(args.endpoints).read_text(encoding="utf-8"))
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    meta = []
    for entry in endpoints:
        method = (entry.get("method") or "").upper()
        url = entry.get("url") or ""
        if not method or not url:
            continue

        if not args.include_non_idempotent and method not in {"GET", "HEAD"}:
            continue

        payload = _payload_for(entry)
        name = _safe_name(method, url)
        out_file = out_dir / f"{name}.json"

        cmd = [
            "curl",
            "-sS",
            "-X",
            method,
            url,
            "-H",
            f"Cookie: {cookie}",
            "-o",
            str(out_file),
            "-w",
            "%{http_code}",
        ]
        if payload and method not in {"GET", "HEAD"}:
            cmd += ["-H", "Content-Type: application/json", "-d", payload]

        if args.dry_run:
            print(" ".join(["curl", "-sS", "-X", method, url, "-H", "Cookie: ${MCDEV_COOKIE}", "..."]))
            continue

        result = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
        )
        meta.append(
            {
                "method": method,
                "url": url,
                "output": str(out_file),
                "http_status": result.stdout.strip(),
                "return_code": result.returncode,
                "stderr": result.stderr[-500:],
            }
        )

    meta_path = out_dir / "meta.json"
    meta_path.write_text(json.dumps(meta, ensure_ascii=True, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
