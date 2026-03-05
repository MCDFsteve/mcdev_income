# MC开发者平台接口汇总

生成时间: 2026-03-05 15:26:58

说明:
- 由 HAR 自动提取，敏感字段已脱敏。
- 建议先用浏览器抓包导出 HAR，再运行脚本生成此文档。

生成命令示例:
- `python3 tools/har_extract.py --har tools/har/session.har --out docs/api.md --json docs/api_endpoints.json`

## GET blob://https://dl.reg.163.com/13ab3256-e0d4-465e-8f3c-36888d67e385

- 查询参数: 无
- 请求头(字段): Accept
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: 无
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'blob://https://dl.reg.163.com/13ab3256-e0d4-465e-8f3c-36888d67e385' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET blob://https://dl.reg.163.com/5f486e44-eff3-4c3c-a5f5-8737e5d449bc

- 查询参数: 无
- 请求头(字段): Accept
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: 无
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'blob://https://dl.reg.163.com/5f486e44-eff3-4c3c-a5f5-8737e5d449bc' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://cstaticdun.126.net/load.min.js

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://cstaticdun.126.net/load.min.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://dl.reg.163.com/UA1435545636633/__utm.gif

- 查询参数: api, config, configlog, from, name, rt, sp, st, timeout, ua, ursfp, utid
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Cookie, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/gif
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://dl.reg.163.com/UA1435545636633/__utm.gif' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://dl.reg.163.com/webzj/v1.0.1/pub/index_dl2_new.html

- 查询参数: MGID, cd, cf, pkid, product, wdaId
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Cookie, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-User, Upgrade-Insecure-Requests, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/html
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://dl.reg.163.com/webzj/v1.0.1/pub/index_dl2_new.html' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://fl.reg.163.com/urs/__utm.gif

- 查询参数: di, rtid, src, time, utid
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Cookie, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/gif
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://fl.reg.163.com/urs/__utm.gif' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://g79.preview-notice.nie.netease.com/game_notice/g79_mc_platform_admin_notices

- 查询参数: 无
- 请求头(字段): Accept, Referer, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: x-unknown
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://g79.preview-notice.nie.netease.com/game_notice/g79_mc_platform_admin_notices' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mam.netease.com/beacons

- 查询参数: data, t
- 请求头(字段): Referer, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: x-unknown
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mam.netease.com/beacons' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com//items/global_developer_configs

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, Accept, Referer, User-Agent, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/html; charset=utf-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com//items/global_developer_configs' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/data_analysis/is_show/

- 查询参数: setting
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/data_analysis/is_show/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/data_analysis/overview/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/data_analysis/overview/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/items/categories/pe/

- 查询参数: is_third_party, span, start
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/items/categories/pe/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/items/categories/pe/4685706883556129523/incomes/

- 查询参数: begin_time, end_time
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/items/categories/pe/4685706883556129523/incomes/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/items/global_developer_configs/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/items/global_developer_configs/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/items/java_permit/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/items/java_permit/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/items/mc_consts/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/items/mc_consts/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/mailbox/unread/count

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/mailbox/unread/count' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/new_issue/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/new_issue/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/new_issue/show_new_version/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/new_issue/show_new_version/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/new_level/settings/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/new_level/settings/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/others/load-image-config

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/others/load-image-config' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/others/red-spots

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/others/red-spots' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/setting/common/

- 查询参数: name
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/setting/common/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/square/content/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/square/content/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/square/news/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/square/news/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/square/us_rank_list/

- 查询参数: first_type, span, start, type
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/square/us_rank_list/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/users/agreement

- 查询参数: type
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/users/agreement' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/users/me

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: msg, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/users/me' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-user, upgrade-insecure-requests, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/html
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/WebUIApp/css/mc-components.min.css

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/css
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/WebUIApp/css/mc-components.min.css' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/WebUIApp/css/webUIApp.min.css

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/css
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/WebUIApp/css/webUIApp.min.css' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/WebUIApp/js/mc-components.min.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/WebUIApp/js/mc-components.min.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/WebUIApp/js/webUIApp.min.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/WebUIApp/js/webUIApp.min.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/css/app.a1785f5ff3c81b99ff24646b6870add0.css

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/css
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/css/app.a1785f5ff3c81b99ff24646b6870add0.css' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/fonts/element-icons.535877f.woff

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: font/woff
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/fonts/element-icons.535877f.woff' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/img/bg-login.848acf9.png

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/img/bg-login.848acf9.png' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/img/logo.4250bcd.png

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/img/logo.4250bcd.png' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/1.6e3a49056641a724418d.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/1.6e3a49056641a724418d.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/109.cca5577c1a31d713e489.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/109.cca5577c1a31d713e489.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/117.fc9e4ba851ca0008b2d6.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/117.fc9e4ba851ca0008b2d6.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/128.baf5bc3bff37df2426bf.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/128.baf5bc3bff37df2426bf.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/129.15079427e67e2c1abffc.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/129.15079427e67e2c1abffc.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/134.b2b0f7919ec8caf5a3c4.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/134.b2b0f7919ec8caf5a3c4.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/153.5601d9387b8f3d0c6188.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/153.5601d9387b8f3d0c6188.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/170.239453d3e985aadf1858.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/170.239453d3e985aadf1858.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/4.b58fc8382be148ebef4f.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/4.b58fc8382be148ebef4f.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/43.58273171d4e336d28c45.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/43.58273171d4e336d28c45.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/app.ca5a3e08e68e7348de89.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/app.ca5a3e08e68e7348de89.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/manifest.00c0973cb57cff2f3f3f.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/manifest.00c0973cb57cff2f3f3f.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/js/vendor.2af594996e2c94e4e363.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/vendor.2af594996e2c94e4e363.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/login/login.css

