// lib/pages/auth_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';
import 'dart:io'; // For SocketException

class AuthPage extends StatefulWidget {
  const AuthPage({Key? key}) : super(key: key);

  @override
  _AuthPageState createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Toggle between login and sign up mode.
  bool isLogin = true;
  bool isLoading = false;

  // Get the Supabase client instance.
  final supabase = Supabase.instance.client;

  /// Toggles the form mode (login vs. register).
  void _toggleFormType() {
    setState(() {
      isLogin = !isLogin;
    });
  }

  /// Authenticate the user (login or sign up) with Supabase.
  Future<void> _authenticate() async {
    // Retrieve and trim inputs.
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Simple input validation.
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and password.')),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      if (isLogin) {
        // Attempt to log in the user.
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        log('Login response: ${response.session}');

        if (response.user == null) {
          // In case the login did not create a valid session.
          throw Exception("Login failed. Please check your credentials.");
        }
      } else {
        // Attempt to sign up the user.
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
        );
        log('Sign-up response: ${response.user}');

        // Note: Depending on your Supabase settings, the user might need to confirm their email.
      }

      // Navigate to the HomePage after a successful authentication.
      Navigator.pushReplacementNamed(context, '/home');
    } on SocketException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Connection failed. Please check your internet connection.')),
      );
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Authentication error: ${e.message}")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Dispose controllers when the widget is disposed.
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Build the UI.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Authentication'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Email input field.
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              // Password input field.
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              // Informational text about password handling.
              const Text(
                'Note: Your password is securely handled by Supabase. '
                'It is hashed and stored safely on the server; '
                'your plain text password is never saved on this device.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Login or Register button.
              ElevatedButton(
                onPressed: isLoading ? null : _authenticate,
                child: isLoading
                    ? const CircularProgressIndicator()
                    : Text(isLogin ? 'Login' : 'Register'),
              ),
              // Toggle between Login and Register.
              TextButton(
                onPressed: _toggleFormType,
                child: Text(
                  isLogin
                      ? "Don't have an account? Register"
                      : "Already have an account? Login",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
