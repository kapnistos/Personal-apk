import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/settings.dart';

const shoppingColor = Color(0xFF2F8F5B);

/// Shops Hub knows, with a colour for each.
const knownStores = {
  'Albert Heijn': 0xFF00A0E2,
  'Lidl': 0xFF0050AA,
  'Aldi': 0xFF1E3A8A,
  'Jumbo': 0xFFE8B500,
  'Plus': 0xFF6BA539,
  'Dirk': 0xFFD7141A,
  'Kruidvat': 0xFFE2001A,
  'Etos': 0xFF0B7A75,
  'Action': 0xFF0067B1,
  'HEMA': 0xFFC8102E,
  'Hollandse markt': 0xFF8A5A44,
};

Color storeColor(String store) => Color(knownStores[store] ?? 0xFF5F6B7A);

class ShopCategory {
  const ShopCategory(this.name, this.icon, this.words);
  final String name;
  final IconData icon;

  /// Words that put an item in this category ("deo" matches "deodorant").
  final List<String> words;
}

/// Categories, checked in order; the first that matches wins.
const shopCategories = [
  ShopCategory('Personal care', Icons.spa_outlined, [
    'deo',
    'shampoo',
    'conditioner',
    'toothpaste',
    'tandpasta',
    'toothbrush',
    'razor',
    'scheermes',
    'shaving',
    'soap',
    'zeep',
    'shower',
    'douche',
    'lotion',
    'face cream',
    'sunscreen',
    'vitamin',
    'plaster',
    'pleister',
    'floss',
    'makeup',
    'mascara',
    'cotton',
    'wattenschijf',
    'hair',
    'gel',
    'paracetamol',
    'ibuprofen',
    'condom',
    'tampon',
    'pads',
    'contact lens',
    'lens',
    'mouthwash',
    'mondwater',
    'perfume',
    'parfum',
  ]),
  ShopCategory('Paper & cleaning', Icons.cleaning_services_outlined, [
    'toilet',
    'wc papier',
    'wcpapier',
    'kitchen roll',
    'keukenrol',
    'tissue',
    'napkin',
    'servet',
    'detergent',
    'wasmiddel',
    'laundry',
    'softener',
    'wasverzachter',
    'dish',
    'afwas',
    'sponge',
    'spons',
    'bleach',
    'cleaner',
    'schoonmaak',
    'trash bag',
    'vuilniszak',
    'garbage',
    'foil',
    'folie',
    'baking paper',
    'bakpapier',
    'dishwasher',
    'vaatwas',
  ]),
  ShopCategory('Home & other', Icons.home_repair_service_outlined, [
    'batter',
    'lamp',
    'bulb',
    'candle',
    'kaars',
    'storage',
    'box',
    'hanger',
    'charger',
    'cable',
    'kabel',
    'tape',
    'glue',
    'lijm',
    'notebook',
    'pens',
    'gift',
    'cadeau',
    'plant',
    'towel',
    'handdoek',
  ]),
  ShopCategory('Fruit & veg', Icons.eco_outlined, [
    'apple',
    'appel',
    'banana',
    'banaan',
    'orange',
    'sinaas',
    'lemon',
    'citroen',
    'grape',
    'druif',
    'berry',
    'bes',
    'tomato',
    'tomaat',
    'cucumber',
    'komkommer',
    'onion',
    'ui',
    'garlic',
    'knoflook',
    'potato',
    'aardappel',
    'carrot',
    'wortel',
    'pepper',
    'paprika',
    'lettuce',
    'sla',
    'spinach',
    'spinazie',
    'broccoli',
    'mushroom',
    'champignon',
    'avocado',
    'zucchini',
    'courgette',
    'herb',
    'kruiden',
    'fruit',
    'veg',
    'groente',
    'salad',
  ]),
  ShopCategory('Dairy & eggs', Icons.egg_outlined, [
    'milk',
    'melk',
    'yog',
    'kwark',
    'cheese',
    'kaas',
    'feta',
    'butter',
    'boter',
    'cream',
    'room',
    'egg',
    'ei',
  ]),
  ShopCategory('Meat & fish', Icons.set_meal_outlined, [
    'chicken',
    'kip',
    'beef',
    'rund',
    'pork',
    'varken',
    'mince',
    'gehakt',
    'sausage',
    'worst',
    'bacon',
    'spek',
    'ham',
    'fish',
    'vis',
    'salmon',
    'zalm',
    'tuna',
    'tonijn',
    'shrimp',
    'garnaal',
    'meat',
    'vlees',
    'turkey',
  ]),
  ShopCategory('Bakery', Icons.bakery_dining_outlined, [
    'bread',
    'brood',
    'croissant',
    'bun',
    'bolletje',
    'wrap',
    'tortilla',
    'pita',
    'bagel',
    'cake',
    'taart',
  ]),
  ShopCategory('Pantry', Icons.kitchen_outlined, [
    'pasta',
    'spaghetti',
    'penne',
    'noodle',
    'rice',
    'rijst',
    'flour',
    'meel',
    'sugar',
    'suiker',
    'salt',
    'zout',
    'oil',
    'olie',
    'vinegar',
    'azijn',
    'sauce',
    'saus',
    'pesto',
    'can',
    'blik',
    'beans',
    'bonen',
    'lentil',
    'linzen',
    'oats',
    'haver',
    'cereal',
    'muesli',
    'granola',
    'honey',
    'honing',
    'jam',
    'peanut',
    'pinda',
    'spice',
    'stock',
    'bouillon',
    'soup',
    'soep',
    'tomato paste',
    'passata',
    'couscous',
    'quinoa',
  ]),
  ShopCategory('Drinks', Icons.local_cafe_outlined, [
    'coffee',
    'koffie',
    'tea',
    'thee',
    'juice',
    'sap',
    'water',
    'cola',
    'soda',
    'beer',
    'bier',
    'wine',
    'wijn',
    'energy',
    'frisdrank',
  ]),
  ShopCategory('Snacks & frozen', Icons.icecream_outlined, [
    'chips',
    'crisps',
    'chocolate',
    'chocola',
    'cookie',
    'koek',
    'biscuit',
    'nuts',
    'noten',
    'candy',
    'snoep',
    'ice',
    'ijs',
    'frozen',
    'diepvries',
    'pizza',
    'popcorn',
    'snack',
  ]),
];

