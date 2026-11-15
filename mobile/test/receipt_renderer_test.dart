import 'package:flutter_test/flutter_test.dart';
import 'package:oma_mobile/receipt_renderer.dart';

void main() {
  test('local receipt renderer creates a PDF from signed receipt data', () async {
    final payload = <String, dynamic>{
      'version': 1,
      'logo_base64': null,
      'receipt': {
        'business_name': 'OmaBuy Nigeria Limited',
        'order_id': 'OMB-TEST01',
        'date_text': '15 Nov 2026',
        'order_status_label': 'Processing',
        'customer_name': 'Test Customer',
        'customer_phone': '08000000000',
        'address_text': 'Lagos, Nigeria',
        'line_items': [
          {
            'name': 'Test product',
            'variant': 'Blue',
            'qty': 2,
            'unit_text': '1,500.00',
            'line_text': '3,000.00',
          },
        ],
        'total_text': '3,000.00',
        'total_note': '(products only)',
        'notice_paragraphs': [],
        'verify_url': 'https://oma-db.onrender.com/track/TEST?sig=ABC123',
        'signature': 'ABC12345678901234567',
        'code_text': 'ABC12-34567-89012-34567',
        'track_display': 'omabuy.ng/track',
        'footer_text': 'Thank you for your order - OmaBuy Nigeria Limited',
      },
    };

    final bytes = await LocalReceiptRenderer.pdf(payload);
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
