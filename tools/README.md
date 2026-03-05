# 工具说明

本目录用于抓取与整理 MC 开发者平台接口。

## 1. 导出 HAR
- 方式 A：浏览器手动导出
  - 在浏览器打开 `https://mcdev.webapp.163.com/` 并登录。
  - 打开开发者工具 -> Network，勾选 Preserve log。
  - 执行你常用的收益查询、列表、筛选等操作。
  - 右键保存网络记录为 HAR 文件。
  - 将 HAR 放到 `tools/har/session.har`（目录已在 .gitignore 中，不要提交）。

- 方式 B：终端启动浏览器并自动保存 HAR
  ```
  python3 -m pip install -r tools/requirements.txt
  python3 tools/capture_har.py --url https://mcdev.webapp.163.com/ --out tools/har/session.har
  ```
  说明：默认使用系统已安装的 Google Chrome（channel=chrome）。会打开真实浏览器，你在浏览器里手动登录并操作，完成后回到终端按回车保存 HAR。
  如果你的系统没有 Chrome，可先安装 Chrome，或改用 Playwright 自带浏览器：
  ```
  python3 -m playwright install chromium
  python3 tools/capture_har.py --channel '' --url https://mcdev.webapp.163.com/ --out tools/har/session.har
  ```

## 2. 生成接口文档
```
python3 tools/har_extract.py --har tools/har/session.har --out docs/api.md --json docs/api_endpoints.json
```

## 3. 使用 curl 验证接口（可选）
后续会根据 `docs/api_endpoints.json` 自动生成/执行 curl 命令。为了避免泄露，请通过环境变量提供 Cookie：
```
export MCDEV_COOKIE='你的登录Cookie'
```

执行（默认只跑 GET/HEAD）：
```
python3 tools/curl_fetch.py --endpoints docs/api_endpoints.json --out tools/output
```

如需包含 POST/PUT/PATCH/DELETE（可能会产生副作用）：
```
python3 tools/curl_fetch.py --include-non-idempotent
```

说明：脚本会对敏感字段做脱敏处理。
