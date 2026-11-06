import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Where and how to reach one mailbox: the incoming (IMAP) and outgoing (SMTP) servers.
class MailServerSettings {
  const MailServerSettings({
    required this.imapHost,
    required this.imapPort,
    required this.imapSecurity,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSecurity,
    this.username,
  });

  final String imapHost;
  final int imapPort;

  /// ssl or starttls
  final String imapSecurity;
  final String smtpHost;
  final int smtpPort;
  final String smtpSecurity;

  /// The login name when it is not the email address itself.
  final String? username;

  @override
  String toString() => 'IMAP $imapHost:$imapPort $imapSecurity, SMTP $smtpHost:$smtpPort $smtpSecurity';
}

/// A link the setup steps can open, such as the page where Google makes app passwords.
class MailHelpLink {
  const MailHelpLink(this.label, this.url);
  final String label;
  final String url;
}

/// A mail provider Hub knows: its servers, what it calls the password, and the steps to get one.
class MailPreset {
  const MailPreset({
    required this.id,
    required this.label,
    required this.tagline,
    required this.settings,
    required this.passwordLabel,
    required this.steps,
    required this.color,
    this.domains = const [],
    this.links = const [],
    this.allowSelfSigned = false,
    this.microsoftSignIn = false,
    this.stripSpaces = false,
  });

  final String id;
  final String label;

  /// One line under the name in the provider list.
  final String tagline;
  final MailServerSettings settings;
  final String passwordLabel;

  /// Short numbered steps shown above the form.
  final List<String> steps;
  final List<MailHelpLink> links;
  final int color;

  /// Address domains that belong to this provider, used to pick it from the email address.
  final List<String> domains;

  /// Proton Bridge uses its own certificate on the local machine.
  final bool allowSelfSigned;

  /// Outlook can also use Microsoft sign-in instead of a password.
  final bool microsoftSignIn;

  /// App passwords are shown in groups ("abcd efgh ijkl mnop"); the spaces are not part of them.
  final bool stripSpaces;

  // Kept so older code can read the servers straight off the preset.
  String get imapHost => settings.imapHost;
  int get imapPort => settings.imapPort;
  String get imapSecurity => settings.imapSecurity;
  String get smtpHost => settings.smtpHost;
  int get smtpPort => settings.smtpPort;
  String get smtpSecurity => settings.smtpSecurity;
  bool get isOther => id == 'imap';
}

