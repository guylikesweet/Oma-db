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

  static Future<bool> require(
    BuildContext context, {
    required String reason,
  }) async {
    // The Flutter web build does not expose the mobile local_auth API.
    // Keep the existing web functionality intact; native mobile builds
    // enforce the biometric gate below.
    if (kIsWeb) return true;

    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();

      if (!canCheck || !supported) {
        if (context.mounted) {
          _show(
            context,
            'Biometric verification is required for this action. '
            'Set up fingerprint or face unlock on this device first.',
          );
        }
        return false;
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
      );

      if (!authenticated && context.mounted) {
        _show(context, 'Biometric verification cancelled or failed.');
      }

      return authenticated;
    } catch (e) {
      if (context.mounted) {
        _show(context, 'Biometric verification failed. Try again.');
      }
      return false;
    }
  }

  static void _show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
