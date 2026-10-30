import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/db/database.dart';
import 'microsoft_auth.dart';

/// Presets for the providers Hub knows. Ports and hosts can be edited.
class MailPreset {
  const MailPreset({
    required this.id,
    required this.label,
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
    required this.passwordLabel,
    required this.help,
    required this.color,
    this.allowSelfSigned = false,
    this.available = true,
  });

  final String id;
  final String label;
  final String imapHost;
  final int imapPort;
  final String imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final String smtpSecurity;
  final String passwordLabel;
  final String help;
  final int color;
  final bool allowSelfSigned;
  final bool available;
}

const mailPresets = <MailPreset>[
  MailPreset(
    id: 'gmail',
    label: 'Gmail',
    imapHost: 'imap.gmail.com',
    imapPort: 993,
    imapSecurity: 'ssl',
    smtpHost: 'smtp.gmail.com',
    smtpPort: 465,
    smtpSecurity: 'ssl',
    passwordLabel: 'App password',
    help:
        'Google needs an app password, not your normal one. Turn on 2-Step Verification, '
        'then create one at myaccount.google.com/apppasswords and paste the 16 letters here.',
    color: 0xFFC0563F,
  ),
  MailPreset(
    id: 'proton',
    label: 'Proton Mail',
    imapHost: '127.0.0.1',
    imapPort: 1143,
    imapSecurity: 'starttls',
    smtpHost: '127.0.0.1',
    smtpPort: 1025,
    smtpSecurity: 'starttls',
    passwordLabel: 'Bridge password',
    help:
        'Proton works through Proton Bridge. Open Bridge on your PC, click your account, '
        'and copy the IMAP username and password it shows (not your Proton password). '
        'On the phone this works once the laptop server runs Bridge; then use its address as the host.',
    color: 0xFF6D4AFF,
    allowSelfSigned: true,
  ),
  MailPreset(
    id: 'outlook',
    label: 'Outlook',
    imapHost: 'outlook.office365.com',
    imapPort: 993,
    imapSecurity: 'ssl',
    smtpHost: 'smtp-mail.outlook.com',
    smtpPort: 587,
    smtpSecurity: 'starttls',
    passwordLabel: 'Microsoft sign-in',
    help:
        'Outlook only allows Microsoft sign-in. That needs a one-time app registration of your own '
        '(free, about 5 minutes): portal.azure.com → App registrations → New registration, name "Hub", '
        'choose "Accounts in any organizational directory and personal Microsoft accounts", Register. '
        'Then Authentication → "Allow public client flows" → Yes, Save. Paste the Application (client) ID below.',
    color: 0xFF2F6FB5,
  ),
  MailPreset(
    id: 'imap',
    label: 'Other (IMAP)',
    imapHost: '',
    imapPort: 993,
    imapSecurity: 'ssl',
    smtpHost: '',
    smtpPort: 465,
    smtpSecurity: 'ssl',
    passwordLabel: 'Password',
    help: 'Any provider with IMAP and SMTP. Your provider lists the server names in its help pages.',
    color: 0xFF2D8C9E,
  ),
];

MailPreset presetFor(String id) => mailPresets.firstWhere((p) => p.id == id, orElse: () => mailPresets.last);

/// One message in the unified inbox.
class MailItem {
  MailItem(this.account, this.message);
  final MailboxAccount account;
  final MimeMessage message;

  DateTime get date => message.decodeDate()?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  String get subject =>
      (message.decodeSubject() ?? '').trim().isEmpty ? '(no subject)' : message.decodeSubject()!.trim();
  String get sender {
    final f = message.from?.firstOrNull;
    if (f == null) return 'Unknown';
    return (f.personalName?.trim().isNotEmpty ?? false) ? f.personalName!.trim() : f.email;
  }

  bool get unread => !message.isSeen;
}

class MailError {
  MailError(this.account, this.message);
  final MailboxAccount account;
  final String message;
}

class MailService {
  MailService._();
  static final instance = MailService._();

  final _storage = const FlutterSecureStorage();
  final _clients = <int, MailClient>{};

  Future<void> savePassword(int accountId, String password) =>
      _storage.write(key: 'mail-pass-$accountId', value: password);

  Future<String?> _password(int accountId) => _storage.read(key: 'mail-pass-$accountId');

  Future<void> forget(int accountId) async {
    await _clients.remove(accountId)?.disconnect().catchError((_) {});
    await _storage.delete(key: 'mail-pass-$accountId');
  }

  static SocketType _socket(String s) => s == 'starttls' ? SocketType.starttls : SocketType.ssl;

  /// What is kept in the keystore: a password, or for Outlook the client id and token.
  static String oauthSecret(String clientId, OauthToken token) =>
      'oauth:${jsonEncode({'clientId': clientId, 'token': token.toJson()})}';

  static (String, OauthToken)? _parseOauth(String secret) {
    if (!secret.startsWith('oauth:')) return null;
    final j = jsonDecode(secret.substring(6)) as Map<String, dynamic>;
    return (j['clientId'] as String, OauthToken.fromJson((j['token'] as Map).cast<String, dynamic>()));
  }

