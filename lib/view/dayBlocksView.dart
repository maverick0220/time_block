// import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/loaders.dart';


class DayBlocksView extends StatefulWidget {
    DayRecord? dayRecord;
    OperationControl operationControl;
    DayBlocksView({super.key, required this.dayRecord, required this.operationControl});

    @override
    State<DayBlocksView> createState() => _DayBlocksViewState();
}


class _DayBlocksViewState extends State<DayBlocksView> {
    // var blockSelectionsViewController = DragSelectGridViewControllers();
    // final bloackViewController = PanelController();

    final ScrollController _scrollController = ScrollController();

    // 长按拖动相关状态
    bool _isLongPressing = false;
    
    // Block 位置映射表：用于长按拖动时快速查找手指下的 block
    final Map<Block, Rect> _blockRects = {};
    final GlobalKey _scrollViewKey = GlobalKey();
    
    // 每个 block 对应的 GlobalKey，用于测量位置
    final Map<Block, GlobalKey> _blockKeys = {};

    @override
    void initState() {
        super.initState();
        // blockSelectionsViewController.addListener(scheduleRebuild);
        // currentFABHeight = initFABHeight;
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
            // -todo: 待修改jumpTo的值
            // print("== scrollController jumpTo: ${_scrollController.position.maxScrollExtent / 2}");
            print("== _scrollController.initialScrollOffset: ${_scrollController.position.maxScrollExtent}");
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            // 初始化时测量所有 block 的位置
            _updateBlockRects();
        });
    }

    @override
    void dispose() {
        // blockSelectionsViewController.removeListener(scheduleRebuild);
        _scrollController.dispose();
        super.dispose();
    }

    // void scheduleRebuild() => setState(() {});
    // final double initFABHeight = 95.0;
    // double currentFABHeight = 0;
    // double panelHeightOpen = 0;
    // double panelHeightClosed = 80.0;

    // void setActivityToSelectedIntervals(String activityKey){

    // }

    // void removeActivityFromSelectedIntervals() {

    // }

    /// 测量并更新所有 block 的全局位置
    void _updateBlockRects() {
        if (widget.dayRecord == null) return;
        
        _blockRects.clear();
        
        // 遍历所有 block，测量其全局位置
        for (final row in widget.dayRecord!.blocks) {
            for (final block in row) {
                final key = _blockKeys[block];
                if (key == null) continue;
                
                final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
                if (renderBox != null && renderBox.hasSize) {
                    final size = renderBox.size;
                    final position = renderBox.localToGlobal(Offset.zero);
                    _blockRects[block] = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
                }
            }
        }
        
        print('== _updateBlockRects: found ${_blockRects.length} block positions');
    }

    /// 查找给定全局坐标对应的 Block
    Block? _findBlockAtPosition(Offset globalPosition) {
        for (final entry in _blockRects.entries) {
            if (entry.value.contains(globalPosition)) {
                return entry.key;
            }
        }
        return null;
    }

    // todo: 这个地方的逻辑错了，不是把widget.dayRecord.blocks画出来，而是创建4*24个方块，再把widget.dayRecord.blocks的颜色填到对应的block里

    @override
    Widget build(BuildContext context) {
        // widget.dayRecord.blocks = List.generate(24, (i) => List.generate(4, (j) => Block(["a", "b", "c", "d"][(j^2+i-7)%4], <int>[2024,12,17,i,j]))) as DayRecord;
        // print("== DayBlockView ${widget.dayRecord.date}");
        // print("== DayBlockView ${widget.dayRecord.events.length}");
        // print("== DayBlockView ${widget.dayRecord.blocks.last.length}");
        
        if (widget.dayRecord != null){
            return SingleChildScrollView(
                key: _scrollViewKey,
                controller: _scrollController,
                child: Column(
                    children: _buildBlockRows(),
                ),
            );
        }else{
            return const Center(child: Text("No Data"));
        }
    }
    
    List<Widget> _buildBlockRows() {
        final List<Widget> rows = [];
        
        for (final row in widget.dayRecord!.blocks) {
            rows.add(
                Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                        Container(
                            width: 80.0,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Text(row[0].getHourTimeStamp(), style: TextStyle(fontSize: 13.0, color: Colors.black)),
                        ),
                        Flexible(child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: 
                                row.map((block) => _buildBlockWidget(block)).toList()
                            ),
                        ),
                    ]
                ),
            );
        }
        
        rows.add(const Padding(padding: EdgeInsets.all(4.0)));
        return rows;
    }

    /// 构建单个 Block 的 Widget，支持点击和长按拖动选中
    Widget _buildBlockWidget(Block block) {
      // 为每个 block 创建或复用 GlobalKey
      _blockKeys.putIfAbsent(block, () => GlobalKey());
      final blockKey = _blockKeys[block]!;
      
      // 延迟注册 block 的位置（在下一帧测量）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateBlockRects();
      });
      
      return GestureDetector(
        // 点击选择（原有逻辑）
        onTap: () {
          final operationControl = Provider.of<OperationControl>(context, listen: false);
          final userProfileLoader = Provider.of<UserProfileLoader>(context, listen: false);
          operationControl.selectBlocks(block, userProfileLoader);
        },

        // 长按开始 → 触发拖动选择
        // 跨平台兼容：Flutter GestureDetector 在 iOS、Android、macOS、Windows、Linux 上行为一致
        onLongPressStart: (details) {
          print("== LongPressStart: ${block.blockIndex}, global: ${details.globalPosition}");
          setState(() {
            _isLongPressing = true;
          });

          // 刷新所有 block 位置（确保位置是最新的）
          _updateBlockRects();

          // 禁用触摸反馈，避免干扰
          HapticFeedback.mediumImpact();

          final operationControl = Provider.of<OperationControl>(context, listen: false);
          final userProfileLoader = Provider.of<UserProfileLoader>(context, listen: false);
          operationControl.startLongPressSelect(block, userProfileLoader);
        },

        // 长按拖动 → 实时更新选中范围
        onLongPressMoveUpdate: (details) {
          if (!_isLongPressing) return;

          // 查找手指位置下的 block
          final targetBlock = _findBlockAtPosition(details.globalPosition);
          if (targetBlock != null) {
            final operationControl = Provider.of<OperationControl>(context, listen: false);
            final userProfileLoader = Provider.of<UserProfileLoader>(context, listen: false);

            // 只有当移动到不同 block 时才更新
            if (operationControl.longPressCurrentBlock != targetBlock) {
              HapticFeedback.selectionClick();
              operationControl.updateLongPressSelect(targetBlock, userProfileLoader);
            }
          }
        },

        // 长按结束 → 完成选择
        onLongPressEnd: (details) {
          print("== LongPressEnd: ${block.blockIndex}");
          setState(() {
            _isLongPressing = false;
          });

          HapticFeedback.lightImpact();

          final operationControl = Provider.of<OperationControl>(context, listen: false);
          final userProfileLoader = Provider.of<UserProfileLoader>(context, listen: false);
          operationControl.endLongPressSelect(userProfileLoader);
        },

        // 长按取消 → 取消选择
        onLongPressCancel: () {
          print("== LongPressCancel");
          setState(() {
            _isLongPressing = false;
          });

          final operationControl = Provider.of<OperationControl>(context, listen: false);
          operationControl.cancelLongPressSelect();
        },

        // Block 内容，使用 GlobalKey 标记
        child: Container(
          key: blockKey,
          margin: const EdgeInsets.all(1.0),
          width: 48.0,
          height: 24.0,
          decoration: BoxDecoration(
            color: block.color,
            borderRadius: BorderRadius.circular(2.0),
            border: Border.all(
              color: (block.isRightNow == true)
                  ? Colors.red // 当前时刻标记
                  : Colors.transparent,
              width: 2.0,
            ),
          ),
          alignment: Alignment.center,
        ),
      );
    }
}
