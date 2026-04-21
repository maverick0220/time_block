// import 'package:flutter/cupertino.dart';
// import 'dart:io';

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:time_block/database/EventRecord.dart';
import 'package:time_block/database/EventInfoRecord.dart';
import 'package:time_block/database/DayEventsRecord.dart';

import 'package:time_block/loaders.dart';

import 'package:time_block/view/appBarViiew.dart';
import 'package:time_block/view/buttonListView.dart';
import 'package:time_block/view/dayBlocksView.dart';
import 'package:time_block/view/editPage.dart';
import 'package:time_block/view/analyzeView.dart';
import 'package:time_block/util/migrateOldData.dart';
import 'package:time_block/network/syncConfig.dart';
// import 'package:time_block/network/dataSync.dart';


void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // ==================== Hive 初始化（跨平台支持） ====================
    // Hive.initFlutter() 会自动处理不同平台的存储路径：
    // - Android/iOS: 使用应用沙盒目录（应用私有目录）
    // - macOS: 使用 ~/Library/Application Support/{bundleID}
    // - Windows: 使用 %APPDATA%/{companyName}/{appName}
    // - Linux: 使用 ~/.local/share/{appName}
    // - Web: 使用 IndexedDB
    // 
    // 注意：
    // 1. 已移除旧的硬编码路径 Hive.init("./hiveDB/")，该路径在不同平台下不可靠
    // 2. HyperOS（小米）本质上是 Android，会自动使用 Android 的存储机制
    // 3. 迁移旧数据：首次运行时，下面可以启用数据迁移功能
    // ====================
    
    // ⚠️  数据迁移（仅首次运行时需要）⚠️
    // 如果你是从旧版本升级，并且 ./hiveDB/ 目录中有数据，
    // 请取消下面这行的注释来迁移数据到新路径
    // await migrateOldHiveData();
    
    await Hive.initFlutter();
    
    Hive.registerAdapter(EventRecordAdapter());
    Hive.registerAdapter(EventInfoRecordAdapter());
    Hive.registerAdapter(DayEventsRecordAdapter());
    final eventInfoBox = await Hive.openBox<EventInfoRecord>('eventInfo');
    final dayRecordBox = await Hive.openBox<DayEventsRecord>("dayRecords");
    await SyncConfig.init();
    final savedEventInfoOrder = await SyncConfig.getEventInfoOrder();

    // ==================== 首次启动自动初始化 eventInfo ====================
    // 如果 eventInfo 数据库为空（首次安装或数据丢失），从内嵌的 config.json 自动导入
    if (eventInfoBox.isEmpty) {
        print("== eventInfoBox is empty, loading from config.json...");
        try {
            final String configStr = await rootBundle.loadString('lib/config.json');
            final Map<String, dynamic> configJson = jsonDecode(configStr);
            for (var event in configJson["eventInfo"]) {
                final String name = event[0] as String;
                final record = EventInfoRecord(
                    eventName: name,
                    color_rgb: [event[1]["r"] as int, event[1]["g"] as int, event[1]["b"] as int],
                    belongingToEvent: "",
                );
                await eventInfoBox.put(name, record);
                print("== imported eventInfo: $name");
            }
            print("== eventInfo init done, total: ${eventInfoBox.length}");
        } catch (e) {
            print("== failed to load config.json: $e");
        }
    } else {
        print("== eventInfoBox already has ${eventInfoBox.length} items, skip init.");
    }
    // ====================

    // ==================== 窗口管理（仅桌面端） ====================
    // window_manager 仅适用于桌面端（macOS、Windows、Linux）
    // 在移动端（Android/iOS/HyperOS）上不会调用，避免导入错误
    // ====================
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await windowManager.ensureInitialized();

        // 设置窗口固定大小
        WindowOptions windowOptions = const WindowOptions(
            size: Size(415, 785), // 初始尺寸
            minimumSize: Size(415, 785), // 最小尺寸
            maximumSize: Size(415, 785), // 最大尺寸（与初始尺寸相同即可固定）
            title: "TimeBlock",
        );

        await windowManager.waitUntilReadyToShow(windowOptions, () async {
            await windowManager.show();
            await windowManager.focus();
        });
        await windowManager.setResizable(false);
    }

    if (Hive.isBoxOpen("eventInfo") && Hive.isBoxOpen("dayRecords")){
        runApp(
            MultiProvider(
                providers: [
                    ChangeNotifierProvider(create: (context) => UserProfileLoader(dayRecordBox, eventInfoBox, savedOrder: savedEventInfoOrder)),
                    ChangeNotifierProvider(create: (context) => OperationControl())
                ],
                child: const TimeBlockApp(),
            )
        );
    }
  
}

class TimeBlockApp extends StatelessWidget {
    const TimeBlockApp({super.key});
    
