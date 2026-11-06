import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hub/apps/mail/account_setup.dart';
import 'package:hub/apps/mail/mail_service.dart';
import 'package:hub/core/db/database.dart';
import 'package:hub/core/settings.dart';

const _ispdb = '''<?xml version="1.0"?>
<clientConfig version="1.1">
  <emailProvider id="example.org">
    <domain>example.org</domain>
    <incomingServer type="pop3">
      <hostname>pop.example.org</hostname><port>995</port><socketType>SSL</socketType>
      <username>%EMAILADDRESS%</username><authentication>password-cleartext</authentication>
    </incomingServer>
    <incomingServer type="imap">
      <hostname>imap.example.org</hostname><port>143</port><socketType>STARTTLS</socketType>
      <username>%EMAILLOCALPART%</username><authentication>password-cleartext</authentication>
    </incomingServer>
    <incomingServer type="imap">
      <hostname>imap.example.org</hostname><port>993</port><socketType>SSL</socketType>
      <username>%EMAILLOCALPART%</username><authentication>password-cleartext</authentication>
    </incomingServer>
    <outgoingServer type="smtp">
      <hostname>smtp.example.org</hostname><port>25</port><socketType>plain</socketType>
      <username>%EMAILLOCALPART%</username><authentication>password-cleartext</authentication>
    </outgoingServer>
    <outgoingServer type="smtp">
      <hostname>smtp.example.org</hostname><port>587</port><socketType>STARTTLS</socketType>
      <username>%EMAILLOCALPART%</username><authentication>password-cleartext</authentication>
    </outgoingServer>
  </emailProvider>
</clientConfig>''';

