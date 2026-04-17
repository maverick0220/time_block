import 'package:flutter/material.dart';
// import 'package:time_block/database/DayEventsRecord.dart';
import 'package:time_block/database/EventRecord.dart';
import 'package:time_block/loaders.dart';


class Block extends ChangeNotifier {
    String eventType = "";
    List<int> blockIndex = [1997, 11, 11, 0]; // [2024,12,17,16], 2024.12.17, 04:00~04:15
    Color color = Color.fromRGBO(0, 1, 1, 1);
    Color backupColor = Color.fromRGBO(0, 1, 1, 1);

    bool withConflict = false;
    bool isRightNow = false;

    Block(this.eventType, this.blockIndex, this.color);

    // void updateBlockColor() {
    //     color = Color.fromRGBO(238, 238, 238, 1);
    // }

    void selectBlock(){
        // print("== block ${this.blockIndex} selecting before: ${this.color.hashCode}, ${this.backupColor.hashCode}");

        if (color != Color.fromRGBO(0, 1, 1, 1) && color != Color.fromRGBO(238, 238, 238, 1)) { backupColor = color; }
        color = Color.fromRGBO(238, 238, 238, 1);

        // print("== block ${this.blockIndex} selecting after : ${this.color.hashCode}, ${this.backupColor.hashCode}\n");

        notifyListeners();
    }

    void unselectBlock(){
        // print("== block ${this.blockIndex} unselecting before: ${this.color}, ${this.backupColor}");
        color = backupColor;
        // print("== block ${this.blockIndex} unselecting after: ${this.color}, ${this.backupColor}\n");
        // backupColor = Color.fromRGBO(0, 1, 1, 1);
        notifyListeners();
    }

    void wipeOutBlock(){
        color = Color.fromRGBO(0, 1, 1, 1);
        backupColor = Color.fromRGBO(0, 1, 1, 1);
        eventType = "";
    }

    String getDateAsString(){
        return "${blockIndex[0]}${blockIndex[1].toString().padLeft(2, '0')}${blockIndex[2].toString().padLeft(2, '0')}";
    }

    int getBlockIndexAsInt(){
        return int.parse("${blockIndex[0]}${blockIndex[1].toString().padLeft(2, '0')}${blockIndex[2].toString().padLeft(2, '0')}");
    }

    String getHourTimeStamp(){
        int hour = blockIndex[3]~/4;
        if (hour == 0){ return "${blockIndex[1]}月 ${hour.toString().padLeft(2, '0')}:00"; }
        if (hour == 1){ return "${blockIndex[2]}日 ${hour.toString().padLeft(2, '0')}:00"; }
        return "${hour.toString().padLeft(2, '0')}:00";
    }
}

// class Event{
//   // 这个类废弃了
//     // 这个是用来记录何时发生了什么事的。不是描述可以有哪些事情发生的
//     // Event类似文章（很多字连在一起描述了一整天），EventInfo类似字典（有哪些字可以用来描述一整天）
//     int startIndex = -1;
//     int endIndex = -1;
//     String event = "";
//     String type = "";
//     String comment = "";

//     Event(List<dynamic> rawEvent){
//     //   print("==Event: ${rawEvent}");
//       startIndex = rawEvent[0];
//       endIndex = rawEvent[1];
//       event = rawEvent[2];
//       type = rawEvent[3];
//       comment = rawEvent[4];
//     }

//     int getEventBlockCount(){
//         return endIndex - startIndex + 1;
//     }
// }

class EventInfo{
    String name;
    Color color;
    String belongingEvent = "";
    // List<String> includingEvents;

    EventInfo(this.name, List<int> color)
        : color = Color.fromRGBO(color[0], color[1], color[2], 1.0);
}


class DayRecord{
    // 以天为单位是最基本的，在加载数据的时候最小单位就是天，所有其他的本质都是List<DayBlockData>
    // late DateTime date; // 这里非要用DateTime的原因是，你不能指望int类型的20241232可以自动进位成20250101，但是DateTime.parse可以。但是我实在没发现这玩意儿有用上过，还是改回String吧
    late String date;
    // late String recordKey;
    List<EventRecord> events = [];
    List<List<Block>> blocks = [];