- 查询参数: v
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: text/css
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/login/login.css' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/login/loginbtn.jpg

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/login/loginbtn.jpg' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mcdev.webapp.163.com/static/login/loginbtnBg.jpg

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/login/loginbtnBg.jpg' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://nos.netease.com/apmsdk/napm-web-min-1.1.6.js

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/octet-stream
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://nos.netease.com/apmsdk/napm-web-min-1.1.6.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://pr.nss.netease.com/sentry/passive

- 查询参数: clusterName, dataTime, modelName, name, one, sp, timeout, wapi
- 请求头(字段): Referer, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: x-unknown
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://pr.nss.netease.com/sentry/passive' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj/fingerprint2.min-1.6.1.js

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj/fingerprint2.min-1.6.1.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj_cdn101/loading_50c5e3e79b276c92df6cc52caeb464f0.gif

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/gif;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj_cdn101/loading_50c5e3e79b276c92df6cc52caeb464f0.gif' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj_cdn101/message.js

- 查询参数: random
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj_cdn101/message.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj_cdn101/pp_index_dl_40af28acec9497accab2dafa2a147015.js

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj_cdn101/pp_index_dl_40af28acec9497accab2dafa2a147015.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj_cdn101/right_d9fec1cfd3a1926f3a0eb37470ee5506.png

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj_cdn101/right_d9fec1cfd3a1926f3a0eb37470ee5506.png' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj_cdn101/sprite_668dd9d8cbed2020ccb35961cb4f4bee.png

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj_cdn101/sprite_668dd9d8cbed2020ccb35961cb4f4bee.png' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://urswebzj.nosdn.127.net/webzj_cdn101/webzjconf.js

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Host, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, Sec-Fetch-Storage-Access, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript;charset=UTF-8
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://urswebzj.nosdn.127.net/webzj_cdn101/webzjconf.js' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6864db4200b50197c45da244RyO2ybpK06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6864db4200b50197c45da244RyO2ybpK06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/694e4dee0949136aa3b65b06Q3pNWPyk07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694e4dee0949136aa3b65b06Q3pNWPyk07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/694e4e09eb22f813068d9242wkUMCBOS07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694e4e09eb22f813068d9242wkUMCBOS07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/694e4e134fa67d1766a918a0LmB2yEWC07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694e4e134fa67d1766a918a0LmB2yEWC07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/694f822cd4c83cc524bf681cydwV1TkX07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694f822cd4c83cc524bf681cydwV1TkX07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/694f8236c2eca4bfffeb3685xx36YJYw07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694f8236c2eca4bfffeb3685xx36YJYw07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/69606d590afe16931218f5c3vbQb2cJu07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/69606d590afe16931218f5c3vbQb2cJu07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6989b2aaf5e11551d51bf6a5tA0GiaCJ07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6989b2aaf5e11551d51bf6a5tA0GiaCJ07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## POST https://dl.reg.163.com/dl/zj/mail/gt

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Content-Length, Content-Type, Cookie, Host, Origin, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: application/json
- 请求体JSON字段: encParams
- 响应类型: application/json;charset=UTF-8
- 响应JSON字段: ret, tk
- 示例请求体(已脱敏):
```
{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcfa4d8b106caf405c82e1d256463df4558eeb2117b997244cc5b2fd5fb53413038f4911ae537b8f6807fc052388d196510895db2009da9167d379bf08e1ed9dee389c87ed3759c08146bbb94a64bfedc733798960c2ca29ad0e69a03941c888f062ba71551199530bf1d0dc93753fe5b4d4b83a61adf55c76009f141d08b7bf9a0dffd590d5f9...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/gt' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcfa4d8b106caf405c82e1d256463df4558eeb2117b997244cc5b2fd5fb53413038f4911ae537b8f6807fc052388d196510895db2009da9167d379bf08e1ed9dee389c87ed3759c08146bbb94a64bfedc733798960c2ca29ad0e69a03941c888f062ba71551199530bf1d0dc93753fe5b4d4b83a61adf55c76009f141d08b7bf9a0dffd590d5f9...(truncated)"}'
```