const mailPresets = <MailPreset>[
  MailPreset(
    id: 'gmail',
    label: 'Gmail',
    tagline: 'With an app password',
    domains: ['gmail.com', 'googlemail.com'],
    settings: MailServerSettings(
      imapHost: 'imap.gmail.com',
      imapPort: 993,
      imapSecurity: 'ssl',
      smtpHost: 'smtp.gmail.com',
      smtpPort: 465,
      smtpSecurity: 'ssl',
    ),
    passwordLabel: 'App password',
    steps: [
      'Google needs an app password here, not your normal password.',
      'Turn on 2-Step Verification for your Google account if it is off.',
      'Create an app password, name it "Hub", and copy the 16 letters Google shows.',
      'Paste them below. Spaces don\'t matter.',
    ],
    links: [
      MailHelpLink('Turn on 2-Step Verification', 'https://myaccount.google.com/signinoptions/two-step-verification'),
      MailHelpLink('Create an app password', 'https://myaccount.google.com/apppasswords'),
    ],
    color: 0xFFC0563F,
    stripSpaces: true,
  ),
  MailPreset(
    id: 'outlook',
    label: 'Outlook / Hotmail',
    tagline: 'Outlook.com, Hotmail, Live and Microsoft 365',
    domains: ['outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'passport.com'],
    settings: MailServerSettings(
      imapHost: 'outlook.office365.com',
      imapPort: 993,
      imapSecurity: 'ssl',
      smtpHost: 'smtp-mail.outlook.com',
      smtpPort: 587,
      smtpSecurity: 'starttls',
    ),
    passwordLabel: 'App password',
    steps: [
      'Turn on two-step verification for your Microsoft account.',
      'Under Advanced security options, create an app password and copy it.',
      'Paste it below. Most personal accounts no longer accept passwords; if the test fails, use Microsoft sign-in.',
    ],
    links: [
      MailHelpLink('Open Microsoft security', 'https://account.microsoft.com/security'),
      MailHelpLink('Create an app password', 'https://account.live.com/proofs/AppPassword'),
    ],
    color: 0xFF2F6FB5,
    microsoftSignIn: true,
  ),
  MailPreset(
    id: 'proton',
    label: 'Proton Mail',
    tagline: 'Through Proton Mail Bridge on your computer',
    domains: ['proton.me', 'protonmail.com', 'protonmail.ch', 'pm.me'],
    settings: MailServerSettings(
      imapHost: '127.0.0.1',
      imapPort: 1143,
      imapSecurity: 'starttls',
      smtpHost: '127.0.0.1',
      smtpPort: 1025,
      smtpSecurity: 'starttls',
    ),
    passwordLabel: 'Bridge password',
    steps: [
      'Open Proton Mail Bridge on your computer and sign in. Leave it running.',
      'In Bridge, click your account, then "Configure email client" (or "Mailbox details").',
      'Copy the password Bridge shows there. It is not your Proton password.',
      'Paste it below. Hub already knows Bridge\'s address and ports.',
    ],
    links: [MailHelpLink('Get Proton Mail Bridge', 'https://proton.me/mail/bridge')],
    color: 0xFF6D4AFF,
    allowSelfSigned: true,
  ),
  MailPreset(
    id: 'icloud',
    label: 'iCloud Mail',
    tagline: 'With an app-specific password',
    domains: ['icloud.com', 'me.com', 'mac.com'],
    settings: MailServerSettings(
      imapHost: 'imap.mail.me.com',
      imapPort: 993,
      imapSecurity: 'ssl',
      smtpHost: 'smtp.mail.me.com',
      smtpPort: 587,
      smtpSecurity: 'starttls',
    ),
    passwordLabel: 'App-specific password',
    steps: [
      'Sign in to your Apple Account and open Sign-In and Security.',
      'Choose App-Specific Passwords, add one named "Hub", and copy it.',
      'Paste it below, dashes included.',
    ],
    links: [MailHelpLink('Open Apple Account', 'https://account.apple.com/account/manage')],
    color: 0xFF5B6B80,
  ),
  MailPreset(
    id: 'yahoo',
    label: 'Yahoo Mail',
    tagline: 'With an app password',
    domains: ['yahoo.com', 'ymail.com', 'rocketmail.com', 'yahoo.co.uk', 'yahoo.fr', 'yahoo.de', 'yahoo.gr'],
    settings: MailServerSettings(
      imapHost: 'imap.mail.yahoo.com',
      imapPort: 993,
      imapSecurity: 'ssl',
      smtpHost: 'smtp.mail.yahoo.com',
      smtpPort: 465,
      smtpSecurity: 'ssl',
    ),
    passwordLabel: 'App password',
    steps: [
      'Open Yahoo Account Security.',
      'Choose "Generate app password", name it "Hub", and copy it.',
      'Paste it below. Spaces don\'t matter.',
    ],
    links: [MailHelpLink('Open Yahoo Account Security', 'https://login.yahoo.com/account/security')],
    color: 0xFFA8458F,
    stripSpaces: true,
  ),
  MailPreset(
    id: 'imap',
    label: 'Other',
    tagline: 'Any provider with IMAP and SMTP',
    settings: MailServerSettings(
      imapHost: '',
      imapPort: 993,
      imapSecurity: 'ssl',
      smtpHost: '',
      smtpPort: 465,
      smtpSecurity: 'ssl',
    ),
    passwordLabel: 'Password',
    steps: [
      'Use the password you sign in to your mail with.',
      'Some providers want an app password instead; their help pages say so.',
    ],
    color: 0xFF2D8C9E,
  ),
];

MailPreset presetFor(String id) => mailPresets.firstWhere((p) => p.id == id, orElse: () => mailPresets.last);

/// The part after the @, lowercased, or null when it isn't an email address.
String? emailDomain(String email) {
  final e = email.trim().toLowerCase();
  final at = e.lastIndexOf('@');
  if (at <= 0 || at == e.length - 1) return null;
  final d = e.substring(at + 1);
  if (!d.contains('.') || d.startsWith('.') || d.endsWith('.') || d.contains(' ')) return null;
  return d;
}

bool looksLikeEmail(String email) => emailDomain(email) != null;

/// The provider an address belongs to, from its domain alone (no network).
MailPreset? detectProvider(String email) {
  final d = emailDomain(email);
  if (d == null) return null;
  for (final p in mailPresets) {
    if (p.domains.contains(d)) return p;
  }
  // Country variants such as hotmail.co.uk, live.nl, outlook.de or yahoo.com.au.
  final first = d.split('.').first;
  const families = {'hotmail': 'outlook', 'outlook': 'outlook', 'live': 'outlook', 'yahoo': 'yahoo'};
  final family = families[first];
  return family == null ? null : presetFor(family);
}

/// The provider behind a custom domain's mail server (MX record), e.g. a Google Workspace domain.
MailPreset? providerForMx(String mxHost) {
  final h = mxHost.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  bool under(String d) => h == d || h.endsWith('.$d');
  if (under('google.com') || under('googlemail.com')) return presetFor('gmail');
  if (under('outlook.com') || under('hotmail.com')) return presetFor('outlook');
  if (under('protonmail.ch') || under('proton.me')) return presetFor('proton');
  if (under('icloud.com') || under('me.com')) return presetFor('icloud');
  if (under('yahoodns.net')) return presetFor('yahoo');
  return null;
}

/// Reads a Thunderbird autoconfig file (config-v1.1.xml). Returns null when it has no usable IMAP and SMTP
/// servers with encryption.
MailServerSettings? parseAutoconfig(String xml, String email) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } catch (_) {
    return null;
  }
  final e = email.trim();
  final at = e.lastIndexOf('@');
  String fill(String s) => s
      .replaceAll('%EMAILADDRESS%', e)
      .replaceAll('%EMAILLOCALPART%', at > 0 ? e.substring(0, at) : e)
      .replaceAll('%EMAILDOMAIN%', at > 0 ? e.substring(at + 1) : '');

  ({String host, int port, String security, String? user})? pick(String tag, String type) {
    final found = <({String host, int port, String security, String? user})>[];
    for (final s in doc.findAllElements(tag)) {
      if (s.getAttribute('type')?.toLowerCase() != type) continue;
      final host = fill(s.getElement('hostname')?.innerText.trim() ?? '');
      final port = int.tryParse(s.getElement('port')?.innerText.trim() ?? '');
      final security = switch (s.getElement('socketType')?.innerText.trim().toUpperCase()) {
        'SSL' => 'ssl',
        'STARTTLS' => 'starttls',
        _ => null, // Plain text is never offered.
      };
      // Only servers that take a normal password; OAuth-only entries need a sign-in Hub doesn't have.
      final auths = s.findElements('authentication').map((a) => a.innerText.trim().toLowerCase()).toList();
      final passwordOk =
          auths.isEmpty || auths.any((a) => a == 'password-cleartext' || a == 'plain' || a == 'password-encrypted');
      if (host.isEmpty || port == null || security == null || !passwordOk) continue;
      final user = s.getElement('username')?.innerText.trim();
      found.add((host: host, port: port, security: security, user: user == null || user.isEmpty ? null : fill(user)));
    }
    if (found.isEmpty) return null;
    // Prefer SSL from the start over STARTTLS, keeping the file's order otherwise.
    return found.firstWhere((f) => f.security == 'ssl', orElse: () => found.first);
  }

  final imap = pick('incomingServer', 'imap');
  final smtp = pick('outgoingServer', 'smtp');
  if (imap == null || smtp == null) return null;
  final user = imap.user;
  return MailServerSettings(
    imapHost: imap.host,
    imapPort: imap.port,
    imapSecurity: imap.security,
    smtpHost: smtp.host,
    smtpPort: smtp.port,
    smtpSecurity: smtp.security,
    username: user == null || user.toLowerCase() == e.toLowerCase() ? null : user,
  );
}

