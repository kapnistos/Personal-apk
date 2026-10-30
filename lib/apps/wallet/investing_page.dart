import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'savings_page.dart' show confirmDelete;

const holdingKinds = {
  'etf': ('ETF', Color(0xFF3A78C9)),
  'stock': ('Stock', Color(0xFF6650AE)),
  'fund': ('Fund', Color(0xFF2D8C9E)),
  'crypto': ('Crypto', Color(0xFFCF9418)),
  'bond': ('Bond', Color(0xFF1F7A5A)),
  'pension': ('Pension', Color(0xFF8A5A44)),
  'other': ('Other', Color(0xFF6F6A60)),
};

int holdingValueCents(Holding h) => (h.units * h.price * 100).round();

/// Latest prices from Yahoo Finance's public chart data (no account or key).
/// Prices in another currency are converted with Yahoo's exchange rates.
class PriceService {
  static Future<(double, String?)?> _quote(String symbol) async {
    final res = await http
        .get(Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${Uri.encodeComponent(symbol)}?range=1d&interval=1d'),
            headers: {'User-Agent': 'Mozilla/5.0 Hub'})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final meta = (jsonDecode(res.body)['chart']?['result'] as List?)?.firstOrNull?['meta'] as Map?;
    if (meta == null) return null;
    final price = (meta['regularMarketPrice'] as num?)?.toDouble();
    final currency = meta['currency'] as String?;
    if (price == null) return null;
    return (price, currency);
  }

  /// Price of one unit of [symbol] in [currency], or null if unknown.
  static Future<double?> price(String symbol, String currency) async {
    final q = await _quote(symbol);
    if (q == null || q.$2 == null) return null;
    var (value, from as String) = q;
    // London prices come in pence.
    if (from == 'GBp' || from == 'GBX') {
      value /= 100;
      from = 'GBP';
    }
    if (from.toUpperCase() == currency.toUpperCase()) return value;
    final rate = await _quote('${from.toUpperCase()}${currency.toUpperCase()}=X');
    return rate == null ? null : value * rate.$1;
  }

  /// Updates every holding with a symbol. Returns how many were updated.
  static Future<int> refreshAll(AppDatabase db, String currency) async {
    final all = await db.watchHoldings().first;
    var n = 0;
    for (final h in all.where((h) => h.symbol.trim().isNotEmpty)) {
      try {
        final p = await price(h.symbol.trim(), currency);
        if (p != null) {
          await db.setHoldingPrice(h.id, p);
          n++;
        }
      } catch (_) {
        // Keep the last known price.
      }
    }
    return n;
  }
}

class InvestingTab extends StatefulWidget {
  const InvestingTab({super.key});

  @override
  State<InvestingTab> createState() => _InvestingTabState();
}

