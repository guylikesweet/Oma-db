import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Client-side receipt artwork. The signed verification URL and receipt facts
/// come from the server; no signing key or trust decision exists in Flutter.
class LocalReceiptRenderer {
  static const _green = PdfColor.fromInt(0xFF1B4326);
  static const _greenMid = PdfColor.fromInt(0xFF4A8C54);
  static const _orange = PdfColor.fromInt(0xFFF97F0E);
  static const _ink = PdfColor.fromInt(0xFF1E1E1E);
  static const _grey = PdfColor.fromInt(0xFF6E6E6E);
  static const _line = PdfColor.fromInt(0xFFDEDEDE);
  static const _tableHead = PdfColor.fromInt(0xFFD9EAD3);
  static const _notice = PdfColor.fromInt(0xFFFFF3CD);

  static String _s(dynamic value, [String fallback = '']) =>
      value == null ? fallback : value.toString().trim();

  static String _money(dynamic value) {
    final n = double.tryParse(_s(value)) ?? 0;
    final fixed = n.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0];
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return 'NGN $grouped.${parts[1]}';
  }

  static Future<Uint8List> pdf(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(payload['receipt'] as Map);
    final items = (data['line_items'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final notices = (data['notice_paragraphs'] as List? ?? const []);
    final logoRaw = _s(payload['logo_base64']);
    final logo = logoRaw.isEmpty ? null : pw.MemoryImage(base64Decode(logoRaw));
    final verifyUrl = _s(data['verify_url']);
    final signature = _s(data['signature']);
    final orderId = _s(data['order_id'], 'Receipt');
    final business = _s(data['business_name'], 'OmaBuy Nigeria Limited');
    final estimatedHeight = 390 +
        items.fold<int>(0, (n, item) => n + 38 + (_s(item['name']).length ~/ 28) * 10) +
        notices.length * 42 +
        (logo == null ? 0 : 35);
    final pageHeight = (estimatedHeight * PdfPageFormat.point).clamp(520.0, 1800.0).toDouble();
    final doc = pw.Document(
      title: 'Receipt $orderId',
      author: business,
      subject: 'Verified customer receipt',
    );

    pw.Widget line() => pw.Container(height: 0.7, color: _line);
    pw.Widget sectionTitle(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7, top: 5),
      child: pw.Text(text, style: pw.TextStyle(
        fontSize: 12, fontWeight: pw.FontWeight.bold, color: _green,
      )),
    );
    pw.Widget detail(String label, String value) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, color: _grey)),
        pw.SizedBox(height: 2),
        pw.Text(value.isEmpty ? '—' : value,
            style: pw.TextStyle(fontSize: 8, color: _ink)),
      ],
    );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, pageHeight),
      margin: const pw.EdgeInsets.fromLTRB(17, 18, 17, 18),
      build: (context) => pw.Stack(
        children: [
          pw.Positioned(
            left: 2, top: pageHeight * 0.36,
            child: pw.Transform.rotate(
              angle: -0.42,
              child: pw.Text(
                '$orderId  •  $signature',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor(0.10, 0.26, 0.15, 0.045),
                ),
              ),
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (logo != null)
                pw.Center(child: pw.Image(logo, height: 48, fit: pw.BoxFit.contain)),
              pw.Center(child: pw.Text(business,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _green))),
              if (_s(data['business_phone']).isNotEmpty)
                pw.Center(child: pw.Text('Phone: ${_s(data['business_phone'])}',
                  style: pw.TextStyle(fontSize: 7, color: _grey))),
              if (_s(data['instagram']).isNotEmpty)
                pw.Center(child: pw.Text('Instagram: ${_s(data['instagram'])}',
                  style: pw.TextStyle(fontSize: 7, color: _grey))),
              if (_s(data['business_address']).isNotEmpty)
                pw.Center(child: pw.Text(_s(data['business_address']),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 7, color: _grey))),
              pw.SizedBox(height: 9),
              pw.Container(height: 2, color: _orange),
              pw.SizedBox(height: 6),
              pw.Center(child: pw.Text('INVOICE / RECEIPT',
                style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _green))),
              pw.SizedBox(height: 8),
              line(),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.Expanded(child: detail('ORDER ID', orderId)),
                pw.Expanded(child: detail('DATE', _s(data['date_text']))),
              ]),
              pw.SizedBox(height: 8),
              pw.Row(children: [
                pw.Expanded(child: pw.Text('Payment: PAID',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _green))),
                pw.Expanded(child: pw.Text('Order: ${_s(data['order_status_label'], 'Processing')}',
                  style: pw.TextStyle(fontSize: 8, color: _green))),
              ]),
              pw.SizedBox(height: 8),
              line(),
              sectionTitle('BILL TO'),
              pw.Text(_s(data['customer_name'], 'Customer'),
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
              if (_s(data['customer_phone']).isNotEmpty)
                pw.Text('Phone: ${_s(data['customer_phone'])}', style: const pw.TextStyle(fontSize: 8)),
              if (_s(data['address_text']).isNotEmpty)
                pw.Text('Address: ${_s(data['address_text'])}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 9),
              pw.Table(
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(color: _line, width: 0.5),
                  top: pw.BorderSide(color: _greenMid, width: 0.8),
                  bottom: pw.BorderSide(color: _greenMid, width: 0.8),
                ),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3.4),
                  1: const pw.FlexColumnWidth(0.7),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _tableHead),
                    children: ['Product', 'Qty', 'Unit', 'Total'].map((t) =>
                      pw.Padding(padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(t, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _green)))
                    ).toList(),
                  ),
                  ...items.map((it) => pw.TableRow(children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(_s(it['name'], 'Product'), style: const pw.TextStyle(fontSize: 7)),
                        if (_s(it['variant']).isNotEmpty)
                          pw.Text(_s(it['variant']), style: pw.TextStyle(fontSize: 6, color: _grey)),
                      ],
                    )),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(_s(it['qty']), style: const pw.TextStyle(fontSize: 7))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('NGN ${_s(it['unit_text'], '0.00')}', style: const pw.TextStyle(fontSize: 6))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('NGN ${_s(it['line_text'], '0.00')}', style: const pw.TextStyle(fontSize: 6))),
                  ])),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(9),
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6F6F4)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL ${_s(data['total_note'])}',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _green)),
                    pw.Text('NGN ${_s(data['total_text'], '0.00')}',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: _green)),
                  ],
                ),
              ),
              if (notices.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: const pw.BoxDecoration(
                    color: _notice,
                    border: pw.Border.fromBorderSide(pw.BorderSide(color: PdfColor.fromInt(0xFFE8C468), width: 0.7)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: notices.map((paragraph) {
                      final runs = (paragraph as List).map((run) => pw.TextSpan(
                        text: _s(run[0]),
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: run[1] == true ? pw.FontWeight.bold : pw.FontWeight.normal,
                        ),
                      )).toList();
                      return pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.RichText(text: pw.TextSpan(children: runs)),
                      );
                    }).toList(),
                  ),
                ),
              ],
              pw.SizedBox(height: 12),
              pw.Center(child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: verifyUrl,
                width: 82,
                height: 82,
                drawText: false,
              )),
              pw.Center(child: pw.Text('SCAN TO VERIFY THIS RECEIPT',
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _green))),
              pw.Center(child: pw.Text(_s(data['track_display']),
                style: pw.TextStyle(fontSize: 7, color: _grey))),
              pw.SizedBox(height: 5),
              pw.Center(child: pw.Container(
                width: 62, height: 62,
                decoration: pw.BoxDecoration(
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: _green, width: 1.6),
                ),
                child: pw.Center(child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('ORIGINAL', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: _green)),
                    pw.Text('VERIFIED', style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: _green)),
                    pw.Text(signature.length > 8 ? signature.substring(0, 8) : signature,
                      style: pw.TextStyle(fontSize: 5, color: _green)),
                  ],
                )),
              )),
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Text(_s(data['code_text']),
                style: pw.TextStyle(fontSize: 8, letterSpacing: 1.2, fontWeight: pw.FontWeight.bold, color: _green))),
              pw.SizedBox(height: 7),
              line(),
              pw.SizedBox(height: 8),
              pw.Center(child: pw.Text(_s(data['footer_text']),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8, color: _green))),
            ],
          ),
        ],
      ),
    ));
    return Uint8List.fromList(await doc.save());
  }

  static Future<Uint8List> image(Map<String, dynamic> payload, {required bool jpeg}) async {
    final document = await pdf(payload);
    final first = await Printing.raster(document, dpi: 144).first;
    final png = await first.toPng();
    if (!jpeg) return png;
    final decoded = img.decodePng(png);
    if (decoded == null) throw StateError('Could not rasterize receipt image.');
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 94));
  }
}
