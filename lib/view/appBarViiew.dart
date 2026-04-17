import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/loaders.dart';
import 'package:time_block/network/dataSync.dart';
import 'package:time_block/network/syncConfig.dart';


class AppBarView extends StatefulWidget {
    OperationControl operationControl;
    UserProfileLoader userProfileLoader;
    AppBarView({super.key, required this.operationControl, required this.userProfileLoader});

    @override
    State<AppBarView> createState() => _AppBarViewState();
}


class _AppBarViewState extends State<AppBarView> {

    bool _isSyncing = false;

    @override
    void initState() {
        super.initState();
    }

    @override
    void dispose() {
        super.dispose();
    }

    /// 触发完整同步（上传增量 + 接收补丁）
    Future<void> _doSync(BuildContext context) async {
        // 检查服务端地址是否已配置
        final serverUrl = await SyncConfig.getServerUrl();
        if (serverUrl.isEmpty) {
            _showSnackBar(context, '请先在编辑页配置服务端地址', isError: true);
            return;
        }

        setState(() => _isSyncing = true);

        final result = await DataSync().runFullSync();

        if (!mounted) return;
        setState(() => _isSyncing = false);

        _showSnackBar(context, result.message, isError: !result.success);

        // 如果有补丁数据写入了本地，精确刷新这些日期的内存数据
        if (result.success && result.patchedDays > 0) {
            // applyPatchedDates 会从 Hive 重读数据并 notifyListeners，
            // 无论补丁日期是否在当前 renderDates 窗口内都能正确更新
            widget.userProfileLoader.applyPatchedDates(result.patchedDates);
        }
    }

    void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(message, style: const TextStyle(fontSize: 12)),
                backgroundColor: isError ? Colors.redAccent.shade700 : Colors.green.shade700,
                duration: Duration(seconds: isError ? 5 : 3),
                behavior: SnackBarBehavior.floating,
            ),
        );
    }

    @override
    Widget build(BuildContext context) {
      final BorderRadius buttonBorderRadius = BorderRadius.circular(6.0);
      
      return Row(
        mainAxisAlignment : MainAxisAlignment.end,
        children: [
          Text(Provider.of<OperationControl>(context, listen: false).selectedBlockEvent),
          ElevatedButton(
            style: ButtonStyle(
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(Colors.amber),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
            ),
            onPressed: () {
                setState(() {
                    print('Button 刷新 pressed');
                    Provider.of<OperationControl>(context, listen: false).refreshRenderDates(widget.userProfileLoader);
                });
            },
            child: const Text("刷新", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
          ),
          const Padding(padding: EdgeInsets.all(2.0)),
          ElevatedButton(
            style: ButtonStyle(
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(
                    _isSyncing ? Colors.amber.shade200 : Colors.amber,
                ),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
            ),
            onPressed: _isSyncing ? null : () => _doSync(context),
            child: _isSyncing
                ? const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                  )
                : const Text("同步", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
          )
        ]
      );
    }
}