class _InvestingTabState extends State<InvestingTab> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    final n = await PriceService.refreshAll(context.db, context.settings.currency);
    if (!mounted) return;
    setState(() => _refreshing = false);
    messenger.showSnackBar(SnackBar(
        content: Text(n == 0 ? 'No prices updated. Check the tickers or your connection.' : 'Updated $n prices')));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final currency = context.settings.currency;
    return StreamBuilder<List<Holding>>(
      stream: context.db.watchHoldings(),
      builder: (context, snap) {
        final holdings = snap.data ?? const <Holding>[];
        final value = holdings.fold<int>(0, (a, h) => a + holdingValueCents(h));
        final invested = holdings.fold<int>(0, (a, h) => a + h.investedCents);
        final gain = value - invested;
        final byKind = <String, int>{};
        for (final h in holdings) {
          byKind[h.kind] = (byKind[h.kind] ?? 0) + holdingValueCents(h);
        }
        final updated = holdings.map((h) => h.priceAt).whereType<DateTime>().fold<DateTime?>(
            null, (a, b) => a == null || b.isAfter(a) ? b : a);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              ContentWidth(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(colors: [Color(0xFF233B5E), Color(0xFF3A5F8F)]),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Portfolio value',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        BigAmount(money(value, currency), size: 38, color: Colors.white),
                        const SizedBox(height: 6),
                        Text(
                          invested == 0
                              ? 'Add what you own to follow it here'
                              : '${money(gain, currency, signed: true)} (${(gain / invested * 100).toStringAsFixed(1)}%) on ${money(invested, currency)} put in',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.88)),
                        ),
                        if (updated != null)
                          Text('Prices from ${relativeTime(updated)}',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 13)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Update prices',
                      onPressed: _refreshing ? null : _refresh,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.refresh_rounded, color: Colors.white),
                    ),
                  ]),
                ),
              ),
              if (value > 0) ...[
                const SizedBox(height: 12),
                ContentWidth(
                  child: Section(
                    title: 'Spread',
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 12,
                            child: Row(children: [
                              for (final MapEntry(key: k, value: v) in byKind.entries)
                                if (v > 0) Expanded(flex: v, child: Container(color: holdingKinds[k]?.$2 ?? p.muted)),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(spacing: 14, runSpacing: 6, children: [
                          for (final MapEntry(key: k, value: v) in byKind.entries)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              CircleAvatar(radius: 5, backgroundColor: holdingKinds[k]?.$2 ?? p.muted),
                              const SizedBox(width: 6),
                              Text('${holdingKinds[k]?.$1 ?? k} ${(v / value * 100).round()}%',
                                  style: const TextStyle(fontSize: 14)),
                            ]),
                        ]),
                      ]),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (holdings.isEmpty)
                const EmptyState(
                  icon: Icons.show_chart_rounded,
                  title: 'Nothing here yet',
                  message: 'Add an ETF, stock, fund or crypto. With a ticker like VWRL.AS or BTC-EUR, '
                      'Hub can fetch the latest price.',
                )
              else
                ContentWidth(
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (var i = 0; i < holdings.length; i++) ...[
                        if (i > 0) const Divider(indent: 64),
                        _HoldingTile(h: holdings[i], currency: currency),
                      ],
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              ContentWidth(
                child: Text(
                  'Hub only follows what you enter. It never connects to your broker or moves money. '
                  'Prices come from Yahoo Finance and can be delayed.',
                  style: TextStyle(color: p.muted, fontSize: 13.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({required this.h, required this.currency});
  final Holding h;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final value = holdingValueCents(h);
    final gain = value - h.investedCents;
    final pct = h.investedCents == 0 ? 0.0 : gain / h.investedCents * 100;
    final (label, color) = holdingKinds[h.kind] ?? ('Other', p.muted);
    return ListTile(
      onTap: () => editHolding(context, holding: h),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Text(
          (h.symbol.isNotEmpty ? h.symbol : h.name).characters.take(2).toString().toUpperCase(),
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      title: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [label, if (h.symbol.isNotEmpty) h.symbol, '${formatUnits(h.units)} units', if (h.account.isNotEmpty) h.account]
            .join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: p.muted),
      ),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(money(value, currency), style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 13.5, color: gain >= 0 ? p.positive : p.danger)),
      ]),
    );
  }
}

String formatUnits(double u) => u == u.roundToDouble() ? u.toStringAsFixed(0) : u.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');

Future<void> editHolding(BuildContext context, {Holding? holding}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Hub(db: context.db, settings: context.settings, child: _HoldingEditor(holding: holding)),
  );
}

class _HoldingEditor extends StatefulWidget {
  const _HoldingEditor({this.holding});
  final Holding? holding;

  @override
  State<_HoldingEditor> createState() => _HoldingEditorState();
}

