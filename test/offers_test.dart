import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/shopping/offers.dart';

Map<String, dynamic> result(
  String retailer,
  String name,
  double price, {
  String status = 'active',
  String from = '2026-10-26',
  String until = '2026-11-01',
  double? unitPrice,
  String? unit,
  double? was,
}) => {
  'retailer': retailer,
  'name': name,
  'price': price,
  'original_price': ?was,
  'promotion_status': status,
  'valid_from': from,
  'valid_until': until,
  'unit_price': ?unitPrice,
  'unit': ?unit,
};

void main() {
  final now = DateTime(2026, 10, 31, 12);

  test('English shopping words are searched in Dutch, anything else as typed', () {
    expect(dutchQuery('Milk'), 'melk');
    expect(dutchQuery('toilet paper'), 'toiletpapier');
    expect(dutchQuery('olive oil'), 'olijfolie');
    expect(dutchQuery('hagelslag'), 'hagelslag');
    expect(dutchQuery('Douwe Egberts'), 'douwe egberts');
  });

  test('the cheapest offer that runs today and matches the item wins', () {
    final o = pickOffer(
      [
        result('albert_heijn', 'AH Koffie snelfilter', 4.99, was: 6.49),
        result('lidl', 'Koffiebonen', 3.79),
        result('jumbo', 'Koffie pads', 2.10, status: 'upcoming'), // next week
        result('dirk', 'Koffie', 1.50, until: '2026-10-30'), // ended yesterday
        result('action', 'Koffiemok', 0.99), // not a supermarket we know
        result('plus', 'Theezakjes', 1.00), // not the item
      ],
      'koffie',
      now,
    );
    expect(o!.store, 'Lidl');
    expect(o.price, 3.79);
  });

  test('prices compare per kilo when every candidate has one in the same unit', () {
    final o = pickOffer(
      [
        result('albert_heijn', 'Pasta penne 500 g', 1.00, unitPrice: 2.00, unit: 'kg'),
        result('aldi', 'Pasta fusilli 1 kg', 1.60, unitPrice: 1.60, unit: 'kg'),
      ],
      'pasta',
      now,
    );
    expect(o!.store, 'Aldi');
  });

  test('nothing on offer gives null', () {
    expect(pickOffer(const [], 'melk', now), isNull);
    expect(pickOffer([result('lidl', 'Kaas', 2.0)], 'melk', now), isNull);
  });

  test('an offer reads naturally and survives saving', () {
    final o = Offer(store: 'Lidl', price: 1.29, was: 1.89, product: 'Melk', until: DateTime(2026, 11, 1));
    expect(o.describe('EUR', now: now), contains('at Lidl'));
    expect(o.describe('EUR', now: now), contains('was'));
    final back = Offer.fromJson(jsonDecode(jsonEncode(o.toJson())));
    expect(back!.store, 'Lidl');
    expect(back.price, 1.29);
    expect(back.until, DateTime(2026, 11, 1));
  });

  test('the API is asked in Dutch, for active offers, with our name in the User-Agent', () async {
    late http.Request seen;
    final api = PrijsProfeet(
      client: MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'results': [result('jumbo', 'Halfvolle melk', 0.99)],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final o = await api.bestOffer('milk', now: now);
    expect(o!.store, 'Jumbo');
    expect(seen.url.queryParameters['q'], 'melk');
    expect(seen.url.queryParameters['promotion_status'], 'active');
    expect(seen.headers['User-Agent'], startsWith('Hub/'));
    expect(seen.headers['User-Agent']!.toLowerCase(), isNot(contains('bot')));
  });

  test('one failing item does not spoil the rest; all failing reports the error', () async {
    final api = PrijsProfeet(
      client: MockClient((req) async {
        if (req.url.queryParameters['q'] == 'kaas') return http.Response('busy', 500);
        return http.Response(jsonEncode({'results': [result('aldi', 'Melk', 0.89)]}), 200);
      }),
    );
    final found = await fetchOffers(api, ['milk', 'cheese'], now: now);
    expect(found['milk']!.store, 'Aldi');
    expect(found['cheese'], isNull);

    final down = PrijsProfeet(client: MockClient((_) async => http.Response('', 503)));
    expect(fetchOffers(down, ['milk', 'cheese'], now: now), throwsA(isA<OfferError>()));
  });
}