    // This widget is the root of your application.
    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            title: 'TimeBlock',
            darkTheme: ThemeData( // 这俩配置都是抄的
                brightness: Brightness.dark,
                useMaterial3: true, colorScheme: ColorScheme.fromSwatch(brightness: Brightness.dark).copyWith(secondary: Colors.blueAccent),
                inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
            ),
            theme: ThemeData(
                brightness: Brightness.light,
                useMaterial3: true,
                canvasColor: Colors.grey[100],
                colorScheme: ColorScheme.fromSwatch(brightness: Brightness.light).copyWith(secondary: Colors.blueAccent),
                inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
            ),
            home: DefaultTabController(
                length: 3, // Tab 的数量
                child: Scaffold(
                    appBar: AppBar(
                        // title: const Text('TabBar Example'),
                        toolbarHeight: 1.0,
                        bottom: const TabBar(
                            tabs: [
                                Tab(icon: Icon(Icons.home, size: 16), height: 24),
                                Tab(icon: Icon(Icons.draw, size: 16), height: 24),
                                Tab(icon: Icon(Icons.search, size: 16), height: 24),
                            ],
                        ),
                    ),
                    body: const TabBarView(
                        children: [
                            MainPage(title: 'TimeBlock'),
                            EditPage(title: 'EventInfoEdit'),
                            AnalyzeView(title: 'Analyze'),
                        ],
                    ),
                )
            )
        );
    }
}

// =====================================

class MainPage extends StatefulWidget {
    const MainPage({super.key, required this.title});
    final String title;

    @override
    State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
    // ScrollController _scrollController = ScrollController();
    late ScrollController _scrollController;

    @override
    void initState() {
        super.initState();
        //load data from the hive box into activitybase and currentdaymodel
        // loadFromBoxes().whenComplete(() {
        //     WidgetsBinding.instance.addPostFrameCallback((_) {
        //     //then push to homescreen
        //     Navigator.pushReplacement(
        //         context,
        //         PageTransition(
        //         type: PageTransitionType.fade,
        //         duration: const Duration(milliseconds: 200),
        //         child: const NavBarScreen(),
        //         //duration: const Duration(seconds: 1),
        //         ),
        //     );
        //     });
        // }
        // );

        // 添加滚动监听器，判断日期是否需要置顶
        // _scrollController.addListener(() {
        // final position = _scrollController.position;
        // if (position.pixels >= position.minScrollExtent) {
        //     setState(() {
        //     // 判断当前滚动位置来设置置顶的日期
        //     _currentDayIndex = (_scrollController.offset / 50).floor();
        //     });
        // }
        // });
        
        _scrollController = ScrollController();
        // 在布局完成后跳转到指定位置
        WidgetsBinding.instance.addPostFrameCallback((_) {
            // 计算第3个元素的起始位置（假设每个子项高度为固定值，例如 100）
            // 注意：实际值需根据 DayBlocksView 的高度调整
            double targetOffset = 3 * 630; // 2 * 子项高度（索引从0开始，跳过前三天）。这里的`3`和loaders.dart里的aroundDayCount变量是对应的
            
            // 确保不超过最大可滚动范围
            if (targetOffset <= _scrollController.position.maxScrollExtent) {
                _scrollController.jumpTo(targetOffset);
            } else {
                _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
        });

        // Provider.of<OperationControl>(context).refreshRenderDates(Provider.of<UserProfileLoader>(context));
    }

    @override
    void dispose() {
        _scrollController.dispose();
        // 注意：不要在 dispose 中关闭 Hive，因为其他页面可能还在使用
        // Hive 的 Box 应该在应用生命周期内保持打开状态
        super.dispose();
    }

    // int _counter = 0;
    // void _incrementCounter() {
    //     setState(() {
    //         // 用setState来改变东西，才能让改变被同步显示出来
    //         _counter++;
    //     });
    // }

    @override
    Widget build(BuildContext context) {
        var operationControl = Provider.of<OperationControl>(context);
        var userProfileLoader = Provider.of<UserProfileLoader>(context);
        List<String> _days = userProfileLoader.renderDates;
        
        // print("== main.build _days: ${_days}");

        // - todo: 这俩玩意儿似乎有些多余，UserProfileLoader都传过去了，何必单独把property放出来呢？
        var dayRecords = Provider.of<UserProfileLoader>(context).dayRecords;
        var eventInfos = Provider.of<UserProfileLoader>(context).eventInfos;
        
        // print("== dayRecords.length: ${dayRecords.length}");
        // for (var dayRecord in dayRecords.entries){
        //     print("== date: ${dayRecord.key}");
        // }
        
        return Scaffold(
            appBar: AppBar(
                backgroundColor: Theme.of(context).colorScheme.background,
                title: AppBarView(
                    operationControl: operationControl,
                    userProfileLoader: userProfileLoader,
                    scrollController: _scrollController,
                ),
            ),
            body: Row(
              children: [
                SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                        children: List.generate(_days.length, (i) => DayBlocksView(dayRecord: dayRecords[_days[i]], operationControl: operationControl))
                    )
                ),
                const Padding(padding: EdgeInsets.all(2.0)),
                ButtonListView(eventInfos: eventInfos, operationControl: operationControl, userProfileLoader: userProfileLoader)
              ],
            )
        );  
    }
}