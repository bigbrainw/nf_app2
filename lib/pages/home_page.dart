// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<String> eegData = [];
  bool isConnected = false;
  StreamSubscription? connectionStateSubscription;
  StreamSubscription? characteristicSubscription;
  final ScrollController _scrollController = ScrollController();
  bool isRecording = false;
  List<String> recordedData = [];

  // BLE Configuration
  final String SERVICE_UUID = "22bbaa2a-c8c3-4d4b-8d7e-96b704283c6c";
  final String CHARACTERISTIC_UUID = "dbecd60f-595a-4ff1-b9cd-fe0491cc1d0d";

  // Focus level indicator (0 to 100)
  double focusLevel = 0;

  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    // Permissions are handled in PermissionsPage, authentication is handled in AuthPage.
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
        scanResults = results.where((result) => result.device.name.isNotEmpty).toList();
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

      // Start polling the backend for focus level updates every 2 seconds.
      _focusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        listenFocusLevelFromBackend();
      });

      connectionStateSubscription = device.state.listen((state) {
        if (state == BluetoothDeviceState.disconnected) {
          setState(() {
            isConnected = false;
            connectedDevice = null;
          });
          _showSnackBar('Device disconnected');
          _focusTimer?.cancel();
        }
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString() == CHARACTERISTIC_UUID &&
                characteristic.properties.notify) {
              await characteristic.setNotifyValue(true);
              characteristicSubscription =
                  characteristic.value.listen((value) {
                _handleEEGData(value);
              });
            }
          }
        }
      }
    } catch (e) {
      _showSnackBar('Failed to connect: ${e.toString()}');
    }
  }

  void _handleEEGData(List<int> data) {
    final dataString = data
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    
    setState(() {
      eegData.add(dataString);
      if (eegData.length > 100) {
        eegData.removeAt(0);
      }
      if (isRecording) {
        recordedData.add(dataString);
      }
    });

    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
        isConnected = false;
        eegData.clear();
      });
      connectionStateSubscription?.cancel();
      characteristicSubscription?.cancel();
      _focusTimer?.cancel();
    }
  }

  Future<void> listenFocusLevelFromBackend() async {
    try {
      final response = await http.get(Uri.parse('https://clean-eeg.onrender.com/focus'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data.containsKey('focus_level')) {
          double newFocusLevel = (data['focus_level'] is num)
              ? data['focus_level'].toDouble()
              : 0.0;
          setState(() {
            focusLevel = newFocusLevel;
          });
        }
      } else {
        log('Error getting focus level: ${response.statusCode}');
      }
    } catch (e) {
      log('Exception in listenFocusLevelFromBackend: $e');
    }
  }

  Future<void> sendDataToServer() async {
    try {
      final response = await http.post(
        Uri.parse('https://clean-eeg.onrender.com/eeg-data'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'data': eegData}),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> resBody = json.decode(response.body);
        if (resBody.containsKey('focus_level')) {
          double newFocusLevel = (resBody['focus_level'] is num)
              ? resBody['focus_level'].toDouble()
              : 0.0;
          setState(() {
            focusLevel = newFocusLevel;
          });
        }
        _showSnackBar('Data sent successfully');
      } else {
        throw Exception('Failed to send data: ${response.statusCode}');
      }
    } catch (e) {
      _showSnackBar('Failed to send data: ${e.toString()}');
    }
  }

  Future<void> stopRecordingAndSend() async {
    setState(() {
      isRecording = false;
    });
    if (recordedData.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('https://clean-eeg.onrender.com/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'data': recordedData}),
        );

        if (response.statusCode == 200) {
          _showSnackBar('Recorded data sent successfully');
        } else {
          throw Exception('Failed to send recorded data: ${response.statusCode}');
        }
      } catch (e) {
        _showSnackBar('Failed to send recorded data: ${e.toString()}');
      }
    }
  }

  void startRecording() {
    setState(() {
      isRecording = true;
      recordedData.clear();
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _getFocusColor(double level) {
    if (level < 40) return Colors.red;
    if (level < 70) return Colors.amber;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    // Retrieve the current user from Supabase.
    final currentUser = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EEG BLE Monitor'),
        actions: [
          // Display the user's ID in the top right corner, if available.
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Text(
                  'ID: ${currentUser.id}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          IconButton(
            icon: Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth),
            onPressed: null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Row of control buttons.
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(isScanning ? Icons.stop : Icons.search),
                  label: Text(isScanning ? 'Stop Scan' : 'Start Scan'),
                  onPressed: isScanning ? () => FlutterBluePlus.stopScan() : startScan,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Send Data'),
                  onPressed: isConnected ? sendDataToServer : null,
                ),
                ElevatedButton.icon(
                  icon: Icon(isRecording ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
                  onPressed: isConnected ? (isRecording ? null : startRecording) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecording ? Colors.red : null,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save & Send'),
                  onPressed: isConnected && isRecording ? stopRecordingAndSend : null,
                ),
              ],
            ),
          ),
          // If not connected, show the scan results list.
          if (isScanning || (!isConnected && scanResults.isNotEmpty))
            Expanded(
              flex: 1,
              child: ListView.builder(
                itemCount: scanResults.length,
                itemBuilder: (context, index) {
                  final result = scanResults[index];
                  return ListTile(
                    title: Text(
                      result.device.name.isEmpty ? 'Unknown Device' : result.device.name,
                    ),
                    subtitle: Text(result.device.id.toString()),
                    trailing: ElevatedButton(
                      child: const Text('Connect'),
                      onPressed: () => connectToDevice(result.device),
                    ),
                  );
                },
              ),
            ),
          // If connected, show a swipeable PageView with the focus indicator and raw data.
          if (isConnected)
            Expanded(
              flex: 2,
              child: PageView(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 150,
                          height: 150,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: focusLevel / 100,
                                strokeWidth: 12,
                                valueColor: AlwaysStoppedAnimation<Color>(_getFocusColor(focusLevel)),
                                backgroundColor: Colors.grey[800],
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
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: eegData.length,
                      itemBuilder: (context, index) {
                        return Text(
                          eegData[index],
                          style: const TextStyle(
                            color: Colors.green,
                            fontFamily: 'Courier',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: isConnected
          ? FloatingActionButton(
              onPressed: disconnectDevice,
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
    _scrollController.dispose();
    super.dispose();
  }
}
