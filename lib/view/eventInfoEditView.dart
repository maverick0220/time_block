// import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/loaders.dart';
import 'package:time_block/view/appBarViiew.dart';


class EventInfoEditView extends StatefulWidget {
    EventInfo eventInfo;
    UserProfileLoader userProfileLoader;
    final Function(EventInfo) onEditPressed; // 编辑回调

    EventInfoEditView({
        super.key,
        required this.eventInfo,
        required this.userProfileLoader,
        required this.onEditPressed,
    });

    @override
    State<EventInfoEditView> createState() => _EventInfoEditViewState();
}


class _EventInfoEditViewState extends State<EventInfoEditView> {
    @override
    void initState() {
        super.initState();
    }

    @override
    void dispose() {
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        double containerWidth = MediaQuery.of(context).size.width * 0.96;
        return SingleChildScrollView(
            child: Container(
                alignment: Alignment.center,
                width: containerWidth,
                color: Colors.black87, // 深黑色底色
                padding: const EdgeInsets.all(4.0),
                child: Row(
                    children: [
                        Container(
                            width: 24.0,
                            height: 24.0,
                            decoration: BoxDecoration(
                                color: widget.eventInfo.color,
                                borderRadius: BorderRadius.circular(4.0),
                            ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                            widget.eventInfo.name,
                            style: const TextStyle(color: Colors.white),
                        ),
                        const Spacer(),
                        // 编辑按钮
                        IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            alignment: Alignment.centerRight,
                            icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                            onPressed: () => widget.onEditPressed(widget.eventInfo),
                        ),
                        const SizedBox(width: 4.0),
                        IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            alignment: Alignment.centerRight,
                            icon: const Icon(Icons.delete, color: Colors.white54, size: 18),
                            onPressed: () {
                                Provider.of<OperationControl>(context, listen: false).deleteEventInfo(widget.eventInfo, Provider.of<UserProfileLoader>(context, listen: false));
                            },
                        ),
                        // 与右侧 ReorderableListView 拖动手柄保持距离
                        const SizedBox(width: 32.0),
                    ],
                ),
            ),
        );
    }
}