const otherCategory = 'Other';

String categorize(String item) {
  final s = item.toLowerCase();
  for (final c in shopCategories) {
    for (final w in c.words) {
      // Short words must match a whole word ("ei" in "eieren" yes, in "reiger" no).
      if (w.length <= 3 ? RegExp('(^|[^a-z])${RegExp.escape(w)}').hasMatch(s) : s.contains(w)) {
        return c.name;
      }
    }
  }
  return otherCategory;
}

IconData categoryIcon(String name) =>
    shopCategories.where((c) => c.name == name).firstOrNull?.icon ?? Icons.shopping_basket_outlined;

/// Where each kind of item is usually cheapest in the Netherlands. Change it in the shopping settings.
const defaultCheapest = {
  'Personal care': 'Kruidvat',
  'Paper & cleaning': 'Lidl',
  'Home & other': 'Action',
  'Fruit & veg': 'Lidl',
  'Dairy & eggs': 'Lidl',
  'Meat & fish': 'Albert Heijn',
  'Bakery': 'Albert Heijn',
  'Pantry': 'Albert Heijn',
  'Drinks': 'Lidl',
  'Snacks & frozen': 'Aldi',
  otherCategory: 'Albert Heijn',
};

Map<String, String> cheapestMap(AppSettings s) {
  final raw = s.raw('shopping.cheapest');
  if (raw == null) return {...defaultCheapest};
  try {
    return {...defaultCheapest, ...(jsonDecode(raw) as Map).cast<String, String>()};
  } catch (_) {
    return {...defaultCheapest};
  }
}

Future<void> saveCheapestMap(AppSettings s, Map<String, String> m) => s.setRaw('shopping.cheapest', jsonEncode(m));

/// Items remembered by name, so "pasta" goes where you last put it.
Map<String, String> rememberedStores(AppSettings s) {
  final raw = s.raw('shopping.remembered');
  if (raw == null) return {};
  try {
    return (jsonDecode(raw) as Map).cast<String, String>();
  } catch (_) {
    return {};
  }
}

