"""
storage.py — 数据持久化层（SQLite 版）

数据库表结构
──────────────────────────────────────────────────
event_info      事件类型配置
  id            INTEGER  PRIMARY KEY AUTOINCREMENT
  name          TEXT     UNIQUE NOT NULL          -- 唯一键
  color_r       INTEGER  NOT NULL DEFAULT 128
  color_g       INTEGER  NOT NULL DEFAULT 128
  color_b       INTEGER  NOT NULL DEFAULT 128
  belonging_to  TEXT     NOT NULL DEFAULT ''
  sort_order    INTEGER  NOT NULL DEFAULT 0       -- 客户端上传的顺序

day_records     主时间块数据（每天一行）
  date_key      TEXT     PRIMARY KEY              -- "YYYYMMDD"
  events_json   TEXT     NOT NULL                 -- JSON 序列化后的 [[s,e,ev,t,c], ...]
  updated_at    TEXT     NOT NULL

conflicts       冲突记录（每条冲突一行）
  id            INTEGER  PRIMARY KEY AUTOINCREMENT
  date_key      TEXT     NOT NULL
  client_id     TEXT     NOT NULL DEFAULT 'unknown'
  client_time   TEXT     NOT NULL
  server_time   TEXT     NOT NULL
  events_json   TEXT     NOT NULL                 -- 冲突事件列表 JSON

version         版本历史（每次 bump 一行）
  id            INTEGER  PRIMARY KEY AUTOINCREMENT
  version       INTEGER  NOT NULL
  changed_at    TEXT     NOT NULL
  changed_dates TEXT     NOT NULL                 -- JSON 数组字符串

meta            全局元信息（key-value）
  key           TEXT     PRIMARY KEY
  value         TEXT     NOT NULL
──────────────────────────────────────────────────

对外接口与原 JSON 版保持完全兼容，app.py 无需修改。
"""

import json
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

# ─────────────────────────────────────────────
# 数据库路径
# ─────────────────────────────────────────────

DATA_DIR = Path(__file__).parent / 'data'
DB_PATH  = DATA_DIR / 'timeblock.db'

# 线程本地存储，确保每个线程有自己的连接（Flask 多线程安全）
_local = threading.local()


def _get_conn() -> sqlite3.Connection:
    """获取当前线程的数据库连接，不存在则新建并初始化。"""
    if not hasattr(_local, 'conn') or _local.conn is None:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(DB_PATH), check_same_thread=False)
        conn.row_factory = sqlite3.Row
        # 开启 WAL 模式：并发读写性能更好，崩溃安全
        conn.execute('PRAGMA journal_mode=WAL')
        conn.execute('PRAGMA foreign_keys=ON')
        _local.conn = conn
        _init_tables(conn)
    return _local.conn


@contextmanager
def _db():
    """事务上下文管理器，自动 commit / rollback。"""
    conn = _get_conn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise


# ─────────────────────────────────────────────
# 建表 & 迁移
# ─────────────────────────────────────────────

