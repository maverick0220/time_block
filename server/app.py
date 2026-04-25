#!/usr/bin/env python3
"""
app.py — TimeBlock 同步服务端入口

接口：
  GET  /ping           连通性检测
  POST /sync           客户端上传增量数据 + 接收补丁
  GET  /data           查看当前数据摘要（调试用）
  GET  /conflicts      查看冲突记录（调试用）
  GET  /sync-log       查看同步操作日志（?summary=1 返回按设备汇总）
  GET  /dashboard      可视化 Dashboard 页面
  GET  /api/dashboard-data  Dashboard 数据 API

启动：
  cd server/
  python app.py
  # 或从项目根目录: python server/app.py
  # 自定义端口: PORT=8888 python server/app.py
"""

import os
import socket
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify, send_from_directory

from storage import (
    # 细粒度接口（直接操作各表，无需全量加载）
    get_all_event_info,
    upsert_event_info_list,
    get_day_records,
    upsert_day_records_bulk,
    get_day_record_dates,
    append_conflict,
    get_conflict_dates,
    get_all_conflicts,
    get_current_version,
    bump_version,
    get_meta,
    set_meta,
    # 同步日志
    append_sync_log,
    get_sync_log,
    get_sync_log_summary,
    # 兼容接口（仅 /data 调试接口仍使用）
    load_version_info,
)
from merger import merge_day, find_missing_for_client

app = Flask(__name__)

# Dashboard 静态文件目录（与 app.py 同级）
DASHBOARD_DIR = Path(__file__).parent


# ─────────────────────────────────────────────
# 路由
# ─────────────────────────────────────────────

@app.route('/ping', methods=['GET'])
def ping():
    """健康检查，客户端用来验证服务端是否可达"""
    current_version = get_current_version()
    print(f'[PING] {datetime.now().isoformat()} from {request.remote_addr}')
    return jsonify({
        'status': 'ok',
        'server': 'TimeBlock Sync Server',
        'time': datetime.now().isoformat(),
        'currentVersion': current_version,
    })


@app.route('/sync', methods=['POST'])
def sync():
    """
    客户端上传增量数据，服务端返回补丁数据。

    请求体：
    {
        "eventInfo":    [...],          // 全量 eventInfo（可选，有则更新）
        "dayRecords":   { "20250101": [[startIdx, endIdx, event, type, comment], ...], ... },
        "uploadRange":  ["20250101", "20250410"],  // 本次上传覆盖的日期范围（用于判断缺失）
        "clientTime":   "2025-04-11T10:00:00",
        "clientId":     "device-abc"    // 可选，用于冲突记录溯源
    }

    响应体：
    {
        "message":       "同步成功：新增 N 天，更新 M 天，冲突 K 天",
        "newVersion":    43,
        "mergedDays":    N,
        "conflictDays":  K,
        "patch":         { "20250105": [[...], ...], ... }  // 客户端缺失的数据，空则为 {}
    }
    """
    if not request.is_json:
        return jsonify({'error': 'Content-Type must be application/json'}), 400

    body = request.get_json(force=True)

    if 'dayRecords' not in body:
        return jsonify({'error': 'Missing dayRecords field'}), 400

    client_day_records: dict = body.get('dayRecords', {})
    upload_range: list      = body.get('uploadRange', [])
    client_id: str          = body.get('clientId', 'unknown')
    client_time: str        = body.get('clientTime', datetime.now().isoformat())

    # ── 更新 eventInfo（以 name 字段为唯一键做 upsert）────────
    # - 客户端有、服务端没有 → 新增
    # - 客户端有、服务端也有 → 以客户端为准覆盖（color / belongingTo 均更新）
    # - 服务端有、客户端没有 → 保留（避免多客户端场景互相删除对方的配置）
    if body.get('eventInfo'):
        color_changed = upsert_event_info_list(body['eventInfo'])
        if color_changed:
            print(f'[SYNC] eventInfo color updated: {"; ".join(color_changed)}')

    # ── 加载本次涉及日期的服务端数据（按需加载，不全量读取）─
    involved_dates = list(client_day_records.keys())
    server_records: dict = get_day_records(involved_dates) if involved_dates else {}

    # ── 逐天合并 ──────────────────────────────────────────
    merged_dates:   list[str] = []
    conflict_dates: list[str] = []
    updated_records: dict     = {}   # 仅记录本次实际变化的天

    for date_key, client_events in client_day_records.items():
        server_events = server_records.get(date_key, [])

        merged, conflicts = merge_day(date_key, client_events, server_events)
        updated_records[date_key] = merged

        if client_events:
            merged_dates.append(date_key)
        if conflicts:
            conflict_dates.append(date_key)
            append_conflict(date_key, {
                'from':        client_id,
                'clientTime':  client_time,
                'serverTime':  datetime.now().isoformat(),
                'events':      conflicts,
            })
            print(f'[CONFLICT] {date_key}: {len(conflicts)} conflicting event(s) from {client_id}')

    # ── 批量写入变更天 ────────────────────────────────────
    if updated_records:
        upsert_day_records_bulk(updated_records)

    set_meta('last_updated', datetime.now().isoformat())

    # ── 版本递增 ──────────────────────────────────────────
    if merged_dates:
        new_version = bump_version(merged_dates)
    else:
        new_version = get_current_version()

    # ── 计算需要回填给客户端的补丁 ──────────────────────
    # 合并后的 server_records（本次涉及的天已是最新值）
    merged_server_records = {**server_records, **updated_records}

    # 补丁计算需要 uploadRange 内所有服务端数据，按需加载
    if len(upload_range) == 2:
        from datetime import date as _date, timedelta
        try:
            s = upload_range[0]
            e = upload_range[1]
            start = _date(int(s[:4]), int(s[4:6]), int(s[6:]))
            end   = _date(int(e[:4]), int(e[4:6]), int(e[6:]))
            all_range_dates = []
            cur = start
            while cur <= end:
                all_range_dates.append(f'{cur.year}{cur.month:02d}{cur.day:02d}')
                cur += timedelta(days=1)

            # 只加载 uploadRange 内尚未在 merged_server_records 中的日期
            missing_keys = [d for d in all_range_dates if d not in merged_server_records]
            if missing_keys:
                extra = get_day_records(missing_keys)
                merged_server_records.update(extra)
        except Exception:
            pass

    patch = find_missing_for_client(
        upload_range,
        set(client_day_records.keys()),
        merged_server_records,
        client_day_records=client_day_records,
    )

    msg = (f'同步成功：处理 {len(merged_dates)} 天，'
           f'冲突 {len(conflict_dates)} 天，'
           f'回填补丁 {len(patch)} 天')
    print(f'[SYNC] {msg} (from {client_id}, version → {new_version})')

    # ── 记录本次同步日志 ──────────────────────────────
    append_sync_log({
        'client_id':      client_id,
        'client_time':    client_time,
        'server_time':    datetime.now().isoformat(),
        'range_start':    upload_range[0] if len(upload_range) == 2 else '',
        'range_end':      upload_range[1] if len(upload_range) == 2 else '',
        'uploaded_dates': list(client_day_records.keys()),
        'merged_days':    len(merged_dates),
        'conflict_days':  len(conflict_dates),
        'patch_days':     len(patch),
        'new_version':    new_version,
    })

    return jsonify({
        'message':      msg,
        'newVersion':   new_version,
        'mergedDays':   len(merged_dates),
        'conflictDays': len(conflict_dates),
        'patch':        patch,
    })


