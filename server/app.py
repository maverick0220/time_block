#!/usr/bin/env python3
"""
app.py — TimeBlock 同步服务端入口

接口：
  GET  /ping               连通性检测
  GET  /handshake          握手：获取服务端状态和能力
  POST /handshake/negotiate  协商：客户端声明需求，服务端返回同步计划
  POST /sync/upload        上传：客户端上传 dayRecords 数据
  GET  /sync/download      下载：客户端获取 downloadRange 内的数据
  GET  /sync               兼容模式：单次完成上传+下载（旧接口，仍保留）
  GET  /data               查看当前数据摘要（调试用）
  GET  /conflicts          查看冲突记录（调试用）
  GET  /sync-log           查看同步操作日志（?summary=1 返回按设备汇总）
  GET  /dashboard          可视化 Dashboard 页面
  GET  /api/dashboard-data  Dashboard 数据 API

新同步协议流程：
  1. GET  /handshake           → 获取服务端状态
  2. POST /handshake/negotiate → 协商同步计划
  3. POST /sync/upload         → 上传数据（如需要）
  4. GET  /sync/download       → 下载数据（如需要）

启动：
  cd server/
  python app.py
  # 或从项目根目录: python server/app.py
  # 自定义端口: PORT=8888 python server/app.py
"""

import os
import socket
from pathlib import Path
from datetime import datetime, date, timedelta
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


@app.route('/handshake', methods=['GET'])
def handshake():
    """
    步骤1：握手。客户端获取服务端状态和能力。

    响应：
    {
        "status": "ok",
        "server": "TimeBlock Sync Server",
        "protocolVersion": "2.0",         # 协议版本
        "currentVersion": 42,
        "dataRange": {                     # 服务端数据范围
            "earliest": "20250101",        # 最早有数据的日期
            "latest": "20250425"           # 最新有数据的日期
        },
        "features": {
            "multiStepSync": True,         # 支持多步同步
            "fullDataPull": True,           # 支持拉取全部历史数据
            "eventInfoSync": True           # 支持事件类型同步
        },
        "serverTime": "2026-04-25T22:00:00"
    }
    """
    all_dates = get_day_record_dates()
    current_version = get_current_version()

    data_range = {
        "earliest": all_dates[0] if all_dates else None,
        "latest": all_dates[-1] if all_dates else None,
    }

    print(f'[HANDSHAKE] {datetime.now().isoformat()} from {request.remote_addr}')

    return jsonify({
        "status": "ok",
        "server": "TimeBlock Sync Server",
        "protocolVersion": "2.0",
        "currentVersion": current_version,
        "dataRange": data_range,
        "features": {
            "multiStepSync": True,
            "fullDataPull": True,
            "eventInfoSync": True,
        },
        "serverTime": datetime.now().isoformat(),
    })


