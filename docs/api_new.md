# MC开发者平台接口汇总

生成时间: 2026-03-10 00:09:04

说明:
- 由 HAR 自动提取，敏感字段已脱敏。
- 建议先用浏览器抓包导出 HAR，再运行脚本生成此文档。

生成命令示例:
- `python3 tools/har_extract.py --har tools/har/session.har --out docs/api.md --json docs/api_endpoints.json`

## GET blob://https://dl.reg.163.com/9ec290de-72b2-46f1-9263-a5ebaba21164

- 查询参数: 无
- 请求头(字段): Accept
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: 无
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'blob://https://dl.reg.163.com/9ec290de-72b2-46f1-9263-a5ebaba21164' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET blob://https://dl.reg.163.com/d565c9f9-d6fa-4ab1-a1b0-1006ab1976f1

- 查询参数: 无
- 请求头(字段): Accept
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: 无
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'blob://https://dl.reg.163.com/d565c9f9-d6fa-4ab1-a1b0-1006ab1976f1' \
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

## GET https://mc-launcher.webapp.163.com/data_analysis/day_detail/

- 查询参数: category, end_date, is_need_us_rank_data, item_list_str, order, platform, sort, span, start, start_date
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/data_analysis/day_detail/' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://mc-launcher.webapp.163.com/data_analysis/day_top_N/