    DayRecord(String timeStamp, List<EventRecord>? inputEvents, UserProfileLoader configLoader){
        // print("== DayRecord input: $timeStamp, $inputEvents");
        // recordKey = timeStamp;
        // date = DateTime.parse("${timeStamp.substring(0,4)}-${timeStamp.substring(4,6)}-${timeStamp.substring(6)}");
        date = timeStamp;
        // List<int> blockDatePrefix = [date.year,date.month,date.day];
        List<int> blockDatePrefix = [int.parse(timeStamp.substring(0,4)), int.parse(timeStamp.substring(4,6)), int.parse(timeStamp.substring(6))];
        // events = List.generate(rawEvents.length, (i) => Event(rawEvents[i]));
        if (inputEvents != null){
          events = inputEvents;
        }else{
          events = [];
        }
        // print("== DayRecord: $date, $events");

        // 给有记录的地方创建出block
        List<Block> tempBlockList = [];
        for (var event in events){
            String eventName = event.eventInfo;
            Color color = configLoader.getBlockColorByEventType(eventName);
            List<Block> eventBlocks = List.generate(event.getEventBlockCount(), (index) => Block(eventName, blockDatePrefix + [event.startIndex+index], color));
            tempBlockList.addAll(eventBlocks);
        }

        // 在把有记录的block往blocks里按小时填放的过程中，顺带检查一下有没有缺的。如果有就给补齐空白block
        List<Block> hourBlocks = [];
        int blockCount = 0;
        for (var block in tempBlockList){
            // 注释是我debug后的代码，能跑但是很丑。下面的代码是deepseek优化过的……在后半夜为我节省了大量的头发
            // print("== DayRecord-1: ${block.blockIndex[3]}, $blockCount, ${block.eventType}");
            // if (block.blockIndex[3] == blockCount){
            //     hourBlocks.add(block);
            //     blockCount++;

            //     if (hourBlocks.length == 4){
            //         blocks.add(hourBlocks);
            //         hourBlocks = [];
            //     }
            //     print("== DayRecord-2: ${block.blockIndex[3]}, $blockCount, ${block.eventType}");
            // }else{
            //     for(int i=blockCount;blockCount<block.blockIndex[3]; i++){
            //         hourBlocks.add(Block("", blockDatePrefix + [blockCount], configLoader.getBlockColorByEventType("")));
            //         blockCount++;
            //         print("== DayRecord-3: ${block.blockIndex[3]}, $blockCount, ${block.eventType}");

            //         if (hourBlocks.length == 4){
            //             blocks.add(hourBlocks);
            //             hourBlocks = [];
            //         }
            //     }

            //     hourBlocks.add(block);
            //     blockCount++;
            //     if (hourBlocks.length == 4){
            //         blocks.add(hourBlocks);
            //         hourBlocks = [];
            //     }
            // }
            
            while (block.blockIndex[3] > blockCount) {
                hourBlocks.add(Block("", blockDatePrefix + [blockCount], configLoader.getBlockColorByEventType("")));
                blockCount++;

                // 检查是否需要将 hourBlocks 添加到 blocks
                if (hourBlocks.length == 4) {
                  blocks.add(hourBlocks);
                  hourBlocks = [];
                }
            }

            // 添加当前 block
            hourBlocks.add(block);
            blockCount++;

            // 检查是否需要将 hourBlocks 添加到 blocks
            if (hourBlocks.length == 4) {
                blocks.add(hourBlocks);
                hourBlocks = [];
            }
        }

        // 给一天中缺的补齐
        if (24*4 > blockCount){
            tempBlockList.clear();
            tempBlockList.addAll(List<Block>.generate(96 - blockCount, (index) => Block("", blockDatePrefix + [tempBlockList.length+index], configLoader.getBlockColorByEventType(""))));
            for (;blockCount<96; blockCount++){
                // print("== DayRecord-3: empty block");
                hourBlocks.add(Block("", blockDatePrefix + [blockCount], configLoader.getBlockColorByEventType("")));

                if (hourBlocks.length == 4){
                    // print("== DayRecord-3: add hour");
                    blocks.add(hourBlocks);
                    hourBlocks = [];
                }
            }
        }
        
        // print("== DayRecord: $date, ${events.length}, ${blocks.length}");
    }

    // List<dynamic> transformToDataFomula(){
    //     return List.generate(events.length, (i) => [events[i].startIndex,events[i].endIndex,events[i].event,events[i].type,events[i].comment]);
    // }

    List<Block> getBlocksFromOneDayByIndex_OpenRange(int startIndex, int endIndex){
        List<Block> requiredBlocks = [];
        for(int h=startIndex~/4; h<=endIndex~/4; h++){
            for (var block in blocks[h]){
                if (block.blockIndex[3] > startIndex && block.blockIndex[3] < endIndex){
                    requiredBlocks.add(block);
                }
            }
        }

        return requiredBlocks;
    }

    List<Block> getBlocksFromOneDayByIndex_CloseRange(int startIndex, int endIndex){
        List<Block> requiredBlocks = [];
        for(int h=startIndex~/4; h<=endIndex~/4; h++){
            for (var block in blocks[h]){
                if (block.blockIndex[3] >= startIndex && block.blockIndex[3] <= endIndex){
                    // print("== block.getBlocksFromOneDayByIndex_CloseRange getting block: ${block.blockIndex}");
                    requiredBlocks.add(block);
                }
            }
        }

        return requiredBlocks;
    }

    Block getBlockFromOneDayByIndex(int index){
        return blocks[index~/4][index%4];
    }

    Future<void> updateDayRecordEvents() async {
        List<EventRecord> newEvents = [];
        String lastBlockEventType = "";

        List<int> temp_BlockHashCode = [];

        for (var hourBlocks in blocks){
            for (var block in hourBlocks){
                temp_BlockHashCode.add(block.hashCode);
                if (block.eventType == ""){ continue; }

                if (newEvents.length == 0){
                    lastBlockEventType = block.eventType;
                    newEvents.add(EventRecord(startIndex: block.blockIndex[3], endIndex: block.blockIndex[3], eventInfo: lastBlockEventType));
                }else{
                    if (lastBlockEventType == block.eventType){
                        newEvents.last.endIndex += 1;
                    }else{
                        lastBlockEventType = block.eventType;
                        newEvents.add(EventRecord(startIndex: block.blockIndex[3], endIndex: block.blockIndex[3], eventInfo: lastBlockEventType));
                    }
                }
            }
        }
        // print("== eventList of ${this.date}: ${events}; ${temp_BlockHashCode}");
        events = newEvents;
    }

    // void markRightNowBlock(){
    //     final rightNowTime = DateTime.now().toString().split(" ")[1].split(":");
    //     final hour = int.parse(rightNowTime[0]);
    //     final quarter = int.parse(rightNowTime[1]) ~/ 15;

    //     blocks[hour][quarter].isRightNow = true;
    // }

}
