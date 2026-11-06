import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/db/database.dart';
import 'mail_errors.dart';
import 'microsoft_auth.dart';

export 'mail_errors.dart';
export 'mail_providers.dart';

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

/// A keystore entry, read back: a password (with an optional login name) or a Microsoft sign-in.
class MailSecret {
  const MailSecret({this.password, this.username, this.clientId, this.token});

  factory MailSecret.parse(String s) {
    try {
      if (s.startsWith('oauth:')) {
        final j = jsonDecode(s.substring(6)) as Map<String, dynamic>;
        return MailSecret(
          clientId: j['clientId'] as String,
          token: OauthToken.fromJson((j['token'] as Map).cast<String, dynamic>()),
        );
      }
      if (s.startsWith('login:')) {
        final j = jsonDecode(s.substring(6)) as Map<String, dynamic>;
        return MailSecret(password: j['password'] as String, username: j['user'] as String?);
      }
    } catch (_) {
      // Not one of ours after all; it is a plain password that happens to start that way.
    }
    return MailSecret(password: s);
  }

  final String? password;

  /// The login name when it isn't the email address.
  final String? username;
  final String? clientId;
  final OauthToken? token;

  bool get isMicrosoft => token != null;
}

class MailService {
  MailService._();
  static final instance = MailService._();

  final _storage = const FlutterSecureStorage();
  final _clients = <int, MailClient>{};

  Future<void> savePassword(int accountId, String password) =>
      _storage.write(key: 'mail-pass-$accountId', value: password);

  Future<String?> _password(int accountId) => _storage.read(key: 'mail-pass-$accountId');

  /// The saved keystore entry of [accountId] as stored, or null.
  Future<String?> savedSecret(int accountId) async {
    try {
      return await _password(accountId);
    } catch (_) {
      return null;
    }
  }

  Future<void> forget(int accountId) async {
    await _clients.remove(accountId)?.disconnect().catchError((_) {});
    await _storage.delete(key: 'mail-pass-$accountId');
  }

  /// The Microsoft app registration's client ID, kept so a second Outlook account doesn't ask for it again.
  Future<String?> savedMicrosoftClientId() async {
    try {
      return await _storage.read(key: 'mail-ms-client-id');
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMicrosoftClientId(String id) => _storage.write(key: 'mail-ms-client-id', value: id);

  static SocketType _socket(String s) => s == 'starttls' ? SocketType.starttls : SocketType.ssl;

  /// What is kept in the keystore: a password, or for Outlook the client id and token.
  static String oauthSecret(String clientId, OauthToken token) =>
      'oauth:${jsonEncode({'clientId': clientId, 'token': token.toJson()})}';

  /// A password, with the login name only when it isn't the email address.
  static String passwordSecret(String password, {String? username}) {
    final u = username?.trim() ?? '';
    return u.isEmpty && !password.startsWith('oauth:') && !password.startsWith('login:')
        ? password
        : 'login:${jsonEncode({'user': u.isEmpty ? null : u, 'password': password})}';
  }

  static (String, OauthToken)? _parseOauth(String secret) {
    final s = MailSecret.parse(secret);
    return s.token == null ? null : (s.clientId!, s.token!);
  }

  static MailAccount buildAccount(MailboxAccount a, String secret) {
    final s = MailSecret.parse(secret);
    return MailAccount.fromManualSettingsWithAuth(
      name: a.name,
      email: a.email,
      userName: a.name,
      auth: s.token != null
          ? OauthAuthentication(a.email, s.token!)
          : PlainAuthentication(s.username ?? a.email, s.password ?? ''),
      incomingHost: a.imapHost,
      incomingPort: a.imapPort,
      incomingSocketType: _socket(a.imapSecurity),
      outgoingHost: a.smtpHost,
      outgoingPort: a.smtpPort,
      outgoingSocketType: _socket(a.smtpSecurity),
      outgoingClientDomain: 'hub.local',
    );
  }

  MailClient _newClient(MailboxAccount a, String secret) {
    final oauth = _parseOauth(secret);
    return MailClient(
      buildAccount(a, secret),
      // Only a server on this computer or the home network (Proton Bridge) may use its own certificate.
      onBadCertificate: (_) => a.allowSelfSigned && isPrivateHost(a.imapHost),
      refresh: oauth == null
          ? null
          : (client, expired) async {
              final fresh = await MicrosoftAuth.refresh(oauth.$1, expired);
              if (a.id > 0) await savePassword(a.id, oauthSecret(oauth.$1, fresh));
              return fresh;
            },
    );
  }

  static bool isPrivateHost(String h) =>
      h == 'localhost' ||
      h.startsWith('127.') ||
      h.startsWith('10.') ||
      h.startsWith('192.168.') ||
      h.startsWith('100.') || // Tailscale
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(h);

  /// Signs in to both servers with [secret] without saving anything: reading mail (IMAP) first, then
  /// sending (SMTP). [onStep] hears "incoming" and "outgoing" as each one starts. Throws a [MailProblem].
  Future<void> test(MailboxAccount a, String secret, {void Function(String step)? onStep}) async {
    final oauth = _parseOauth(secret) != null;
    onStep?.call('incoming');
    final client = _newClient(a, secret);
    try {
      await client.connect(timeout: const Duration(seconds: 15)).timeout(const Duration(seconds: 40));
    } catch (e) {
      throw describeMailError(e, provider: a.provider, host: a.imapHost, port: a.imapPort, oauth: oauth);
    } finally {
      unawaited(client.disconnect().catchError((_) {}));
    }
    onStep?.call('outgoing');
    final account = buildAccount(a, secret);
    final smtp = SmtpClient('hub.local', onBadCertificate: (_) => a.allowSelfSigned && isPrivateHost(a.smtpHost));
    try {
      await () async {
        final config = account.outgoing.serverConfig;
        await smtp.connectToServer(
          config.hostname,
          config.port,
          isSecure: config.socketType == SocketType.ssl,
          timeout: const Duration(seconds: 15),
        );
        await smtp.ehlo();
        if (config.socketType == SocketType.starttls) {
          // Never send the password in clear text.
          if (!smtp.serverInfo.supportsStartTls) throw 'STARTTLS is not supported by ${config.hostname}';
          await smtp.startTls();
        }
        await account.outgoing.authentication.authenticate(config, smtp: smtp);
      }().timeout(const Duration(seconds: 40));
    } catch (e) {
      throw describeMailError(
        e,
        provider: a.provider,
        host: a.smtpHost,
        port: a.smtpPort,
        outgoing: true,
        oauth: oauth,
      );
    } finally {
      unawaited(smtp.disconnect().catchError((_) {}));
    }
  }

  static String explain(String raw, MailboxAccount a) =>
      describeMailError(raw, provider: a.provider, host: a.imapHost, port: a.imapPort).text;

  Future<MailClient> _client(MailboxAccount a) async {
    final existing = _clients[a.id];
    if (existing != null && existing.isConnected) return existing;
    final password = await _password(a.id);
    if (password == null) throw 'Password missing. Open the account under Accounts and enter it again.';
    final client = _newClient(a, password);
    try {
      await client.connect();
    } catch (e) {
      throw describeMailError(
        e,
        provider: a.provider,
        host: a.imapHost,
        port: a.imapPort,
        oauth: _parseOauth(password) != null,
      ).text;
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
      throw describeMailError(e, provider: a.provider, host: a.smtpHost, port: a.smtpPort, outgoing: true).text;
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