def _init_tables(conn: sqlite3.Connection):
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS event_info (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            name         TEXT    UNIQUE NOT NULL,
            color_r      INTEGER NOT NULL DEFAULT 128,
            color_g      INTEGER NOT NULL DEFAULT 128,
            color_b      INTEGER NOT NULL DEFAULT 128,
            belonging_to TEXT    NOT NULL DEFAULT '',
            sort_order   INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS day_records (
            date_key    TEXT PRIMARY KEY,
            events_json TEXT NOT NULL DEFAULT '[]',
            updated_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS conflicts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            date_key    TEXT    NOT NULL,
            client_id   TEXT    NOT NULL DEFAULT 'unknown',
            client_time TEXT    NOT NULL,
            server_time TEXT    NOT NULL,
            events_json TEXT    NOT NULL DEFAULT '[]'
        );
        CREATE INDEX IF NOT EXISTS idx_conflicts_date ON conflicts(date_key);

        CREATE TABLE IF NOT EXISTS version (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            version_num   INTEGER NOT NULL,
            changed_at    TEXT    NOT NULL,
            changed_dates TEXT    NOT NULL DEFAULT '[]'
        );

        CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sync_log (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            client_id       TEXT    NOT NULL DEFAULT 'unknown',
            client_time     TEXT    NOT NULL,
            server_time     TEXT    NOT NULL,
            range_start     TEXT    NOT NULL DEFAULT '',
            range_end       TEXT    NOT NULL DEFAULT '',
            uploaded_dates  TEXT    NOT NULL DEFAULT '[]',
            merged_days     INTEGER NOT NULL DEFAULT 0,
            conflict_days   INTEGER NOT NULL DEFAULT 0,
            patch_days      INTEGER NOT NULL DEFAULT 0,
            new_version     INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_sync_log_client ON sync_log(client_id);
        CREATE INDEX IF NOT EXISTS idx_sync_log_time   ON sync_log(server_time);
    """)
    conn.commit()


# ─────────────────────────────────────────────
# event_info — 事件类型
# ─────────────────────────────────────────────

def _rows_to_event_info_list(rows) -> list[dict]:
    """将数据库行转换为 eventInfo 字典列表（与 JSON 版格式一致）。"""
    result = []
    for row in rows:
        result.append({
            'name': row['name'],
            'color': {
                'r': row['color_r'],
                'g': row['color_g'],
                'b': row['color_b'],
            },
            'belongingTo': row['belonging_to'],
        })
    return result


def get_all_event_info() -> list[dict]:
    """返回所有事件类型，按 sort_order 升序排列。"""
    with _db() as conn:
        rows = conn.execute(
            'SELECT * FROM event_info ORDER BY sort_order ASC, id ASC'
        ).fetchall()
    return _rows_to_event_info_list(rows)


def upsert_event_info_list(client_list: list[dict]) -> list[str]:
    """
    以 name 为唯一键，将客户端上传的 eventInfo 列表 upsert 到数据库。
    - 客户端有 → 覆盖（包括颜色）
    - 服务端独有 → 保留
    返回有颜色变化的条目名称列表（用于日志）。
    """
    color_changed: list[str] = []

    with _db() as conn:
        for order_idx, ci in enumerate(client_list):
            name = ci.get('name', '')
            if not name:
                continue
            color = ci.get('color', {})
            r = color.get('r', 128)
            g = color.get('g', 128)
            b = color.get('b', 128)
            belonging = ci.get('belongingTo', '')

            # 检查颜色是否有变化
            existing = conn.execute(
                'SELECT color_r, color_g, color_b FROM event_info WHERE name = ?',
                (name,)
            ).fetchone()
            if existing and (existing['color_r'] != r or
                             existing['color_g'] != g or
                             existing['color_b'] != b):
                color_changed.append(
                    f"{name}: rgb({existing['color_r']},{existing['color_g']},{existing['color_b']})"
                    f" → rgb({r},{g},{b})"
                )

            conn.execute("""
                INSERT INTO event_info (name, color_r, color_g, color_b, belonging_to, sort_order)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(name) DO UPDATE SET
                    color_r      = excluded.color_r,
                    color_g      = excluded.color_g,
                    color_b      = excluded.color_b,
                    belonging_to = excluded.belonging_to,
                    sort_order   = excluded.sort_order
            """, (name, r, g, b, belonging, order_idx))

    return color_changed


# ─────────────────────────────────────────────
# day_records — 主时间块数据
# ─────────────────────────────────────────────

def get_day_records(date_keys: list[str] | None = None) -> dict[str, list]:
    """
    获取时间块数据。
    - date_keys=None → 返回全部
    - date_keys=[...] → 只返回指定日期
    返回格式：{ "YYYYMMDD": [[s,e,ev,t,c], ...], ... }
    """
    with _db() as conn:
        if date_keys is None:
            rows = conn.execute('SELECT date_key, events_json FROM day_records').fetchall()
        else:
            if not date_keys:
                return {}
            placeholders = ','.join('?' * len(date_keys))
            rows = conn.execute(
                f'SELECT date_key, events_json FROM day_records WHERE date_key IN ({placeholders})',
                date_keys
            ).fetchall()

    return {row['date_key']: json.loads(row['events_json']) for row in rows}


def upsert_day_record(date_key: str, events: list) -> None:
    """写入或更新单天的时间块数据。"""
    with _db() as conn:
        conn.execute("""
            INSERT INTO day_records (date_key, events_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(date_key) DO UPDATE SET
                events_json = excluded.events_json,
                updated_at  = excluded.updated_at
        """, (date_key, json.dumps(events, ensure_ascii=False), datetime.now().isoformat()))


def upsert_day_records_bulk(records: dict[str, list]) -> None:
    """批量写入多天数据（在单个事务内完成，性能更好）。"""
    now = datetime.now().isoformat()
    with _db() as conn:
        conn.executemany("""
            INSERT INTO day_records (date_key, events_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(date_key) DO UPDATE SET
                events_json = excluded.events_json,
                updated_at  = excluded.updated_at
        """, [
            (dk, json.dumps(evts, ensure_ascii=False), now)
            for dk, evts in records.items()
        ])


def get_day_record_dates() -> list[str]:
    """返回所有有记录的日期列表，升序。"""
    with _db() as conn:
        rows = conn.execute('SELECT date_key FROM day_records ORDER BY date_key ASC').fetchall()
    return [row['date_key'] for row in rows]


# ─────────────────────────────────────────────
# conflicts — 冲突记录
# ─────────────────────────────────────────────

def append_conflict(date_key: str, conflict_entry: dict) -> None:
    """
    追加一条冲突记录。
    conflict_entry 格式：{ 'from': str, 'clientTime': str, 'serverTime': str, 'events': list }
    """
    with _db() as conn:
        conn.execute("""
            INSERT INTO conflicts (date_key, client_id, client_time, server_time, events_json)
            VALUES (?, ?, ?, ?, ?)
        """, (
            date_key,
            conflict_entry.get('from', 'unknown'),
            conflict_entry.get('clientTime', ''),
            conflict_entry.get('serverTime', datetime.now().isoformat()),
            json.dumps(conflict_entry.get('events', []), ensure_ascii=False),
        ))


def get_conflict_dates() -> list[str]:
    """返回存在冲突记录的所有日期（去重，升序）。"""
    with _db() as conn:
        rows = conn.execute(
            'SELECT DISTINCT date_key FROM conflicts ORDER BY date_key ASC'
        ).fetchall()
    return [row['date_key'] for row in rows]


def get_all_conflicts() -> dict[str, list[dict]]:
    """
    返回全部冲突记录，格式与 JSON 版一致：
    { "YYYYMMDD": [ { "from": ..., "serverTime": ..., "events": [...] }, ... ] }
    """
    with _db() as conn:
        rows = conn.execute(
            'SELECT date_key, client_id, client_time, server_time, events_json '
            'FROM conflicts ORDER BY date_key ASC, id ASC'
        ).fetchall()

    result: dict[str, list[dict]] = {}
    for row in rows:
        entry = {
            'from': row['client_id'],
            'clientTime': row['client_time'],
            'serverTime': row['server_time'],
            'events': json.loads(row['events_json']),
        }
        result.setdefault(row['date_key'], []).append(entry)
    return result


# ─────────────────────────────────────────────
# version — 版本管理
# ─────────────────────────────────────────────

def get_current_version() -> int:
    """返回当前版本号（无记录时返回 0）。"""
    with _db() as conn:
        row = conn.execute(
            'SELECT version_num FROM version ORDER BY id DESC LIMIT 1'
        ).fetchone()
    return row['version_num'] if row else 0


def bump_version(changed_dates: list[str]) -> int:
    """
    递增版本号，记录本次变更的日期列表，返回新版本号。
    只保留最近 200 条历史防止无限增长。
    """
    with _db() as conn:
        # 获取当前版本
        row = conn.execute(
            'SELECT version_num FROM version ORDER BY id DESC LIMIT 1'
        ).fetchone()
        new_ver = (row['version_num'] + 1) if row else 1

        conn.execute("""
            INSERT INTO version (version_num, changed_at, changed_dates)
            VALUES (?, ?, ?)
        """, (new_ver, datetime.now().isoformat(), json.dumps(sorted(changed_dates))))

        # 保留最近 200 条
        conn.execute("""
            DELETE FROM version WHERE id NOT IN (
                SELECT id FROM version ORDER BY id DESC LIMIT 200
            )
        """)

    return new_ver


def get_version_history(limit: int = 50) -> list[dict]:
    """返回最近 N 条版本历史（用于调试/展示）。"""
    with _db() as conn:
        rows = conn.execute(
            'SELECT version_num, changed_at, changed_dates '
            'FROM version ORDER BY id DESC LIMIT ?',
            (limit,)
        ).fetchall()
    return [
        {
            'version': row['version_num'],
            'time': row['changed_at'],
            'changedDates': json.loads(row['changed_dates']),
        }
        for row in rows
    ]


# ─────────────────────────────────────────────
# meta — 全局元信息
# ─────────────────────────────────────────────

def get_meta(key: str, default: str = '') -> str:
    with _db() as conn:
        row = conn.execute('SELECT value FROM meta WHERE key = ?', (key,)).fetchone()
    return row['value'] if row else default


def set_meta(key: str, value: str) -> None:
    with _db() as conn:
        conn.execute("""
            INSERT INTO meta (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, (key, value))


# ─────────────────────────────────────────────
# 兼容旧接口（供 app.py 调用，行为与 JSON 版一致）
# ─────────────────────────────────────────────

def load_main() -> dict:
    """
    [兼容接口] 返回与原 JSON 版格式完全相同的主数据结构：
    { 'eventInfo': [...], 'dayRecords': {...}, 'lastUpdated': '...' }
    """
    return {
        'eventInfo':   get_all_event_info(),
        'dayRecords':  get_day_records(),
        'lastUpdated': get_meta('last_updated', ''),
    }


def save_main(data: dict) -> None:
    """
    [兼容接口] 接受与原 JSON 版完全相同的结构并拆分写入各表。
    调用方无需修改，直接替换 JSON 版即可。
    """
    # eventInfo 由 upsert_event_info_list 管理，这里仅处理 dayRecords
    day_records: dict = data.get('dayRecords', {})
    if day_records:
        upsert_day_records_bulk(day_records)

    last_updated = data.get('lastUpdated', datetime.now().isoformat())
    set_meta('last_updated', last_updated)


def load_conflicts() -> dict:
    """[兼容接口] 返回与原 JSON 版格式完全相同的冲突记录字典。"""
    return get_all_conflicts()


def load_version_info() -> dict:
    """[兼容接口] 返回与原 JSON 版格式兼容的版本信息字典。"""
    return {
        'currentVersion': get_current_version(),
        'history': get_version_history(),
    }


# ─────────────────────────────────────────────
# sync_log — 同步操作日志
# ─────────────────────────────────────────────

def append_sync_log(entry: dict) -> None:
    """
    追加一条同步日志记录。

    entry 字段说明：
      client_id      str   — 客户端设备标识
      client_time    str   — 客户端本地时间（ISO8601）
      server_time    str   — 服务端处理时间（ISO8601）
      range_start    str   — 上传数据起始日期（YYYYMMDD）
      range_end      str   — 上传数据截止日期（YYYYMMDD）
      uploaded_dates list  — 实际上传的日期列表
      merged_days    int   — 成功合并的天数
      conflict_days  int   — 发生冲突的天数
      patch_days     int   — 回填给客户端的补丁天数
      new_version    int   — 本次同步后的版本号
    """
    with _db() as conn:
        conn.execute("""
            INSERT INTO sync_log
              (client_id, client_time, server_time,
               range_start, range_end, uploaded_dates,
               merged_days, conflict_days, patch_days, new_version)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            entry.get('client_id', 'unknown'),
            entry.get('client_time', ''),
            entry.get('server_time', datetime.now().isoformat()),
            entry.get('range_start', ''),
            entry.get('range_end', ''),
            json.dumps(sorted(entry.get('uploaded_dates', [])), ensure_ascii=False),
            int(entry.get('merged_days', 0)),
            int(entry.get('conflict_days', 0)),
            int(entry.get('patch_days', 0)),
            int(entry.get('new_version', 0)),
        ))

    # 只保留最近 1000 条，防止无限增长
    with _db() as conn:
        conn.execute("""
            DELETE FROM sync_log WHERE id NOT IN (
                SELECT id FROM sync_log ORDER BY id DESC LIMIT 1000
            )
        """)


def get_sync_log(limit: int = 100, client_id: str | None = None) -> list[dict]:
    """
    查询同步日志。
    - limit    : 返回最近 N 条（默认 100）
    - client_id: 若指定，则只返回该设备的记录
    """
    with _db() as conn:
        if client_id:
            rows = conn.execute(
                """SELECT id, client_id, client_time, server_time,
                          range_start, range_end, uploaded_dates,
                          merged_days, conflict_days, patch_days, new_version
                   FROM sync_log WHERE client_id = ?
                   ORDER BY id DESC LIMIT ?""",
                (client_id, limit)
            ).fetchall()
        else:
            rows = conn.execute(
                """SELECT id, client_id, client_time, server_time,
                          range_start, range_end, uploaded_dates,
                          merged_days, conflict_days, patch_days, new_version
                   FROM sync_log ORDER BY id DESC LIMIT ?""",
                (limit,)
            ).fetchall()

    return [
        {
            'id':            row['id'],
            'clientId':      row['client_id'],
            'clientTime':    row['client_time'],
            'serverTime':    row['server_time'],
            'rangeStart':    row['range_start'],
            'rangeEnd':      row['range_end'],
            'uploadedDates': json.loads(row['uploaded_dates']),
            'mergedDays':    row['merged_days'],
            'conflictDays':  row['conflict_days'],
            'patchDays':     row['patch_days'],
            'newVersion':    row['new_version'],
        }
        for row in rows
    ]


def get_sync_log_summary() -> dict:
    """
    返回各客户端的同步统计摘要：
    总次数、最近一次同步时间、累计上传天数等。
    """
    with _db() as conn:
        rows = conn.execute("""
            SELECT client_id,
                   COUNT(*)         AS total_syncs,
                   MAX(server_time) AS last_sync_time,
                   SUM(merged_days) AS total_merged_days,
                   MAX(new_version) AS latest_version
            FROM sync_log
            GROUP BY client_id
            ORDER BY last_sync_time DESC
        """).fetchall()

    return {
        row['client_id']: {
            'totalSyncs':       row['total_syncs'],
            'lastSyncTime':     row['last_sync_time'],
            'totalMergedDays':  row['total_merged_days'],
            'latestVersion':    row['latest_version'],
        }
        for row in rows
    }
