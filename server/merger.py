"""
merger.py — 核心数据合并逻辑

规则（与客户端约定）：
  每天的时间被切成 96 个块（每块 15 分钟），block 用 [startIdx, endIdx, event, type, comment] 表示，
  startIdx/endIdx 是闭区间，取值范围 [0, 95]。

合并策略：
  1. 对于客户端上传的每一天：
     a. 与主数据库该天的已有 block 对比，找出占用了相同时间块（重叠）的 block → 冲突
     b. 不冲突的部分直接写入主数据库
     c. 冲突部分写入冲突库（不改变主数据库）
  2. 对于客户端上传范围内主数据库中存在但客户端未上传（空缺）的天：
     这些天的数据作为"补丁"返回给客户端，让客户端写入补全
"""

from typing import TypeAlias

# 单条事件 = [startIndex, endIndex, event, type, comment]
Event: TypeAlias = list


# ─────────────────────────────────────────────
# 工具函数
# ─────────────────────────────────────────────

def events_overlap(a: Event, b: Event) -> bool:
    """判断两个事件（时间块区间）是否存在重叠（startIdx/endIdx 均为闭区间）"""
    return not (a[1] < b[0] or b[1] < a[0])


def build_occupied_set(events: list[Event]) -> set[int]:
    """把一组事件展开为「已被占用的时间块索引」集合"""
    occupied: set[int] = set()
    for ev in events:
        for i in range(ev[0], ev[1] + 1):
            occupied.add(i)
    return occupied


# ─────────────────────────────────────────────
# 主合并函数
# ─────────────────────────────────────────────

def merge_day(
    date_key: str,
    client_events: list[Event],
    server_events: list[Event],
) -> tuple[list[Event], list[Event]]:
    """
    合并单天数据。

    参数：
      date_key      -- 日期字符串，如 "20250101"（仅用于日志）
      client_events -- 客户端上传的该天事件列表
      server_events -- 服务端主数据库中该天已有的事件列表

    返回：
      (merged_events, conflict_events)
      - merged_events  : 应写入主数据库的事件列表（主数据不变 + 客户端不冲突部分）
      - conflict_events: 存在冲突的客户端事件列表（写入冲突库）
    """
    # 已被服务端主数据占用的时间块
    server_occupied = build_occupied_set(server_events)

    non_conflict: list[Event] = []
    conflict: list[Event] = []

    for ev in client_events:
        # 检查该事件的每个块是否都不在服务端已占用集合里
        ev_blocks = set(range(ev[0], ev[1] + 1))
        if ev_blocks.isdisjoint(server_occupied):
            # 完全不冲突 → 直接写入主数据库，并更新 server_occupied
            non_conflict.append(ev)
            server_occupied.update(ev_blocks)
        else:
            # 存在冲突 → 放入冲突库
            conflict.append(ev)

    # 最终主数据 = 原有服务端数据 + 不冲突的客户端数据，按 startIndex 排序
    merged = sorted(server_events + non_conflict, key=lambda e: e[0])
    return merged, conflict


# ─────────────────────────────────────────────
# 计算客户端需要补全的数据
# ─────────────────────────────────────────────

def find_missing_for_client(
    upload_date_range: list[str],
    client_uploaded_dates: set[str],
    server_day_records: dict[str, list[Event]],
    client_day_records: dict[str, list[Event]] | None = None,
) -> dict[str, list[Event]]:
    """
    在客户端上传的日期范围内，找出需要回填给客户端的数据。

    回填规则（满足任一即回填）：
      1. 客户端没有上传这一天，但服务端有数据（经典补丁场景：B 拉 A 的历史数据）
      2. 客户端上传了这一天，但合并后服务端的事件数量 > 客户端上传的事件数量
         （多客户端叠加场景：A 和 B 同天有不同时间段的事件，合并后 B 要拿到 A 的部分）

    参数：
      upload_date_range    -- 客户端声明的上传范围 ["20250101", "20250131"]（首尾日期字符串）
      client_uploaded_dates-- 客户端实际上传了的日期集合
      server_day_records   -- 合并后的服务端主数据库（已经把客户端数据写入了）
      client_day_records   -- 客户端上传的原始数据（用于对比合并前后的事件数量），可为 None

    返回：
      { "20250105": [[...], ...], ... }  需要下发给客户端的数据
    """
    if len(upload_date_range) < 2:
        return {}

    start_str, end_str = upload_date_range[0], upload_date_range[1]

    # 枚举范围内所有日期
    from datetime import date, timedelta
    try:
        start_date = date(int(start_str[:4]), int(start_str[4:6]), int(start_str[6:]))
        end_date   = date(int(end_str[:4]),   int(end_str[4:6]),   int(end_str[6:]))
    except Exception:
        return {}

    patch: dict[str, list[Event]] = {}
    cur = start_date
    while cur <= end_date:
        d = f"{cur.year}{cur.month:02d}{cur.day:02d}"
        server_events = server_day_records.get(d, [])

        if d not in client_uploaded_dates:
            # 规则1：客户端没上传这一天，服务端有数据 → 回填
            if server_events:
                patch[d] = server_events
        else:
            # 规则2：客户端上传了，但合并后服务端有更多事件 → 回填完整合并结果
            client_events = (client_day_records or {}).get(d, [])
            if len(server_events) > len(client_events):
                patch[d] = server_events

        cur += timedelta(days=1)

    return patch
