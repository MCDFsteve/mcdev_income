#!/usr/bin/env python3
import argparse
from pathlib import Path

from playwright.sync_api import sync_playwright


def main():
    parser = argparse.ArgumentParser(
        description="Open a real browser for manual login and capture a HAR file."
    )
    parser.add_argument(
        "--url",
        default="https://mcdev.webapp.163.com/",
        help="Target site url",
    )
    parser.add_argument(
        "--out",
        default="tools/har/session.har",
        help="Output HAR path",
    )
    parser.add_argument(
        "--channel",
        default="chrome",
        help="Browser channel to launch (default: chrome). Use empty string to use Playwright bundled browser.",
    )
    args = parser.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print("即将打开浏览器，请在浏览器里手动登录并执行收益相关操作。")
    print("操作完成后，回到终端按回车结束并保存 HAR。")

    with sync_playwright() as p:
        launch_kwargs = {"headless": False}
        if args.channel:
            launch_kwargs["channel"] = args.channel
        browser = p.chromium.launch(**launch_kwargs)
        context = browser.new_context(record_har_path=str(out_path))
        page = context.new_page()
        page.goto(args.url, wait_until="domcontentloaded")
        try:
            input()
        except KeyboardInterrupt:
            pass
        context.close()
        browser.close()

    print(f"HAR 已保存: {out_path}")


if __name__ == "__main__":
    main()
