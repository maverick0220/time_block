// import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
    // var blockSelectionsViewController = DragSelectGridViewController();
    // final bloackViewController = PanelController();

    final ScrollController _scrollController = ScrollController();

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

    // todo: 这个地方的逻辑错了，不是把widget.dayRecord.blocks画出来，而是创建4*24个方块，再把widget.dayRecord.blocks的颜色填到对应的block里

    @override
    Widget build(BuildContext context) {
        // widget.dayRecord.blocks = List.generate(24, (i) => List.generate(4, (j) => Block(["a", "b", "c", "d"][(j^2+i-7)%4], <int>[2024,12,17,i,j]))) as DayRecord;
        // print("== DayBlockView ${widget.dayRecord.date}");
        // print("== DayBlockView ${widget.dayRecord.events.length}");
        // print("== DayBlockView ${widget.dayRecord.blocks.last.length}");
        
        if (widget.dayRecord != null){
            return SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                    // alignment: Alignment.center,
                    children: [
                    //     Row(
                    //     mainAxisSize: MainAxisSize.min,
                    //     crossAxisAlignment: CrossAxisAlignment.center,
                    //     children: [
                    //         Container(
                    //             width: 80.0,
                    //             alignment: Alignment.centerRight,
                    //             padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    //             child: Text(date, style: TextStyle(fontSize: 12.0, color: Colors.black)),
                    //         ),
                    //         Flexible(child: Row(
                    //             mainAxisAlignment: MainAxisAlignment.start,
                    //             children: List.generate(4, (index) => Container(
                    //                         margin: const EdgeInsets.all(1.0),
                    //                         width: 48.0,
                    //                         height: 4.0,
                    //                         decoration: BoxDecoration(
                    //                             color: Color(0x00000000),//Colors.blueAccent,
                    //                             borderRadius: BorderRadius.circular(2.0),
                    //                         ),
                    //                         alignment: Alignment.center,
                    //                         // child: Text(block.eventType, style: const TextStyle(color: Colors.white)),
                    //                     ),
                    //                 )
                    //             )
                    //         ),
                    //     ]
                    // ),
                    ...widget.dayRecord!.blocks.map((row){
                      return Row(
                          // mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                              // 先放置每行开头的那个Container
                                Container(
                                    width: 80.0,
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                    child: Text(row[0].getHourTimeStamp(), style: TextStyle(fontSize: 13.0, color: Colors.black)),
                                ),
                                Flexible(child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: 
                                        row.map((block) => InkWell(
                                            onTap: () { 
                                                setState(() {
                                                    print("== tap: ${block.blockIndex}, ${block.color}, ${block.eventType}");
                                                    Provider.of<OperationControl>(context, listen: false).selectBlocks(block, Provider.of<UserProfileLoader>(context, listen: false)); 
                                                });
                                            },
                                            onLongPress: () { /*print("Long-Pressed: ${block.blockIndex}, ${block.color}");*/ },
                                            // child: Container(
                                            //     margin: const EdgeInsets.all(1.0),
                                            //     // padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                            //     width: 48.0,
                                            //     height: 24.0,
                                            //     decoration: BoxDecoration(
                                            //         color: block.color,//Colors.blueAccent,
                                            //         borderRadius: BorderRadius.circular(2.0),
                                            //     ),
                                            //     alignment: Alignment.center,
                                            //     // child: Text(block.eventType, style: const TextStyle(color: Colors.white)),
                                            // ),

                                            child: Container(
                                                margin: const EdgeInsets.all(1.0),
                                                width: 48.0,
                                                height: 24.0,
                                                decoration: BoxDecoration(
                                                    color: block.color,
                                                    borderRadius: BorderRadius.circular(2.0),
                                                    border: Border.all(
                                                        color: (block.isRightNow == true)
                                                            ? Colors.red // 选中时外圈为红色
                                                            : Colors.transparent, // 未选中时无边框
                                                        width: 2.0,
                                                    ),
                                                ),
                                                alignment: Alignment.center,
                                                // child: Text(block.eventType, style: const TextStyle(color: Colors.white)),
                                            ),
                                        )).toList()
                                    ),
                                ),
                            ]
                        );
                    }).toList(),
                    const Padding(padding: EdgeInsets.all(4.0))
                    ],
                ),
            );
        }else{
            return const Center(child: Text("No Data"));
        }
    }
}