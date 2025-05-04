import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:time_block/loaders.dart';

class DataSync{

    String broadcastAddressRange = "192.168.99.";
    String serverIP = "";
    int serverPort = 8888;
    // int localPort = 9999;

    late Socket socket;

    late UserProfileLoader userProfileLoader;
    late OperationControl operationControl;

    // DataSync(String IPRange, int local_port, int server_port, UserProfileLoader dataLoader, OperationControl operationloader){
    //     broadcastAddressRange = IPRange;
    //     serverPort = server_port;
    //     localPort = local_port;
    //     userProfileLoader = dataLoader;
    //     operationControl = operationloader;
    // }

    DataSync(String IPRange, int server_port, UserProfileLoader dataLoader){
        broadcastAddressRange = IPRange; // ip网段，局域网ip网段。如果是newifi3的局域网的话，
        serverPort = server_port; // 服务端的端口。客户端的端口无所谓，因为是临时建立的
        userProfileLoader = dataLoader; // 数据类的pointer，直接走这里调数据

        // socket = await searchServer_test();
    }

    Future<void> runUploadTask() async {
        // 上传客户端数据到服务端。因为上传完一个客户端的还有别的客户端没上传完，服务端这个时候可能还是没有全部数据
        // 所以把上传数据和同步数据（其实就是下载完整版并更新到客户端里）拆成了两个部分

        // - todo: 服务端那边还没有json数据解析的功能
        if (socket == null){
            final socket = await searchServer_test();
        }

    }

    Future<void> runSnycTask() async{
        // 优先保证服务端的数据完整，再补全客户端上的数据
        // -todo: 现在还没考虑服务端的数据同步到客户端

        // listenLocalPort();
        
        final socket = await searchServer_test();

        try {
            // 配置数据流处理器
            final reader = socket.transform(utf8.decoder.cast<Uint8List, String>()).transform(const LineSplitter());
            // final reader = socket.transform(utf8.decoder as StreamTransformer<Uint8List, dynamic>).transform(const LineSplitter());

            // 发送请求
            socket.writeln(jsonEncode({"time_block_client": "get_to_sync_dates"}));
            await socket.flush();
            print('📨 已发送验证请求');

            // 把数据往服务端传
            final syncTask = jsonDecode(await reader.first) as Map<String, dynamic>;
            if (syncTask.containsKey("success")){
                String toSyncData = await userProfileLoader.exportRecordDataByDates(syncTask["success"]);
                socket.writeln(toSyncData);
                await socket.flush();
            }

            // 整理出来本地还缺什么，问服务端要
            

            await socket.close();
        }catch (e) {
            print("== Failed to connect to server: $e");
            print("== runSnycTask: Cannot find server in ${broadcastAddressRange+"x"}");
            return;
        }
    }

    Future<void> listenLocalPort() async {
        final server = await ServerSocket.bind(InternetAddress.anyIPv4, serverPort);
        print('== listenLocalPort: Server is listening on port $serverPort');

        await for (Socket socket in server) {
            print('== listenLocalPort: Client connected: ${socket.remoteAddress.address}:${socket.remotePort}');

            // 接收客户端的身份验证信息
            socket.listen((List<int> data) {
                final authMessage = String.fromCharCodes(data);
                print('Received authentication message: $authMessage');

                // 发送验证反馈信息
                const responseMessage = 'Authentication successful. Ready to receive data.';
                socket.write(responseMessage);
            }, onDone: () {
                print('== listenLocalPort Client: disconnected');
                // socket.destroy();
            }, onError: (error) {
                print('== listenLocalPort Error: $error');
                // socket.destroy();
            });
        }
    } 


    Future<Socket> searchServer() async {
        print("== DataSync did call search");
        final verifyMessage = json.encode({"time_block_client": "Maverick"});

        for (int i=0; i<256; i++){
            print("== DataSync searchServer: binding ${broadcastAddressRange+"$i"} ${serverPort}");
            try {
                final socket = await Socket.connect(broadcastAddressRange+"${i}", serverPort, timeout: Duration(milliseconds: 10));
                // final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
                
                socket.write(verifyMessage);
                await socket.flush();
                // await socket.close();
                print('== searchServer: Data sent successfully to ${socket.address}:${socket.port}');
                return socket;
                
            } catch (e) {
                // 忽略连接错误
            }
        }
        // return null;
        // 如果所有尝试都失败，抛出异常
        throw Exception("No server found in ${broadcastAddressRange}x");
    }

    Future<Socket> searchServer_test() async {
        print("== DataSync did call search");
        final verifyMessage = json.encode({"time_block_client": "Maverick", "random": "752767126461438714652135752767126461435642673561653871"});

        print("== DataSync searchServer: binding 172.26.0.1 ${serverPort}");
        try {
            final socket = await Socket.connect("172.26.0.1", serverPort, timeout: Duration(milliseconds: 10));
            // final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
            
            socket.writeln(verifyMessage);
            await socket.flush();
            // await socket.close();
            print('== searchServer: Data sent successfully to ${socket.address}:${socket.port}');
            return socket;
            
        } catch (e) {
            // 忽略连接错误
        }
        // return null;
        // 如果所有尝试都失败，抛出异常
        throw Exception("No server found in ${broadcastAddressRange}x");
    }


}