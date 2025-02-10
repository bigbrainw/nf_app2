// lib/pages/permissions_page.dart
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({Key? key}) : super(key: key);

  @override
  _PermissionsPageState createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.bluetooth.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.location.request();
    }
    setState(() {
      _permissionsGranted = true;
    });
    await Future.delayed(const Duration(seconds: 1));
    Navigator.pushReplacementNamed(context, '/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _permissionsGranted
            ? const Text("Permissions granted. Redirecting...")
            : const CircularProgressIndicator(),
      ),
    );
  }
}
