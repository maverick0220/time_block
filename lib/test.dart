import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';

void main() async {
  // 创建一个File对象来表示JSON文件
  // File file = File('../2025.json');
  // try {
  //   // 读取文件内容
  //   String contents = await file.readAsString();
  //   // 将JSON字符串解码为Dart对象（通常是Map或List）
  //   Map<String, dynamic> jsonData = json.decode(contents);
  //   print(jsonData.keys.toList());
  //   // print(jsonData.values);
  //   print(jsonData["20250103"].runtimeType);
  //   print(jsonData["20250103"]);
  // } catch (e) {
  //   print('读取文件出错: $e');
  // }

  // String a = "20241232";
  // DateTime t = DateTime.parse("${a.substring(0,4)}-${a.substring(4,6)}-${a.substring(6)}");
  // print(t);

  // List<int> numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  // int n = 3;
  // List<int> lastNNumbers = numbers.sublist(numbers.length - n);
  // print(lastNNumbers);

  // print(3~/4);
  // print(16~/4);

  // var today = DateTime.now().toString().split(" ")[0].replaceAll("-", "");
  // print(today);
  // print(DateTime.parse("${today[0]}-${int.parse(today[1])}-${int.parse(today[2]) + 1}"));

  // List<Widget> a = List.generate(4, (index) => null)

  // var blockIndex = [1997, 2, 13, 4];
  // print("${blockIndex[0]}${blockIndex[1].toString().padLeft(2, '0')}${blockIndex[2].toString().padLeft(2, '0')},${blockIndex[3]}");

  // print(List.generate(7, (index) => index, growable: true));

  const port = 8888;
  final jsonData = {
    "20250108": [
        [
            0,
            15,
            "打游戏",
            "",
            ""
        ],
        [
            16,
            17,
            "家务事",
            "",
            ""
        ],
        [
            18,
            19,
            "工作",
            "",
            ""
        ],
        [
            20,
            21,
            "构思",
            "",
            ""
        ],
        [
            22,
            29,
            "锻炼",
            "",
            ""
        ],
        [
            30,
            34,
            "代码",
            "",
            ""
        ],
        [
            35,
            38,
            "锻炼",
            "",
            ""
        ],
        [
            39,
            48,
            "杂务事",
            "",
            ""
        ]
    ],
    "20250109": [
        [
            1,
            4,
            "与人交际",
            "",
            ""
        ],
        [
            11,
            31,
            "工作",
            "",
            ""
        ],
        [
            32,
            36,
            "代码",
            "",
            ""
        ],
        [
            37,
            46,
            "代码",
            "",
            ""
        ],
        [
            47,
            48,
            "构思",
            "",
            ""
        ],
        [
            49,
            49,
            "代码",
            "",
            ""
        ],
        [
            50,
            50,
            "构思",
            "",
            ""
        ],
        [
            51,
            55,
            "摸鱼",
            "",
            ""
        ],
        [
            56,
            59,
            "工作",
            "",
            ""
        ],
        [
            60,
            60,
            "杂务事",
            "",
            ""
        ],
        [
            61,
            62,
            "杂务事",
            "",
            ""
        ],
        [
            63,
            63,
            "杂务事",
            "",
            ""
        ],
        [
            64,
            74,
            "与人交际",
            "",
            ""
        ],
        [
            75,
            80,
            "与人交际",
            "",
            ""
        ],
        [
            81,
            82,
            "隐私相关",
            "",
            ""
        ],
        [
            83,
            87,
            "工作",
            "",
            ""
        ],
        [
            88,
            94,
            "打游戏",
            "",
            ""
        ],
        [
            95,
            94,
            "业余爱好",
            "",
            ""
        ],
        [
            95,
            95,
            "摸鱼",
            "",
            ""
        ]
    ]};
  final jsonString = json.encode(jsonData);

  // 获取本地网络接口
  // for (var interface in await NetworkInterface.list()) {
  //   for (var addr in interface.addresses) {
  //     if (addr.type == InternetAddressType.IPv4) {
  //       final ipParts = addr.address.split('.');
        for (int i = 1; i < 10; i++) {
          // final targetIp = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.$i';
          final targetIp = '172.26.0.1';
          // final targetIp = "192.168.0.104";
          print("Asking ip ${targetIp}");
          try {
            final socket = await Socket.connect(targetIp, port, timeout: Duration(milliseconds: 10));
            print('Connected to $targetIp:$port');
            socket.write(jsonString);
            await socket.flush();
            await socket.close();
            print('Data sent successfully to $targetIp:$port');
            break;
          } catch (e) {
            // 忽略连接错误
          }
        }
  //     }
  //   }
  // }


}