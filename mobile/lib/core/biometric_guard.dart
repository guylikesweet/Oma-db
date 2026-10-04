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
      // Attempt the native biometric prompt directly. Some Android devices
      // report canCheckBiometrics inconsistently even though the system can
      // successfully present the enrolled biometric prompt.
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
    // Web/classic authentication is password-based. Mobile gets the OS
    // biometric first, with an explicit password fallback for hardware issues.
    Future<bool> passwordFallback() async {
      final verifier = passwordVerifier;
      if (verifier == null) return false;
      final controller = TextEditingController();
      try {
        final password = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Verify with password'),
            content: TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
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
        if (!ok && context.mounted) _show(context, 'Password verification failed.');
        return ok;
      } finally {
        controller.dispose();
      }
    }

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
    } catch (e) {
      // Hardware/OS biometric errors must never lock the user out.
      return passwordFallback();
    }
  }

  static void _show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
