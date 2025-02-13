// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import '../styles.dart';
import '../widgets/graph_widget.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  FlutterBluePlus flutterBluePlus = FlutterBluePlus();
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  bool isConnected = false;
  StreamSubscription? connectionStateSubscription;
  StreamSubscription? characteristicSubscription;
  Timer? _focusTimer;
  double focusLevel = 0;
  // Socket connection variables.
  IO.Socket? _socket;
  bool _socketConnected = false;

  // BLE data for graph.
  List<double> bleGraphData = [];

  @override
  void initState() {
    super.initState();
    // Permissions are handled in PermissionsPage, authentication is handled in AuthPage.
    // Start periodic focus level updates.
    _focusTimer = Timer.periodic(const Duration(seconds: 15), (timer) {

      listenFocusLevelFromBackend();
    });
  }

  void startScan() {
    setState(() {
      scanResults.clear();
      isScanning = true;
    });
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4)).then((_) {
      setState(() {
        isScanning = false;
      });
    }).catchError((error) {
      setState(() {
        isScanning = false;
      });
      _showSnackBar('Failed to start scan: $error');
    });
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults =
            results.where((result) => result.device.name.isNotEmpty).toList();
      });
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        connectedDevice = device;
        isConnected = true;
        focusLevel = 0;
      });
      connectionStateSubscription = device.state.listen((state) {
        if (state == BluetoothDeviceState.disconnected) {
          setState(() {
            isConnected = false;
            connectedDevice = null;
          });
          _showSnackBar('Device disconnected');
        }
      });
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            characteristicSubscription = characteristic.value.listen((value) {
              _handleEEGData(value);
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Failed to connect: ${e.toString()}');
    }
  }

  void _handleEEGData(List<int> data) {
    try {
      final decodedString = utf8.decode(data).trim();
      List<double> values =
          decodedString.split(',').map((e) => double.tryParse(e) ?? 0).toList();

      setState(() {
        if (values.isNotEmpty) {
          bleGraphData.add(values.reduce((a, b) => a + b) / values.length);
          if (bleGraphData.length > 100) {
            bleGraphData.removeAt(0);
          }
        }
      });

      // Send data to socket if connected
      if (_socketConnected && _socket != null) {
        log('Sending BLE data to socket: $decodedString');
        try {
          _socket!.emit('eeg_data', {
            'data': decodedString,
            'timestamp': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          log('Socket emit error: $e');
          _reconnectSocket();
        }
      }
    } catch (e) {
      log('Error handling EEG data: $e');
    }
  }

  // json response example:
  //     {
  // "eeg_data": [
  // {
  // "beta_power": 12.7291946411133,
  // "created_at": "2025-02-13T00:54:44.210034+00:00",
  // "eeg_data": [[123,123,1234,1234,123456,-1245]],
  // "id": 16,
  //       "user_id": "6300f723-b5d2-4672-9e29-bcc62ac9f547"
  //     }
  //   ]
  // }


  Future<void> listenFocusLevelFromBackend() async {
    try {
      final response = await http.get(
        Uri.parse('https://clean-eeg.onrender.com/eeg-data/${Supabase.instance.client.auth.currentUser?.id}'),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data.containsKey('eeg_data')) {
          // Assuming you want the first item in the eeg_data array
          final List<dynamic> eegDataList = data['eeg_data'];
          if (eegDataList.isNotEmpty) {
            final Map<String, dynamic> firstEegData = eegDataList[0];

            // Extract beta_power (or any other field) as the focus level
            double newLevel = (firstEegData['beta_power'] is num)
                ? firstEegData['beta_power'].toDouble()
                : 0.0;

            setState(() {
              focusLevel = newLevel;
            });
          }
        }
      } else {
        log('Error getting focus level: ${response.statusCode}');
      }
    } catch (e) {
      log('Exception in listenFocusLevelFromBackend: $e');
    }
  }
  Future<void> _startSocket() async {
    try {
      log('Attempting to connect socket...');
      IO.Socket socket =
          IO.io('https://clean-eeg.onrender.com'); // Corrected socket URL
      socket.onConnect((_) {
        print('connect');
        socket.emit('msg', 'test');
      });
      socket.on('event', (data) => print(data));
      socket.onDisconnect((_) => print('disconnect'));
      socket.on('fromServer', (_) => print(_));

      _socket = socket;
      await _socket!.connect();
    } catch (e) {
      log('Error initializing socket: $e');
      _showSnackBar('Failed to initialize socket: $e');
    }
  }

  Future<void> _stopSocket() async {
    try {
      if (_socket != null) {
        log('Disconnecting socket...');
        _socket!.disconnect();
        _socket!.dispose();
        setState(() {
          _socketConnected = false;
          _socket = null;
        });
        _showSnackBar('Socket disconnected');
      }
    } catch (e) {
      log('Error stopping socket: $e');
      _showSnackBar('Error disconnecting socket: $e');
    }
  }

  void _reconnectSocket() async {
    log('Attempting to reconnect socket...');
    await _stopSocket();
    await Future.delayed(const Duration(seconds: 1));
    await _startSocket();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Color _getFocusColor(double level) {
    if (level < 40) return Colors.red;
    if (level < 70) return AppStyles.accentColor;
    return AppStyles.accentColor;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        // ...existing code...
        title: const Text('EEG BLE Monitor'),
        actions: [
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Text(
                  'User: ${currentUser.email}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          IconButton(
            icon:
                Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
            onPressed: null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Control Buttons Row: Keep Scan and add Socket Start/Stop button.
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(isScanning ? Icons.stop : Icons.search),
                  label: Text(isScanning ? 'Stop Scan' : 'Start Scan'),
                  onPressed:
                      isScanning ? () => FlutterBluePlus.stopScan() : startScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.buttonColor,
                    foregroundColor: AppStyles.accentColor,
                  ),
                ),
                ElevatedButton.icon(
                  icon: Icon(_socketConnected ? Icons.stop : Icons.play_arrow),
                  label:
                      Text(_socketConnected ? 'Stop Socket' : 'Start Socket'),
                  onPressed: _socketConnected ? _stopSocket : _startSocket,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.buttonColor,
                    foregroundColor: AppStyles.accentColor,
                  ),
                ),
              ],
            ),
          ),
          // If not connected, show scan results.
          if (isScanning || (!isConnected && scanResults.isNotEmpty))
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: scanResults.length,
                itemBuilder: (context, index) {
                  final result = scanResults[index];
                  return ListTile(
                    title: Text(result.device.name.isEmpty
                        ? 'Unknown Device'
                        : result.device.name),
                    subtitle: Text(result.device.id.toString()),
                    trailing: ElevatedButton(
                      child: const Text('Connect'),
                      onPressed: () => connectToDevice(result.device),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyles.buttonColor,
                        foregroundColor: AppStyles.accentColor,
                      ),
                    ),
                  );
                },
              ),
            ),
          // If connected, show a swipeable PageView with focus indicator and graph.
          if (isConnected)
            Expanded(
              flex: 2,
              child: PageView(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 150,
                          height: 150,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: focusLevel / 100,
                                strokeWidth: 12,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    _getFocusColor(focusLevel)),
                                backgroundColor: Colors.black,
                              ),
                              Text(
                                '${focusLevel.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: _getFocusColor(focusLevel),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Focus Indicator',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  // Graph view for BLE data.
                  Container(
                    margin: const EdgeInsets.all(8.0),
                    child: GraphWidget(data: bleGraphData),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: isConnected
          ? FloatingActionButton(
              onPressed: () async {
                if (connectedDevice != null) {
                  await connectedDevice!.disconnect();
                  setState(() {
                    isConnected = false;
                    connectedDevice = null;
                  });
                  connectionStateSubscription?.cancel();
                  characteristicSubscription?.cancel();
                }
              },
              backgroundColor: AppStyles.accentColor,
              child: const Icon(Icons.bluetooth_disabled),
            )
          : null,
    );
  }

  @override
  void dispose() {
    connectionStateSubscription?.cancel();
    characteristicSubscription?.cancel();
    _focusTimer?.cancel();
    _stopSocket();
    super.dispose();
  }
}
