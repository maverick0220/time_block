import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_block/dataStructure.dart';
import 'package:time_block/loaders.dart';
import 'package:time_block/network/dataSync.dart';


class AppBarView extends StatefulWidget {
    OperationControl operationControl;
    UserProfileLoader userProfileLoader;
    AppBarView({super.key, required this.operationControl, required this.userProfileLoader});

    @override
    State<AppBarView> createState() => _AppBarViewState();
}


class _AppBarViewState extends State<AppBarView> {

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
      final BorderRadius buttonBorderRadius = BorderRadius.circular(6.0);
      
      return Row(
        mainAxisAlignment : MainAxisAlignment.end,
        children: [
          Text(Provider.of<OperationControl>(context, listen: false).selectedBlockEvent),
          ElevatedButton(
            style: ButtonStyle(
                // fixedSize: MaterialStateProperty.all(const Size.fromHeight(20)),
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(Colors.amber),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                // minimumSize: MaterialStateProperty.all(const Size(14, 36)),
            ),
            onPressed: () {
                setState(() {
                    print('Button 刷新 pressed');
                    // Provider.of<OperationControl>(context, listen: false).refreshRenderDates(Provider.of<UserProfileLoader>(context, listen: false));
                    Provider.of<UserProfileLoader>(context, listen: false).updateDayRecordToBox("20250109");
                });
            },
            child: Text("刷新", style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
          ),
          const Padding(padding: EdgeInsets.all(2.0)),
          ElevatedButton(
            style: ButtonStyle(
                // fixedSize: MaterialStateProperty.all(const Size.fromHeight(20)),
                shape: MaterialStateProperty.all<RoundedRectangleBorder>(RoundedRectangleBorder(borderRadius: buttonBorderRadius)),
                backgroundColor: MaterialStateProperty.all(Colors.amber),
                textStyle: MaterialStateProperty.all(const TextStyle(color: Colors.black)),
                // minimumSize: MaterialStateProperty.all(const Size(14, 36)),
            ),
            onPressed: () {
                setState(() {
                    var dataSync = DataSync("172.26.0.1", 8888, Provider.of<UserProfileLoader>(context, listen: false));
                    dataSync.runSnycTask();
                
                    print('Button 同步 pressed');
                    // for (var date in Provider.of<UserProfileLoader>(context, listen: false).renderDates){
                    //     Provider.of<UserProfileLoader>(context, listen: false).dayEventsRecordBox.get(date)?.printRecord();
                    // }
                    
                });
            },
            child: Text("同步", style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.normal)),
          )
        ]
      );
        
    }
}