@app.route('/data', methods=['GET'])
def view_data():
    """查看当前数据摘要（调试用）"""
    day_keys      = get_day_record_dates()
    event_infos   = get_all_event_info()
    cur_version   = get_current_version()
    last_updated  = get_meta('last_updated', '')

    return jsonify({
        'eventInfoCount':  len(event_infos),
        'dayRecordCount':  len(day_keys),
        'dateRange':       f'{day_keys[0]} ~ {day_keys[-1]}' if day_keys else 'empty',
        'lastUpdated':     last_updated,
        'currentVersion':  cur_version,
        'eventInfoNames':  [e['name'] for e in event_infos],
    })


@app.route('/conflicts', methods=['GET'])
def view_conflicts():
    """查看冲突记录（调试用）"""
    conflicts = get_all_conflicts()
    summary = {
        'totalConflictDays': len(conflicts),
        'dates':             sorted(conflicts.keys()),
        'detail': {
            d: [
                {
                    'from':        e['from'],
                    'time':        e['serverTime'],
                    'eventCount':  len(e['events']),
                }
                for e in entries
            ]
            for d, entries in conflicts.items()
        },
    }
    return jsonify(summary)


@app.route('/sync-log', methods=['GET'])
def view_sync_log():
    """
    查看同步操作日志。

    查询参数：
      ?limit=N      返回最近 N 条（默认 100，最大 1000）
      ?client=ID    只返回指定客户端的记录
      ?summary=1    返回各客户端汇总统计，忽略其他参数

    响应（详细模式）：
    {
        "total": 42,
        "logs": [
            {
                "id": 42,
                "clientId": "iPhone-A1B2",
                "clientTime": "2026-04-23T19:00:00",
                "serverTime": "2026-04-23T19:00:01",
                "rangeStart": "20260420",
                "rangeEnd":   "20260423",
                "uploadedDates": ["20260421", "20260423"],
                "mergedDays": 2,
                "conflictDays": 0,
                "patchDays": 1,
                "newVersion": 15
            },
            ...
        ]
    }

    响应（汇总模式 ?summary=1）：
    {
        "summary": {
            "iPhone-A1B2": { "totalSyncs": 5, "lastSyncTime": "...", ... },
            ...
        }
    }
    """
    if request.args.get('summary') == '1':
        return jsonify({'summary': get_sync_log_summary()})

    limit     = min(int(request.args.get('limit', 100)), 1000)
    client_id = request.args.get('client') or None
    logs      = get_sync_log(limit=limit, client_id=client_id)

    return jsonify({'total': len(logs), 'logs': logs})


@app.route('/dashboard', methods=['GET'])
def dashboard():
    """可视化 Dashboard 页面"""
    return send_from_directory(str(DASHBOARD_DIR), 'dashboard.html')


@app.route('/api/dashboard-data', methods=['GET'])
def dashboard_data():
    """
    Dashboard 数据 API，返回用于前端渲染所需的全量数据。

    响应结构：
    {
        "eventInfo": [...],
        "dayRecords": { "20250101": [[...], ...], ... },
        "conflictDates": ["20250105", ...],
        "currentVersion": 42,
        "lastUpdated": "..."
    }
    """
    return jsonify({
        'eventInfo':      get_all_event_info(),
        'dayRecords':     get_day_records(),
        'conflictDates':  get_conflict_dates(),
        'currentVersion': get_current_version(),
        'lastUpdated':    get_meta('last_updated', ''),
    })


# ─────────────────────────────────────────────
# 启动
# ─────────────────────────────────────────────

if __name__ == '__main__':
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = '127.0.0.1'

    port = int(os.environ.get('PORT', 5001))
    print('=' * 55)
    print('  TimeBlock Sync Server (SQLite)')
    print(f'  本机局域网地址: http://{local_ip}:{port}')
    print(f'  在客户端"服务端地址"栏填入上方地址即可')
    print('=' * 55)

    app.run(host='0.0.0.0', port=port, debug=False)