void main() {
  group('provider from the address', () {
    test('known domains', () {
      expect(detectProvider('someone@gmail.com')?.id, 'gmail');
      expect(detectProvider(' Someone@GoogleMail.com ')?.id, 'gmail');
      expect(detectProvider('someone@hotmail.com')?.id, 'outlook');
      expect(detectProvider('someone@outlook.com')?.id, 'outlook');
      expect(detectProvider('someone@live.nl')?.id, 'outlook');
      expect(detectProvider('someone@hotmail.co.uk')?.id, 'outlook');
      expect(detectProvider('someone@proton.me')?.id, 'proton');
      expect(detectProvider('someone@pm.me')?.id, 'proton');
      expect(detectProvider('someone@protonmail.com')?.id, 'proton');
      expect(detectProvider('someone@icloud.com')?.id, 'icloud');
      expect(detectProvider('someone@me.com')?.id, 'icloud');
      expect(detectProvider('someone@yahoo.com')?.id, 'yahoo');
      expect(detectProvider('someone@yahoo.com.au')?.id, 'yahoo');
    });

    test('unknown or invalid addresses', () {
      expect(detectProvider('someone@example.org'), isNull);
      expect(detectProvider('not an email'), isNull);
      expect(detectProvider('someone@'), isNull);
      expect(detectProvider('@gmail.com'), isNull);
      expect(looksLikeEmail('a@b.co'), isTrue);
      expect(looksLikeEmail('a@localhost'), isFalse);
    });

    test('presets carry working defaults', () {
      final proton = presetFor('proton');
      expect(proton.imapHost, '127.0.0.1');
      expect(proton.imapPort, 1143);
      expect(proton.smtpPort, 1025);
      expect(proton.imapSecurity, 'starttls');
      expect(proton.smtpSecurity, 'starttls');
      expect(proton.allowSelfSigned, isTrue);
      expect(presetFor('gmail').links.map((l) => l.url), contains('https://myaccount.google.com/apppasswords'));
      expect(presetFor('nonsense').id, 'imap');
      for (final p in mailPresets.where((p) => !p.isOther)) {
        expect(p.imapHost, isNotEmpty, reason: p.id);
        expect(p.smtpHost, isNotEmpty, reason: p.id);
        expect(p.steps, isNotEmpty, reason: p.id);
      }
    });

    test('custom domains by their mail server', () {
      expect(providerForMx('aspmx.l.google.com.')?.id, 'gmail');
      expect(providerForMx('example-org.mail.protection.outlook.com')?.id, 'outlook');
      expect(providerForMx('mail.protonmail.ch')?.id, 'proton');
      expect(providerForMx('mx01.mail.icloud.com')?.id, 'icloud');
      expect(providerForMx('mx.example.org'), isNull);
      // Not fooled by a lookalike.
      expect(providerForMx('mail.notgoogle.com'), isNull);
    });
  });

  group('autoconfig', () {
    test('picks IMAP and SMTP with encryption, SSL first', () {
      final s = parseAutoconfig(_ispdb, 'alex@example.org')!;
      expect(s.imapHost, 'imap.example.org');
      expect(s.imapPort, 993);
      expect(s.imapSecurity, 'ssl');
      expect(s.smtpHost, 'smtp.example.org');
      expect(s.smtpPort, 587);
      expect(s.smtpSecurity, 'starttls');
      expect(s.username, 'alex');
    });

    test('no username when it is the email address', () {
      final xml = _ispdb.replaceAll('%EMAILLOCALPART%', '%EMAILADDRESS%');
      expect(parseAutoconfig(xml, 'alex@example.org')!.username, isNull);
    });

    test('broken or plain-only files give nothing', () {
      expect(parseAutoconfig('<html>Not found</html>', 'a@example.org'), isNull);
      expect(parseAutoconfig('not xml at all <', 'a@example.org'), isNull);
      final plainOnly = _ispdb.replaceAll('SSL', 'plain').replaceAll('STARTTLS', 'plain');
      expect(parseAutoconfig(plainOnly, 'a@example.org'), isNull);
      final oauthOnly = _ispdb.replaceAll('password-cleartext', 'OAuth2');
      expect(parseAutoconfig(oauthOnly, 'a@example.org'), isNull);
    });

    test('MX answers pick the preferred host', () {
      const body =
          '{"Status":0,"Answer":[{"name":"example.org","type":15,"data":"20 mx2.example.net."},'
          '{"name":"example.org","type":15,"data":"10 mx1.example.net."}]}';
      expect(parseMxAnswer(body), 'mx1.example.net');
      expect(parseMxAnswer('{"Status":3}'), isNull);
      expect(parseMxAnswer('garbage'), isNull);
    });

    test('lookup tries Thunderbird first and needs no network for known providers', () async {
      final asked = <String>[];
      final client = MockClient((req) async {
        asked.add(req.url.toString());
        if (req.url.host == 'autoconfig.thunderbird.net') return http.Response(_ispdb, 200);
        return http.Response('nope', 404);
      });
      final known = await discoverMailSettings('a@gmail.com', client: client);
      expect(known!.preset.id, 'gmail');
      expect(asked, isEmpty);

      final found = await discoverMailSettings('alex@example.org', client: client);
      expect(found!.preset.id, 'imap');
      expect(found.source, 'autoconfig');
      expect(found.settings.imapHost, 'imap.example.org');
      expect(asked, contains('https://autoconfig.thunderbird.net/v1.1/example.org'));
    });

    test('custom domain on Google is found through MX', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'cloudflare-dns.com') {
          return http.Response('{"Answer":[{"type":15,"data":"1 aspmx.l.google.com."}]}', 200);
        }
        return http.Response('nope', 404);
      });
      final found = await discoverMailSettings('me@mydomain.nl', client: client);
      expect(found!.preset.id, 'gmail');
      expect(found.source, 'mx');
    });

    test('lookup gives up in time when nothing answers', () async {
      final client = MockClient((req) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response(_ispdb, 200);
      });
      final sw = Stopwatch()..start();
      final found = await discoverMailSettings(
        'a@slow.example',
        client: client,
        timeout: const Duration(milliseconds: 100),
      );
      expect(found, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    });
  });

  group('errors in plain words', () {
    MailProblem d(Object e, String provider, {bool outgoing = false, bool oauth = false}) =>
        describeMailError(e, provider: provider, host: 'mail.example.org', port: 993, outgoing: outgoing, oauth: oauth);

    test('Gmail login refusal asks for an app password', () {
      final p = d('MailException: imap: [AUTHENTICATIONFAILED] Invalid credentials (Failure)', 'gmail');
      expect(p.kind, MailProblemKind.appPasswordNeeded);
      expect(p.title, contains('app password'));
      final smtp = d('534-5.7.9 Application-specific password required.', 'imap', outgoing: true);
      expect(smtp.kind, MailProblemKind.appPasswordNeeded);
      expect(smtp.outgoing, isTrue);
    });

    test('wrong password, Outlook and Proton', () {
      expect(d('NO LOGIN failed.', 'imap').kind, MailProblemKind.wrongPassword);
      expect(d('535 5.7.8 Username and Password not accepted', 'imap').kind, MailProblemKind.wrongPassword);
      expect(d('NO LOGIN failed.', 'outlook').kind, MailProblemKind.microsoftSignInNeeded);
      expect(d('NO AUTHENTICATE failed.', 'outlook', oauth: true).kind, MailProblemKind.signInExpired);
      final proton = d('NO [AUTHENTICATIONFAILED] Invalid credentials', 'proton');
      expect(proton.kind, MailProblemKind.wrongPassword);
      expect(proton.message, contains('Bridge'));
    });

    test('unreachable servers and Bridge not running', () {
      const refused = SocketException(
        'Connection refused',
        osError: OSError('Connection refused', 111),
        address: null,
        port: 1143,
      );
      expect(d(refused, 'proton').kind, MailProblemKind.bridgeNotRunning);
      expect(d(refused, 'imap').kind, MailProblemKind.unreachable);
      expect(
        d(
          "SocketException: Failed host lookup: 'imap.exmaple.org' (OS Error: No address associated with hostname, errno = 7)",
          'imap',
        ).kind,
        MailProblemKind.serverNotFound,
      );
      expect(
        d('TimeoutException after 0:00:15.000000: Future not completed', 'imap').kind,
        MailProblemKind.unreachable,
      );
    });

    test('certificates and SSL/STARTTLS mix-ups', () {
      expect(
        d(
          'HandshakeException: Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: self signed)',
          'imap',
        ).kind,
        MailProblemKind.certificate,
      );
      expect(
        d('HandshakeException: Handshake error in client (OS Error: WRONG_VERSION_NUMBER)', 'imap').kind,
        MailProblemKind.securityMismatch,
      );
      expect(d('no server greeting received from x:993 within 0:00:15', 'imap').kind, MailProblemKind.securityMismatch);
    });

    test('anything else keeps a short version of the original', () {
      final p = d('MailException: Something odd\nwith a second line', 'imap');
      expect(p.kind, MailProblemKind.unknown);
      expect(p.message, 'Something odd');
      expect(d('x' * 500, 'imap').message.length, lessThan(200));
    });
  });

  group('keystore entries', () {
    test('a plain password stays as it is', () {
      expect(MailService.passwordSecret('secret'), 'secret');
      expect(MailSecret.parse('secret').password, 'secret');
      expect(MailSecret.parse('secret').username, isNull);
    });

    test('a login name is kept with the password', () {
      final s = MailSecret.parse(MailService.passwordSecret('pw', username: 'alex'));
      expect(s.password, 'pw');
      expect(s.username, 'alex');
      expect(s.isMicrosoft, isFalse);
    });

    test('a password that looks like our own prefix survives', () {
      final s = MailSecret.parse(MailService.passwordSecret('login:{oops'));
      expect(s.password, 'login:{oops');
    });
  });

  group('setup screens', () {
    Future<AppDatabase> pump(WidgetTester t, Widget home) async {
      // Tall enough that the whole form is built, phone-wide.
      t.view.physicalSize = const Size(420, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await t.runAsync(settings.load);
      await t.pumpWidget(
        Hub(
          db: db,
          settings: settings,
          child: MaterialApp(home: home),
        ),
      );
      await t.pump(const Duration(milliseconds: 50));
      return db;
    }

    Future<void> done(WidgetTester t, AppDatabase db) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(db.close);
    }

    testWidgets('a Gmail address goes straight to its steps', (t) async {
      final db = await pump(t, const AddMailAccountPage());
      expect(find.text('Proton Mail'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'nope');
      await t.tap(find.text('Continue'));
      await t.pump();
      expect(find.textContaining('full email address'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'someone@gmail.com');
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Create an app password'), findsOneWidget);
      expect(find.text('Test connection'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'App password'), findsOneWidget);

      // Nothing is tested or saved without a password.
      await t.tap(find.text('Test connection'));
      await t.pump();
      expect(find.textContaining('Paste your app password'), findsOneWidget);
      expect(find.text('Save account'), findsNothing);
      await done(t, db);
    });

    testWidgets('Proton fills in Bridge and Outlook offers Microsoft sign-in', (t) async {
      final db = await pump(t, const AddMailAccountPage());
      await t.tap(find.text('Proton Mail'));
      await t.pumpAndSettle();
      expect(find.text('Bridge password', skipOffstage: false), findsOneWidget);
      await t.tap(find.text('Advanced'));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, '127.0.0.1'), findsNWidgets(2));
      expect(find.widgetWithText(TextField, '1143'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1025'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();

      await t.tap(find.text('Outlook / Hotmail'));
      await t.pumpAndSettle();
      expect(find.text('Microsoft sign-in'), findsOneWidget);
      expect(find.text('Sign in with Microsoft'), findsOneWidget);
      await t.tap(find.text('App password').first);
      await t.pumpAndSettle();
      expect(find.text('Test connection'), findsOneWidget);
      await done(t, db);
    });

    testWidgets('accounts page lists accounts and adds new ones', (t) async {
      final db = await pump(t, const MailAccountsPage());
      await t.runAsync(
        () => db.saveMailAccount(
          MailboxAccountsCompanion.insert(
            provider: 'gmail',
            name: 'Test',
            email: 'test@example.org',
            imapHost: 'imap.gmail.com',
            imapPort: 993,
            imapSecurity: 'ssl',
            smtpHost: 'smtp.gmail.com',
            smtpPort: 465,
            smtpSecurity: 'ssl',
            color: 0,
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('test@example.org'), findsOneWidget);
      expect(find.text('Add account'), findsOneWidget);
      await done(t, db);
    });
  });
}
