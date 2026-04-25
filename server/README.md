# TimeBlock 同步服务端

## 目录结构

```
server/
├── app.py          # Flask 主入口，定义所有 HTTP 路由
├── storage.py      # 数据持久化层（主数据库、冲突库、版本信息）
├── merger.py       # 核心合并逻辑（冲突检测、缺失回填）
├── requirements.txt
├── README.md
└── data/           # 运行时自动创建，存放 JSON 数据文件
    ├── timeblock_main.json      # 主数据库
    ├── timeblock_conflicts.json # 冲突记录库
    └── version.json             # 版本历史
```

## 启动

```bash
cd server/
pip install -r requirements.txt
python app.py

# 自定义端口
PORT=8888 python app.py
```

## 接口说明

| 方法 | 路径 | 说明 |
|------|------|------|
| GET  | `/ping`      | 连通性检测，返回服务端版本号 |
| POST | `/sync`      | 上传增量数据并接收补丁 |
| GET  | `/data`      | 查看数据摘要（调试） |
| GET  | `/conflicts` | 查看冲突记录（调试） |

## 同步协议

### POST /sync 请求体

```json
{
  "eventInfo": [...],
  "dayRecords": {
    "20250101": [[0, 7, "睡觉", "", ""], [32, 47, "工作", "", ""]],
    "20250102": []
  },
  "uploadRange": ["20250101", "20250410"],
  "clientTime": "2025-04-11T10:00:00",
  "clientId": "my-macbook"
}
```

- `dayRecords`：本次上传的日期 → 事件数组
- `uploadRange`：上次同步到本次同步之间的日期范围（用于服务端判断哪些天客户端有空缺）
- `clientId`：可选，用于冲突记录溯源

### POST /sync 响应体

```json
{
  "message": "同步成功：处理 10 天，冲突 1 天，回填补丁 2 天",
  "newVersion": 43,
  "mergedDays": 10,
  "conflictDays": 1,
  "patch": {
    "20250105": [[0, 3, "早起", "", ""]],
    "20250107": [[40, 55, "锻炼", "", ""]]
  }
}
```

- `patch`：服务端发现客户端在 `uploadRange` 内缺失的数据，客户端收到后写入本地

## 合并规则

1. 对于客户端上传的每一天，与服务端主数据逐 block 对比：
   - **不冲突**的 block → 直接写入主数据库
   - **冲突**（同一时间块被主数据和客户端数据都占用）→ 写入冲突库，不覆盖主数据库
2. 在 `uploadRange` 范围内，客户端未上传的天，若服务端有记录 → 作为补丁返回客户端
