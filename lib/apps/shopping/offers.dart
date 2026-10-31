import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/format.dart';
import '../../core/settings.dart';

/// This week's supermarket offers from PrijsProfeet (prijsprofeet.nl), a free public API with the folder deals of
/// sixteen Dutch chains. It only knows what is on offer: an item that no chain has on offer finds nothing, and the
/// list falls back to the usual cheapest shop or the AI's guess. The free tier asks for a visible credit.
class PrijsProfeet {
  PrijsProfeet({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const base = 'https://www.prijsprofeet.nl/api/v1';
  static const credit = 'Offers via PrijsProfeet';
  static const site = 'https://www.prijsprofeet.nl';

  /// Their retailer keys, as the shop names the list uses.
  static const chains = {
    'albert_heijn': 'Albert Heijn',
    'jumbo': 'Jumbo',
    'aldi': 'Aldi',
    'lidl': 'Lidl',
    'plus': 'Plus',
    'dirk': 'Dirk',
    'hoogvliet': 'Hoogvliet',
    'vomar': 'Vomar',
    'dekamarkt': 'DekaMarkt',
    'ekoplaza': 'Ekoplaza',
    'spar': 'Spar',
    'poiesz': 'Poiesz',
    'nettorama': 'Nettorama',
    'coop': 'Coop',
    'gewoon_coop': 'Coop',
    'mcd': 'MCD',
    'boons_markt': "Boon's Markt",
  };

  /// The cheapest offer running today for [item], or null when no chain has it on offer.
  Future<Offer?> bestOffer(String item, {DateTime? now}) async {
    final query = dutchQuery(item);
    final uri = Uri.parse('$base/search')
        .replace(queryParameters: {'q': query, 'page_size': '25', 'promotion_status': 'active'});
    // Naming ourselves is their one request for callers without a key; "bot" in it would get a 403.
    final res = await _client
        .get(uri, headers: {'User-Agent': 'Hub/1.0 (+https://github.com/kapnistos/personal-apk)'})
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw OfferError(res.statusCode);
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final results = (body is Map ? body['results'] : null) as List? ?? const [];
    return pickOffer(results.whereType<Map>().map((m) => m.cast<String, dynamic>()), query, now ?? DateTime.now());
  }

  void close() => _client.close();
}

class OfferError implements Exception {
  const OfferError(this.status);
  final int status;
  @override
  String toString() => status == 429 ? 'Too many price checks at once; try again in a minute' : 'Offers: HTTP $status';
}

/// One offer: where, for how much, and until when.
class Offer {
  const Offer({
    required this.store,
    required this.price,
    required this.product,
    this.was,
    this.until,
    this.unitPrice,
    this.unit,
  });

  final String store;
  final double price;
  final double? was;
  final String product;
  final DateTime? until;
  final double? unitPrice;
  final String? unit;

  /// "€1.29 at Lidl, was €1.89, until Sun"
  String describe(String currency, {DateTime? now}) {
    String m(double v) => money((v * 100).round(), currency);
    final end = until;
    return [
      '${m(price)} at $store',
      if (was != null && was! > price) 'was ${m(was!)}',
      if (end != null) 'until ${friendlyDay(end, now: now)}',
    ].join(', ');
  }

  Map<String, dynamic> toJson() => {
    'store': store,
    'price': price,
    'product': product,
    if (was != null) 'was': was,
    if (until != null) 'until': until!.toIso8601String(),
    if (unitPrice != null) 'unitPrice': unitPrice,
    if (unit != null) 'unit': unit,
  };

  static Offer? fromJson(Object? j) {
    if (j is! Map || j['store'] is! String || j['price'] is! num) return null;
    return Offer(
      store: j['store'] as String,
      price: (j['price'] as num).toDouble(),
      product: j['product'] as String? ?? '',
      was: (j['was'] as num?)?.toDouble(),
      until: DateTime.tryParse(j['until'] as String? ?? ''),
      unitPrice: (j['unitPrice'] as num?)?.toDouble(),
      unit: j['unit'] as String?,
    );
  }
}

/// The cheapest result that is really on offer today and really is the item searched for. Fuzzy search returns
/// near misses ("pastasaus" for "pasta" is fine, "pasta-bord" from Action is not), so a result has to contain one of
/// the query's words; and prices compare per kilo or litre when every candidate has one, else per pack.
Offer? pickOffer(Iterable<Map<String, dynamic>> results, String query, DateTime now) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length >= 3).toList();
  final today = dateOnly(now);
  final candidates = <Offer>[];
  for (final r in results.take(15)) {
    if (r['promotion_status'] != 'active') continue;
    final store = PrijsProfeet.chains[r['retailer']];
    final price = (r['price'] as num?)?.toDouble();
    if (store == null || price == null || price <= 0) continue;
    final until = DateTime.tryParse(r['valid_until'] as String? ?? '');
    if (until != null && dateOnly(until).isBefore(today)) continue;
    final from = DateTime.tryParse(r['valid_from'] as String? ?? '');
    if (from != null && dateOnly(from).isAfter(today)) continue;
    final text = '${r['name'] ?? ''} ${r['brand'] ?? ''}'.toLowerCase();
    if (words.isNotEmpty && !words.any(text.contains)) continue;
    candidates.add(
      Offer(
        store: store,
        price: price,
        was: (r['original_price'] as num?)?.toDouble(),
        product: '${r['name'] ?? ''}'.trim(),
        until: until,
        unitPrice: (r['unit_price'] as num?)?.toDouble(),
        unit: r['unit'] as String?,
      ),
    );
  }
  if (candidates.isEmpty) return null;
  final perUnit =
      candidates.every((c) => c.unitPrice != null && c.unitPrice! > 0) &&
      candidates.map((c) => c.unit).toSet().length == 1;
  candidates.sort((a, b) => perUnit ? a.unitPrice!.compareTo(b.unitPrice!) : a.price.compareTo(b.price));
  return candidates.first;
}