@app.route('/handshake/negotiate', methods=['POST'])
def handshake_negotiate():
    """
    步骤2：协商。客户端声明需求，服务端返回同步计划。

    请求：
    {
        "clientId": "device-abc",
        "lastSyncDate": "20260401",       # 上次同步截止日期（可为空字符串表示从未同步）
        "wantFullData": true,              # 是否想拉取全部历史数据
        "clientEventInfo": [...],          # 客户端 eventInfo 列表（可选）
        "clientDates": ["20260420", ...]   # 客户端本地的日期列表（可选，用于增量判断）
    }

    响应：
    {
        "uploadRequired": true,            # 是否需要客户端上传数据
        "downloadRequired": true,           # 是否需要客户端下载数据
        "uploadRange": ["20260420", "20260425"],  # 客户端应上传的日期范围
        "downloadRange": ["20250101", "20260419"], # 客户端应下载的日期范围
        "serverHasDates": ["20250101", ...],       # 服务端有的所有日期
        "eventInfoChanged": true,           # eventInfo 是否有变化
        "newVersion": 43
    }
    """
    if not request.is_json:
        return jsonify({'error': 'Content-Type must be application/json'}), 400

    body = request.get_json(force=True)
    client_id = body.get('clientId', 'unknown')
    last_sync_date = body.get('lastSyncDate', '')
    want_full_data = body.get('wantFullData', False)
    client_event_info = body.get('clientEventInfo', [])
    client_dates = set(body.get('clientDates', []))

    print(f'[NEGOTIATE] {datetime.now().isoformat()} from {client_id}, wantFullData={want_full_data}')

    # 更新 eventInfo（如果有的话）
    event_info_changed = False
    if client_event_info:
        color_changed = upsert_event_info_list(client_event_info)
        event_info_changed = len(color_changed) > 0
        if color_changed:
            print(f'[NEGOTIATE] eventInfo updated: {"; ".join(color_changed)}')

    # 获取服务端所有日期
    server_dates = set(get_day_record_dates())
    server_dates_sorted = sorted(server_dates)

    # 确定上传范围
    upload_required = False
    upload_range = ['', '']

    if last_sync_date:
        # 有上次同步日期：从次日开始到今天
        try:
            last_date = date(int(last_sync_date[:4]), int(last_sync_date[4:6]), int(last_sync_date[6:]))
            tomorrow = last_date + timedelta(days=1)
            today = date.today()
            if tomorrow <= today:
                upload_range = [
                    f"{tomorrow.year}{tomorrow.month:02d}{tomorrow.day:02d}",
                    f"{today.year}{today.month:02d}{today.day:02d}"
                ]
                upload_required = True
        except Exception:
            pass
    else:
        # 从未同步过：今天需要上传（如果有数据的话）
        today = date.today()
        upload_range = [
            f"{today.year}{today.month:02d}{today.day:02d}",
            f"{today.year}{today.month:02d}{today.day:02d}"
        ]

    # 确定下载范围
    download_required = False
    download_range = ['', '']

    if want_full_data:
        # 想拉取全部历史数据：服务端所有日期
        if server_dates:
            download_range = [server_dates_sorted[0], server_dates_sorted[-1]]
            download_required = True
    elif last_sync_date:
        # 增量下载：从上次同步日期次日开始，服务端有的所有日期
        try:
            last_date = date(int(last_sync_date[:4]), int(last_sync_date[4:6]), int(last_sync_date[6:]))
            tomorrow = last_date + timedelta(days=1)
            if server_dates:
                server_has_after_last = [d for d in server_dates_sorted if d >= f"{tomorrow.year}{tomorrow.month:02d}{tomorrow.day:02d}"]
                if server_has_after_last:
                    download_range = [server_has_after_last[0], server_dates_sorted[-1]]
                    download_required = True
        except Exception:
            pass
    else:
        # 从未同步过且不想拉全量：拉取服务端所有数据
        if server_dates:
            download_range = [server_dates_sorted[0], server_dates_sorted[-1]]
            download_required = True

    # 如果客户端声明了 clientDates，下载范围应该排除客户端已有的日期
    if download_required and client_dates:
        # 找出服务端有但客户端没有的日期
        missing_on_client = sorted(server_dates - client_dates)
        if missing_on_client:
            download_range = [missing_on_client[0], missing_on_client[-1]]
        else:
            download_required = False
            download_range = ['', '']

    new_version = get_current_version()

    response = {
        "uploadRequired": upload_required,
        "downloadRequired": download_required,
        "uploadRange": upload_range,
        "downloadRange": download_range,
        "serverHasDates": server_dates_sorted,
        "eventInfoChanged": event_info_changed,
        "newVersion": new_version,
    }

    print(f'[NEGOTIATE] Response for {client_id}: upload={upload_range}, download={download_range}')

    # 记录本次协商
    append_sync_log({
        'client_id': client_id,
        'client_time': datetime.now().isoformat(),
        'server_time': datetime.now().isoformat(),
        'range_start': upload_range[0] if upload_range[0] else '',
        'range_end': upload_range[1] if upload_range[1] else '',
        'uploaded_dates': [],
        'merged_days': 0,
        'conflict_days': 0,
        'patch_days': 0,
        'new_version': new_version,
    })

    return jsonify(response)


