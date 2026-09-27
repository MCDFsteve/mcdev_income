# 桌面可执行文件的无头模式

桌面 GUI 可执行文件追加 `--headless` 后会直接运行命令，不打开应用窗口。命令与桌面软件共用登录、平台接口、作品模型和校验。覆盖当前软件的业务能力；网站中尚未实现的结算、团队、运营和网络服运维不在此范围。

## 快速使用

使用发布包中的桌面可执行文件（保留同目录的 Flutter 运行库和资源）。macOS 示例：

```sh
APP="build/macos/Build/Products/Release/我的世界开发者管理.app/Contents/MacOS/我的世界开发者管理"
"$APP" --headless schema
"$APP" --headless auth status
```

Windows 的可执行文件是 `build/windows/x64/runner/Release/minecraft_developer_manager.exe`，Linux 是 `build/linux/x64/release/bundle/minecraft_developer_manager`。下面的 `mcdev` 仅为示例中的简写；在 POSIX shell 中可先定义：

```sh
mcdev() { "$APP" --headless "$@"; }
```

```sh
./mcdev --help
./mcdev schema                          # 完整命令、参数、状态和冲突类型，JSON
./mcdev auth status --check             # 与桌面端共用会话
./mcdev list -q 背包                    # 作品搜索
./mcdev show 作品编号                    # 详情，包含完整平台字段
./mcdev upload work.json --dry-run      # 先校验并预览裁剪方案
./mcdev upload work.json --submit       # 上传、保存、提交审核
./mcdev edit 作品编号 --name 新名字       # 局部修改，其余字段保留
./mcdev submit 作品编号 --notes 修复说明
```

所有普通命令只向 stdout 输出一个 JSON 文档；`--verbose` 进度写入 stderr。`--pretty` 格式化 JSON。`--help` 默认输出文本，配合 `--json` 可输出机器可读帮助。全局选项可以放在命令前后。没有交互式确认弹窗；命令参数表达操作意图。

## 构建和登录

开发构建仍使用项目的 Flutter 依赖解析（包括相邻的本地 OreUI 项目）；发布后的无头命令无需单独编译 CLI，但必须保留完整桌面应用包。

```sh
flutter pub get
flutter build macos --release   # 或 flutter build windows/linux --release
```

首次升级后打开一次桌面端，会自动迁移原会话、主题、本机草稿和收益预设。之后 GUI 与 CLI 共用状态，新登录、退出和本机草稿都可以互通。已打开的 GUI 页面需要重新进入或刷新；主题重启生效。

无 GUI 的机器可直接登录：

```sh
mcdev auth login name@example.com --password-stdin < /secure/password.txt
mcdev auth status --check
mcdev auth refresh
mcdev auth logout
```

也可通过 `MCDEV_PASSWORD` 环境变量传入密码。密码没有命令行参数，不会出现在输出中。默认只保存会话；加 `--remember` 才保存密码并在会话临近过期时自动刷新。`auth refresh` 需要保存过密码。验证码等平台额外挑战会返回登录错误，不会卡在交互提示中。

`--home /path` 或 `MCDEV_HOME` 可以指定隔离的状态目录。默认位置：

| 系统 | 状态目录 |
| --- | --- |
| macOS | `~/Library/Containers/com.aimessoft.consmelt/Data/Library/Application Support/mcdev` |
| Linux | `${XDG_CONFIG_HOME:-~/.config}/mcdev` |
| Windows | `%APPDATA%/mcdev` |

状态采用加锁、原子替换；POSIX 系统目录权限为 `0700`、会话及任务文件为 `0600`。会话和选择保存的密码存储在本机 JSON 中。Windows 使用用户目录继承的 ACL。

高级用法：`MCDEV_COOKIE` 可提供当前进程的会话，不写入本地登录状态。使用这种方式创建的上传任务绑定该凭据的摘要，恢复时需使用同一份 Cookie。`auth logout` 清理本机保存的会话；不会移除父进程提供的环境变量。

## 上传清单

