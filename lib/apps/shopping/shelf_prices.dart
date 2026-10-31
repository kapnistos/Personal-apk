import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Regular shelf prices of whole supermarket ranges, from Checkjebon (checkjebon.nl, MIT licensed open data). One
/// file of about 10 MB with every product of AH, Jumbo, Lidl, Plus, Dirk, Hoogvliet, Vomar and more, refreshed
/// daily upstream. Hub fetches it at most once a day, only when you ask for prices, and keeps it on the device.
class ShelfPrices {
  ShelfPrices(this.chains);

  /// Products by shop name.
  final Map<String, List<ShelfProduct>> chains;

  static const urls = [
    'https://www.checkjebon.nl/data/supermarkets.json',
    'https://raw.githubusercontent.com/supermarkt/checkjebon/main/data/supermarkets.json',
  ];
  static const credit = 'Shelf prices via Checkjebon';
  static const site = 'https://www.checkjebon.nl';

  /// Their codes, as the shop names the list uses.
  static const names = {
    'ah': 'Albert Heijn',
    'aldi': 'Aldi',
    'dekamarkt': 'DekaMarkt',
    'dirk': 'Dirk',
    'ekoplaza': 'Ekoplaza',
    'hoogvliet': 'Hoogvliet',
    'jumbo': 'Jumbo',
    'lidl': 'Lidl',
    'plus': 'Plus',
    'poiesz': 'Poiesz',
    'spar': 'Spar',
    'vomar': 'Vomar',
    'coop': 'Coop',
    'janlinders': 'Jan Linders',
  };

  static ShelfPrices parse(String body) {
    final out = <String, List<ShelfProduct>>{};
    for (final s in (jsonDecode(body) as List).whereType<Map>()) {
      final name = names[s['n']] ?? s['c'] as String?;
      final items = s['d'];
      if (name == null || items is! List || items.isEmpty) continue;
      out[name] = [
        for (final p in items.whereType<Map>())
          if (p['n'] is String && p['p'] is num)
            ShelfProduct(p['n'] as String, (p['p'] as num).toDouble(), '${p['s'] ?? ''}'),
      ];
    }
    return ShelfPrices(out);
  }

  /// The file on the device, fetched again when older than a day. Falls back to the old copy when offline.
  static Future<ShelfPrices> load({http.Client? client, Directory? dir, DateTime? now}) async {
    final folder = dir ?? await getApplicationSupportDirectory();
    final file = File('${folder.path}/shelf-prices.json');
    final fresh = file.existsSync() && (now ?? DateTime.now()).difference(file.lastModifiedSync()).inHours < 24;
    if (!fresh) {
      final c = client ?? http.Client();
      try {
        for (final url in urls) {
          try {
            final res = await c.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
            if (res.statusCode == 200 && res.bodyBytes.isNotEmpty && res.bodyBytes.first == 0x5B) {
              await file.writeAsBytes(res.bodyBytes, flush: true);
              break;
            }
          } catch (_) {
            // Try the next copy.
          }
        }
      } finally {
        if (client == null) c.close();
      }
    }
    if (!file.existsSync()) throw const HttpException('Shelf prices could not be downloaded');
    final body = await file.readAsString();
    // Ten megabytes of JSON: parsed off the main thread so the list keeps scrolling.
    return compute(ShelfPrices.parse, body);
  }

