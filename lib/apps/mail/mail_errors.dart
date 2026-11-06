/// Turns what mail servers and sockets say into something a person can act on.
library;

enum MailProblemKind {
  appPasswordNeeded,
  microsoftSignInNeeded,
  wrongPassword,
  bridgeNotRunning,
  serverNotFound,
  unreachable,
  certificate,
  securityMismatch,
  signInExpired,
  unknown,
}

class MailProblem implements Exception {
  const MailProblem(this.kind, this.title, this.message, {this.outgoing = false});

  final MailProblemKind kind;
  final String title;
  final String message;

  /// True when sending (SMTP) failed after reading (IMAP) worked.
  final bool outgoing;

  /// The whole thing as one line, for places with room for a single message.
  String get text => '$title. $message';

  @override
  String toString() => text;
}

bool _any(String s, List<String> needles) => needles.any(s.contains);

/// Explains [error] for an account with [provider] (gmail, outlook, proton, icloud, yahoo or imap) on
/// [host]:[port]. [outgoing] says the error came from the sending server.
MailProblem describeMailError(
  Object error, {
  required String provider,
  required String host,
  required int port,
  bool outgoing = false,
  bool oauth = false,
}) {
  if (error is MailProblem) return error;
  final r = '$error'.toLowerCase();
  final where = outgoing ? 'the sending server' : 'the mail server';
  MailProblem p(MailProblemKind k, String title, String message) => MailProblem(k, title, message, outgoing: outgoing);

  if (_any(r, ['unable to refresh token', 'invalid_grant', 'aadsts70008', 'aadsts50173'])) {
    return p(
      MailProblemKind.signInExpired,
      'Microsoft sign-in expired',
      'Open the account and sign in with Microsoft again.',
    );
  }

  if (_any(r, [
    'certificate_verify_failed',
    'certificate verify failed',
    'bad certificate',
    'certificate has expired',
  ])) {
    return p(
      MailProblemKind.certificate,
      'Security certificate not trusted',
      provider == 'proton'
          ? 'Hub accepts Bridge\'s own certificate only when Bridge runs on this computer or your home network. '
                'Check the server address under Advanced.'
          : '$host showed a certificate Hub can\'t verify, so it didn\'t send your password. '
                'Check the server name under Advanced.',
    );
  }

  if (_any(r, [
    'wrong_version_number',
    'wrong version number',
    'starttls is not supported',
    'handshakeexception',
    'handshake error',
    'connection terminated during handshake',
    'unknown protocol',
    'no server greeting',
  ])) {
    return p(
      MailProblemKind.securityMismatch,
      'Security setting doesn\'t match',
      'The server on port $port expects a different security setting. Under Advanced, switch between SSL and '
          'STARTTLS. Ports 993 and 465 usually use SSL, ports 143, 587 and Proton Bridge use STARTTLS.',
    );
  }

  final appPasswordText = _any(r, [
    'application-specific password',
    'application specific password',
    'app password',
    '5.7.9',
    'webloginrequired',
    'web login required',
  ]);
  final authFailed =
      appPasswordText ||
      _any(r, [
        'authenticat',
        'credential',
        'login fail',
        'logon fail',
        'invalid login',
        'login denied',
        'password',
        '535 ',
        '535-',
        'access denied',
        'not accepted',
      ]);
  if (authFailed) {
    if (oauth) {
      return p(
        MailProblemKind.signInExpired,
        'Microsoft didn\'t accept the sign-in',
        'Sign in with Microsoft again. If it keeps failing, check that IMAP is turned on for this mailbox.',
      );
    }
    switch (provider) {
      case 'gmail':
        return p(
          MailProblemKind.appPasswordNeeded,
          'Google wants an app password',
          'Your normal Google password doesn\'t work here. Turn on 2-Step Verification, create an app password '
              'and paste its 16 letters. If you already did, check the email address.',
        );
      case 'yahoo':
        return p(
          MailProblemKind.appPasswordNeeded,
          'Yahoo wants an app password',
          'Create an app password in Yahoo Account Security and paste it here, instead of your normal password.',
        );
      case 'icloud':
        return p(
          MailProblemKind.appPasswordNeeded,
          'Apple wants an app-specific password',
          'Create one in your Apple Account under Sign-In and Security, and paste it here with its dashes.',
        );
      case 'outlook':
        return p(
          MailProblemKind.microsoftSignInNeeded,
          'Microsoft didn\'t accept the password',
          'Most Outlook and Hotmail accounts no longer allow passwords in other apps. Use Microsoft sign-in instead.',
        );
      case 'proton':
        return p(
          MailProblemKind.wrongPassword,
          'Bridge didn\'t accept the password',
          'Use the password Proton Mail Bridge shows for this account, not your Proton password. '
              'The email must match the one in Bridge too.',
        );
    }
    if (appPasswordText) {
      return p(
        MailProblemKind.appPasswordNeeded,
        'An app password is needed',
        'Your provider wants an app password for other apps. Create one in its security settings and paste it here.',
      );
    }
    return p(
      MailProblemKind.wrongPassword,
      'Wrong email or password',
      '$host said no to this email and password. Check both. Some providers want an app password instead.',
    );
  }

  final notFound = _any(r, [
    'failed host lookup',
    'no address associated',
    'nodename nor servname',
    'name or service not known',
    'no such host',
    'host not found',
    'errno = 11001)',
    'errno = 7)',
    'errno = 8)',
  ]);
  final unreachable =
      notFound ||
      _any(r, [
        'connection refused',
        'errno = 111',
        'errno = 61',
        'errno = 10061',
        'network is unreachable',
        'no route to host',
        'connection reset',
        'timed out',
        'timeout',
        'errno = 10060',
        'connection closed',
        'socketexception',
        'before server greeting',
      ]);
  if (provider == 'proton' && unreachable) {
    return p(
      MailProblemKind.bridgeNotRunning,
      'Proton Mail Bridge isn\'t answering',
      'Open Bridge on this computer and check that you\'re signed in. If Bridge shows other port numbers than '
          '$port, enter them under Advanced.',
    );
  }
  if (notFound) {
    return p(
      MailProblemKind.serverNotFound,
      'Server not found',
      'Hub couldn\'t find "$host". Check the spelling under Advanced, and that you\'re online.',
    );
  }
  if (unreachable) {
    return p(
      MailProblemKind.unreachable,
      'Can\'t reach $where',
      '$host on port $port didn\'t answer. Check that you\'re online and that the port is right.',
    );
  }

  var raw = '$error'.replaceFirst(RegExp(r'^(MailException|Exception):\s*'), '').trim();
  raw = raw.split('\n').first;
  if (raw.length > 160) raw = '${raw.substring(0, 160)}…';
  return p(MailProblemKind.unknown, 'Couldn\'t connect', raw.isEmpty ? 'Something went wrong. Try again.' : raw);
}