先读取平台配置，选择当前有效的类别、游戏版本、图片渠道和价格档位：

```sh
mcdev resource options > options.json
mcdev upload work.json --dry-run --options options.json  # 使用配置快照离线校验新作品
```

`work.json` 示例（类别、渠道和版本编号请以配置为准）：

```json
{
  "category": "pe",
  "fields": {
    "item_name": "示例模组",
    "pri_type": 2,
    "sub_type": 6,
    "price_type": "free",
    "price": 0,
    "mod_version": "3.9",
    "info": "<p>玩法介绍</p>",
    "is_original": true
  },
  "packages": ["files/mod.zip"],
  "images": {
    "3": "images/cover.jpg",
    "5": "images/preview.png"
  },
  "description_images": ["images/detail.png"],
  "video": {
    "path": "media/demo.mp4",
    "cover": "images/video-cover.jpg"
  },
  "notes": "本次提交说明"
}
```

清单中的文件路径相对于清单所在目录，支持绝对路径、空格和中文。命令行传入的路径相对于当前工作目录。视频、介绍图片等可选项不需要时直接删除。

图片会自动修正 EXIF 方向，以居中的最大矩形裁剪并缩放到渠道要求的精确尺寸，再以 PNG 上传，不修改源文件。未规定比例的介绍图和授权证明保留完整画面重新编码。视频封面为 992×558，封面最多 10 MB，MP4 最多 50 MB；视频编码是否满足平台要求由服务器最终校验。PNG 皮肤资源包、ZIP/JAR 模组包保持原字节，不进入图片处理流程。

上传前会先检查所有文件和表单。`--dry-run` 返回裁剪尺寸、文件摘要、待上传列表和预期字段，不上传、不保存、不提审；待上传素材在预览载荷中使用 `pending:` 占位值。实际上传总是读取最新平台配置。对于现有作品，dry-run 会在线读取原字段进行合并。

支持的其他清单字段：

| 字段 | 用途 |
| --- | --- |
| `packages` | 字符串路径数组，或 `{ "path": "mod.jar", "replace": 0, "mc_version": ["1.20.1"], "java_version": "17" }` 数组。`replace` 为原资源文件零起始下标；省略则追加。替换保留 `res_id` 等已有元数据 |
| `images` | 渠道编号或渠道标题 → 图片路径，替换对应渠道 |
| `description_images` | 上传图片后追加带签名的 `<img>` 到介绍 HTML |
| `proof` | 非原创授权证明图片路径，代替 `is_original: true` |
| `banner` | 横幅图片路径 |
| `sync.images` / `sync.description_images` | PE 同步 PC 的图片，配合 `fields.sync_pc_flag` 和 `fields.sync_item_info` |
| `conflict_notify` | 冲突报告范围，0 不接收、1 本账号、2 全平台，需要账号权限 |
| `conflict_types` | 冲突类型整数数组；`[0]` 表示全部；对应表见 `schema` |

`fields` 支持 GUI 里所有可编辑平台字段，包括收费类型、版本、加密、反作弊、搜索开关、更新说明、前置作品、DLC 和同步 PC 配置。嵌套对象递归合并，数组整体替换；未知的已有字段会保留，响应元数据会剔除。移除已有图片或资源时，用 `fields.channel` / `fields.res` 提供剩余数组。同步生成的 PC 作品须编辑关联 PE 作品。

简单上传可以不用清单：

```sh
mcdev upload --name 示例 --primary 2 --secondary 6 --original \
  --intro description.html --file mod.zip --image 3=cover.jpg --image 5=preview.jpg \
  --set 'mod_version="3.9"' --submit

mcdev edit 作品编号 patch.json
mcdev edit 作品编号 --set 'price_type="diamond"' --set 'price=100'
mcdev upload --resume 任务编号 --confirm-queue
```

`--set 字段路径=JSON值` 可重复，字符串值需要 JSON 引号；显式命令参数覆盖清单值。

## 审核、发布和恢复

