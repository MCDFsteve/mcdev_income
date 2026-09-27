# 作品与模组管理

本轮优先实现普通 PE / PC 作品从编辑、上传、保存、提审到发布维护的流程，使用现有 OreUI 控件。平台特权、审核额度和实际可用状态仍由服务器决定。

## 使用与覆盖

| 环节 | 实现 |
| --- | --- |
| 查找作品 | PE / PC 列表，名称或 ID 搜索、状态筛选、30 条分页、刷新、完整详情和更新日志 |
| 编辑 | 新建、编辑草稿、驳回后修改、线上作品更新；类别、版本、价格、标签、皮肤体型、简介、HTML 介绍和预览、更新日志、原创证明、加密等设置 |
| 上传 | 按平台类别选择资源包格式；流式上传、进度、签名校验；替换资源保留编号；PC 文件分别选择游戏版本 |
| 展示内容 | 展示图片、介绍图片、视频封面、推广图和原创证明均支持上传前裁剪；展示图和封面按平台比例输出指定尺寸，其余自由裁剪；展示视频上传 |
| 定价 | 获取当前定价档位；支持账号启用的官方价和渠道价，渠道价不得低于官方价；已上架作品的快速改价 |
| 关联 | 前置模组；有权限账号的 DLC 主副包关联；PE 同步 PC 的基础信息、介绍、图片、依赖及弱下架设置 |
| 审核 | 保存后提审或从列表独立提审；500 字备注、本账号/全平台冲突报告和检测范围；审核排队再次确认；撤销、富文本反馈、下架反馈 |
| 发布维护 | PE 机审自测、免机审自测及取消；上架、定时上架及取消；弱下架编辑；按权限开放的免审弱下架、加急和 PC 催审；待提交作品删除 |
| 恢复 | 本机草稿按账号、类别、资源编号隔离；提审失败保留已保存编号；新建保存超时、服务端异常或缺少编号时阻止重复创建，提示返回列表核对 |

PC 同步作品不提供独立修改状态的入口，编辑跳转到关联 PE 作品。列表操作按状态和权限显示；所有改变平台数据的操作均需要在应用中明确触发，审核、删除等还会展示确认弹窗。

编辑界面按可用宽度排布：默认字号下，1000 像素起使用两栏，1600 像素起使用三栏；较窄窗口使用单栏，放大字号时相应提高分栏所需宽度。桌面各栏独立滚动，短字段在栏内并排显示，保存操作始终固定在底部，切换窗口大小保留已编辑内容。

详情介绍默认显示排版效果，包括段落、列表、文字样式和图片；需要修改源码时点击“编辑 HTML”，修改后可切回“排版效果”查看。同步 PC 的详情采用相同方式。切换视图不改写 HTML 或图片签名数据。

展示图片在栏内按宽度排列为网格，缩略图高度为 80 像素；未上传的图片不预留缩略图空位。同步 PC 作品使用相同布局。

选择展示类图片后打开 OreUI 裁剪弹窗，可移动选区、拖动四角、滚轮或双指缩放、旋转和重置；确认后生成 PNG 再上传。尺寸不符或小于目标尺寸时可裁剪、缩放到要求尺寸，不会因原图尺寸直接拒绝。取消不请求上传凭证、不替换原图；图片大小限制以裁剪后的文件为准。皮肤等 PNG 资源包保持原始字节，不进入展示图片裁剪流程。

尚未实现网页的全部功能。集合/合集、特殊官方形象与礼包、海外资源、试玩/联机大厅专属配置、运营活动联动及性能免审/优化服务不在本轮完整覆盖范围；已有作品的未知字段尽量保留，不能据此视为这些功能已经实现。网络游戏当前只保留查看。结算提现、团队和网络服运维按本轮范围安排后续处理。

## 网页接口依据

核对日期：2026-09-27。依据官方网页的公开客户端代码和授权账号的只读响应，未通过真实写操作探测平台。

