# 下载量接口抓包记录（2026-03-10）

抓包文件：`tools/har/session_new.har`

## 1. 下载量明细接口

- 方法：`GET`
- URL：`https://mc-launcher.webapp.163.com/data_analysis/day_detail/`

### 请求参数（抓包实测）

- `platform`: `pe`（Java 侧通常为 `pc`）
- `category`: `pe`
- `start_date`: `YYYYMMDD`
- `end_date`: `YYYYMMDD`
- `item_list_str`: 逗号拼接的 mod id 列表
- `sort`: `dateid`
- `order`: `ASC`
- `start`: `0`
- `span`: `999999999`（页面也会发 `span=10`）
- `is_need_us_rank_data`: `true`

### 抓包示例请求

```text
GET /data_analysis/day_detail/?platform=pe&category=pe&start_date=20260303&end_date=20260309&item_list_str=4654544190222314712,...&sort=dateid&order=ASC&start=0&span=999999999&is_need_us_rank_data=true
```

### 响应关键字段

```json
{
  "status": "ok",
  "data": {
    "data": [
      {
        "iid": "4654544190222314712",
        "dateid": "20260303",
        "download_num": 1765727,
        "cnt_buy": 344,
        "diamond": 0
      }
    ]
  }
}
```

## 2. 口径与现象

- `download_num` 在抓包中表现为“累计下载量”（同一个 `iid`，日期越新数值越大）。
- 若查询“区间内每个 mod 当前总下载量”，可按 `iid` 取该区间内 `max(download_num)`。
- 抓包中 `start_date=end_date=当天` 的请求出现过空列表，`start_date=end_date=昨天` 有数据。

## 3. 相关接口（页面联动）

- `GET /data_analysis/overview/`：下载相关概览字段（如 `this_month_download`、`days_14_total_download`）。
- `GET /data_analysis/day_top_N/`：页面会请求榜单数据（`sort=cnt_buy`）。
