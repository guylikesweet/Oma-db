import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'core/config.dart';
import 'core/network_errors.dart';
import 'data/api_client.dart';

/// The three ways a receipt can be handed to a customer. The server draws one
/// receipt picture; JPG/PNG send it as a photo (best for WhatsApp) and PDF is a
/// small 80 mm page carrying the same picture.
enum _ReceiptFormat { png, jpg, pdf }

extension _ReceiptFormatInfo on _ReceiptFormat {
  String get ext {
    if (this == _ReceiptFormat.png) return 'png';
    if (this == _ReceiptFormat.pdf) return 'pdf';
    return 'jpg';
  }

  String get mime {
    if (this == _ReceiptFormat.png) return 'image/png';
    if (this == _ReceiptFormat.pdf) return 'application/pdf';
    return 'image/jpeg';
  }

  String get label {
    if (this == _ReceiptFormat.png) return 'Photo (PNG)';
    if (this == _ReceiptFormat.pdf) return 'PDF';
    return 'Photo (JPG)';
  }

  bool get isImage => this != _ReceiptFormat.pdf;
}

/// Downloads one receipt from the server. Same authenticated binary fetch as
/// [ApiClient.invoicePdf], but for the receipt endpoints that can return a
/// photo as well as a PDF.
Future<Uint8List> _fetchReceipt(
  ApiClient api,
  int saleId,
  _ReceiptFormat format,
) async {
  final savedToken = await api.token();

  final base = Uri.parse(AppConfig.apiBaseUrl);
  final basePath = base.path.replaceFirst(RegExp(r'/$'), '');
  final uri = base.replace(
    path: '$basePath/v1/sales/$saleId/receipt.${format.ext}',
  );

  final headers = <String, String>{'Accept': format.mime};
  if (savedToken != null && savedToken.isNotEmpty) {
    headers['Authorization'] = 'Bearer $savedToken';
  }

  late http.Response response;
  try {
    response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 90));
  } on TimeoutException catch (e) {
    throw ApiException(0, 'Network request timed out.', cause: e);
  } on http.ClientException catch (e) {
    throw ApiException(0, 'Network connection failed.', cause: e);
  }

  if (response.statusCode < 200 || response.statusCode >= 300) {
    // The server explains refusals in plain words, e.g. "Receipts are only
    // issued for paid orders."
    var message = 'Could not generate the receipt.';
    try {
      final text = response.body;
      final match = RegExp(r'"error"\s*:\s*"([^"]+)"').firstMatch(text);
      if (match != null) message = match.group(1) ?? message;
    } catch (_) {}
    throw ApiException(response.statusCode, message);
  }

  return response.bodyBytes;
}

