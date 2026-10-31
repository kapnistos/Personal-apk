import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/shopping/offers.dart';
import 'package:hub/apps/shopping/shelf_prices.dart';

String data() => jsonEncode([
  {
    'n': 'ah',
    'c': 'AH',
    'd': [
      {'n': 'AH Halfvolle melk', 'p': 0.89, 's': '0,5 l'},
      {'n': 'AH Biologisch Schelpjes pasta', 'p': 1.39, 's': '500 g'},
      {'n': 'AH Blik stoof lam-pasta-groente', 'p': 0.99, 's': '400 g'},
    ],
  },
  {
    'n': 'jumbo',
    'c': 'Jumbo',
    'd': [
      {'n': 'Jumbo Halfvolle Melk 2 L', 'p': 1.55, 's': ''},
      {'n': 'Jumbo Melkchocolade reep', 'p': 0.49, 's': '100 g'},
    ],
  },
  {
    'n': 'dirk',
    'c': 'Dirk',
    'd': [
      {'n': 'Confina Chocoladereep melk hazelnoot', 'p': 0.85, 's': '100 g'},
      {'n': 'Pastaschotel met melk', 'p': 0.30, 's': '1 l'},
      {'n': 'Voucher melk', 'p': 0.01, 's': '1 l'},
    ],
  },
  {'n': 'aldi', 'c': 'ALDI', 'd': []},
]);

void main() {
  test('pack sizes become kilos, litres or pieces', () {
    expect(packSize('0,5 l', '')!.amount, 0.5);
    expect(packSize('Per 350 g', '')!.unit, 'kg');
    expect(packSize('', 'Melk 6 x 1 liter')!.amount, 6);
    expect(packSize('', 'Eieren 12 stuks')!.unit, 'piece');
    expect(packSize('', 'Bananen los'), isNull);
  });

  test('the item itself is compared per litre, not chocolate or a stew with it in', () {
    final shelf = ShelfPrices.parse(data());
    expect(shelf.chains.keys, containsAll(['Albert Heijn', 'Jumbo', 'Dirk']));
    expect(shelf.chains.containsKey('Aldi'), isFalse);
    final melk = shelf.compare('melk');
    expect(melk.map((m) => m.shop), ['Jumbo', 'Albert Heijn']);
    expect(melk.first.perUnit, closeTo(0.775, 0.001));
    expect(melk.first.unit, 'l');
    final pasta = shelf.compare('pasta');
    expect(pasta.single.product.name, 'AH Biologisch Schelpjes pasta');
  });

  test('an offer wins unless a shelf price is lower', () {
    final shelf = ShelfPrices.parse(data());
    const deal = Offer(store: 'Lidl', price: 0.69, product: 'Melk');
    expect(cheapestOf(deal, shelf, 'milk')!.store, 'Lidl');
    const dear = Offer(store: 'Lidl', price: 2.50, product: 'Melk');
    final o = cheapestOf(dear, shelf, 'milk')!;
    expect(o.store, 'Jumbo');
    expect(o.onOffer, isFalse);
    expect(o.describe('EUR'), contains('a litre'));
    expect(Offer.fromJson(jsonDecode(jsonEncode(o.toJson())))!.onOffer, isFalse);
    expect(cheapestOf(null, null, 'milk'), isNull);
  });

  test('the file is fetched once a day and kept for offline use', () async {
    final dir = await Directory.systemTemp.createTemp('shelf');
    addTearDown(() => dir.delete(recursive: true));
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(data(), 200);
    });
    await ShelfPrices.load(client: client, dir: dir);
    await ShelfPrices.load(client: client, dir: dir);
    expect(calls, 1);
    final offline = MockClient((_) async => throw const SocketException('offline'));
    final later = await ShelfPrices.load(client: offline, dir: dir, now: DateTime.now().add(const Duration(days: 2)));
    expect(later.chains, isNotEmpty);
  });
}