  static MailAccount buildAccount(MailboxAccount a, String secret) => MailAccount.fromManualSettingsWithAuth(
    name: a.name,
    email: a.email,
    userName: a.name,
    auth: switch (_parseOauth(secret)) {
      (_, final token) => OauthAuthentication(a.email, token),
      null => PlainAuthentication(a.email, secret),
    },
    incomingHost: a.imapHost,
    incomingPort: a.imapPort,
    incomingSocketType: _socket(a.imapSecurity),
    outgoingHost: a.smtpHost,
    outgoingPort: a.smtpPort,
    outgoingSocketType: _socket(a.smtpSecurity),
    outgoingClientDomain: 'hub.local',
  );

  MailClient _newClient(MailboxAccount a, String secret) {
    final oauth = _parseOauth(secret);
    return MailClient(
      buildAccount(a, secret),
      // Only Proton Bridge on a local or private address may use its own certificate.
      onBadCertificate: (_) => a.allowSelfSigned && _isPrivateHost(a.imapHost),
      refresh: oauth == null
          ? null
          : (client, expired) async {
              final fresh = await MicrosoftAuth.refresh(oauth.$1, expired);
              if (a.id > 0) await savePassword(a.id, oauthSecret(oauth.$1, fresh));
              return fresh;
            },
    );
  }

  static bool _isPrivateHost(String h) =>
      h == 'localhost' ||
      h.startsWith('127.') ||
      h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      h.startsWith('100.') || // Tailscale
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h);

  /// Connects with the given password without saving anything. Throws a
  /// readable message on failure.
  Future<void> test(MailboxAccount a, String password) async {
    final client = _newClient(a, password);
    try {
      await client.connect(timeout: const Duration(seconds: 15));
      await client.disconnect();
    } on MailException catch (e) {
      throw explain(e.message ?? '$e', a);
    } catch (e) {
      throw explain('$e', a);
    }
  }

  static String explain(String raw, MailboxAccount a) {
    final r = raw.toLowerCase();
    if (r.contains('authenticat') || r.contains('login') || r.contains('credentials') || r.contains('password')) {
      return a.provider == 'gmail'
          ? 'Gmail refused the login. Use an app password, not your normal password.'
          : 'The server refused the email or password.';
    }
    if (r.contains('refused') || r.contains('connection') || r.contains('socket') || r.contains('timeout')) {
      return a.provider == 'proton'
          ? 'Could not reach Proton Bridge at ${a.imapHost}:${a.imapPort}. Is Bridge running?'
          : 'Could not reach ${a.imapHost}. Check the server name and your connection.';
    }
    return raw;
  }

  Future<MailClient> _client(MailboxAccount a) async {
    final existing = _clients[a.id];
    if (existing != null && existing.isConnected) return existing;
    final password = await _password(a.id);
    if (password == null) throw 'Password missing. Open the account and enter it again.';
    final client = _newClient(a, password);
    try {
      await client.connect();
    } on MailException catch (e) {
      throw explain(e.message ?? '$e', a);
    } catch (e) {
      throw explain('$e', a);
    }
    _clients[a.id] = client;
    return client;
  }

  /// Latest inbox messages of every account, newest first.
  Future<(List<MailItem>, List<MailError>)> inbox(List<MailboxAccount> accounts, {int perAccount = 30}) async {
    final items = <MailItem>[];
    final errors = <MailError>[];
    await Future.wait(
      accounts.map((a) async {
        try {
          // A server that stops answering shouldn't keep the inbox spinning forever.
          final msgs = await () async {
            final client = await _client(a);
            await client.selectInbox();
            return client.fetchMessages(count: perAccount, fetchPreference: FetchPreference.envelope);
          }().timeout(const Duration(seconds: 40));
          items.addAll(msgs.map((m) => MailItem(a, m)));
        } on TimeoutException {
          _clients.remove(a.id);
          errors.add(MailError(a, 'The server took too long to answer. Pull down to try again.'));
        } catch (e) {
          _clients.remove(a.id);
          errors.add(MailError(a, e is String ? e : explain('$e', a)));
        }
      }),
    );
    items.sort((x, y) => y.date.compareTo(x.date));
    return (items, errors);
  }

  Future<MimeMessage> open(MailItem item) async {
    final client = await _client(item.account);
    return client.fetchMessageContents(item.message, markAsSeen: true);
  }

  Future<void> send(MailboxAccount a, MimeMessage message) async {
    final client = await _client(a);
    try {
      await client.sendMessage(message);
    } on MailException catch (e) {
      throw explain(e.message ?? '$e', a);
    }
  }

  static MailAddress addressOf(MailboxAccount a) => MailAddress(a.name, a.email);
}

/// Readable text for a message: the plain part, or the HTML part flattened.
String messageText(MimeMessage m) {
  final plain = m.decodeTextPlainPart();
  if (plain != null && plain.trim().isNotEmpty) return plain.replaceAll('\r\n', '\n').trim();
  final html = m.decodeTextHtmlPart();
  if (html == null) return '';
  return htmlToText(html);
}

String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<(style|script|head)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</(p|div|tr|h[1-6]|li|table)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&euro;': '€',
    '&zwnj;': '',
  };
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
  return s
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
