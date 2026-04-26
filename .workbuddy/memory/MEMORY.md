# 项目记忆

## time_block Flutter 项目

### 环境信息
- **Flutter**: 3.41.6 (arm64) 安装于 ~/development/flutter/
- **Xcode**: 26.2，需通过 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 激活
- **CocoaPods**: 1.16.2 (通过 Homebrew 安装)
- **macOS**: 15.7.4 darwin-arm64

### 必要环境变量
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$HOME/development/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export SSL_CERT_FILE=/etc/ssl/cert.pem
```

### 快速运行
```bash
cd ~/Downloads/time_block
./run_macos.sh
```

### 已知问题和解决方案
1. Homebrew portable-ruby 4.0.2_1 下载失败 → 软链接 4.0.1→4.0.2_1 解决
2. Homebrew Ruby 3.4.4 SSL 证书问题 → `SSL_CERT_FILE=/etc/ssl/cert.pem` 解决
3. xcode-select 指向 CommandLineTools → 通过 `DEVELOPER_DIR` 环境变量绕过（无需 sudo）

### ~/.zshrc 已写入的内容
- Flutter PATH
- PUB_HOSTED_URL 和 FLUTTER_STORAGE_BASE_URL 镜像配置

---

## 数据同步功能（2026-04-11 完善）

### 架构概述
- **协议**：HTTP REST API
- **客户端**：Flutter app，`lib/network/dataSync.dart` + `lib/network/syncConfig.dart`
- **服务端**：Python Flask，`server/app.py`，默认端口 **5001**（macOS 5000 被 AirPlay 占用）
- **旧 server.py**：已废弃，保留在根目录仅供参考，实际请使用 `server/app.py`

### 服务端文件结构（server/ 目录）
| 文件 | 说明 |
|------|------|
| `server/app.py` | Flask 主入口：/ping、POST /sync（增量合并+补丁）、/data、/conflicts、/sync-log、/dashboard |
| `server/storage.py` | 持久化层：**SQLite**（data/timeblock.db），WAL 模式，6张表 |
| `server/merger.py` | 合并逻辑：block 级冲突检测、缺失补丁计算 |
| `server/migrate.py` | 一次性迁移脚本：旧 JSON → SQLite |
| `server/dashboard.html` | 可视化 Dashboard 前端（纯 HTML 单文件）|
| `server/data/timeblock.db` | SQLite 主数据库（WAL 模式）|
| `server/data/json_backup/` | 旧 JSON 文件备份 |

### SQLite 数据库表
| 表名 | 内容 |
|------|------|
| event_info | 事件类型（name UNIQUE，含 color_r/g/b、belonging_to、sort_order）|
| day_records | 主时间块数据（date_key PRIMARY KEY，events_json TEXT）|
| conflicts | 冲突记录（每条一行）|
| version | 版本历史（保留最近 200 条）|
| meta | 全局 key-value 元信息 |
| sync_log | 同步操作日志（client_id、time、range、merged/conflict/patch_days，最近 1000 条）|

### 客户端文件
| 文件 | 说明 |
|------|------|
| `lib/network/syncConfig.dart` | 服务端地址 + lastSyncEndDate + eventInfoOrder + **clientId**（设备唯一标识）持久化 |
| `lib/network/dataSync.dart` | HTTP 客户端，`runMultiStepSync()` 多步同步，含 eventInfo 配置同步（`_applyServerEventInfo()`）|
| `lib/view/appBarViiew.dart` | MainPage AppBar 同步按钮，同步后刷新 patchedDates 和 eventInfo |
| `lib/view/editPage.dart` | 底部"立即同步"按钮 + 服务端地址配置 |
| `lib/loaders.dart` | `applyPatchedDates()` + **`applyServerEventInfo()`**（同步后刷新 eventInfo 内存列表）|
| `lib/main.dart` | 启动时调用 SyncConfig.init() |
| `pubspec.yaml` | 依赖 `http: ^1.2.0` |

### API 接口
- `GET  /ping`      — 连通性检测，返回服务端当前版本号
- `POST /sync`      — 增量上传+接收补丁（核心接口）
- `GET  /data`      — 数据摘要（调试用）
- `GET  /conflicts` — 冲突记录（调试用）

### 同步协议
- **上传范围**：由 `lastSyncEndDate`（上次同步截止日期）次日 → 今天确定
- **合并规则**：服务端以 block（15分钟）为单位检测冲突；不冲突→主库；冲突→冲突库
- **补丁回填**：`uploadRange` 内客户端未上传但服务端有数据的天，作为 `patch` 返回
- **版本号**：每次成功 POST /sync 递增，客户端可感知

### 启动服务端
```bash
cd ~/Downloads/time_block/server
python3 app.py
# 自定义端口: PORT=8888 python3 app.py
```

### 客户端使用
- 切到第二个 Tab（画笔图标）→ 底部填写服务端地址 → 验证连接
- 回到第一个 Tab（首页）→ 右上角点"同步"即触发双向增量同步

---

## 2026-04-12 优化记录

### 1. 修复 macOS App Sandbox 网络权限问题
- **根因**：`macos/Runner/DebugProfile.entitlements` 和 `Release.entitlements` 缺少 `com.apple.security.network.client` 权限
- **现象**：curl 能连、App 里报无法连接服务端
- **修复**：两个 entitlements 文件均添加 `network.client` = true

### 2. 服务端 eventInfo 合并逻辑优化（server/app.py）
- **旧逻辑**：`main_data['eventInfo'] = body['eventInfo']`（整体替换，会丢失服务端独有条目）
- **新逻辑**：以 `name` 字段为唯一键做 upsert；客户端有→覆盖，服务端独有→保留，颜色变更自动检测并打印日志

### 3. editPage eventInfo 拖动排序功能
- **涉及文件**：`lib/network/syncConfig.dart`、`lib/loaders.dart`、`lib/view/editPage.dart`、`lib/main.dart`
- **存储**：排序持久化到 `syncConfig` Hive box，key 为 `eventInfoOrder`（JSON 数组字符串）
- **加载**：`main.dart` 读取 `savedOrder` → 传给 `UserProfileLoader` 构造函数 → 按顺序初始化 `eventInfos`
- **拖动**：`editPage` 改用 `ReorderableListView`，拖动后调用 `userProfileLoader.reorderEventInfos(old, new)` 持久化并触发 `notifyListeners()` 更新全局视图
- **编辑保持顺序**：`_saveEventInfo` 更新 eventInfo 后在原位更新 list，不重排顺序

---

## 2026-04-25 新增功能

### 1. 多步同步协议 v2.0（server/app.py + lib/network/dataSync.dart）

**新增 API 接口：**
- `GET  /handshake` — 握手，获取服务端能力
- `POST /handshake/negotiate` — 协商，服务端返回 syncPlan
- `POST /sync/upload` — 上传 dayRecords 数据（含 eventInfo + sortOrder）
- `GET  /sync/download` — 下载指定日期范围数据（含 eventInfo + sortOrder）

**eventInfo 配置同步（2026-04-26 完善）：**
- 上传时：`_buildEventInfoList()` 包含 `sortOrder` 字段
- 下载后：`_applyServerEventInfo()` 写入 Hive，合并规则「服务端有→新增/更新，本地独有→保留」
- `SyncResult.eventInfoUpdated` 为 true 时，调用 `applyServerEventInfo()` 刷新 UI
- 设备 clientId：`{平台}-{8位hex}`，首次生成后持久化，用于 sync-log 溯源

**数据层冲突策略：**
- 时间块不冲突→写主库；冲突→只追加到冲突库，主库不变（只新增，不删除）

### 2. 长按拖动选中功能（lib/view/dayBlocksView.dart + lib/loaders.dart）

**功能描述：**
- 长按某个 block 触发拖动模式
- 拖动到其他 block 时，自动选中起点到终点的所有 block
- UI 实时更新预览选中状态
- 松手完成选择

**涉及文件：**
- `lib/view/dayBlocksView.dart` — 重构 Block 构建逻辑，添加 GestureDetector
- `lib/loaders.dart` — `OperationControl` 新增长按拖动状态管理

**关键代码：**
- `startLongPressSelect()` — 开始长按选择
- `updateLongPressSelect()` — 更新拖动范围
- `endLongPressSelect()` — 完成选择
- `cancelLongPressSelect()` — 取消选择
- `_BlockHitArea` — 用于 hit test 找到当前手指下的 Block

**跨平台兼容：**
- Flutter GestureDetector 在 iOS、Android、macOS、Windows、Linux 行为一致
- 使用 HapticFeedback 提供触觉反馈