class _HoldingEditorState extends State<_HoldingEditor> {
  late final _name = TextEditingController(text: widget.holding?.name ?? '');
  late final _symbol = TextEditingController(text: widget.holding?.symbol ?? '');
  late final _units = TextEditingController(text: widget.holding == null ? '' : _units0(widget.holding!.units));
  late final _invested = TextEditingController(
      text: widget.holding == null ? '' : (widget.holding!.investedCents / 100).toStringAsFixed(2));
  late final _price = TextEditingController(text: widget.holding == null ? '' : widget.holding!.price.toStringAsFixed(2));
  late final _account = TextEditingController(text: widget.holding?.account ?? '');
  late String _kind = widget.holding?.kind ?? 'etf';
  String? _status;

  static String _units0(double u) => formatUnits(u);

  @override
  void dispose() {
    for (final c in [_name, _symbol, _units, _invested, _price, _account]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  Future<void> _lookup() async {
    final sym = _symbol.text.trim();
    if (sym.isEmpty) return;
    setState(() => _status = 'Looking up $sym…');
    try {
      final p = await PriceService.price(sym, context.settings.currency);
      if (!mounted) return;
      setState(() {
        if (p != null) _price.text = p.toStringAsFixed(2);
        _status = p == null ? 'No price found for $sym' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _status = 'Could not reach Yahoo Finance');
    }
  }

  Future<void> _save() async {
    final units = _num(_units.text);
    final invested = parseMoney(_invested.text);
    final price = _num(_price.text) ?? (units != null && units > 0 && invested != null ? invested / 100 / units : null);
    if (_name.text.trim().isEmpty || units == null || invested == null || price == null) {
      setState(() => _status = 'Fill in name, units and amount put in');
      return;
    }
    await context.db.saveHolding(HoldingsCompanion(
      id: widget.holding == null ? const Value.absent() : Value(widget.holding!.id),
      name: Value(_name.text.trim()),
      symbol: Value(_symbol.text.trim().toUpperCase()),
      kind: Value(_kind),
      units: Value(units),
      investedCents: Value(invested),
      price: Value(price),
      priceAt: Value(widget.holding?.price == price ? widget.holding?.priceAt : DateTime.now()),
      account: Value(_account.text.trim()),
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _buyMore() async {
    final units = TextEditingController();
    final cost = TextEditingController();
    final currency = context.settings.currency;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bought more'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: units,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Units bought')),
          const SizedBox(height: 10),
          TextField(
              controller: cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Total paid', prefixText: '${currencySymbol(currency)} ')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    final u = _num(units.text), c = parseMoney(cost.text);
    if (ok != true || u == null || c == null) return;
    setState(() {
      _units.text = _units0((_num(_units.text) ?? 0) + u);
      _invested.text = (((parseMoney(_invested.text) ?? 0) + c) / 100).toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final currency = context.settings.currency;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.holding == null ? 'Add holding' : 'Edit holding', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'Vanguard FTSE All-World'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _symbol,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Ticker (optional)', hintText: 'VWRL.AS'),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: _lookup, child: const Text('Get price')),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final MapEntry(key: k, value: (label, _)) in holdingKinds.entries)
              ChoiceChip(
                showCheckmark: false,
                label: Text(label),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _units,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Units'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _invested,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Put in', prefixText: '${currencySymbol(currency)} '),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Price per unit', prefixText: '${currencySymbol(currency)} '),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _account,
                decoration: const InputDecoration(labelText: 'Where', hintText: 'DEGIRO, Revolut…'),
              ),
            ),
          ]),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: TextStyle(color: p.muted)),
            ),
          const SizedBox(height: 14),
          Row(children: [
            if (widget.holding != null) ...[
              TextButton(
                style: TextButton.styleFrom(foregroundColor: p.danger),
                onPressed: () async {
                  if (!await confirmDelete(context, 'Remove ${widget.holding!.name}?') || !context.mounted) return;
                  await context.db.deleteHolding(widget.holding!.id);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Remove'),
              ),
              TextButton(onPressed: _buyMore, child: const Text('Bought more')),
            ],
            const Spacer(),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ]),
        ]),
      ),
    );
  }
}
