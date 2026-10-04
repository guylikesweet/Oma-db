import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'brand_loader.dart';
import 'data/api_client.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _shortDate(dynamic iso) {
  final parsed = DateTime.tryParse('${iso ?? ''}');
  if (parsed == null) return '';
  final d = parsed.toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _naira(dynamic value) {
  final number = value is num ? value : double.tryParse('${value ?? ''}');
  if (number == null) return '—';
  final whole = number.round().toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '₦$grouped';
}

/// Where one order is on its journey (order confirmed → … → delivered or
/// returned), plus its shipping estimate and the customer's tracking link.
/// Needs the live server, so offline it just says so.
class JourneyCard extends StatefulWidget {
  const JourneyCard({super.key, required this.api, required this.saleId});

  final ApiClient api;
  final int saleId;

  @override
  State<JourneyCard> createState() => _JourneyCardState();
}

class _JourneyCardState extends State<JourneyCard> {
  Map<String, dynamic>? detail;
  bool failed = false;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      failed = false;
    });

    try {
      final result = await widget.api.saleJourney(widget.saleId);
      if (mounted) setState(() => detail = result);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> moveTo(String stage) async {
    try {
      final result = await widget.api.setJourneyStage([widget.saleId], stage);
      final skipped = List<String>.from(
        (result['skipped'] as List? ?? const []).map((x) => '$x'),
      );

      if (skipped.isNotEmpty) {
        say(skipped.first);
      } else {
        say('Order journey updated.');
      }

      await load();
    } catch (e) {
      say('$e');
    }
  }

  Future<void> copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    say('Tracking link copied.');
  }

  Widget stepRow(Map<String, dynamic> step, ColorScheme scheme) {
    final state = '${step['state']}';
    final done = state == 'done';
    final active = state == 'current' || state == 'final';

    final color = done
        ? scheme.secondary
        : active
            ? scheme.primary
            : Colors.grey;

    final date = _shortDate(step['at']);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${step['label']}',
              style: TextStyle(
                color: active || done ? null : Colors.grey,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (date.isNotEmpty)
            Text(
              date,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget shippingEstimate(Map<String, dynamic> d) {
    if ('${d['sale_type']}' == 'stock') return const SizedBox.shrink();

    final mode = d['batch_transport_mode'];

    if (mode == 'air' || mode == 'sea') {
      final value = mode == 'air'
          ? d['estimated_shipping_air']
          : d['estimated_shipping_sea'];

      return Text(
        'Estimated shipping (${mode == 'air' ? 'air' : 'sea'} batch): '
        '${value == null ? 'set the air rate to estimate' : _naira(value)}',
      );
    }

    final air = d['estimated_shipping_air'];

    return Text(
      'Estimated shipping — Sea: ${_naira(d['estimated_shipping_sea'])}'
      '  •  Air: ${air == null ? 'no air rate set' : _naira(air)}\n'
      'The method is decided by the shipment batch this order goes into.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget body;

    if (busy && detail == null) {
      body = const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: BrandLoader(size: 48)),
      );
    } else if (failed || detail == null) {
      body = Row(
        children: [
          const Expanded(
            child: Text(
              'Couldn\'t load this order\'s journey — you may be offline, or the sale hasn\'t synced yet.',
            ),
          ),
          TextButton(onPressed: load, child: const Text('Retry')),
        ],
      );
    } else {
      final d = detail!;
      final journey = Map<String, dynamic>.from(d['journey'] as Map);
      final steps = (journey['steps'] as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      final manual = (d['manual_stages'] as List? ?? const [])
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      final url = '${d['tracking_url'] ?? ''}';

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order journey',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Chip(
                label: Text(
                  '${journey['current_label']}',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                backgroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (journey['cancelled'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'This order was cancelled.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 6),
          ...steps.map((step) => stepRow(step, scheme)),
          const SizedBox(height: 8),
          shippingEstimate(d),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (url.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => copyLink(url),
                  icon: const Icon(Icons.link),
                  label: const Text('Copy tracking link'),
                ),
              if (url.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Share.share(
                    'Track your order ${d['order_id'] ?? ''}: $url',
                  ),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              if (manual.isNotEmpty)
                PopupMenuButton<String>(
                  onSelected: moveTo,
                  itemBuilder: (_) => manual
                      .map(
                        (m) => PopupMenuItem<String>(
                          value: '${m['key']}',
                          child: Text('Move to ${m['label']}'),
                        ),
                      )
                      .toList(),
                  child: const Chip(
                    avatar: Icon(Icons.edit_road, size: 18),
                    label: Text('Update stage'),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: body,
      ),
    );
  }
}

/// Move many orders through the early stages at once. Preordered goods:
/// Fulfilled, CN domestic transit, Consolidation. Stocked goods: Packing.
/// Every later stage updates by itself from batches, shipping settlement
/// and deliveries.
class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  static const _preorderStages = <String, String>{
    'fulfilled': 'Fulfilled',
    'cn_transit': 'CN domestic transit',
    'consolidation': 'Consolidation',
  };
  static const _stockStages = <String, String>{
    'packing': 'Packing',
  };

  List<Map<String, dynamic>> sales = [];
  final Set<int> selected = {};
  bool busy = true;
  bool saving = false;
  String? error;
  bool stocked = false;
  String? stage;

  Map<String, String> get stages => stocked ? _stockStages : _preorderStages;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      final rows = await widget.api.sales();
      sales = rows
          .map((x) => Map<String, dynamic>.from(x as Map))
          .where((s) {
        final key = '${s['journey_stage'] ?? ''}';
        return s['order_status'] != 'Cancelled' &&
            key != 'delivered' &&
            key != 'returned';
      }).toList();
      selected.clear();
    } catch (e) {
      error = '$e';
    }

    if (mounted) setState(() => busy = false);
  }

  bool isStock(Map<String, dynamic> s) => '${s['sale_type']}' == 'stock';

  /// Once an order is in a batch (or a stocked order has a delivery) the app
  /// tracks it by itself, so it can't be moved by hand any more.
  bool movable(Map<String, dynamic> s) =>
      isStock(s) ? s['delivery_id'] == null : s['batch_id'] == null;

  Future<void> move() async {
    final chosen = stage;
    if (chosen == null || selected.isEmpty) return;

    setState(() => saving = true);

    try {
      final result = await widget.api.setJourneyStage(
        selected.toList(),
        chosen,
      );

      final updated = result['updated'] ?? 0;
      final unchanged = result['unchanged'] ?? 0;
      final skipped = List<String>.from(
        (result['skipped'] as List? ?? const []).map((x) => '$x'),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$updated moved to ${stages[chosen]}'
            '${unchanged == 0 ? '' : ', $unchanged already there'}'
            '${skipped.isEmpty ? '' : ', ${skipped.length} skipped'}.',
          ),
        ),
      );

      if (skipped.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Some orders were skipped'),
            content: SingleChildScrollView(
              child: Text(skipped.join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = sales.where((s) => isStock(s) == stocked).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Order journey')),
      body: busy
          ? const Center(child: BrandLoader())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      TextButton(
                        onPressed: load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Preorders'),
                            icon: Icon(Icons.flight_takeoff),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Stocked'),
                            icon: Icon(Icons.inventory_2_outlined),
                          ),
                        ],
                        selected: {stocked},
                        onSelectionChanged: (value) {
                          setState(() {
                            stocked = value.first;
                            stage = null;
                            selected.clear();
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: stage,
                              decoration: const InputDecoration(
                                labelText: 'Move ticked orders to',
                                border: OutlineInputBorder(),
                              ),
                              items: stages.entries
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                      value: e.key,
                                      child: Text(e.value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => stage = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: saving ||
                                    stage == null ||
                                    selected.isEmpty
                                ? null
                                : move,
                            child: Text(
                              saving ? 'Moving…' : 'Move (${selected.length})',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: load,
                        child: shown.isEmpty
                            ? ListView(
                                children: const [
                                  SizedBox(height: 120),
                                  Center(child: Text('No orders in progress.')),
                                ],
                              )
                            : ListView.builder(
                                itemCount: shown.length,
                                itemBuilder: (_, index) {
                                  final s = shown[index];
                                  final id = s['id'] as int;
                                  final canMove = movable(s);

                                  return CheckboxListTile(
                                    value: selected.contains(id),
                                    onChanged: canMove
                                        ? (value) {
                                            setState(() {
                                              if (value == true) {
                                                selected.add(id);
                                              } else {
                                                selected.remove(id);
                                              }
                                            });
                                          }
                                        : null,
                                    title: Text(
                                      '${s['order_id'] ?? id}'
                                      ' • ${s['customer_name'] ?? ''}',
                                    ),
                                    subtitle: Text(
                                      '${s['journey_label'] ?? ''}'
                                      '${canMove ? '' : ' (updates by itself now)'}',
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