- [官方客户端与接口表](https://mcdev.webapp.163.com/static/js/app.96444e39812c10d90e5e.js)
- [PE 编辑器与上传组件](https://mcdev.webapp.163.com/static/js/2.74db7a2e32c994bdb277.js)
- [PE 列表和审核流程](https://mcdev.webapp.163.com/static/js/14.3d396e3438378a6d220d.js)
- [PC 列表和审核流程](https://mcdev.webapp.163.com/static/js/22.3bf080d9d49d8de1eb4d.js)
- [PC 编辑器](https://mcdev.webapp.163.com/static/js/16.b23876d5b0918996292f.js)

业务 API 主机为 `mc-launcher.webapp.163.com`，`{category}` 为 `pe` 或 `comp`。

| 操作 | 方法与路径 / 关键字段 |
| --- | --- |
| 列表 | `GET /items/categories/{category}/`，`fuzzy_key`、`status`、`start`、`span` |
| 详情 | `GET /items/categories/{category}/{id}` |
| 创建 / 更新 | `POST .../upload` / `POST .../{id}/update`，保存成功先保留 `data.item_id` |
| 提审 | `PUT .../{id}/apply_review`，`apply_review_text`、`is_check_apply`、可选 `conflict_notify` |
| 反馈 | `GET .../{id}/feedback`，单数路径；`data` 可为 HTML 反馈对象 |
| 自测 | `PUT .../{id}/self-test-apply`，`self_test_pass_check: false`、`is_check_apply` |
| 撤销审核 / 自测 | `PUT .../{id}/cancel_review` / `cancel_self_test` |
| 上架 / 定时 | `PUT .../{id}/online` / `appoint_online`；时间为本地 `yyyy-MM-dd HH:mm:00` 字符串，取消为 `null` |
| 改价 / 加急 / 催审 | `POST .../{id}/change_price` / `urgent-admin` / `remind` |
| 免审弱下架 | `PUT .../{id}/exempt_review`，`type: weak_offline`、原因；同步作品使用 `op_platform: all` |
| 删除 | `DELETE .../{id}` |
| 表单配置 | `GET /items/mc_consts/`；`GET /setting/common/?name=item_price_setting` |
| PC 前置 | `GET /items/categories/comp/requirements`，`query_str` |
| PE 前置 | `GET /items/categories/pe/`，`pri_type: 9`、`item_name` |
| DLC 选择 | `GET /items/categories/pe/`，`item_name`、`mc_status: 1` |

HTTP 200 不代表业务成功，必须检查 `status == ok`（文件服务器的直接响应除外）。`data.need_check_apply == true` 表示等待排队确认，不能显示为保存/提审成功；用户确认后才以 `is_check_apply: true` 再次请求。

文件上传先向 `/filepicker/file_token` 获取指定 `file_type` 的令牌，再以 multipart 提交到 `https://fp.ps.netease.com/x19/file/new/`，字段为 `Authorization` 和 `fpfile`。不向文件主机转发登录 Cookie 或 ACCOUNT-TOKEN。保留 `x-ntes-signature` 与网页格式化后的 JSON 响应，组装 `{body, file_type, sign}` 写入资源字段。介绍图片也携带签名属性。未替换的文件元数据保持原样。

文件请求显式发送 `Accept: application/json`。2026-09-27 实测发现，缺少此请求头时，文件服务器会把成功 JSON 包在 HTML 的 `<textarea>` 中，同时返回 HTTP 200 和签名。客户端同时兼容直接 JSON 和带签名的单个 textarea 响应，仅解析数据，不执行 HTML 中的脚本；非成功响应按上传凭证、大小、频率或服务器错误分别提示。

## 验证与边界

- 已用真实只读接口验证 PE / PC 列表、名称/ID 搜索、状态过滤、详情、反馈、表单常量、版本配置、用户权限和当前定价档位。
- 自动测试覆盖业务拒绝、签名上传和 Cookie 隔离、排队确认、分页、已保存资源的提审失败重试、结果不明时防止重复创建、DLC 元数据、定价约束和窄屏交互。
- 已构建 macOS Debug 应用。电脑锁屏期间使用合成数据做明暗主题和 390 像素宽界面渲染检查；未把模拟数据作为真实平台响应。
- 已用本机 16 × 16 图标通过真实文件服务器和应用的 `McDevApi` 验证图片上传、尺寸信息和签名回传。没有将测试图片保存为作品，也没有真实提审、改价、上架或删除账号内作品；作品写接口仍需在实际操作时确认平台业务校验。
- 裁剪测试覆盖选区边界、输出像素和尺寸、旋转方向、桌面/窄屏弹窗、取消不上传、签名文件替换及皮肤 PNG 原样上传。
- 视频在本地检查扩展名和大小，封面裁剪到指定尺寸；H.264 编码、画面比例及内容规则最终由平台审核。真实账号权限未开放的流程不能宣称完成线上验证。
- `flutter analyze` 没有编译错误；仓库原有收益页面、闲置变量和 vendored 依赖仍有警告/提示。

运行检查：

```sh
flutter test
flutter analyze --no-pub
flutter build macos --debug
```

账号、密码和临时登录会话不属于测试夹具或文档，不能写入仓库。