/// Opens a "Receipt ready" popup for one sale with Share and Print buttons.
///
/// Why a popup instead of acting straight away: browsers only allow the
/// share sheet (and print dialog) from a fresh tap. The receipt has to be
/// fetched from the server first, which can take a moment — by the time it
/// arrives the original tap has "expired" and the browser falls back to
/// just downloading the file. Fetching first and then asking for a tap on
/// Share fixes that: the share sheet opens straight away, to WhatsApp
/// Business or any other app, and nothing is saved to the phone.
///
/// The format chips choose what is shared: a JPG or PNG photo (opens straight
/// in WhatsApp, no zoom needed) or a small PDF. JPG is the default because a
/// WhatsApp photo cannot show transparent corners.
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
  _ReceiptFormat format = _ReceiptFormat.png;
  final Map<_ReceiptFormat, Uint8List> cache = {};
  bool loading = false;
  String? error;
  // After a few seconds of waiting we explain why (free servers go to sleep
  // when idle and take up to a minute to wake up).
  bool slow = false;
  Timer? slowTimer;
  // Set when the browser/phone refuses to open the share sheet, so we can
  // say why instead of silently downloading the file.
  String? shareError;

  Uint8List? get bytes => cache[format];

  String get fileName => 'receipt-${widget.label}.${format.ext}';

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
    final wanted = format;

    if (cache.containsKey(wanted)) {
      setState(() {
        error = null;
        shareError = null;
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
      slow = false;
      shareError = null;
    });

    slowTimer?.cancel();
    slowTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && loading) setState(() => slow = true);
    });

    try {
      Uint8List data;

      data = await _fetchReceipt(widget.api, widget.saleId, wanted);

      cache[wanted] = data;
    } catch (e) {
      if (mounted) {
        setState(() => error = userFacingError(e));
      }
    } finally {
      slowTimer?.cancel();
      if (mounted) setState(() => loading = false);
    }
  }

  void choose(_ReceiptFormat next) {
    if (loading || next == format) return;
    setState(() {
      format = next;
      error = null;
      shareError = null;
    });
    load();
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
    final chosen = format;
    final name = fileName;

    // Never fall back to quietly downloading the file — the whole point of
    // this button is sharing without saving. If sharing is refused we show
    // the reason instead.
    Share.downloadFallbackEnabled = false;

    Future<void> attempt({required bool withText}) {
      return Share.shareXFiles(
        [
          XFile.fromData(
            fresh,
            mimeType: chosen.mime,
            name: name,
          ),
        ],
        fileNameOverrides: [name],
        text: withText ? 'Receipt ${widget.label}' : null,
      );
    }

    bool cancelled(Object e) {
      final text = '$e'.toLowerCase();
      return text.contains('abort') || text.contains('cancel');
    }

    try {
      await attempt(withText: false);
    } catch (first) {
      if (cancelled(first)) return;

      // Some browsers/apps refuse a file shared on its own; adding a short
      // caption is the other thing worth trying before giving up.
      try {
        await attempt(withText: true);
      } catch (second) {
        if (cancelled(second)) return;
        if (mounted) {
          setState(() => shareError = '$second');
        }
      }
    }
  }

  /// Explicit "save a copy" of the PDF — only offered after sharing failed.
  Future<void> savePdf() async {
    final data = cache[_ReceiptFormat.pdf];
    if (data == null) return;

    try {
      await Printing.sharePdf(
        bytes: data,
        filename: 'receipt-${widget.label}.pdf',
      );
    } catch (e) {
      say('Could not save: ${userFacingError(e)}');
    }
  }

  /// Printing always uses the PDF, whichever format is selected.
  Future<void> printIt() async {
    try {
      var pdf = cache[_ReceiptFormat.pdf];
      pdf ??= await _fetchReceipt(
        widget.api,
        widget.saleId,
        _ReceiptFormat.pdf,
      );
      cache[_ReceiptFormat.pdf] = pdf;
      final data = pdf;

      await Printing.layoutPdf(
        name: 'receipt-${widget.label}.pdf',
        onLayout: (_) async => data,
      );
    } catch (e) {
      say('Could not print: ${userFacingError(e)}');
    }
  }

  Widget buildPreview() {
    final data = bytes;
    if (data == null) return const SizedBox.shrink();

    if (!format.isImage) {
      return const Text(
        'PDF is ready: one small 80 mm wide page with the same receipt.',
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: SingleChildScrollView(
        child: Image.memory(data, fit: BoxFit.fitWidth),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = bytes != null && !loading;

    Widget body;
    if (error != null) {
      body = Text(error!);
    } else if (loading || bytes == null) {
      body = Row(
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
                  : 'Preparing receipt…',
            ),
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildPreview(),
          const SizedBox(height: 12),
          const Text(
            'Share it straight to WhatsApp or any other app — nothing is '
            'saved to your phone.',
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
      );
    }

    return AlertDialog(
      title: Text('Receipt ${widget.label}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final f in _ReceiptFormat.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: format == f,
                    onSelected: loading ? null : (_) => choose(f),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (error != null && !loading)
          FilledButton(onPressed: load, child: const Text('Try again')),
        if (ready) ...[
          if (shareError != null && format == _ReceiptFormat.pdf)
            TextButton(
              onPressed: savePdf,
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
