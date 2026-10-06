// ignore_for_file: dead_code

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

/// Gates sensitive mobile actions with the device's enrolled biometrics.
///
/// Raw biometric data never leaves the device. The app only receives the
/// success/failure result from the operating system.
class BiometricGuard {
  BiometricGuard._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Set by the authenticated mobile session. Returns true only when the
  /// server verifies the user's current password.
  static Future<bool> Function(String password)? passwordVerifier;

  static Future<bool> canUseBiometrics() async {
    if (kIsWeb) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateForLogin({
    required String reason,
  }) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> require(
    BuildContext context, {
    required String reason,
  }) async {
    Future<bool> passwordFallback() async {
      final verifier = passwordVerifier;
      if (verifier == null) return false;
      final controller = TextEditingController();
      try {
        final password = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Verify with password'),
            content: StatefulBuilder(
              builder: (context, setState) {
                var obscure = true;
                return TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => obscure = !obscure),
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                  onSubmitted: (value) => Navigator.pop(dialogContext, value),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, controller.text),
                child: const Text('Verify'),
              ),
            ],
          ),
        );
        if (password == null || password.isEmpty) return false;
        final ok = await verifier(password);
        if (!ok && context.mounted) {
          _show(context, 'Password verification failed.');
        }
        return ok;
      } finally {
        controller.dispose();
      }
    }

    // kIsWeb is a compile-time constant on each Flutter target. This source
    // is shared with the web build, where this branch is required.
    // ignore: dead_code
    if (kIsWeb) return passwordFallback();

    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return passwordFallback();

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      if (authenticated) return true;
      return passwordFallback();
    } catch (_) {
      return passwordFallback();
    }
  }

  static void _show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
