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

/// Full order-journey management page.
///
/// The server already exposes the journey engine and manual-stage endpoint;
/// this page now uses those APIs instead of displaying the old placeholder.
class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage> {
  List<Map<String, dynamic>> sales = [];
  final Set<int> selectedIds = <int>{};
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      final raw = await widget.api.sales();
      final loaded = raw
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['id'] != null)
          .toList();

      if (mounted) {
        setState(() => sales = loaded);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '${e}');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> updateSelected() async {
    if (selectedIds.isEmpty) return;
    try {
      final detail = await widget.api.saleJourney(selectedIds.first);
      if (!mounted) return;
      final raw = detail['manual_stages'];
      final stages = raw is List
          ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList()
          : <Map<String, dynamic>>[];
      String? selectedStage;
      final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Move ' + selectedIds.length.toString() + ' selected sale(s)'),
            content: DropdownButtonFormField<String>(
              value: selectedStage,
              decoration: const InputDecoration(labelText: 'Milestone'),
              items: stages.map((stage) => DropdownMenuItem<String>(
                value: stage['key']?.toString(),
                child: Text(stage['label']?.toString() ?? stage['key'].toString()),
              )).toList(),
              onChanged: (value) => setDialogState(() => selectedStage = value),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(
                onPressed: selectedStage == null
                    ? null
                    : () => Navigator.pop(dialogContext, selectedStage),
                child: const Text('Update'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      final response = await widget.api.setJourneyStage(selectedIds.toList(), result);
      final updated = (response['updated'] as num?)?.toInt() ?? 0;
      final skipped = response['skipped'];
      if (!mounted) return;
      setState(() => selectedIds.clear());
      await load();
      final suffix = skipped is List && skipped.isNotEmpty
          ? ' ' + skipped.length.toString() + ' could not be changed.'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(updated.toString() + ' sale(s) updated.' + suffix)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update selected journeys: ' + e.toString())),
        );
      }
    }
  }

  Future<void> openSale(Map<String, dynamic> sale) async {
    final saleId = (sale['id'] as num?)?.toInt();
    if (saleId == null) return;

    try {
      final detail = await widget.api.saleJourney(saleId);
      if (!mounted) return;

      final updated = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _JourneyEditor(
          api: widget.api,
          sale: sale,
          detail: detail,
        ),
      );

      if (updated == true) {
        await load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load this journey: ${e}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedIds.isEmpty ? 'Order journey' : selectedIds.length.toString() + ' selected'),
        actions: [
          if (selectedIds.isNotEmpty)
            IconButton(
              tooltip: 'Update selected',
              onPressed: loading ? null : updateSelected,
              icon: const Icon(Icons.update),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: loading
          ? const Center(child: BrandLoader(label: 'Loading journeys…'))
          : error != null
              ? _ErrorState(error: error!, onRetry: load)
              : sales.isEmpty
                  ? const Center(child: Text('No sales found.'))
                  : RefreshIndicator(
                      onRefresh: load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sales.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final sale = sales[index];
                          final id = (sale['id'] as num?)?.toInt();
                          final order =
                              '${sale['order_id'] ?? '#${sale['id']}'}';
                          final customer =
                              '${sale['customer_name'] ?? 'Customer'}';
                          final current =
                              '${sale['journey_label'] ?? sale['order_status'] ?? 'Order received'}';

                          return Card(
                            child: ListTile(
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: id != null && selectedIds.contains(id),
                                    onChanged: id == null
                                        ? null
                                        : (checked) {
                                            setState(() {
                                              if (checked == true) {
                                                selectedIds.add(id);
                                              } else {
                                                selectedIds.remove(id);
                                              }
                                            });
                                          },
                                  ),
                                  CircleAvatar(
                                    child: Text(id?.toString() ?? ''),
                                  ),
                                ],
                              ),
                              title: Text(
                                order,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$customer\n$current',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_right),
                              onTap: selectedIds.isNotEmpty
                                  ? () {
                                      if (id == null) return;
                                      setState(() {
                                        if (selectedIds.contains(id)) {
                                          selectedIds.remove(id);
                                        } else {
                                          selectedIds.add(id);
                                        }
                                      });
                                    }
                                  : () => openSale(sale),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _JourneyEditor extends StatefulWidget {
  const _JourneyEditor({
    required this.api,
    required this.sale,
    required this.detail,
  });

  final ApiClient api;
  final Map<String, dynamic> sale;
  final Map<String, dynamic> detail;

  @override
  State<_JourneyEditor> createState() => _JourneyEditorState();
}

class _JourneyEditorState extends State<_JourneyEditor> {
  String? selectedStage;
  bool saving = false;

  List<Map<String, dynamic>> get stages {
    final raw = widget.detail['manual_stages'];
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['key'] != null)
        .toList();
  }

  String get currentLabel {
    final raw = widget.detail['journey'];
    if (raw is Map) {
      return '${raw['current_label'] ?? 'Order received'}';
    }
    return 'Order received';
  }

  Future<void> save() async {
    final saleId = (widget.sale['id'] as num?)?.toInt();
    final stage = selectedStage;

    if (saleId == null || stage == null || stage.isEmpty) return;

    setState(() => saving = true);

    try {
      final result = await widget.api.setJourneyStage([saleId], stage);
      if (!mounted) return;

      final updated = (result['updated'] as num?)?.toInt() ?? 0;
      final skipped = result['skipped'];

      if (updated > 0) {
        Navigator.pop(context, true);
        return;
      }

      final message = skipped is List && skipped.isNotEmpty
          ? '${skipped.first}'
          : 'That milestone could not be applied to this order.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update journey: ${e}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = '${widget.sale['order_id'] ?? '#${widget.sale['id']}'}';
    final customer = '${widget.sale['customer_name'] ?? 'Customer'}';

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Order journey',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '$order • $customer',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Current milestone'),
              subtitle: Text(currentLabel),
            ),
          ),
          const SizedBox(height: 12),
          if (stages.isEmpty)
            const Text(
              'There are no manual milestones available for this order yet.',
            )
          else
            DropdownButtonFormField<String>(
              value: selectedStage,
              decoration: const InputDecoration(labelText: 'Move to milestone'),
              items: stages
                  .map(
                    (stage) => DropdownMenuItem<String>(
                      value: '${stage['key']}',
                      child: Text('${stage['label'] ?? stage['key']}'),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() => selectedStage = value),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving || selectedStage == null ? null : save,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.update),
              label: Text(saving ? 'Updating…' : 'Update milestone'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            const Text(
              'Could not load order journeys.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
