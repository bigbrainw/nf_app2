import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
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
  double focusLevel = 0;
  IO.Socket? _socket;
  bool _socketConnected = false;
  List<double> bleGraphData = [];

  // Local buffer for unsent EEG data (each entry is a list of doubles from one BLE notification)
  List<List<double>> _unsentDataQueue = [];
  Timer? _transmissionTimer;

  @override
  void initState() {
    super.initState();
    _startSocket(); // Establish the socket connection when the page initializes

    // Start a timer to periodically send buffered data every 200 milliseconds
    _transmissionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendBufferedData();
    });
  }

  void startScan() {
    setState(() {
      scanResults.clear();
      isScanning = true;
    });
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 4))
        .then((_) => setState(() => isScanning = false))
        .catchError((error) {
      setState(() => isScanning = false);
      _showSnackBar('Failed to start scan: $error');
    });
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results.where((r) => r.device.name.isNotEmpty).toList();
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

  // This function is called whenever a BLE notification is received.
  // It decodes, parses, and buffers the incoming EEG data.
  void _handleEEGData(List<int> data) {
    try {
      final decodedString = utf8.decode(data).trim();
      List<double> values =
          decodedString.split(',').map((e) => double.tryParse(e) ?? 0).toList();

      // Update UI for the graph (optional visual feedback)
      setState(() {
        if (values.isNotEmpty) {
          bleGraphData.add(values.reduce((a, b) => a + b) / values.length);
          if (bleGraphData.length > 100) bleGraphData.removeAt(0);
        }
      });

      // Buffer the data instead of sending it immediately
      _unsentDataQueue.add(values);
    } catch (e) {
      log('Error handling EEG data: $e');
    }
  }

  // This function sends the buffered data via the socket connection.
  // It clears the local buffer after sending.
  void _sendBufferedData() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (_socketConnected &&
        _socket != null &&
        userId != null &&
        _unsentDataQueue.isNotEmpty) {
      // Copy the buffered data and then clear the queue
      final batchToSend = List.from(_unsentDataQueue);
      _unsentDataQueue.clear();

      log('Sending batch of ${batchToSend.length} data sets to backend...');
      _socket!.emit('eeg_data', {
        'user_id': userId,
        'data': batchToSend,
      });
      log('Sent EEG batch data', time: DateTime.now());
    }
  }

  Future<void> _startSocket() async {
    try {
      _socket = IO.io(
        'https://clean-eeg.onrender.com',
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );

      _socket!.onConnect((_) {
        log('Socket connected ' + DateTime.now().toString());
        setState(() => _socketConnected = true);
      });

      // Listen for responses from the backend
      _socket!.on('eeg_response', (data) {
        log('Received EEG response: $data');
        // Assume the response contains a beta_power value that determines focusLevel
        final double newFocusLevel =
            (data['beta_power'] as num?)?.toDouble() ?? 0;
        setState(() {
          focusLevel = newFocusLevel;
        });
      });

      _socket!.onDisconnect((_) {
        log('Socket disconnected ' + DateTime.now().toString());
        setState(() => _socketConnected = false);
      });

      _socket!.onError(
          (err) => log('Socket error: $err ' + DateTime.now().toString()));
      _socket!.connect();
    } catch (e) {
      _showSnackBar('Socket error: $e ' + DateTime.now().toString());
    }
  }

  Future<void> _stopSocket() async {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      setState(() {
        _socketConnected = false;
        _socket = null;
      });
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          // Buttons for scanning and socket connection
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(isScanning ? Icons.stop : Icons.search),
                  label: Text(isScanning ? 'Stop Scan' : 'Start Scan'),
                  onPressed: isScanning ? FlutterBluePlus.stopScan : startScan,
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
          // Display scan results if not connected
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
          // Main content when connected: focus indicator and live graph
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
    _transmissionTimer?.cancel();
    _stopSocket();
    super.dispose();
  }
}
