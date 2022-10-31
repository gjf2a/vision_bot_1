import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:network_info_plus/network_info_plus.dart';

const int ourPort = 8888;

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum RobotStatus {
  notStarted, started, stopped;
}

class _MyHomePageState extends State<MyHomePage> {
  late CameraController controller;
  final Queue<String> _requests = Queue();
  late CameraOpticFlowPainter _livePicture;
  String _ipAddr = "Awaiting IP Address...";
  String _incoming = "Setting up server...";
  RobotStatus _robotStatus = RobotStatus.notStarted;
  RobotState _robotState = RobotState(left: WheelAction.stop, right: WheelAction.stop);

  @override
  void initState() {
    super.initState();
    _livePicture = CameraOpticFlowPainter(_requests);
    controller = CameraController(_cameras[0], ResolutionPreset.medium);
    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      controller.startImageStream((image) {
        setState(() {
          _livePicture.setImageWithAction(image, _robotState).whenComplete(() {});
        });
      });
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            print('User denied camera access.');
            break;
          default:
            print('Handle other errors.');
            break;
        }
      }
    });

    _setupServer();
    _findIPAddress();
  }

  Widget makeCmdButton(String label, void Function() cmd, Color color) {
    return SizedBox(
        width: 100,
        height: 100,
        child: ElevatedButton(
            onPressed: cmd,
            style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20))),
            child: Text(label)));
  }

  Future<void> _findIPAddress() async {
    // Thank you https://stackoverflow.com/questions/52411168/how-to-get-device-ip-in-dart-flutter
    String? ip = await NetworkInfo().getWifiIP();
    setState(() {
      _ipAddr = "My IP: ${ip!}";
    });
  }

  Future<void> _setupServer() async {
    try {
      ServerSocket server = await ServerSocket.bind(InternetAddress.anyIPv4, ourPort);
      server.listen(_listenToSocket); // StreamSubscription<Socket>
      setState(() {
        _incoming = "Server ready";
      });
    } on SocketException catch (e) {
      print("ServerSocket setup error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error: $e"),
      ));
    }
  }

  void _listenToSocket(Socket socket) {
    socket.listen((data) {
      String msg = String.fromCharCodes(data);
      print("received $msg");
      if (msg == "cmd") {
        if (_requests.isEmpty) {
          socket.write("None");
        } else {
          socket.write(_requests.removeFirst());
        }
      } else {
        getProcessedData(msg);
      }
      socket.close();
    });
  }

  Future<void> getProcessedData(String incomingData) async {
    String processed = await api.processSensorData(incomingData: incomingData);
    SensorData data = await api.parseSensorData(incomingData: incomingData);
    _robotState = RobotState.decode(data.actionTag);
    setState(() {
      _incoming = processed;
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  String shiftStr() {
    CorrelationFlow? shift = _livePicture.getShift();
    if (shift == null) {
      return "No shift";
    } else {
      return "Shift: (${shift.dx}, ${shift.dy})";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return Container();
    }
    return MaterialApp(
        home: Scaffold(
            appBar: AppBar(
                title: const Text("This is a title")),
            body: Center(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      CustomPaint(painter: _livePicture),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _startStopButton(),
                          Text(_ipAddr),
                          Text("Grabbed: ${_livePicture.frameCount()} (${_livePicture.width()} x ${_livePicture.height()}) FPS: ${_livePicture.fps().toStringAsFixed(2)}"),
                          Text(shiftStr()),
                          Text(_incoming),
                        ],
                      ),
                    ]
                )
            )
        )
    );
  }

  Widget _startStopButton() {
    if (_robotStatus == RobotStatus.notStarted) {
      return makeCmdButton("Start", () {
        api.resetPositionEstimate().then((value) {
          setState(() {
            _robotStatus = RobotStatus.started;
          });
          _requests.addLast('Start');
          print("Sending Start");
        });
      }, Colors.purple);
    } else if (_robotStatus == RobotStatus.started) {
      return makeCmdButton("Stop", () {
        api.resetPositionEstimate().then((value) {
          setState(() {
            _robotStatus = RobotStatus.stopped;
          });
          _requests.addLast('Stop');
          print("Sending Stop");
        });
      }, Colors.red);
    } else {
      return const Text("Robot stopped");
    }
  }
}

class CameraOpticFlowPainter extends CameraImagePainter {
  Uint8List? _lastYs;
  CorrelationFlow? _shift;
  RobotState _lastAction = RobotState(left: WheelAction.stop, right: WheelAction.stop);
  Queue requests;

  CameraOpticFlowPainter(this.requests);

  Future<void> setImageWithAction(CameraImage img, RobotState action) async {
    super.setImage(img);
    Uint8List ys = img.planes[0].bytes;
    if (_lastYs != null) {
      _shift = await api.getCorrelationFlow(prevYs: _lastYs!, currentYs: ys, width: img.width, height: img.height);
      if (requests.isEmpty) {
        requests.addLast("${_shift!.dx} ${_shift!.dy}");
      }
    }
    if (_lastYs == null || action != _lastAction) {
      _lastYs = ys;
      _lastAction = action;
    }
  }

  @override
  Future<void> setImage(CameraImage img) async {
    super.setImage(img);
    Uint8List ys = img.planes[0].bytes;
    if (_lastYs != null) {
      _shift = await api.getCorrelationFlow(prevYs: _lastYs!, currentYs: ys, width: img.width, height: img.height);
    }
    _lastYs = ys;
  }

  CorrelationFlow? getShift() {return _shift;}
}