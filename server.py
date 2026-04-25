#!/usr/bin/env python3
"""
TimeBlock 数据同步服务端

功能：
  - GET  /ping         健康检查，客户端用来验证连接
  - POST /sync         接收客户端上传的完整数据（eventInfo + dayRecords）并持久化
  - GET  /sync         返回服务端存储的全部数据（供客户端下载补全）
  - GET  /data         查看当前存储的数据（调试用）

数据存储：
  所有数据以 JSON 格式保存到 ./data/timeblock_data.json

使用：
  pip install flask
  python server.py
  # 默认监听 0.0.0.0:5001，局域网内任意设备均可访问
  # 如需自定义端口：PORT=8888 python server.py

客户端配置示例：
  http://192.168.x.x:5001
"""

import json
import os
import shutil
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify

app = Flask(__name__)

# 数据存储目录和文件路径
DATA_DIR = Path('./data')
DATA_FILE = DATA_DIR / 'timeblock_data.json'


def load_data() -> dict:
    """加载本地存储的数据"""
    if not DATA_FILE.exists():
        return {'eventInfo': [], 'dayRecords': {}, 'lastUpdated': ''}
    try:
        with open(DATA_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        print(f'[WARN] Failed to load data: {e}')
        return {'eventInfo': [], 'dayRecords': {}, 'lastUpdated': ''}


def save_data(data: dict):
    """持久化数据到本地文件（先写临时文件再原子替换，避免写入中断损坏）"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp_file = DATA_FILE.with_suffix('.tmp')
    with open(tmp_file, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    shutil.move(str(tmp_file), str(DATA_FILE))


def backup_data():
    """在每次写入前备份一次（保留最近一次的备份）"""
    if DATA_FILE.exists():
        backup_path = DATA_DIR / 'timeblock_data.bak.json'
        shutil.copy2(str(DATA_FILE), str(backup_path))


# ─────────────────────────────────────────────
# 路由
# ─────────────────────────────────────────────

@app.route('/ping', methods=['GET'])
def ping():
    """健康检查接口，客户端用来验证服务端是否可达"""
    return jsonify({'status': 'ok', 'server': 'TimeBlock Sync Server', 'time': datetime.now().isoformat()})


@app.route('/sync', methods=['POST'])
def upload_sync():
    """
    接收客户端上传的数据，合并到本地存储。
    策略：
      - eventInfo：以客户端为准（整体覆盖）
      - dayRecords：以客户端为主，补充服务端已有但客户端没有的日期
    请求体格式：
    {
        "eventInfo": [{"name": "...", "color": {"r":0,"g":204,"b":102}, "belongingTo": ""},...],
        "dayRecords": { "20250101": [[startIdx, endIdx, event, type, comment], ...], ... },
        "clientTime": "2025-01-01T12:00:00"
    }
    """
    if not request.is_json:
        return jsonify({'error': 'Content-Type must be application/json'}), 400

    client_data = request.get_json(force=True)

    if 'dayRecords' not in client_data:
        return jsonify({'error': 'Missing dayRecords field'}), 400

    backup_data()
    server_data = load_data()

    # 更新 eventInfo（以客户端为准）
    if 'eventInfo' in client_data and client_data['eventInfo']:
        server_data['eventInfo'] = client_data['eventInfo']

    # 合并 dayRecords（客户端优先覆盖，保留服务端独有的日期）
    client_records: dict = client_data['dayRecords']
    server_records: dict = server_data.get('dayRecords', {})

    merged_records = dict(server_records)  # 先拷贝服务端已有记录
    new_count = 0
    updated_count = 0

    for date_key, events in client_records.items():
        if date_key not in merged_records:
            new_count += 1
        else:
            updated_count += 1
        merged_records[date_key] = events  # 客户端数据优先

    server_data['dayRecords'] = merged_records
    server_data['lastUpdated'] = datetime.now().isoformat()
    server_data['lastClientTime'] = client_data.get('clientTime', '')

    save_data(server_data)

    total_days = len(merged_records)
    msg = f'同步成功：新增 {new_count} 天，更新 {updated_count} 天，服务端共 {total_days} 天数据'
    print(f'[SYNC] {msg}')

    return jsonify({
        'message': msg,
        'totalDays': total_days,
        'newDays': new_count,
        'updatedDays': updated_count,
    })


@app.route('/sync', methods=['GET'])
def download_sync():
    """
    返回服务端存储的全部数据，供客户端下载补全。
    响应格式与上传格式相同。
    """
    data = load_data()
    return jsonify(data)


@app.route('/data', methods=['GET'])
def view_data():
    """查看当前存储数据的摘要（调试用）"""
    data = load_data()
    day_keys = sorted(data.get('dayRecords', {}).keys())
    summary = {
        'eventInfoCount': len(data.get('eventInfo', [])),
        'dayRecordCount': len(day_keys),
        'dateRange': f'{day_keys[0]} ~ {day_keys[-1]}' if day_keys else 'empty',
        'lastUpdated': data.get('lastUpdated', ''),
        'eventInfoNames': [e['name'] for e in data.get('eventInfo', [])],
    }
    return jsonify(summary)


# ─────────────────────────────────────────────
# 启动
# ─────────────────────────────────────────────

if __name__ == '__main__':
    import socket

    # 显示本机局域网 IP，方便填入客户端
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
        s.close()
    except Exception:
        local_ip = '127.0.0.1'

    port = int(os.environ.get('PORT', 5001))
    print('=' * 50)
    print(f'  TimeBlock Sync Server')
    print(f'  本机局域网地址: http://{local_ip}:{port}')
    print(f'  在客户端填入上方地址即可')
    print('=' * 50)

    app.run(host='0.0.0.0', port=port, debug=False)
