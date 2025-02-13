// lib/main.dart
import 'package:flutter/material.dart';
import 'pages/permissions_page.dart';
import 'pages/auth_page.dart';
import 'pages/home_page.dart';
import 'pages/sign_up_page.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: const String.fromEnvironment('supabase_url',
        defaultValue: 'https://hgayqneyregefvokcuiy.supabase.co'),
    anonKey: const String.fromEnvironment('supabase_anon_key',
        defaultValue:
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhnYXlxbmV5cmVnZWZ2b2tjdWl5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Mzg1NDM3NTcsImV4cCI6MjA1NDExOTc1N30._3gQfG2lEkO0H0z55zCjK9_sjhU8eu-jdHe8Ux7rkQY'),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EEG BLE Monitor',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      initialRoute: '/permissions',
      routes: {
        '/permissions': (context) => const PermissionsPage(),
        '/auth': (context) => const AuthPage(),
        '/home': (context) => const HomePage(),
        '/signup': (context) => const SignupPage(),
      },
    );
  }
}