- 查询参数: category, dateid, platform, sort, span
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, origin, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/json
- 响应JSON字段: data, status
- 示例curl:
```
curl -sS -X GET 'https://mc-launcher.webapp.163.com/data_analysis/day_top_N/' \
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

- 查询参数: span, start
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

## GET https://mcdev.webapp.163.com/static/js/112.635c42f19a7dde25cb26.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/112.635c42f19a7dde25cb26.js' \
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

## GET https://mcdev.webapp.163.com/static/js/27.28907a6309a87695f38b.js

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, cookie, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: application/javascript
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://mcdev.webapp.163.com/static/js/27.28907a6309a87695f38b.js' \
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

## GET https://x19.fp.ps.netease.com/file/67c59c1b1e7e28f973af2f9e8oAmDtGw06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/67c59c1b1e7e28f973af2f9e8oAmDtGw06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/67d3dacb6366220dfe53dc1fBDNeOPPq06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/67d3dacb6366220dfe53dc1fBDNeOPPq06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/681328f632ba3ec98598e3cdPCAW4R0u06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/681328f632ba3ec98598e3cdPCAW4R0u06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/683a9ae976e419388bc4ca5cAT0sXG1b06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/683a9ae976e419388bc4ca5cAT0sXG1b06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6848016bdc98471294085fb1HgTKLB9a06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6848016bdc98471294085fb1HgTKLB9a06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68512b8b5f35f7d9814422f9t1dTGv6b06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68512b8b5f35f7d9814422f9t1dTGv6b06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6854c5a0b1508336e3d4a63cYsrOSFds06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6854c5a0b1508336e3d4a63cYsrOSFds06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6854f0a04df1693dc2d914dbdjVExtlD06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6854f0a04df1693dc2d914dbdjVExtlD06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/685f663fe4fa3ed46c2ec6dd9iHfKoTl06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/685f663fe4fa3ed46c2ec6dd9iHfKoTl06' \
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

## GET https://x19.fp.ps.netease.com/file/687084edaddde6a5b020a16a8zTYzw7C06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/687084edaddde6a5b020a16a8zTYzw7C06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6878e5f53ec164088052ecf4DBVvjfM706

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6878e5f53ec164088052ecf4DBVvjfM706' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/687d97c3abe7332f9f6f28bdjaXWhFbC06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/687d97c3abe7332f9f6f28bdjaXWhFbC06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68a9c170c8b276ca792bbf80zFXGxtm606

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68a9c170c8b276ca792bbf80zFXGxtm606' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68c7ca926414d95db17d69aaQA809gFv06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68c7ca926414d95db17d69aaQA809gFv06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68ccb7f9b0acc203d235309b0ibztlPz06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68ccb7f9b0acc203d235309b0ibztlPz06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68da5c8d8e8483a3e6d50c74fQdzfy0906

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68da5c8d8e8483a3e6d50c74fQdzfy0906' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68f0a79a15abfac33106c2e1rHWV4BHz06

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68f0a79a15abfac33106c2e1rHWV4BHz06' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/68fda80f4cc4edf29728fca3NT6Jz6C706

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/68fda80f4cc4edf29728fca3NT6Jz6C706' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/691e87ac6de0deef658a4554O41I4lTk07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/691e87ac6de0deef658a4554O41I4lTk07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6936cddb2cdb38538a44a893LP2AL1ZD07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6936cddb2cdb38538a44a893LP2AL1ZD07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6937b53e175849c407114999h2rAvhNh07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6937b53e175849c407114999h2rAvhNh07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/693926471d73ed601d7c97608NIg3eVM07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/693926471d73ed601d7c97608NIg3eVM07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/694000e6e704e08374c0fcd4ilratJJm07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694000e6e704e08374c0fcd4ilratJJm07' \
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

## GET https://x19.fp.ps.netease.com/file/694e9f681b972f34f3a91a52CX8z5tWN07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/694e9f681b972f34f3a91a52CX8z5tWN07' \
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

## GET https://x19.fp.ps.netease.com/file/6951fc1b62f05d048169fa11S5iS2FIz07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6951fc1b62f05d048169fa11S5iS2FIz07' \
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

## GET https://x19.fp.ps.netease.com/file/6969b79b4f24c43765b8b042GT1iIvET07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6969b79b4f24c43765b8b042GT1iIvET07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/696b491afa8bf54e98f610f7AFHuCSSF07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/696b491afa8bf54e98f610f7AFHuCSSF07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/696bb2407e47e41c9f9a420b98HLe8YG07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/696bb2407e47e41c9f9a420b98HLe8YG07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/696d00730bba48d652cc0329EuNxMEyA07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/696d00730bba48d652cc0329EuNxMEyA07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/696f78eff68dcbfbaab33e019FKV1aMu07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/696f78eff68dcbfbaab33e019FKV1aMu07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/69774b9703cdb46b4595c178bvJrohgc07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/69774b9703cdb46b4595c178bvJrohgc07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6978a9e44876b9af6993cdb2AMWtUfL507

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6978a9e44876b9af6993cdb2AMWtUfL507' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/697ae0d3b9ef19be1cd4249fWbfJlRBV07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/697ae0d3b9ef19be1cd4249fWbfJlRBV07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/697b0de4de19d3d80affe077IqWaizo907

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/697b0de4de19d3d80affe077IqWaizo907' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/69808d44490e6d95475b6ae7Zd7WEMXV07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/69808d44490e6d95475b6ae7Zd7WEMXV07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698310cbf26c21b13c401f9f4LBqZuvG07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698310cbf26c21b13c401f9f4LBqZuvG07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698478257ba2839f662831a2b5wXWit107

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698478257ba2839f662831a2b5wXWit107' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/69847893478bb74814f81c06lGNbefo307

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/69847893478bb74814f81c06lGNbefo307' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698484136b9b6af71388f07eZzr44ZXi07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698484136b9b6af71388f07eZzr44ZXi07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6988768d6e6484f8f68d1d9f7cDP1U1507

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6988768d6e6484f8f68d1d9f7cDP1U1507' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/6989744f5997e1f9b5d34a23BFOOG2VI07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/6989744f5997e1f9b5d34a23BFOOG2VI07' \
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

## GET https://x19.fp.ps.netease.com/file/698a54df88f15ea5c9dd8192btKmXUPT07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698a54df88f15ea5c9dd8192btKmXUPT07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698b0451e1d6ec1765b863c13O3sXQ1007

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698b0451e1d6ec1765b863c13O3sXQ1007' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698c9b4c3e40b5eb982395d6X5Q4tC8g07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698c9b4c3e40b5eb982395d6X5Q4tC8g07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698df2632d882cb50bc472ddlANR0faa07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698df2632d882cb50bc472ddlANR0faa07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/698f645d199ffd9cc12c4245M2MklfJK07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/698f645d199ffd9cc12c4245M2MklfJK07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/69909f52f16e66b9e5accc6eAwBV3fCK07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/69909f52f16e66b9e5accc6eAwBV3fCK07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/69912769d61b007d30d0160cQMDXJfmF07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/jpeg; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/69912769d61b007d30d0160cQMDXJfmF07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/699966d33fa4ccc46e37f347C3GpK3cJ07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/699966d33fa4ccc46e37f347C3GpK3cJ07' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
```

## GET https://x19.fp.ps.netease.com/file/699bc8dbbdca34e80679c122OgQMYM7A07

