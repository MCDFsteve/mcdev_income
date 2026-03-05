#!/usr/bin/env python3
import argparse
import json
import re
from datetime import datetime
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

SENSITIVE_KEY_RE = re.compile(
    r"(token|secret|password|passwd|cookie|session|auth|sid|uid|email|phone|mobile)",
    re.IGNORECASE,
)


def _limit_text(text, limit=1000):
    if text is None:
        return None
    if len(text) <= limit:
        return text
    return text[:limit] + "...(truncated)"


def _redact(obj):
    if isinstance(obj, dict):
        redacted = {}
        for key, value in obj.items():
            if SENSITIVE_KEY_RE.search(str(key)):
                redacted[key] = "***"
            else:
                redacted[key] = _redact(value)
        return redacted
    if isinstance(obj, list):
        return [_redact(item) for item in obj[:50]]
    if isinstance(obj, str):
        return _limit_text(obj, 300)
    return obj


def _try_parse_json(text):
    if text is None:
        return None
    stripped = text.strip()
    if not stripped:
        return None
    if not (stripped.startswith("{") or stripped.startswith("[")):
        return None
    try:
        return json.loads(stripped)
    except Exception:
        return None


def _top_keys(obj):
    keys = set()
    if isinstance(obj, dict):
        keys.update(obj.keys())
    elif isinstance(obj, list):
        for item in obj[:50]:
            if isinstance(item, dict):
                keys.update(item.keys())
    return keys


def _safe_sample(obj):
    if obj is None:
        return None
    return _redact(obj)


def parse_har(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    entries = data.get("log", {}).get("entries", [])
    endpoints = {}

    for entry in entries:
        req = entry.get("request", {})
        method = req.get("method")
        url = req.get("url")
        if not method or not url:
            continue

        parsed = urlsplit(url)
        base_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
        key = f"{method} {base_url}"

        endpoint = endpoints.setdefault(
            key,
            {
                "method": method,
                "url": base_url,
                "query_params": set(),
                "headers": set(),
                "request_mime_types": set(),
                "request_json_keys": set(),
                "response_mime_types": set(),
                "response_json_keys": set(),
                "sample_request": None,
                "sample_response": None,
            },
        )

        for h in req.get("headers", []):
            name = h.get("name")
            if name:
                endpoint["headers"].add(name)

        for q in req.get("queryString", []):
            name = q.get("name")
            if name:
                endpoint["query_params"].add(name)

        if parsed.query:
            for name in parse_qs(parsed.query, keep_blank_values=True).keys():
                endpoint["query_params"].add(name)

        post = req.get("postData", {})
        mime = post.get("mimeType")
        if mime:
            endpoint["request_mime_types"].add(mime)

        post_text = post.get("text")
        if post_text and endpoint["sample_request"] is None:
            parsed_json = _try_parse_json(post_text)
            if parsed_json is not None:
                endpoint["request_json_keys"].update(_top_keys(parsed_json))
                endpoint["sample_request"] = _safe_sample(parsed_json)
            else:
                endpoint["sample_request"] = _limit_text(post_text, 600)

        resp = entry.get("response", {})
        content = resp.get("content", {})
        resp_mime = content.get("mimeType")
        if resp_mime:
            endpoint["response_mime_types"].add(resp_mime)

        resp_text = content.get("text")
        encoding = content.get("encoding")
        if resp_text and encoding == "base64":
            resp_text = None
        if resp_text and endpoint["sample_response"] is None:
            parsed_json = _try_parse_json(resp_text)
            if parsed_json is not None:
                endpoint["response_json_keys"].update(_top_keys(parsed_json))
                endpoint["sample_response"] = _safe_sample(parsed_json)
            else:
                endpoint["sample_response"] = _limit_text(resp_text, 600)

    return endpoints


def _normalize(endpoints):
    normalized = []
    for key in sorted(endpoints.keys()):
        e = endpoints[key]
        normalized.append(
            {
                "method": e["method"],
                "url": e["url"],
                "query_params": sorted(e["query_params"]),
                "headers": sorted(e["headers"]),
                "request_mime_types": sorted(e["request_mime_types"]),
                "request_json_keys": sorted(e["request_json_keys"]),
                "response_mime_types": sorted(e["response_mime_types"]),
                "response_json_keys": sorted(e["response_json_keys"]),
                "sample_request": e["sample_request"],
                "sample_response": e["sample_response"],
            }
        )
    return normalized


def write_json(endpoints, path):
    normalized = _normalize(endpoints)
    Path(path).write_text(json.dumps(normalized, ensure_ascii=True, indent=2), encoding="utf-8")


def _format_keys(keys):
    return ", ".join(keys) if keys else "无"


def write_markdown(endpoints, path):
    normalized = _normalize(endpoints)
    lines = []
    lines.append("# MC开发者平台接口汇总")
    lines.append("")
    lines.append("生成时间: " + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("")
    lines.append("说明:")
    lines.append("- 由 HAR 自动提取，敏感字段已脱敏。")
    lines.append("- 建议先用浏览器抓包导出 HAR，再运行脚本生成此文档。")
    lines.append("")
    lines.append("生成命令示例:")
    lines.append(
        "- `python3 tools/har_extract.py --har tools/har/session.har --out docs/api.md --json docs/api_endpoints.json`"
    )
    lines.append("")

    for e in normalized:
        method = e["method"]
        url = e["url"]
        lines.append(f"## {method} {url}")
        lines.append("")
        lines.append(f"- 查询参数: {_format_keys(e['query_params'])}")
        lines.append(f"- 请求头(字段): {_format_keys(e['headers'])}")
        lines.append(f"- 请求体类型: {_format_keys(e['request_mime_types'])}")
        lines.append(f"- 请求体JSON字段: {_format_keys(e['request_json_keys'])}")
        lines.append(f"- 响应类型: {_format_keys(e['response_mime_types'])}")
        lines.append(f"- 响应JSON字段: {_format_keys(e['response_json_keys'])}")

        sample_request = e.get("sample_request")
        if isinstance(sample_request, dict):
            sample_payload = json.dumps(sample_request, ensure_ascii=True)
        elif isinstance(sample_request, str):
            sample_payload = sample_request
        else:
            sample_payload = ""

        if sample_payload:
            lines.append("- 示例请求体(已脱敏):")
            lines.append("```")
            lines.append(sample_payload)
            lines.append("```")

        lines.append("- 示例curl:")
        lines.append("```")
        lines.append(f"curl -sS -X {method} '{url}' \\")
        lines.append("  -H 'Cookie: ${MCDEV_COOKIE}' \\")
        if e["request_mime_types"]:
            lines.append("  -H 'Content-Type: application/json' \\")
        if sample_payload:
            lines.append(f"  -d '{sample_payload}'")
        lines.append("```")
        lines.append("")

    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Extract API endpoints from a HAR file.")
    parser.add_argument("--har", required=True, help="Path to HAR file")
    parser.add_argument("--out", default="docs/api.md", help="Markdown output path")
    parser.add_argument("--json", default="docs/api_endpoints.json", help="JSON output path")
    args = parser.parse_args()

    endpoints = parse_har(args.har)
    write_json(endpoints, args.json)
    write_markdown(endpoints, args.out)


if __name__ == "__main__":
    main()
