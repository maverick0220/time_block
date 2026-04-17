# TimeBlock 数据同步系统 - 功能说明书与代码结构文档

> 生成时间：2026-04-11  
> 版本：v1.0

---

## 目录

1. [系统概述](#1-系统概述)
2. [客户端功能详解](#2-客户端功能详解)
3. [服务端功能详解](#3-服务端功能详解)
4. [同步协议规范](#4-同步协议规范)
5. [代码结构说明](#5-代码结构说明)
6. [使用指南](#6-使用指南)
7. [故障排查](#7-故障排查)

---

## 1. 系统概述

### 1.1 设计目标

TimeBlock 数据同步系统实现了一个**增量双向同步**机制，让多个客户端（Flutter App）可以通过一个中央服务端（Python Flask）同步时间块数据。核心设计原则：

- **增量同步**：只上传自上次同步以来新增/修改的数据
- **智能合并**：服务端负责解决冲突，客户端只管上传和接收补丁
- **版本管理**：每次同步递增版本号，可追溯历史变更
- **冲突隔离**：冲突数据单独存储，不影响主数据库

### 1.2 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                         客户端 (Flutter)                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  SyncConfig │  │   DataSync  │  │      Hive Database      │  │
│  │  (配置管理)  │◄─┤  (HTTP客户端)│◄─┤  (dayRecords/eventInfo) │  │
│  └──────┬──────┘  └──────┬──────┘  └─────────────────────────┘  │
│         │                │                                       │
│         └────────────────┘                                       │
│                    HTTP/JSON                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      服务端 (Python Flask)                       │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────────┐ │
│  │  app.py │  │storage.py│  │merger.py│  │   JSON 数据文件      │ │
│  │(路由入口)│◄─┤(持久化层)│◄─┤(合并逻辑)│◄─┤ timeblock_main.json │ │
│  └────┬────┘  └─────────┘  └─────────┘  │ timeblock_conflicts │ │
│       │                                  │     version.json    │ │
│       └──────────────────────────────────┴─────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 数据模型

#### 时间块 (Event Block)
每天被切分为 **96 个块**（每块 15 分钟，索引 0-95）：

```json
{
  "dayRecords": {
    "20250411": [
      [0, 7, "代码", "", ""],      // 00:00-02:00 写代码
      [32, 47, "会议", "", "周会"]   // 08:00-12:00 开会
    ]
  }
}
```

事件数组格式：`[startIndex, endIndex, eventName, type, comment]`
- `startIndex/endIndex`: 闭区间，取值范围 [0, 95]
- `eventName`: 事件类型名称（如"代码"、"休息"）
- `type`: 预留字段
- `comment`: 备注

---

## 2. 客户端功能详解

### 2.1 文件清单

| 文件路径 | 功能描述 |
|---------|---------|
| `lib/network/syncConfig.dart` | 同步配置管理（服务端地址、上次同步时间） |
| `lib/network/dataSync.dart` | HTTP 客户端，实现与服务端的通信 |
| `lib/view/editPage.dart` | 编辑页面，包含服务端配置 UI |
| `lib/view/appBarViiew.dart` | 主页面 AppBar，包含同步按钮 |

### 2.2 SyncConfig - 配置管理

**职责**：管理同步相关的持久化配置，使用 Hive 存储。

#### 存储的 Key

| Key | 类型 | 说明 |
|-----|------|------|
| `serverUrl` | String | 服务端地址，如 `http://192.168.1.100:5001` |
| `lastSyncEndDate` | String | 上次成功同步的截止日期，格式 `YYYYMMDD` |

#### 核心方法

```dart
// 初始化（在 main.dart 中调用一次）
static Future<void> init()

// 服务端地址读写
static Future<String> getServerUrl()
static Future<void> setServerUrl(String url)

// 上次同步日期读写
static Future<String?> getLastSyncEndDate()
static Future<void> setLastSyncEndDate(String date)

// 计算本次需要上传的日期范围
static Future<List<String>?> calcUploadRange({String? fallbackStartDate})
// 返回: [startDate, endDate] 或 null（无需上传）
```

#### 增量范围计算逻辑

```
if (从未同步过):
    startDate = fallbackStartDate ?? 今天
else:
    startDate = lastSyncEndDate + 1天

endDate = 今天

if (startDate > endDate): 返回 null（无需同步）
else: 返回 [startDate, endDate]
```

### 2.3 DataSync - HTTP 客户端

**职责**：封装所有与服务端的 HTTP 通信。

#### 数据结构：SyncResult

```dart
class SyncResult {
  final bool success;           // 是否成功
  final String message;         // 用户提示信息
  final int uploadedDays;       // 上传的天数
  final int patchedDays;        // 接收补丁的天数
  final int conflictDays;       // 发生冲突的天数
  final int serverVersion;      // 服务端版本号
}
```

#### 核心方法

```dart
// 测试服务端连通性（GET /ping）
Future<bool> pingServer()

// 执行完整同步流程（POST /sync）
Future<SyncResult> runFullSync({String? fallbackStartDate})
```

#### runFullSync 执行流程

```
1. 获取服务端地址，检查是否已配置
2. 调用 calcUploadRange() 计算上传范围
3. 读取 Hive 中该范围内的 dayRecords
4. 读取所有 eventInfo
5. 构造请求体，POST 到 /sync
6. 解析响应：
   - patch: 需要回填到本地的数据
   - conflictDays: 冲突统计
   - newVersion: 服务端新版本号
7. 将 patch 写入本地 Hive
8. 更新 lastSyncEndDate = 今天
9. 返回 SyncResult
```

### 2.4 UI 入口

#### EditPage（编辑页）- 第二个 Tab

- **服务端地址输入框**：填写服务端 URL
- **验证连接按钮**：调用 `pingServer()` 测试连通性
- **立即同步按钮**：调用 `runFullSync()` 执行同步

#### AppBarView（主页面）- 第一个 Tab

- **同步按钮**：右上角显示，点击调用 `runFullSync()`
- **加载状态**：同步中显示旋转动画
- **结果提示**：通过 SnackBar 显示同步结果

---

## 3. 服务端功能详解

### 3.1 文件清单

| 文件路径 | 功能描述 |
|---------|---------|
| `server/app.py` | Flask 应用入口，定义 HTTP 路由 |
| `server/storage.py` | 数据持久化层，JSON 文件读写 |
| `server/merger.py` | 核心合并逻辑，冲突检测与补丁计算 |
| `server/data/` | 运行时数据目录（自动创建） |

### 3.2 数据文件结构

服务端运行时会在 `server/data/` 目录下创建三个 JSON 文件：

#### timeblock_main.json - 主数据库

```json
{
  "eventInfo": [
    {"name": "代码", "color": {"r": 0, "g": 204, "b": 102}, "belongingTo": ""},
    {"name": "休息", "color": {"r": 255, "g": 200, "b": 100}, "belongingTo": ""}
  ],
  "dayRecords": {
    "20250410": [[0, 7, "代码", "", ""]],
    "20250411": [[8, 15, "会议", "", ""]]
  },
  "lastUpdated": "2026-04-11T12:00:00"
}
```

#### timeblock_conflicts.json - 冲突库

```json
{
  "20250410": [
    {
      "from": "flutter-client",
      "clientTime": "2026-04-11T10:00:00",
      "serverTime": "2026-04-11T10:00:05",
      "events": [[4, 10, "会议", "", "冲突测试"]]
    }
  ]
}
```

#### version.json - 版本信息

```json
{
  "currentVersion": 42,
  "history": [
    {
      "version": 42,
      "time": "2026-04-11T12:00:00",
      "changedDates": ["20250410", "20250411"]
    }
  ]
}
```

### 3.3 API 接口

#### GET /ping - 连通性检测

**响应**：
```json
{
  "status": "ok",
  "server": "TimeBlock Sync Server",
  "time": "2026-04-11T12:00:00",
  "currentVersion": 42
}
```

#### POST /sync - 核心同步接口

**请求体**：
```json
{
  "eventInfo": [...],           // 全量 eventInfo（可选）
  "dayRecords": {               // 增量 dayRecords
    "20250410": [[0, 7, "代码", "", ""]]
  },
  "uploadRange": ["20250408", "20250411"],  // 声明的上传范围
  "clientTime": "2026-04-11T10:00:00",
  "clientId": "flutter-client"
}
```

**响应体**：
```json
{
  "message": "同步成功：处理 2 天，冲突 0 天，回填补丁 1 天",
  "newVersion": 43,
  "mergedDays": 2,
  "conflictDays": 0,
  "patch": {
    "20250409": [[16, 23, "运动", "", ""]]
  }
}
```

#### GET /data - 数据摘要（调试）

返回主数据库的统计信息，用于调试。

#### GET /conflicts - 冲突记录（调试）

返回所有冲突记录的摘要，用于调试。

### 3.4 合并逻辑 (merger.py)

#### 冲突检测

两个事件冲突的条件：时间块区间重叠（闭区间比较）

```python
def events_overlap(a, b) -> bool:
    return not (a[1] < b[0] or b[1] < a[0])
```

#### 单日合并流程

```
对于客户端上传的每一天：
  1. 构建服务端已占用的时间块集合
  2. 遍历客户端事件：
     - 如果事件的所有块都不在服务端集合中 → 不冲突，写入主库
     - 否则 → 冲突，写入冲突库
  3. 返回 (merged_events, conflict_events)
```

#### 补丁计算

```
在 uploadRange 范围内枚举每一天：
  如果该天客户端未上传 且 服务端有数据：
    将该天数据加入 patch
返回 patch
```

### 3.5 持久化安全 (storage.py)

#### 原子写入

```python
def _atomic_write(path: Path, data: dict):
    # 1. 先写入临时文件
    # 2. 用 shutil.move 原子替换目标文件
    # 避免写入中断导致文件损坏
```

#### 自动备份

每次保存主数据前，自动复制 `.bak.json` 备份。

---

## 4. 同步协议规范

### 4.1 时序图

```
客户端                                    服务端
  │                                         │
  │  1. 计算 uploadRange                    │
  │     [lastSyncEndDate+1, today]          │
  │                                         │
  │  2. 读取 Hive 中该范围的 dayRecords     │
  │                                         │
  │  3. POST /sync                          │
  │     {                                   │
  │       dayRecords: {...},                │
  │       uploadRange: ["20250408","20250411"],
  │       eventInfo: [...]                  │
  │     }                                   │
  │────────────────────────────────────────>│
  │                                         │
  │                                         │  4. 逐天合并
  │                                         │     - 不冲突 → 主库
  │                                         │     - 冲突 → 冲突库
  │                                         │
  │                                         │  5. 计算 patch
  │                                         │     (范围内空缺的天)
  │                                         │
  │                                         │  6. 递增版本号
  │                                         │
  │  7. 响应 {                              │
  │       patch: {...},                     │
  │       newVersion: 43,                   │
  │       conflictDays: 0                   │
  │     }                                   │
  │<────────────────────────────────────────│
  │                                         │
  │  8. 将 patch 写入 Hive                  │
  │                                         │
  │  9. 更新 lastSyncEndDate = today        │
  │                                         │
```

### 4.2 冲突处理规则

| 场景 | 处理方式 |
|------|---------|
| 客户端 block 与服务端 block 不重叠 | 直接合并到主库 |
| 客户端 block 与服务端 block 重叠 | 客户端 block 写入冲突库，主库不变 |
| 同一客户端多次上传同一天 | 以最后一次为准（覆盖） |
| 多客户端上传同一天冲突 block | 先到的入主库，后到的入冲突库 |

### 4.3 版本号规则

- 初始版本号为 0
- 每次有数据变更（mergedDays > 0）时递增
- 纯查询（如只传了 eventInfo 没有 dayRecords）不递增
- 版本历史保留最近 200 条

---

## 5. 代码结构说明

### 5.1 客户端目录结构

```
lib/
├── network/
│   ├── syncConfig.dart      # 配置管理类
│   └── dataSync.dart        # HTTP 客户端类
├── view/
│   ├── editPage.dart        # 编辑页面（含同步配置 UI）
│   └── appBarViiew.dart     # 主页面 AppBar（含同步按钮）
└── main.dart                # 应用入口，初始化 SyncConfig
```

### 5.2 服务端目录结构

```
server/
├── app.py                   # Flask 应用入口
├── storage.py               # 数据持久化模块
├── merger.py                # 合并逻辑模块
├── requirements.txt         # Python 依赖
├── README.md                # 服务端说明
└── data/                    # 运行时数据目录（自动创建）
    ├── timeblock_main.json
    ├── timeblock_conflicts.json
    └── version.json
```

### 5.3 关键类/函数对照表

#### 客户端

| 类/函数 | 所在文件 | 功能 |
|--------|---------|------|
| `SyncConfig` | syncConfig.dart | 配置管理，Hive 封装 |
| `SyncConfig.init()` | syncConfig.dart | 初始化 Hive box |
| `SyncConfig.calcUploadRange()` | syncConfig.dart | 计算增量范围 |
| `DataSync` | dataSync.dart | HTTP 客户端 |
| `DataSync.pingServer()` | dataSync.dart | 测试连通性 |
| `DataSync.runFullSync()` | dataSync.dart | 执行完整同步 |
| `SyncResult` | dataSync.dart | 同步结果数据结构 |

#### 服务端

| 函数 | 所在文件 | 功能 |
|-----|---------|------|
| `ping()` | app.py | /ping 路由 |
| `sync()` | app.py | /sync 路由（核心） |
| `load_main()` | storage.py | 加载主数据库 |
| `save_main()` | storage.py | 保存主数据库（原子写入+备份） |
| `append_conflict()` | storage.py | 追加冲突记录 |
| `bump_version()` | storage.py | 递增版本号 |
| `merge_day()` | merger.py | 单日数据合并 |
| `find_missing_for_client()` | merger.py | 计算客户端补丁 |

---

## 6. 使用指南

### 6.1 启动服务端

```bash
cd ~/Downloads/time_block/server
python3 app.py

# 自定义端口（macOS 5000 被 AirPlay 占用）
PORT=8888 python3 app.py
```

启动后会显示本机局域网地址：
```
=======================================================
  TimeBlock Sync Server
  本机局域网地址: http://192.168.1.100:5001
  在客户端"服务端地址"栏填入上方地址即可
=======================================================
```

### 6.2 配置客户端

1. 打开 App，切换到第二个 Tab（画笔图标）
2. 在"数据备份 / 同步"卡片中填入服务端地址
3. 点击"验证连接"测试连通性
4. 回到第一个 Tab，点击右上角"同步"按钮

### 6.3 首次同步

首次同步时，`lastSyncEndDate` 为 null，系统会使用 `fallbackStartDate`（默认为今天）。

如果要同步历史数据，可以在调用 `runFullSync()` 时传入：

```dart
// 从 2025-01-01 开始同步到今天
await DataSync().runFullSync(fallbackStartDate: '20250101');
```

### 6.4 日常同步

日常使用时，只需点击"同步"按钮，系统会自动：
1. 计算上次同步截止日期次日 → 今天的范围
2. 上传该范围内的本地数据
3. 接收服务端返回的补丁（如果有）
4. 更新 lastSyncEndDate

---

## 7. 故障排查

### 7.1 常见问题

| 问题 | 可能原因 | 解决方案 |
|------|---------|---------|
| "未配置服务端地址" | serverUrl 为空 | 在编辑页填写服务端地址 |
| "无法连接服务端" | 服务端未启动或网络不通 | 检查服务端是否运行，防火墙设置 |
| "SyncConfig not initialized" | Hive 未初始化 | 确保 main.dart 中调用了 `SyncConfig.init()` |
| 同步后数据丢失 | 冲突导致数据进入冲突库 | 检查服务端 `timeblock_conflicts.json` |

### 7.2 调试接口

```bash
# 测试连通性
curl http://192.168.1.100:5001/ping

# 查看数据摘要
curl http://192.168.1.100:5001/data

# 查看冲突记录
curl http://192.168.1.100:5001/conflicts
```

### 7.3 数据备份

服务端数据文件位于 `server/data/` 目录，建议定期备份：

```bash
# 备份
cp -r server/data server/data.backup.$(date +%Y%m%d)

# 恢复
cp server/data.backup.20250411/timeblock_main.json server/data/
```

---

## 附录：变更日志

| 日期 | 版本 | 变更内容 |
|------|------|---------|
| 2026-04-11 | v1.0 | 初始版本，实现增量双向同步、版本管理、冲突隔离 |

---

*文档结束*
