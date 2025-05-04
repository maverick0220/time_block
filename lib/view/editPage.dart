import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/loaders.dart';
import 'package:time_block/view/appBarViiew.dart';
import 'package:time_block/view/eventInfoEditView.dart';


class EditPage extends StatefulWidget {
    // OperationControl operationControl;
    // UserProfileLoader userProfileLoader;
    // EditPage({super.key, required this.operationControl, required this.userProfileLoader});
    const EditPage({super.key, required this.title});
    final String title;
    @override
    State<EditPage> createState() => _EditPageState();
}


class _EditPageState extends State<EditPage> {

    @override
    void initState() {
        super.initState();
    }

    @override
    void dispose() {
        // blockSelectionsViewController.removeListener(scheduleRebuild);
        super.dispose();
    }

    @override
    Widget build(BuildContext context) {
        var operationControl = Provider.of<OperationControl>(context);
        var userProfileLoader = Provider.of<UserProfileLoader>(context);
        List<EventInfo> eventInfos = userProfileLoader.eventInfos;

        final BorderRadius buttonBorderRadius = BorderRadius.circular(6.0);

        return Scaffold(
            appBar: AppBar(
                backgroundColor: Theme.of(context).colorScheme.background,
                title: Row(
                    mainAxisAlignment : MainAxisAlignment.end,
                    children: [
                        ElevatedButton(
                            style: ButtonStyle(
                                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                                backgroundColor: MaterialStateProperty.all(Color.fromARGB(255, 90, 187, 26)),
                                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                                // minimumSize: MaterialStateProperty.all(const Size(14, 36)),
                            ),
                            onPressed: () {
                                setState(() {
                                    print('Button 新增eventInfo pressed');
                                    // Provider.of<OperationControl>(context, listen: false).refreshRenderDates(Provider.of<UserProfileLoader>(context, listen: false));
                                    // Provider.of<UserProfileLoader>(context, listen: false).updateDayRecordToBox("20250109");
                                });
                            },
                            child: Text("新增", style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
                        ),
                        const Padding(padding: EdgeInsets.all(2.0)),
                        ElevatedButton(
                            style: ButtonStyle(
                                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                                backgroundColor: MaterialStateProperty.all(Color.fromARGB(255, 90, 187, 26)),
                                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                                // minimumSize: MaterialStateProperty.all(const Size(14, 36)),
                            ),
                            onPressed: () {
                                setState(() {
                                    print('Button 查找eventInfo pressed');
                                    // Provider.of<OperationControl>(context, listen: false).refreshRenderDates(Provider.of<UserProfileLoader>(context, listen: false));
                                    // Provider.of<UserProfileLoader>(context, listen: false).updateDayRecordToBox("20250109");
                                });
                            },
                            child: Text("查找", style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
                        )
                    ]
                )
            ),
            body: Row(
              children: [
                Expanded(child: SingleChildScrollView(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        // children: List.generate(eventInfos.length, (i) => Text(eventInfos[i].name))
                        children: List.generate(eventInfos.length, (i) => EventInfoEditView(eventInfo: eventInfos[i], userProfileLoader: userProfileLoader))
                    )
                )),
                const Padding(padding: EdgeInsets.all(2.0)),
              ],
            )
        );  
    }
}




