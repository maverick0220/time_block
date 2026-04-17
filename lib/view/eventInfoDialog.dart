import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:time_block/database/EventInfoRecord.dart';

/// EventInfo 编辑弹窗
/// 支持编辑现有 EventInfo 和新增 EventInfo
class EventInfoDialog extends StatefulWidget {
  final String? initialName; // 编辑时传入，新增时为 null
  final List<int>? initialColor; // 编辑时传入，新增时为 null

  const EventInfoDialog({
    super.key,
    this.initialName,
    this.initialColor,
  });

  @override
  State<EventInfoDialog> createState() => _EventInfoDialogState();
}

class _EventInfoDialogState extends State<EventInfoDialog> {
  late TextEditingController _nameController;
  late int _r;
  late int _g;
  late int _b;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _r = widget.initialColor?[0] ?? 128;
    _g = widget.initialColor?[1] ?? 128;
    _b = widget.initialColor?[2] ?? 128;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Color get _previewColor => Color.fromRGBO(_r, _g, _b, 1.0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white70 : Colors.black87;

    return AlertDialog(
      title: Text(
        widget.initialName == null ? '新增事件类型' : '编辑事件类型',
        style: TextStyle(color: labelColor, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 事件名称输入
            Text(
              '事件名称',
              style: TextStyle(fontSize: 12, color: labelColor.withOpacity(0.7)),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _nameController,
              style: TextStyle(fontSize: 14, color: labelColor),
              decoration: InputDecoration(
                hintText: '请输入事件名称',
                hintStyle: TextStyle(color: labelColor.withOpacity(0.4)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 颜色预览
            Center(
              child: Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  color: _previewColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: labelColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    _nameController.text.isEmpty ? '预览' : _nameController.text,
                    style: TextStyle(
                      color: (_r * 0.299 + _g * 0.587 + _b * 0.114) > 186
                          ? Colors.black
                          : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // RGB 滑块
            _buildColorSlider('R', _r, Colors.red, (value) {
              setState(() => _r = value.toInt());
            }),
            const SizedBox(height: 12),
            _buildColorSlider('G', _g, Colors.green, (value) {
              setState(() => _g = value.toInt());
            }),
            const SizedBox(height: 12),
            _buildColorSlider('B', _b, Colors.blue, (value) {
              setState(() => _b = value.toInt());
            }),

            // RGB 数值显示
            const SizedBox(height: 8),
            Center(
              child: Text(
                'RGB: ($_r, $_g, $_b)',
                style: TextStyle(
                  fontSize: 12,
                  color: labelColor.withOpacity(0.6),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: labelColor.withOpacity(0.7)),
          ),
        ),
        ElevatedButton(
          onPressed: _validateAndSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color.fromARGB(255, 60, 130, 220),
          ),
          child: const Text('保存', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildColorSlider(
    String label,
    int value,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white70 : Colors.black87;

    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: labelColor.withOpacity(0.7),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withOpacity(0.3),
              thumbColor: color,
              overlayColor: color.withOpacity(0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              label: value.toString(),
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            value.toString(),
            style: TextStyle(
              fontSize: 12,
              color: labelColor.withOpacity(0.7),
              fontFamily: 'monospace',
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  void _validateAndSave() {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入事件名称'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // 返回编辑结果
    Navigator.of(context).pop({
      'name': name,
      'color': [_r, _g, _b],
      'isNew': widget.initialName == null,
      'oldName': widget.initialName,
    });
  }
}

/// 显示 EventInfo 编辑弹窗
Future<Map<String, dynamic>?> showEventInfoDialog(
  BuildContext context, {
  String? initialName,
  List<int>? initialColor,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => EventInfoDialog(
      initialName: initialName,
      initialColor: initialColor,
    ),
  );
}