```sh
mcdev resource actions 作品编号         # 当前状态和权限允许的操作
mcdev resource feedback 作品编号        # 审核/下架反馈，包含平台原始内容
mcdev submit 作品编号 --notes 已修复 --confirm-queue
mcdev resource action 作品编号 cancel-review
mcdev resource action 作品编号 self-test
mcdev resource action 作品编号 self-test-unchecked
mcdev resource action 作品编号 cancel-test
mcdev resource action 作品编号 publish
mcdev resource action 作品编号 schedule --at '2026-12-01 10:00'
mcdev resource action 作品编号 cancel-schedule
mcdev resource action 作品编号 price --price 100
mcdev resource action 作品编号 price --rank 2 --channel-rank 2
mcdev resource action 作品编号 offline --reason 下架原因
mcdev resource action 作品编号 urgent --reason 加急原因
mcdev resource action 作品编号 remind -c pc
mcdev resource action 作品编号 delete --yes
```

时间使用本机时区。档位从 0 开始，改价遵循当前账号的价格档位和相邻调整限制；有渠道定价权限时需要同时提供 `--channel-price` 或 `--channel-rank`。`delete` 必须提供 `--yes`。定时发布在命令执行时必须是未来时间。

每次实际上传生成一个任务号，每个文件成功后记录进度；一旦保存成功，立即记录作品编号。提审失败后 `mcdev upload --resume 任务号` 会继续该作品，不重新上传或重复创建。恢复时会验证账号、类别和剩余文件摘要。同一任务不能同时执行。

```sh
mcdev jobs list
mcdev jobs show 任务号
mcdev upload --resume 任务号
mcdev upload --resume 任务号 --confirm-queue
```

若保存期间断网或进程被终止，远端可能已创建作品，任务会拒绝盲目重试。先用 `list` / `show` 核对，再关联结果：

```sh
mcdev jobs resolve 任务号 --id 已保存的作品编号
mcdev upload --resume 任务号
# 仅在已核实平台没有新建作品时：
mcdev jobs resolve 任务号 --not-created --yes
```

更新结果不明时，先核对原作品字段；`resolve --id` 表示确认保存结果已存在。上传任务已经完成后，再次恢复只返回结果；后来需要提审时使用独立的 `submit` 命令。

## 查询、收益和本机数据

| 能力 | 命令 |
| --- | --- |
| 概览 / 账号信息 | `overview` / `profile`（过滤密码、Token 等凭证字段） |
| 排行榜 | `rank --type pe_download --kind mods --page 1 --limit 50` |
| 邮件 | `mail count` / `mail list --unread --type review_notice -q 审核` / `mail show 邮件编号` |
| 作品查询 | `list -c pe --status init --page 1 --limit 30`，`--all` 获取全部页 |
| PC / 网络作品只读查询 | `list -c pc` / `list -c multi` / `list -c pe_multi` |
| Mod 列表 | `mods list -c java --priced --published --query 名称` |
| 下载增量 / 累计 | `mods sales --id 编号 --from 2026-09-01 --to 2026-09-27`，`--total` 改为区间内累计最大值 |
| 前置作品 / DLC | `resource requirements 名称 -c pe` / `resource dlc 名称` |
| 本机草稿 | `draft list` / `draft get [编号或new]` / `draft put fields.json [编号或new]` / `draft delete [编号或new]` |
| 收益预设 | `preset list` / `preset get 编号` / `preset put preset.json` / `preset rename 编号 名称` / `preset delete 编号` |
| 主题 | `settings get` / `settings set theme system`（也支持 light、dark） |
| 单素材上传 | `media upload cover.jpg --channel 3 --secondary 6`，或 `--width 992 --height 558`；`--type zip_package` 上传原资源包 |
| 离线图片裁剪 | `media crop input.jpg --width 992 --height 558 --out output.png` |

收益示例：

```sh
mcdev income --from 2026-09-01 --to 2026-09-27 --id 编号1,编号2 \
  --internal 0.5 --netease 0.3 --tax 0.16 --sort diamonds --csv income.csv
mcdev income --preset 预设编号 --from 2026-09-01 --to 2026-09-27
```