@app.route('/sync/upload', methods=['POST'])
def sync_upload():
    """
    步骤3：上传。客户端上传 dayRecords 数据。

    请求：
    {
        "clientId": "device-abc",
        "uploadRange": ["20260420", "20260425"],
        "dayRecords": { "20260420": [[...], ...], ... },
        "eventInfo": [...]  // 可选
    }

    响应：
    {
        "success": true,
        "mergedDays": 5,
        "conflictDays": 1,
        "newVersion": 44,
        "message": "上传成功"
    }
    """
    if not request.is_json:
        return jsonify({'error': 'Content-Type must be application/json'}), 400

    body = request.get_json(force=True)

    client_id = body.get('clientId', 'unknown')
    upload_range = body.get('uploadRange', [])
    client_day_records = body.get('dayRecords', {})
    client_time = body.get('clientTime', datetime.now().isoformat())

    print(f'[UPLOAD] {datetime.now().isoformat()} from {client_id}, range={upload_range}')

    # 更新 eventInfo
    if body.get('eventInfo'):
        upsert_event_info_list(body['eventInfo'])

    # 加载本次涉及日期的服务端数据
    involved_dates = list(client_day_records.keys())
    server_records = get_day_records(involved_dates) if involved_dates else {}

    # 逐天合并
    merged_dates = []
    conflict_dates = []
    updated_records = {}

    for date_key, client_events in client_day_records.items():
        server_events = server_records.get(date_key, [])
        merged, conflicts = merge_day(date_key, client_events, server_events)
        updated_records[date_key] = merged

        if client_events:
            merged_dates.append(date_key)
        if conflicts:
            conflict_dates.append(date_key)
            append_conflict(date_key, {
                'from': client_id,
                'clientTime': client_time,
                'serverTime': datetime.now().isoformat(),
                'events': conflicts,
            })

    # 批量写入
    if updated_records:
        upsert_day_records_bulk(updated_records)

    # 版本递增
    if merged_dates:
        new_version = bump_version(merged_dates)
    else:
        new_version = get_current_version()

    set_meta('last_updated', datetime.now().isoformat())

    msg = f'上传成功：合并 {len(merged_dates)} 天，冲突 {len(conflict_dates)} 天'
    print(f'[UPLOAD] {msg} (from {client_id})')

    append_sync_log({
        'client_id': client_id,
        'client_time': client_time,
        'server_time': datetime.now().isoformat(),
        'range_start': upload_range[0] if len(upload_range) == 2 else '',
        'range_end': upload_range[1] if len(upload_range) == 2 else '',
        'uploaded_dates': list(client_day_records.keys()),
        'merged_days': len(merged_dates),
        'conflict_days': len(conflict_dates),
        'patch_days': 0,
        'new_version': new_version,
    })

    return jsonify({
        'success': True,
        'mergedDays': len(merged_dates),
        'conflictDays': len(conflict_dates),
        'newVersion': new_version,
        'message': msg,
    })


@app.route('/sync/download', methods=['GET'])
def sync_download():
    """
    步骤4：下载。客户端获取 downloadRange 内的所有数据。

    查询参数：
      range_start  YYYYMMDD  下载范围起始日期
      range_end    YYYYMMDD  下载范围结束日期

    响应：
    {
        "success": true,
        "dayRecords": { "20250101": [[...], ...], ... },
        "eventInfo": [...],
        "dateCount": 100,
        "newVersion": 44,
        "message": "下载完成"
    }
    """
    range_start = request.args.get('range_start', '')
    range_end = request.args.get('range_end', '')

    if not range_start or not range_end:
        return jsonify({'error': 'Missing range_start or range_end'}), 400

    print(f'[DOWNLOAD] {datetime.now().isoformat()}, range={range_start}~{range_end}')

    # 枚举范围内的所有日期
    try:
        start_date = date(int(range_start[:4]), int(range_start[4:6]), int(range_start[6:]))
        end_date = date(int(range_end[:4]), int(range_end[4:6]), int(range_end[6:]))
    except Exception:
        return jsonify({'error': 'Invalid date format'}), 400

    all_dates = []
    cur = start_date
    while cur <= end_date:
        all_dates.append(f"{cur.year}{cur.month:02d}{cur.day:02d}")
        cur += timedelta(days=1)

    # 获取这些日期的数据
    day_records = get_day_records(all_dates)
    event_info = get_all_event_info()
    new_version = get_current_version()

    msg = f'下载完成：{len(day_records)} 天数据'
    print(f'[DOWNLOAD] {msg}')

    return jsonify({
        'success': True,
        'dayRecords': day_records,
        'eventInfo': event_info,
        'dateCount': len(day_records),
        'newVersion': new_version,
        'message': msg,
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
