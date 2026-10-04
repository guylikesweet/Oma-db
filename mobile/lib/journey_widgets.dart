import 'package:flutter/material.dart';

import 'brand_loader.dart';
import 'data/api_client.dart';

/// Compact first-stage journey card for the sale detail screen.
///
/// This intentionally starts with only the current journey state. The
/// timeline and controls will be added in later, independently verified
/// steps so the detail page never gets an unbounded/nested layout again.
class JourneyCard extends StatefulWidget {
  const JourneyCard({
    super.key,
    required this.api,
    required this.saleId,
  });

  final ApiClient api;
  final int saleId;

  @override
  State<JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends State<JourneyCard> {
  Map<String, dynamic>? detail;
  bool busy = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        busy = true;
        failed = false;
      });
    }

    try {
      final result = await widget.api.saleJourney(widget.saleId);
      if (mounted) {
        setState(() => detail = result);
      }
    } catch (_) {
      if (mounted) {
        setState(() => failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content;

    if (busy && detail == null) {
      content = const SizedBox(
        height: 48,
        child: Center(
          child: BrandLoader(size: 32),
        ),
      );
    } else if (failed || detail == null) {
      content = Row(
        children: [
          const Expanded(
            child: Text('Order journey is unavailable right now.'),
          ),
          TextButton(
            onPressed: load,
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      final rawJourney = detail!['journey'];
      final journey = rawJourney is Map
          ? Map<String, dynamic>.from(rawJourney)
          : <String, dynamic>{};
      final current = '${journey['current_label'] ?? 'Order received'}';

      content = Row(
        children: [
          Icon(
            Icons.local_shipping_outlined,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Order journey',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  current,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        child: content,
      ),
    );
  }
}

/// Full order-journey management page is intentionally left out of this
/// incremental rebuild. It can be restored separately after the compact
/// sale-detail card has been verified.
class JourneyPage extends StatelessWidget {
  const JourneyPage({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order journey')),
      body: const Center(
        child: Text('Order journey management is temporarily unavailable.'),
      ),
    );
  }
}
