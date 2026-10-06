import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

enum NetworkFailureKind {
  offline,
  serverWaking,
  weakConnection,
}

class NetworkFailure {
  const NetworkFailure(this.kind);

  final NetworkFailureKind kind;

  String get message {
    switch (kind) {
      case NetworkFailureKind.offline:
        return 'Oops! Looks like you need an active internet connection for this action.';
      case NetworkFailureKind.serverWaking:
        return 'App server is crazy right now, try again in a few seconds.';
      case NetworkFailureKind.weakConnection:
        return 'Your connection is weak, fix or try a different WiFi.';
    }
  }
}

NetworkFailure? classifyNetworkError(Object error) {
  if (error is TimeoutException) {
    return const NetworkFailure(NetworkFailureKind.serverWaking);
  }

  if (error is SocketException) {
    return const NetworkFailure(NetworkFailureKind.offline);
  }

  final text = error.toString().toLowerCase();

  if (text.contains('failed host lookup') ||
      text.contains('no address associated with hostname') ||
      text.contains('network is unreachable') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection closed') ||
      text.contains('clientexception')) {
    return const NetworkFailure(NetworkFailureKind.offline);
  }

  return null;
}

String userFacingError(Object error) {
  return classifyNetworkError(error)?.message ?? error.toString();
}

void showNetworkError(
  BuildContext context,
  Object error, {
  VoidCallback? onRetry,
}) {
  final failure = classifyNetworkError(error);
  if (failure == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(failure.message),
      action: onRetry == null
          ? null
          : SnackBarAction(
              label: 'Try',
              onPressed: onRetry,
            ),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
