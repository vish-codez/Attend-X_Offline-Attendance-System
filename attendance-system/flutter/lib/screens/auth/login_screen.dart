import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/custom_text_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _isLoading = false;
  bool _showAdvanced = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final url = await ApiService.instance.getBaseUrl();
    _serverUrlController.text = url ?? 'http://192.168.1.100:8080';
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    if (_showAdvanced) {
      await ApiService.instance.setBaseUrl(_serverUrlController.text.trim());
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authProvider.notifier).login(
            _usernameController.text.trim(),
            _passwordController.text,
          );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Login failed: ${e.toString().replaceAll('Exception: ', '')}',
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.school_rounded, size: 72, color: Colors.white),
                const SizedBox(height: 12),
                const Text('Attendance System',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const Text('Offline LAN-Based',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 40),

                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Sign In',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          CustomTextField(
                            controller: _usernameController,
                            label: 'Username',
                            prefixIcon: Icons.person_outline,
                            validator: (v) => v?.isEmpty == true ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                          CustomTextField(
                            controller: _passwordController,
                            label: 'Password',
                            prefixIcon: Icons.lock_outline,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) => v?.isEmpty == true ? 'Required' : null,
                          ),
                          const SizedBox(height: 8),

                          // Advanced: server URL
                          TextButton.icon(
                            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
                            icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 16),
                            label: Text(_showAdvanced ? 'Hide Server Settings' : 'Server Settings'),
                            style: TextButton.styleFrom(foregroundColor: Colors.grey),
                          ),

                          if (_showAdvanced) ...[
                            CustomTextField(
                              controller: _serverUrlController,
                              label: 'Server URL',
                              prefixIcon: Icons.dns_outlined,
                              hint: 'http://192.168.1.100:8080',
                            ),
                            const SizedBox(height: 8),
                          ],

                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1565C0),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }
}
