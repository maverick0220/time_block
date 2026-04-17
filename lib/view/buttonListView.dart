import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/loaders.dart';


class ButtonListView extends StatefulWidget {
    List<EventInfo> eventInfos;
    OperationControl operationControl;
    UserProfileLoader userProfileLoader;
    ButtonListView({super.key, required this.eventInfos, required this.operationControl, required this.userProfileLoader});

    @override
    State<ButtonListView> createState() => _ButtonListViewState();
}


class _ButtonListViewState extends State<ButtonListView> {

    @override
    void initState() {
        super.initState();
    }

    @override
    void dispose() {
        // blockSelectionsViewController.removeListener(scheduleRebuild);
        super.dispose();
    }

    List<ElevatedButton> _getButtonList(){
        // 除了所有的event，还有wipe和cancel已选择的button
        List<ElevatedButton> buttons = [];

        final BorderRadius buttonBorderRadius = BorderRadius.circular(6.0);

        for(int i=0; i<widget.eventInfos.length; i++){
            buttons.add(
                ElevatedButton(
                    style: ButtonStyle(
                        shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                        backgroundColor: MaterialStateProperty.all(widget.eventInfos[i].color),
                        textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                        // minimumSize: MaterialStateProperty.all(const Size(14, 36)),
                    ),
                    onPressed: () {
                        setState(() {
                            print('Button ${widget.eventInfos[i].name} pressed');
                            Provider.of<OperationControl>(context, listen: false).recordBlocksAsEvent(widget.eventInfos[i].name, widget.userProfileLoader);
                        });
                    },
                    child: Text(widget.eventInfos[i].name, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
                )
            );
        }

        // wipeSelection
        buttons.add(ElevatedButton(
            style: ButtonStyle(
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(2.0))),
                backgroundColor: MaterialStateProperty.all(Colors.red),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
            ),
            onPressed: () {
                setState(() {
                    print('wipeSelection() pressed');
                    Provider.of<OperationControl>(context, listen: false).wipeSelection(Provider.of<UserProfileLoader>(context, listen: false));
                });
            },
            child: Text("wipe", style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.normal)),
        ));
        
        // cancelSelection
        buttons.add(ElevatedButton(
                style: ButtonStyle(
                    shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: BorderRadius.circular(2.0))),
                    backgroundColor: MaterialStateProperty.all(Colors.blue),
                    textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                ),
                onPressed: () {
                    setState(() {
                        print('cancelSelection() pressed');
                        Provider.of<OperationControl>(context, listen: false).cancelSelection();
                    });
                },
                child: Text("cancel", style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.normal)),
            )
        );

        return buttons;
    }

    @override
    Widget build(BuildContext context) {
        // print("== buttonListView widget.eventInfos: ${widget.eventInfos}");
        final List<Widget> buttonList = _getButtonList();

        // if (widget.eventInfos.isNotEmpty){
        return Expanded(child: ListView.builder(
            itemCount: buttonList.length,
            itemBuilder: (context, index) {
                return Padding(
                    padding: EdgeInsets.all(2.0),
                    child: buttonList[index],
                );
            }
        ));
        // }else{
        //     return const Center(child: Text("No Data"));
        // }
    }
}