/// What a lookup found for an address.
class MailDiscovery {
  const MailDiscovery(this.preset, this.settings, this.source);

  /// A known provider, or the Other preset with [settings] filled in.
  final MailPreset preset;
  final MailServerSettings settings;

  /// known, autoconfig or mx, for the message shown to the user.
  final String source;
}

/// Finds the servers for an address: the known providers first, then Thunderbird's database and the
/// domain's own autoconfig file, then the domain's mail server. Returns null when nothing is found in time.
Future<MailDiscovery?> discoverMailSettings(
  String email, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final domain = emailDomain(email);
  if (domain == null) return null;
  final known = detectProvider(email);
  if (known != null) return MailDiscovery(known, known.settings, 'known');
  final c = client ?? http.Client();
  try {
    Future<MailServerSettings?> fetch(String url) async {
      try {
        final res = await c.get(Uri.parse(url)).timeout(timeout);
        if (res.statusCode != 200) return null;
        return parseAutoconfig(utf8.decode(res.bodyBytes, allowMalformed: true), email);
      } catch (_) {
        return null;
      }
    }

    final q = Uri.encodeQueryComponent(email.trim());
    // All three at once; the first in this order that has an answer wins.
    final answers = await Future.wait([
      fetch('https://autoconfig.thunderbird.net/v1.1/$domain'),
      fetch('https://autoconfig.$domain/mail/config-v1.1.xml?emailaddress=$q'),
      fetch('https://$domain/.well-known/autoconfig/mail/config-v1.1.xml'),
    ]);
    final direct = answers.whereType<MailServerSettings>().firstOrNull;
    if (direct != null) return MailDiscovery(presetFor('imap'), direct, 'autoconfig');

    // A custom domain hosted by Google, Microsoft, Proton and so on: its MX record says who.
    final mx = await _mxHost(c, domain, timeout);
    if (mx == null) return null;
    final byMx = providerForMx(mx);
    if (byMx != null) return MailDiscovery(byMx, byMx.settings, 'mx');
    final parts = mx.replaceAll(RegExp(r'\.$'), '').split('.');
    if (parts.length >= 2) {
      final base = parts.sublist(parts.length - 2).join('.');
      if (base != domain) {
        final s = await fetch('https://autoconfig.thunderbird.net/v1.1/$base');
        if (s != null) return MailDiscovery(presetFor('imap'), s, 'mx');
      }
    }
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// The preferred mail server of a domain, through DNS over HTTPS.
Future<String?> _mxHost(http.Client c, String domain, Duration timeout) async {
  try {
    final res = await c
        .get(
          Uri.https('cloudflare-dns.com', '/dns-query', {'name': domain, 'type': 'MX'}),
          headers: {'accept': 'application/dns-json'},
        )
        .timeout(timeout);
    if (res.statusCode != 200) return null;
    return parseMxAnswer(res.body);
  } catch (_) {
    return null;
  }
}

/// The lowest-preference host in a DNS-over-HTTPS JSON answer for an MX query.
String? parseMxAnswer(String body) {
  try {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final answers = (j['Answer'] as List?) ?? const [];
    (int, String)? best;
    for (final a in answers) {
      if (a is! Map || a['type'] != 15) continue;
      final parts = '${a['data']}'.trim().split(RegExp(r'\s+'));
      if (parts.length != 2) continue;
      final pref = int.tryParse(parts[0]);
      if (pref == null) continue;
      if (best == null || pref < best.$1) best = (pref, parts[1].replaceAll(RegExp(r'\.$'), ''));
    }
    return best?.$2;
  } catch (_) {
    return null;
  }
}