Future<void> rememberStore(AppSettings s, String item, String store) {
  final m = rememberedStores(s)..[item.trim().toLowerCase()] = store;
  return s.setRaw('shopping.remembered', jsonEncode(m));
}

/// The shop to buy [item] at: where you put it before, otherwise the cheapest for its kind.
String suggestStore(String item, Map<String, String> cheapest, Map<String, String> remembered) =>
    remembered[item.trim().toLowerCase()] ?? cheapest[categorize(item)] ?? cheapest[otherCategory] ?? '';

/// Splits "pasta, 2x toilet paper; deodorant" into names with quantities.
List<(String, String)> parseShoppingInput(String input) {
  final out = <(String, String)>[];
  for (var part in input.split(RegExp(r'[,;\n]'))) {
    part = part.trim();
    if (part.isEmpty) continue;
    final m =
        RegExp(r'^(\d+(?:[.,]\d+)?\s*(?:x|×|kg|g|l|ml|pcs|stuks)?)\s+(.+)$', caseSensitive: false).firstMatch(part) ??
        RegExp(r'^(.+?)\s+(\d+(?:[.,]\d+)?\s*(?:x|×|kg|g|l|ml|pcs|stuks))$', caseSensitive: false).firstMatch(part);
    if (m == null) {
      out.add((part, ''));
    } else if (RegExp(r'^\d').hasMatch(m[1]!)) {
      out.add((m[2]!.trim(), m[1]!.replaceAll(RegExp(r'\s+'), '')));
    } else {
      out.add((m[1]!.trim(), m[2]!.replaceAll(RegExp(r'\s+'), '')));
    }
  }
  return out;
}

/// Reads Claude's answer: lines like "Pasta → Albert Heijn", "pasta: Lidl", or a
/// shop heading followed by "- item" lines. Returns item name (lower case) to shop.
Map<String, String> parseStorePlan(String text, Iterable<String> items) {
  final names = {for (final i in items) i.trim().toLowerCase(): i};
  final stores = {...knownStores.keys};
  String? heading;
  final out = <String, String>{};
  String? matchStore(String s) {
    final t = s.replaceAll(RegExp(r'[*_#:]'), '').trim().toLowerCase();
    for (final st in stores) {
      if (t == st.toLowerCase() || t.startsWith('${st.toLowerCase()} ') || t.startsWith('${st.toLowerCase()}(')) {
        return st;
      }
    }
    return null;
  }

  String? matchItem(String s) {
    final t = s.replaceAll(RegExp(r'^[\s\-*•\d.)]+'), '').replaceAll(RegExp(r'[*_]'), '').trim().toLowerCase();
    if (names.containsKey(t)) return t;
    for (final n in names.keys) {
      if (t.startsWith(n) || t.contains(n)) return n;
    }
    return null;
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final split = RegExp(r'\s*(?:→|->|–|—|:|=)\s*').firstMatch(line);
    if (split != null && split.start > 0) {
      final left = line.substring(0, split.start);
      final right = line.substring(split.end);
      final item = matchItem(left);
      final store = matchStore(right.split(RegExp(r'[(,]')).first);
      if (item != null && store != null) {
        out[item] = store;
        continue;
      }
      final headingStore = matchStore(left);
      if (headingStore != null && right.trim().isEmpty) {
        heading = headingStore;
        continue;
      }
    }
    final s = matchStore(line);
    if (s != null) {
      heading = s;
      continue;
    }
    final item = matchItem(line);
    if (item != null && heading != null) out[item] = heading;
  }
  return out;
}

/// The question for Claude: which shop is cheapest for each item right now.
String shoppingPrompt(List<String> items, String city) =>
    '''
I shop in $city, Netherlands. For each item below, tell me which supermarket or shop is usually cheapest for it right now: Albert Heijn, Lidl, Aldi, Jumbo, Plus, Dirk, Kruidvat, Etos, Action or HEMA. Think of current bonus offers if you know them.

Answer with one line per item, exactly like "item → Shop", and nothing else, so my app can read it.

${items.map((i) => '- $i').join('\n')}
''';
