#!/usr/bin/env python3
"""
migrate.py — 将旧版 JSON 数据迁移至 SQLite 数据库

用法：
    cd server/
    python migrate.py               # 迁移后保留 JSON 文件（推荐先用这个）
    python migrate.py --delete-json # 迁移成功后删除旧 JSON 文件

迁移内容：
    data/timeblock_main.json  → event_info 表 + day_records 表 + meta 表
    data/timeblock_conflicts.json → conflicts 表
    data/version.json         → version 表

幂等性：可多次运行，已存在的记录会被覆盖更新，不会重复插入。
"""

import json
import sys
import shutil
from pathlib import Path
from datetime import datetime

# 确保可以导入同目录的 storage 模块
sys.path.insert(0, str(Path(__file__).parent))

from storage import (
    DATA_DIR,
    DB_PATH,
    _get_conn,
    _db,
    upsert_event_info_list,
    upsert_day_records_bulk,
    append_conflict,
    get_current_version,
    set_meta,
    _init_tables,
)

MAIN_FILE     = DATA_DIR / 'timeblock_main.json'
CONFLICT_FILE = DATA_DIR / 'timeblock_conflicts.json'
VERSION_FILE  = DATA_DIR / 'version.json'


def _load_json(path: Path, default):
    if not path.exists():
        return default
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f'  [WARN] 读取 {path.name} 失败: {e}')
        return default


def migrate_main(data: dict) -> tuple[int, int]:
    """迁移 eventInfo 和 dayRecords，返回 (event_count, day_count)。"""
    event_info = data.get('eventInfo', [])
    day_records = data.get('dayRecords', {})
    last_updated = data.get('lastUpdated', datetime.now().isoformat())

    if event_info:
        upsert_event_info_list(event_info)
        print(f'  ✓ event_info: 写入 {len(event_info)} 条')

    if day_records:
        upsert_day_records_bulk(day_records)
        print(f'  ✓ day_records: 写入 {len(day_records)} 天')

    set_meta('last_updated', last_updated)

    return len(event_info), len(day_records)


def migrate_conflicts(data: dict) -> int:
    """迁移冲突记录，返回写入条数。"""
    total = 0
    for date_key, entries in data.items():
        for entry in entries:
            append_conflict(date_key, entry)
            total += 1
    print(f'  ✓ conflicts: 写入 {total} 条（跨 {len(data)} 天）')
    return total


def migrate_versions(data: dict) -> int:
    """迁移版本历史，返回写入条数。"""
    history = data.get('history', [])
    if not history:
        # 若没有历史，但有 currentVersion，补写一条占位记录
        cur_ver = data.get('currentVersion', 0)
        if cur_ver > 0:
            with _db() as conn:
                conn.execute(
                    'INSERT OR IGNORE INTO version (version_num, changed_at, changed_dates) VALUES (?, ?, ?)',
                    (cur_ver, datetime.now().isoformat(), '[]')
                )
            print(f'  ✓ version: 写入占位版本 {cur_ver}')
            return 1
        return 0

    with _db() as conn:
        for entry in history:
            conn.execute("""
                INSERT INTO version (version_num, changed_at, changed_dates)
                VALUES (?, ?, ?)
            """, (
                entry.get('version', 0),
                entry.get('time', datetime.now().isoformat()),
                json.dumps(entry.get('changedDates', []))
            ))
    print(f'  ✓ version: 写入 {len(history)} 条历史')
    return len(history)


def backup_json():
    """把 JSON 文件备份到 data/json_backup/ 目录。"""
    backup_dir = DATA_DIR / 'json_backup'
    backup_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')

    for src in [MAIN_FILE, CONFLICT_FILE, VERSION_FILE]:
        if src.exists():
            dst = backup_dir / f'{src.stem}_{ts}{src.suffix}'
            shutil.copy2(str(src), str(dst))
            print(f'  备份: {src.name} → json_backup/{dst.name}')


def main():
    delete_json = '--delete-json' in sys.argv

    print('=' * 55)
    print('  TimeBlock JSON → SQLite 数据迁移')
    print('=' * 55)

    # 检查是否有可迁移的数据
    has_any = any(f.exists() for f in [MAIN_FILE, CONFLICT_FILE, VERSION_FILE])
    if not has_any:
        print('\n  没有找到旧 JSON 文件，无需迁移。')
        print('  （数据库将在服务端首次启动时自动创建）')
        return

    print(f'\n  目标数据库: {DB_PATH}')

    # 确保数据库表已创建
    conn = _get_conn()
    _init_tables(conn)

    print('\n[1/3] 迁移主数据...')
    main_data = _load_json(MAIN_FILE, {'eventInfo': [], 'dayRecords': {}})
    ei_cnt, dr_cnt = migrate_main(main_data)

    print('\n[2/3] 迁移冲突记录...')
    conflict_data = _load_json(CONFLICT_FILE, {})
    migrate_conflicts(conflict_data)

    print('\n[3/3] 迁移版本历史...')
    version_data = _load_json(VERSION_FILE, {'currentVersion': 0, 'history': []})
    migrate_versions(version_data)

    print('\n  备份旧 JSON 文件...')
    backup_json()

    if delete_json:
        print('\n  删除旧 JSON 文件...')
        for f in [MAIN_FILE, CONFLICT_FILE, VERSION_FILE]:
            if f.exists():
                f.unlink()
                print(f'  删除: {f.name}')

    print('\n' + '=' * 55)
    print('  迁移完成！')
    print(f'  事件类型: {ei_cnt} 条')
    print(f'  时间记录: {dr_cnt} 天')
    print(f'  数据库路径: {DB_PATH}')
    print('=' * 55)


if __name__ == '__main__':
    main()