## POST https://dl.reg.163.com/dl/zj/mail/ini

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Content-Length, Content-Type, Cookie, Host, Origin, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: application/json
- 请求体JSON字段: encParams
- 响应类型: application/json;charset=UTF-8
- 响应JSON字段: capFlag, capId, pv, ret
- 示例请求体(已脱敏):
```
{"encParams": "0fca5dcd3b72ed18732aade75d7ab0881be41de8e71b07a7ecf4ded63db95db23214fc20a2d756bc1ecfefb16b871a7a766a5e870d8784b82d2b6377a802ca62e37f3764b0c1dcc33aa189405c5735218e467dd3c6a4c14d0a92423a291f2177b00edfac56185de349fc7253f4f05e147037734ba83cbe0e2a76ea779c04d6ffe4215c5952ab4593461a263a6b9d41bb6f2750229a32...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/ini' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "0fca5dcd3b72ed18732aade75d7ab0881be41de8e71b07a7ecf4ded63db95db23214fc20a2d756bc1ecfefb16b871a7a766a5e870d8784b82d2b6377a802ca62e37f3764b0c1dcc33aa189405c5735218e467dd3c6a4c14d0a92423a291f2177b00edfac56185de349fc7253f4f05e147037734ba83cbe0e2a76ea779c04d6ffe4215c5952ab4593461a263a6b9d41bb6f2750229a32...(truncated)"}'
```

## POST https://dl.reg.163.com/dl/zj/mail/l

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Content-Length, Content-Type, Cookie, Host, Origin, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: application/json
- 请求体JSON字段: encParams
- 响应类型: application/json;charset=UTF-8
- 响应JSON字段: ret
- 示例请求体(已脱敏):
```
{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcdef79d9498eb249cf7af509c9c2809972c7fd783d5286cd9ae6300e647711a53418aaf26aee9e1fb0f86db94d7cf361352c7564fd1d49b633ca84e31ce0cdc3f32c8bd2280dfbf6013fcabba23b8347fa4e73e9885154d9defa28ce2ce45563f8be9e05cb6f979669ee91c43ba344bc52101715a4a4e92a833edcb6ddb70a43420de00ed209a...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/l' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcdef79d9498eb249cf7af509c9c2809972c7fd783d5286cd9ae6300e647711a53418aaf26aee9e1fb0f86db94d7cf361352c7564fd1d49b633ca84e31ce0cdc3f32c8bd2280dfbf6013fcabba23b8347fa4e73e9885154d9defa28ce2ce45563f8be9e05cb6f979669ee91c43ba344bc52101715a4a4e92a833edcb6ddb70a43420de00ed209a...(truncated)"}'
```

## POST https://dl.reg.163.com/dl/zj/mail/powGetP

- 查询参数: 无
- 请求头(字段): Accept, Accept-Encoding, Accept-Language, Connection, Content-Length, Content-Type, Cookie, Host, Origin, Referer, Sec-Fetch-Dest, Sec-Fetch-Mode, Sec-Fetch-Site, User-Agent, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform
- 请求体类型: application/json
- 请求体JSON字段: encParams
- 响应类型: application/json;charset=UTF-8
- 响应JSON字段: pVInfo, ret
- 示例请求体(已脱敏):
```
{"encParams": "408afa64b5ec3fd2072e42eb2ee3d343faff546f8878f98a2e90041ca8fbaf3b62b63f55cb9ef7b1e0e7ec347e3c545c21307d73e54443ffc443f82ef8abd16fb252e0656f145513bcb8be85ad22daf5f689133b9418c0019281aa5308c5d3a17c903cbbc94db2154ad5ae1f688e1f468e00109150155a692c2621179b90d6e5dbe0e4af8da96a45a45e4967dffb2c3e75bf3e30e541...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/powGetP' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "408afa64b5ec3fd2072e42eb2ee3d343faff546f8878f98a2e90041ca8fbaf3b62b63f55cb9ef7b1e0e7ec347e3c545c21307d73e54443ffc443f82ef8abd16fb252e0656f145513bcb8be85ad22daf5f689133b9418c0019281aa5308c5d3a17c903cbbc94db2154ad5ae1f688e1f468e00109150155a692c2621179b90d6e5dbe0e4af8da96a45a45e4967dffb2c3e75bf3e30e541...(truncated)"}'
```

## POST https://mc-launcher.webapp.163.com/salog/

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, content-length, content-type, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: application/json;charset=UTF-8
- 请求体JSON字段: log_data, log_name
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例请求体(已脱敏):
```
{"log_name": "statement_show", "log_data": {"agreement_id": "20240801", "agreement_type": "agreement_01"}}
```
- 示例curl:
```
curl -sS -X POST 'https://mc-launcher.webapp.163.com/salog/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"log_name": "statement_show", "log_data": {"agreement_id": "20240801", "agreement_type": "agreement_01"}}'
```

## POST https://mc-launcher.webapp.163.com/users/login

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, content-length, content-type, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: application/json;charset=UTF-8
- 请求体JSON字段: browser, monitor_system, source, urs
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例请求体(已脱敏):
```
{"monitor_system": "Mac", "browser": "Chrome", "source": "", "urs": "2911898435@qq.com"}
```
- 示例curl:
```
curl -sS -X POST 'https://mc-launcher.webapp.163.com/users/login' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"monitor_system": "Mac", "browser": "Chrome", "source": "", "urs": "2911898435@qq.com"}'
```