- 查询参数: 无
- 请求头(字段): :authority, :method, :path, :scheme, accept, accept-encoding, accept-language, priority, referer, sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, sec-fetch-dest, sec-fetch-mode, sec-fetch-site, sec-fetch-storage-access, user-agent
- 请求体类型: 无
- 请求体JSON字段: 无
- 响应类型: image/png; charset=binary
- 响应JSON字段: 无
- 示例curl:
```
curl -sS -X GET 'https://x19.fp.ps.netease.com/file/699bc8dbbdca34e80679c122OgQMYM7A07' \
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
{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcfa4d8b106caf405c82e1d256463df4558eeb2117b997244cc5b2fd5fb53413038f4911ae537b8f6807fc052388d196510895db2009da9167d379bf08e1ed9dee389c87ed3759c08146bbb94a64bfedc733798960c2ca29ad0e69a03941c888f062ba71551199530bf1d0dc93753fe5b4d4b83a61adf55c76009f141d08b7bf9ae911796b8cfe...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/gt' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcfa4d8b106caf405c82e1d256463df4558eeb2117b997244cc5b2fd5fb53413038f4911ae537b8f6807fc052388d196510895db2009da9167d379bf08e1ed9dee389c87ed3759c08146bbb94a64bfedc733798960c2ca29ad0e69a03941c888f062ba71551199530bf1d0dc93753fe5b4d4b83a61adf55c76009f141d08b7bf9ae911796b8cfe...(truncated)"}'
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
{"encParams": "0fca5dcd3b72ed18732aade75d7ab0881be41de8e71b07a7ecf4ded63db95db23214fc20a2d756bc1ecfefb16b871a7a766a5e870d8784b82d2b6377a802ca62e37f3764b0c1dcc33aa189405c5735218e467dd3c6a4c14d0a92423a291f2177b00edfac56185de349fc7253f4f05e147037734ba83cbe0e2a76ea779c04d6ffe4215c5952ab4593461a263a6b9d41bbefd50a2596b0...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/ini' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "0fca5dcd3b72ed18732aade75d7ab0881be41de8e71b07a7ecf4ded63db95db23214fc20a2d756bc1ecfefb16b871a7a766a5e870d8784b82d2b6377a802ca62e37f3764b0c1dcc33aa189405c5735218e467dd3c6a4c14d0a92423a291f2177b00edfac56185de349fc7253f4f05e147037734ba83cbe0e2a76ea779c04d6ffe4215c5952ab4593461a263a6b9d41bbefd50a2596b0...(truncated)"}'
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
{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcdef79d9498eb249cf7af509c9c280997e199faa24f9bfa8355f24067d1695a789c54e18fb0d0868bf0a20ba97c4bd1a22400dfb1cbfa62d5df1f588faa5b6003ad28228cac519dc2b491d2eec2dd20c7541c6ad40a5e685705ebfb41ce22ac9849f5ea2f02cc25d07ed1bbdae471c09b096b35550c21dc1b552acdb63b86ce9269f9337603a2...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/l' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "fd871ca8d5b2fc88266bd9eba94191dcdef79d9498eb249cf7af509c9c280997e199faa24f9bfa8355f24067d1695a789c54e18fb0d0868bf0a20ba97c4bd1a22400dfb1cbfa62d5df1f588faa5b6003ad28228cac519dc2b491d2eec2dd20c7541c6ad40a5e685705ebfb41ce22ac9849f5ea2f02cc25d07ed1bbdae471c09b096b35550c21dc1b552acdb63b86ce9269f9337603a2...(truncated)"}'
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
{"encParams": "408afa64b5ec3fd2072e42eb2ee3d343faff546f8878f98a2e90041ca8fbaf3b62b63f55cb9ef7b1e0e7ec347e3c545c21307d73e54443ffc443f82ef8abd16fb252e0656f145513bcb8be85ad22daf5f689133b9418c0019281aa5308c5d3a17c903cbbc94db2154ad5ae1f688e1f46a01462500e07ce3d7f1362f4ffbf6726ff3d9ce7c2a8239447fba61cfe2c7d724e0e18d27b77...(truncated)"}
```
- 示例curl:
```
curl -sS -X POST 'https://dl.reg.163.com/dl/zj/mail/powGetP' \
  -H 'Cookie: ${MCDEV_COOKIE}' \
  -H 'Content-Type: application/json' \
  -d '{"encParams": "408afa64b5ec3fd2072e42eb2ee3d343faff546f8878f98a2e90041ca8fbaf3b62b63f55cb9ef7b1e0e7ec347e3c545c21307d73e54443ffc443f82ef8abd16fb252e0656f145513bcb8be85ad22daf5f689133b9418c0019281aa5308c5d3a17c903cbbc94db2154ad5ae1f688e1f46a01462500e07ce3d7f1362f4ffbf6726ff3d9ce7c2a8239447fba61cfe2c7d724e0e18d27b77...(truncated)"}'
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