日期默认本月 1 日到今天，首尾日期均包含；省略作品编号时查询全部。收益结果包含钻石、绿宝石、订单、下载增量、退款统计及分成，公式与 GUI 一致：钻石 ÷ 100 × 网易比例 × 内部比例 × (1 − 税率)。可用 `--sort downloads|release` 和 `--asc`；CSV 是 UTF-8 BOM 文件。若部分查询失败，退出码为 4，并在 `error.details` 中返回带错误项的部分结果，CSV 同样保留错误列。

预设 JSON 使用 GUI 的结构：`id`、`name`、`category`（pe/java）、`scope`（all/multiple/single）、`modIds`、`internalRatios`、`neteaseRatios`、`defaultInternalRatio`、`defaultNeteaseRatio`、`taxRate`。省略 id 创建新预设；指定 id 覆盖合并。比例范围 0–1；命令行显式比例会覆盖预设和各 Mod 的比例。本机草稿保存的是可编辑 `fields`，未上传的路径清单应保存在工作目录，而不是草稿字段中。

## 排行榜与邮件

```sh
mcdev rank                                # 默认手游热门飙升榜，模组
mcdev rank --type hot_search               # 热搜词与搜索指数
mcdev rank --type pc_like --kind maps --page 2
mcdev mail count                          # 未读数量
mcdev mail list --unread                   # 列表查询不会改变已读状态
mcdev mail list --type review_notice -q 审核 --page 2 --limit 30
mcdev mail show 邮件编号                    # 读取正文，并将这封邮件标记为已读
```

排行榜 `--type` 支持 `pe_hot`（热门飙升）、`hot_search`（热搜）、`pe_download`（手游免费）、`pe_sell`（手游畅销）、`pc_download`（端游下载）、`pc_like`（端游点赞）。热门飙升与热搜需要平台账号的 `can_us_rank` 权限；没有权限可选 `pe_download` 等普通榜单。`--kind` 支持 `mods/maps/textures/multiplayer`，热搜榜不按作品类别筛选。`--limit` 为 1–100。

邮件 `--type` 支持 `all/system_notice/review_notice/important_notice/income_notice/issue_feedback/notify`。列表返回 `_id` 供 `mail show` 使用，正文保留平台原始 HTML 或纯文本。打开邮件会触发平台的已读行为，GUI 与 CLI 相同。邮件列表默认每页 30 条，排行榜默认 50 条；均返回 `total/items/next_offset`，最后一页 `next_offset` 为 `null`。

## Agent 输出协议

```json
{"ok":true,"data":{"job":"任务号","item_id":"作品编号","phase":"complete","submitted":true}}
```

```json
{"ok":false,"error":{"code":"queue_confirmation_required","message":"保存需要确认排队","details":{"job":"任务号","phase":"save_queue"}}}
```

| 退出码 | 含义与后续操作 |
| --- | --- |
| 0 | 成功；读取 `data` |
| 1 | 文件、锁或本机异常 |
| 2 | 参数、表单、状态或操作确认不符合要求；按错误修正 |
| 3 | 需要登录或权限不足 |
| 4 | 平台明确失败或只读网络错误；检查错误信息 |
| 5 | 需要排队确认；确认后加 `--confirm-queue` |
| 6 | 写入结果不明；先查询核对，避免重复创建/发布 |

推荐 Agent 流程：`schema` → `auth status --check` → `resource options` → 编写清单 → `upload --dry-run` → `upload [--submit]`。以退出码和 `ok` 判断结果，勿把 stdout 当作日志解析。取消正在执行的上传后，通过任务列表恢复；进程中断并不代表远端操作被取消。

## 验证边界

自动化测试覆盖接口载荷、路径预检、裁剪尺寸、签名绑定、保存与审核失败恢复、排队确认、并发任务锁、共享状态、预设/草稿、收益 CSV 和认证输入。生产账号仅进行只读验证；创建、提审、上架和删除用模拟平台响应验证，没有为测试创建或发布真实作品。