  /// The cheapest match for [query] at each shop, compared per kilo, litre or piece where the pack size says.
  List<ShelfMatch> compare(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final found = <(String, ShelfProduct, Size?)>[];
    for (final e in chains.entries) {
      for (final p in e.value) {
        if (p.price < 0.2 || !_matches(p.name.toLowerCase(), words, query.toLowerCase())) continue;
        found.add((e.key, p, packSize(p.size, p.name)));
      }
    }
    if (found.isEmpty) return const [];
    // Compare like with like: the unit most matches are sold in.
    final counts = <String, int>{};
    for (final (_, _, z) in found) {
      if (z != null) counts[z.unit] = (counts[z.unit] ?? 0) + 1;
    }
    final unit = counts.isEmpty ? null : (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
    final best = <String, ShelfMatch>{};
    for (final (shop, p, z) in found) {
      final perUnit = unit == null ? null : (z?.unit == unit ? p.price / z!.amount : null);
      if (unit != null && perUnit == null) continue;
      final m = ShelfMatch(shop, p, perUnit, unit);
      final old = best[shop];
      if (old == null || m.rank < old.rank) best[shop] = m;
    }
    return best.values.toList()..sort((a, b) => a.rank.compareTo(b.rank));
  }
}

/// Words that mean a different product with the item in it: "melk" chocolate, "pasta" stew, "kaas" pizza.
const _otherProducts = [
  'hondenvoer', 'kattenvoer', 'reep', 'chocola', 'koek', 'wafel', 'creamer', 'smaak', 'saus', 'ijs', 'dessert', //
  'snoep', 'drop', 'muesli', 'digestive', 'spread', 'mix', 'gom', 'chips', 'soep', 'salade', 'maaltijd', 'voucher',
  'bruintjes', 'pizza', 'stoof', 'schotel', 'gekookte', 'biomenu', 'baby', 'shake', 'smoothie', 'ontbijtkoek',
  'deeg', 'gratin', 'knabbel', 'zonnebloem', 'vochtig', 'cracker', 'stengel',
];

final _sizeWord = RegExp(r'^(\d.*|g|gr|gram|kg|kilo|ml|cl|l|lt|liter|st|stuks?|x|per)$');

bool _matches(String name, List<String> words, String query) {
  final tokens = RegExp(r"[a-z0-9à-ÿ'-]+").allMatches(name).map((m) => m.group(0)!).toList();
  if (!words.every(tokens.contains)) return false;
  // The item is the product itself when it is one of the last words: "AH Halfvolle melk", not "melk hazelnoot".
  final core = tokens.where((t) => !_sizeWord.hasMatch(t)).toList();
  final last = words.last;
  final at = core.lastIndexOf(last);
  if (at < 0 || at < core.length - 2) return false;
  if (at > 0 && const {'met', 'en', '&'}.contains(core[at - 1])) return false;
  return !_otherProducts.any((w) => name.contains(w) && !query.contains(w));
}

class ShelfProduct {
  const ShelfProduct(this.name, this.price, this.size);
  final String name;
  final double price;
  final String size;
}

class ShelfMatch {
  const ShelfMatch(this.shop, this.product, this.perUnit, this.unit);
  final String shop;
  final ShelfProduct product;
  final double? perUnit;
  final String? unit;

  double get rank => perUnit ?? product.price;
}

class Size {
  const Size(this.amount, this.unit);
  final double amount;
  final String unit;
}

final _sizeRe = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(?:x\s*(\d+(?:[.,]\d+)?)\s*)?(kg|kilo|gram|gr|g|milliliter|ml|cl|liter|lt|l|stuks|stuk|st)\b',
);
const _units = {
  'g': ('kg', 0.001),
  'gr': ('kg', 0.001),
  'gram': ('kg', 0.001),
  'kg': ('kg', 1.0),
  'kilo': ('kg', 1.0),
  'ml': ('l', 0.001),
  'milliliter': ('l', 0.001),
  'cl': ('l', 0.01),
  'l': ('l', 1.0),
  'lt': ('l', 1.0),
  'liter': ('l', 1.0),
  'st': ('piece', 1.0),
  'stuk': ('piece', 1.0),
  'stuks': ('piece', 1.0),
};

/// "500 ml", "Per 350 g", "6 x 1 liter", or the size in the name: as an amount in kilos, litres or pieces.
Size? packSize(String size, String name) {
  for (final t in [size, name]) {
    final m = _sizeRe.firstMatch(t.toLowerCase());
    if (m == null) continue;
    var a = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    if (m.group(2) != null) a *= double.tryParse(m.group(2)!.replaceAll(',', '.')) ?? 1;
    final (unit, factor) = _units[m.group(3)]!;
    if (a > 0) return Size(a * factor, unit);
  }
  return null;
}