/// The search runs on Dutch product names, so common English shopping words are put into Dutch first. Anything else,
/// Dutch already or a brand, goes through as typed.
String dutchQuery(String item) {
  final t = item.trim().toLowerCase();
  if (_dutch.containsKey(t)) return _dutch[t]!;
  final words = t.split(RegExp(r'\s+')).map((w) => _dutch[w] ?? w).join(' ');
  return words;
}

const _dutch = {
  'milk': 'melk',
  'bread': 'brood',
  'butter': 'boter',
  'cheese': 'kaas',
  'eggs': 'eieren',
  'egg': 'eieren',
  'yoghurt': 'yoghurt',
  'yogurt': 'yoghurt',
  'chicken': 'kip',
  'chicken breast': 'kipfilet',
  'beef': 'rundvlees',
  'minced meat': 'gehakt',
  'mince': 'gehakt',
  'pork': 'varkensvlees',
  'fish': 'vis',
  'salmon': 'zalm',
  'tuna': 'tonijn',
  'rice': 'rijst',
  'flour': 'bloem',
  'sugar': 'suiker',
  'salt': 'zout',
  'oil': 'olie',
  'olive oil': 'olijfolie',
  'coffee': 'koffie',
  'tea': 'thee',
  'water': 'water',
  'sparkling water': 'bruisend water',
  'juice': 'sap',
  'orange juice': 'sinaasappelsap',
  'beer': 'bier',
  'wine': 'wijn',
  'apples': 'appels',
  'apple': 'appels',
  'bananas': 'bananen',
  'banana': 'bananen',
  'oranges': 'sinaasappels',
  'tomatoes': 'tomaten',
  'tomato': 'tomaten',
  'potatoes': 'aardappelen',
  'onions': 'uien',
  'onion': 'uien',
  'garlic': 'knoflook',
  'cucumber': 'komkommer',
  'lettuce': 'sla',
  'carrots': 'wortels',
  'peppers': 'paprika',
  'mushrooms': 'champignons',
  'strawberries': 'aardbeien',
  'grapes': 'druiven',
  'toilet paper': 'toiletpapier',
  'kitchen roll': 'keukenpapier',
  'paper towels': 'keukenpapier',
  'dish soap': 'afwasmiddel',
  'washing up liquid': 'afwasmiddel',
  'detergent': 'wasmiddel',
  'laundry detergent': 'wasmiddel',
  'shampoo': 'shampoo',
  'toothpaste': 'tandpasta',
  'deodorant': 'deodorant',
  'deo': 'deodorant',
  'soap': 'zeep',
  'crisps': 'chips',
  'chocolate': 'chocolade',
  'cookies': 'koekjes',
  'biscuits': 'koekjes',
  'ice cream': 'ijs',
  'pizza': 'pizza',
  'cereal': 'ontbijtgranen',
  'oats': 'havermout',
  'peanut butter': 'pindakaas',
  'jam': 'jam',
  'honey': 'honing',
  'ham': 'ham',
  'sausages': 'worst',
  'bacon': 'spek',
  'cream': 'room',
  'sour cream': 'zure room',
  'feta': 'feta',
  'tomato sauce': 'tomatensaus',
  'beans': 'bonen',
  'nuts': 'noten',
  'diapers': 'luiers',
  'nappies': 'luiers',
  'cat food': 'kattenvoer',
  'dog food': 'hondenvoer',
};

/// Offers found last time, by item name, so the list shows them without asking again.
const offersKey = 'shopping.offers';

Map<String, Offer> savedOffers(AppSettings s) {
  try {
    final m = jsonDecode(s.raw(offersKey) ?? '{}') as Map;
    final out = <String, Offer>{};
    for (final e in m.entries) {
      final o = Offer.fromJson(e.value);
      if (o != null) out[e.key as String] = o;
    }
    return out;
  } catch (_) {
    return {};
  }
}

Future<void> saveOffers(AppSettings s, Map<String, Offer> offers) =>
    s.setRaw(offersKey, jsonEncode({for (final e in offers.entries) e.key: e.value.toJson()}));

/// Asks for the offers of several items at once, a few at a time to stay well inside the free limit. Throws the first
/// error only when every request failed (no connection, say), so one odd item never spoils the rest.
Future<Map<String, Offer?>> fetchOffers(PrijsProfeet api, List<String> items, {DateTime? now}) async {
  final out = <String, Offer?>{};
  Object? error;
  var failed = 0;
  for (var i = 0; i < items.length; i += 4) {
    final batch = items.skip(i).take(4).toList();
    final found = await Future.wait(
      batch.map((n) async {
        try {
          return await api.bestOffer(n, now: now);
        } catch (e) {
          error ??= e;
          failed++;
          return null;
        }
      }),
    );
    for (var j = 0; j < batch.length; j++) {
      out[batch[j].trim().toLowerCase()] = found[j];
    }
  }
  if (items.isNotEmpty && failed == items.length) throw error!;
  return out;
}
