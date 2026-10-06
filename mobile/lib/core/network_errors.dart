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
    final socketText = error.toString().toLowerCase();
    if (socketText.contains('timed out') || socketText.contains('timeout')) {
      return const NetworkFailure(NetworkFailureKind.weakConnection);
    }
    return const NetworkFailure(NetworkFailureKind.offline);
  }

  final text = error.toString().toLowerCase();

  if (text.contains('app server is crazy right now') ||
      text.contains('server is crazy right now') ||
      text.contains('server waking')) {
    return const NetworkFailure(NetworkFailureKind.serverWaking);
  }

  if (text.contains('your connection is weak') ||
      text.contains('weak connection') ||
      text.contains('timed out') ||
      text.contains('timeout')) {
    return const NetworkFailure(NetworkFailureKind.weakConnection);
  }

  if (text.contains('oops! looks like you need an active internet connection') ||
      text.contains('failed host lookup') ||
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
              label: 'Try Again',
              onPressed: onRetry,
            ),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
