import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'data/api_client.dart';
import 'core/network_errors.dart';

/// Opens an "Invoice ready" popup for one sale with Share and Print buttons.
///
/// Why a popup instead of acting straight away: browsers only allow the
/// share sheet (and print dialog) from a fresh tap. The invoice has to be
/// fetched from the server first, which can take a moment — by the time it
/// arrives the original tap has "expired" and the browser falls back to
/// just downloading the file. Fetching first and then asking for a tap on
/// Share fixes that: the share sheet opens straight away, to WhatsApp
/// Business or any other app, and nothing is saved to the phone.
Future<void> showInvoiceDialog(
  BuildContext context,
  ApiClient api,
  int saleId, {
  String? label,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _InvoiceDialog(
      api: api,
      saleId: saleId,
      label: label ?? '$saleId',
    ),
  );
}

class _InvoiceDialog extends StatefulWidget {
  const _InvoiceDialog({
    required this.api,
    required this.saleId,
    required this.label,
  });

  final ApiClient api;
  final int saleId;
  final String label;

  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  Uint8List? bytes;
  String? error;
  // After a few seconds of waiting we explain why (free servers go to sleep
  // when idle and take up to a minute to wake up).
  bool slow = false;
  Timer? slowTimer;
  // Set when the browser/phone refuses to open the share sheet, so we can
  // say why instead of silently downloading the file.
  String? shareError;

  String get fileName => 'invoice-${widget.label}.pdf';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    slowTimer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      bytes = null;
      error = null;
      slow = false;
    });

    slowTimer?.cancel();
    slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && bytes == null && error == null) {
        setState(() => slow = true);
      }
    });

    try {
      Uint8List data;

      try {
        data = await widget.api.invoicePdf(widget.saleId);
      } on TimeoutException {
        // A sleeping server often answers on the second try.
        data = await widget.api.invoicePdf(widget.saleId);
      }

      if (mounted) setState(() => bytes = data);
    } catch (e) {
      if (mounted) {
        setState(() => error = userFacingError(e));
      }
    } finally {
      slowTimer?.cancel();
    }
  }

  void say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> share() async {
    final data = bytes;
    if (data == null) return;

    if (shareError != null) setState(() => shareError = null);

    // An exact-size copy: the bytes from the network can be a view into a
    // larger buffer, and the web share code hands the whole buffer to the
    // browser.
    final fresh = Uint8List.fromList(data);

    // Never fall back to quietly downloading the file — the whole point of
    // this button is sharing without saving. If sharing is refused we show
    // the reason instead (and offer an explicit Save button).
    Share.downloadFallbackEnabled = false;

    Future<void> attempt({required bool withText}) {
      return Share.shareXFiles(
        [
          XFile.fromData(
            fresh,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
        fileNameOverrides: [fileName],
        text: withText ? 'Invoice / receipt ${widget.label}' : null,
      );
    }

    bool cancelled(Object e) {
      final text = '$e'.toLowerCase();
      return text.contains('abort') || text.contains('cancel');
    }

    try {
      await attempt(withText: true);
    } catch (first) {
      if (cancelled(first)) return;

      // Some browsers/apps refuse a file shared together with text; the
      // file on its own is what matters, so try that before giving up.
      try {
        await attempt(withText: false);
      } catch (second) {
        if (cancelled(second)) return;
        if (mounted) {
          setState(() => shareError = '$second');
        }
      }
    }
  }

  /// Explicit "save a copy" — only offered after sharing has failed.
  Future<void> save() async {
    final data = bytes;
    if (data == null) return;

    try {
      await Printing.sharePdf(bytes: data, filename: fileName);
    } catch (e) {
      say('Could not save: $e');
    }
  }

  Future<void> printIt() async {
    final data = bytes;
    if (data == null) return;

    try {
      await Printing.layoutPdf(
        name: fileName,
        onLayout: (_) async => data,
      );
    } catch (e) {
      say('Could not print: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = bytes != null;

    return AlertDialog(
      title: Text('Invoice ${widget.label}'),
      content: error != null
          ? Text(error!)
          : ready
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invoice is ready. Share it straight to WhatsApp or '
                      'any other app — nothing is saved to your phone — or '
                      'print it.',
                    ),
                    if (shareError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Sharing didn\'t open: $shareError',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        slow
                            ? 'Still working — the server may be waking up. '
                                'This can take up to a minute.'
                            : 'Preparing invoice…',
                      ),
                    ),
                  ],
                ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (error != null)
          FilledButton(onPressed: load, child: const Text('Try again')),
        if (ready) ...[
          if (shareError != null)
            TextButton(
              onPressed: save,
              child: const Text('Save PDF'),
            ),
          OutlinedButton.icon(
            onPressed: printIt,
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          FilledButton.icon(
            onPressed: share,
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ],
    );
  }
}
