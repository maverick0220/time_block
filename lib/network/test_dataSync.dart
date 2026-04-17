import 'dart:io';
import 'dart:convert';

// 采用UDP局域网广播的方式，发射端和接收端建立联系
void startBroadcast(String deviceName, String ip, int port) async {
  final broadcastAddress = InternetAddress("255.255.255.255");
  final broadcastPort = 8888;

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
  socket.broadcastEnabled = true;

  final message = jsonEncode({
    "deviceName": deviceName,
    "ip": ip,
    "port": port,
  });

  socket.send(utf8.encode(message), broadcastAddress, broadcastPort);
  print("Broadcast sent: $message");
}

void listenForBroadcast() async {
  final broadcastPort = 8888;

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
  print("Listening for broadcast on port $broadcastPort");

  socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final datagram = socket.receive();
      if (datagram != null) {
        final message = utf8.decode(datagram.data);
        final deviceInfo = jsonDecode(message);
        print("Device discovered: ${deviceInfo['deviceName']} at ${deviceInfo['ip']}:${deviceInfo['port']}");
      }
    }
  });
}

Future<void> startSync(String targetIp, int targetPort) async {
  final socket = await Socket.connect(targetIp, targetPort);
  print("Connected to $targetIp:$targetPort");

  // 发送同步请求
  final syncRequest = jsonEncode({
    "type": "syncRequest",
    "dataRange": {
      "startTime": "2024-01-01T00:00:00Z",
      "endTime": "2024-01-31T23:59:59Z"
    }
  });
  socket.write(syncRequest);
  print("Sync request sent: $syncRequest");

  // 接收设备 B 的响应
  socket.listen(
    (data) {
      final response = jsonDecode(utf8.decode(data));
      print("Sync response received: $response");

      // 处理接收到的数据
      if (response['type'] == 'syncResponse') {
        final syncData = response['data'];
        print("Data to process: $syncData");

        // 发送本地数据给设备 B
        final localData = jsonEncode({
          "type": "syncData",
          "data": [
            {"id": 3, "content": "data3"},
            {"id": 4, "content": "data4"}
          ]
        });
        socket.write(localData);
        print("Local data sent: $localData");
      }
    },
    onDone: () {
      print("Sync completed");
      socket.destroy();
    },
    onError: (error) {
      print("Sync error: $error");
      socket.destroy();
    },
  );
}