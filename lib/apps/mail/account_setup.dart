import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/database.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'mail_service.dart';
import 'microsoft_auth.dart';

/// Adds a new account (starting with the provider) or edits [existing].
Future<void> openAccountSetup(BuildContext context, {MailboxAccount? existing}) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => existing == null ? const AddMailAccountPage() : MailAccountForm(existing: existing),
  ),
);

const _appRegistrationsUrl = 'https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade';

Future<void> _openLink(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t open the browser. The link is copied instead.')));
  }
}

/// A round badge in the provider's colour with its first letter.
class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge(this.preset, {this.size = 40});
  final MailPreset preset;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: Color(preset.color), shape: BoxShape.circle),
    child: preset.isOther
        ? Icon(Icons.alternate_email_rounded, color: Colors.white, size: size * 0.5)
        : Text(
            preset.label.characters.first,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.42),
          ),
  );
}

/// Step one: type the address (Hub finds the settings) or pick the provider.
class AddMailAccountPage extends StatefulWidget {
  const AddMailAccountPage({super.key});

  @override
  State<AddMailAccountPage> createState() => _AddMailAccountPageState();
}

class _AddMailAccountPageState extends State<AddMailAccountPage> {
  final _email = TextEditingController();
  bool _looking = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _open(MailPreset preset, {MailServerSettings? settings, String? note, bool advanced = false}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MailAccountForm(
          preset: preset,
          email: _email.text.trim(),
          settings: settings,
          note: note,
          showAdvanced: advanced,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _continue() async {
    final email = _email.text.trim();
    final domain = emailDomain(email);
    if (domain == null) {
      setState(() => _error = 'Enter your full email address, like name@example.com.');
      return;
    }
    setState(() => _error = null);
    final known = detectProvider(email);
    if (known != null) return _open(known);
    setState(() => _looking = true);
    MailDiscovery? found;
    try {
      found = await discoverMailSettings(email).timeout(const Duration(seconds: 15));
    } catch (_) {
      found = null;
    }
    if (!mounted) return;
    setState(() => _looking = false);
    if (found == null) {
      // A sensible guess beats empty boxes; the test tells whether it is right.
      return _open(
        presetFor('imap'),
        settings: MailServerSettings(
          imapHost: 'imap.$domain',
          imapPort: 993,
          imapSecurity: 'ssl',
          smtpHost: 'smtp.$domain',
          smtpPort: 465,
          smtpSecurity: 'ssl',
        ),
        note:
            'Hub couldn\'t look up the settings for $domain, so it filled in the usual ones. '
            'If the test fails, check the server names in your provider\'s help pages.',
        advanced: true,
      );
    }
    return _open(
      found.preset,
      settings: found.settings,
      note: found.preset.isOther
          ? 'Hub found the settings for $domain.'
          : '$domain uses ${found.preset.label}, so Hub picked its settings.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: HubBar(title: const Text('Add account')),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text('What\'s your email address?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text('Hub looks up the right settings for you.', style: TextStyle(color: p.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _looking ? null : _continue(),
              decoration: const InputDecoration(hintText: 'name@example.com'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(_error!, style: TextStyle(color: p.danger)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _looking ? null : _continue,
              child: _looking
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Looking up settings…'),
                      ],
                    )
                  : const Text('Continue'),
            ),
            const SizedBox(height: 28),
            const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: SectionLabel('Or choose your provider')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final (i, preset) in mailPresets.indexed) ...[
                    if (i > 0) Divider(height: 1, indent: 72, color: p.line),
                    Press(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: _ProviderBadge(preset),
                        title: Text(preset.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(preset.tagline, style: TextStyle(color: p.muted, fontSize: 13.5)),
                        trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
                        onTap: _looking ? null : () => _open(preset, advanced: preset.isOther),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Test { idle, running, passed, failed }

/// Step two: what the provider needs, the sign-in fields, a connection test, then save.
class MailAccountForm extends StatefulWidget {
  const MailAccountForm({
    super.key,
    this.preset,
    this.email = '',
    this.settings,
    this.note,
    this.showAdvanced = false,
    this.existing,
  });

  final MailPreset? preset;
  final String email;
  final MailServerSettings? settings;

  /// What the lookup found, shown above the form.
  final String? note;
  final bool showAdvanced;
  final MailboxAccount? existing;

  @override
  State<MailAccountForm> createState() => _MailAccountFormState();
}

class _MailAccountFormState extends State<MailAccountForm> {
  late final MailPreset _preset = widget.preset ?? presetFor(widget.existing?.provider ?? 'imap');
  late final MailServerSettings _start = widget.settings ?? _preset.settings;
  late final _email = TextEditingController(text: widget.existing?.email ?? widget.email);
  late final _name = TextEditingController(
    text: widget.existing == null || widget.existing!.name == widget.existing!.email ? '' : widget.existing!.name,
  );
  final _password = TextEditingController();
  late final _username = TextEditingController(text: _start.username ?? '');
  late final _imapHost = TextEditingController(text: widget.existing?.imapHost ?? _start.imapHost);
  late final _imapPort = TextEditingController(text: '${widget.existing?.imapPort ?? _start.imapPort}');
  late final _smtpHost = TextEditingController(text: widget.existing?.smtpHost ?? _start.smtpHost);
  late final _smtpPort = TextEditingController(text: '${widget.existing?.smtpPort ?? _start.smtpPort}');
  final _clientId = TextEditingController();
  late String _imapSecurity = widget.existing?.imapSecurity ?? _start.imapSecurity;
  late String _smtpSecurity = widget.existing?.smtpSecurity ?? _start.smtpSecurity;
  late bool _selfSigned = widget.existing?.allowSelfSigned ?? _preset.allowSelfSigned;
  late bool _advanced = widget.showAdvanced;
  late bool _microsoft = _preset.microsoftSignIn;
  bool _showPassword = false;

  /// The keystore entry of the account being edited, so an empty password field keeps it.
  MailSecret? _saved;
  String? _savedClientId;
  bool _changeClientId = false;
  String? _oauthSecret;
  String? _oauthClientId;
  DeviceCode? _code;

  _Test _test = _Test.idle;
  String? _step;
  MailProblem? _problem;
  String? _formError;
  bool _saving = false;
  bool _disposed = false;

  List<TextEditingController> get _fields => [
    _email,
    _password,
    _username,
    _imapHost,
    _imapPort,
    _smtpHost,
    _smtpPort,
    _clientId,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _fields) {
      c.addListener(_untested);
    }
    _load();
  }

  Future<void> _load() async {
    final clientId = await MailService.instance.savedMicrosoftClientId();
    final e = widget.existing;
    final raw = e == null ? null : await MailService.instance.savedSecret(e.id);
    if (!mounted) return;
    setState(() {
      _savedClientId = clientId;
      if (raw != null) {
        final s = MailSecret.parse(raw);
        _saved = s;
        if (s.isMicrosoft) {
          _oauthSecret = raw;
          _oauthClientId = s.clientId;
          _savedClientId ??= s.clientId;
        } else if (_preset.microsoftSignIn) {
          _microsoft = false;
        }
        if (s.username != null) {
          _username.text = s.username!;
          _advanced = true;
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in [..._fields, _name]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Any change after a test means the result no longer applies.
  void _untested() {
    if (_test == _Test.passed || _test == _Test.failed) {
      setState(() {
        _test = _Test.idle;
        _problem = null;
      });
    }
  }

  MailboxAccount _draft() {
    final email = _email.text.trim();
    return MailboxAccount(
      id: widget.existing?.id ?? 0,
      provider: _preset.id,
      name: _name.text.trim().isEmpty ? email : _name.text.trim(),
      email: email,
      imapHost: _imapHost.text.trim(),
      imapPort: int.tryParse(_imapPort.text.trim()) ?? _start.imapPort,
      imapSecurity: _imapSecurity,
      smtpHost: _smtpHost.text.trim(),
      smtpPort: int.tryParse(_smtpPort.text.trim()) ?? _start.smtpPort,
      smtpSecurity: _smtpSecurity,
      color: widget.existing?.color ?? _preset.color,
      allowSelfSigned: _selfSigned,
    );
  }

  /// What would be saved in the keystore, or null with [_formError] set when something is missing.
  String? _secret() {
    if (!looksLikeEmail(_email.text)) return _fail('Enter your full email address.');
    bool badPort(String s) => (int.tryParse(s.trim()) ?? 0) <= 0 || int.parse(s.trim()) > 65535;
    if (_imapHost.text.trim().isEmpty || _smtpHost.text.trim().isEmpty) {
      setState(() => _advanced = true);
      return _fail('Fill in both server names under Advanced.');
    }
    if (badPort(_imapPort.text) || badPort(_smtpPort.text)) {
      setState(() => _advanced = true);
      return _fail('A port is a number like 993 or 587.');
    }
    if (_microsoft) {
      return _oauthSecret ?? _fail('Sign in with Microsoft first.');
    }
    var password = _password.text;
    if (_preset.stripSpaces) password = password.replaceAll(RegExp(r'\s'), '');
    if (password.isEmpty) password = _saved?.password ?? '';
    if (password.isEmpty) return _fail('Paste your ${_preset.passwordLabel.toLowerCase()}.');
    return MailService.passwordSecret(password, username: _username.text);
  }

  String? _fail(String message) {
    setState(() => _formError = message);
    return null;
  }

  Future<void> _runTest() async {
    setState(() => _formError = null);
    final secret = _secret();
    if (secret == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _test = _Test.running;
      _problem = null;
      _step = 'incoming';
    });
    try {
      await MailService.instance.test(
        _draft(),
        secret,
        onStep: (s) {
          if (mounted) setState(() => _step = s);
        },
      );
      if (!mounted) return;
      setState(() => _test = _Test.passed);
    } catch (e) {
      if (!mounted) return;
      final d = _draft();
      setState(() {
        _test = _Test.failed;
        _problem = e is MailProblem
            ? e
            : describeMailError(e, provider: d.provider, host: d.imapHost, port: d.imapPort);
      });
    }
  }

  Future<void> _signInMicrosoft() async {
    if (!looksLikeEmail(_email.text)) {
      setState(() => _formError = 'Enter your full email address first.');
      return;
    }
    final clientId = (_savedClientId == null || _changeClientId) ? _clientId.text.trim() : _savedClientId!;
    if (clientId.isEmpty) {
      setState(() => _formError = 'Paste the Application (client) ID from step 4 first.');
      return;
    }
    setState(() {
      _formError = null;
      _problem = null;
      _test = _Test.running;
      _step = 'microsoft';
    });
    try {
      final code = await MicrosoftAuth.start(clientId);
      if (!mounted) return;
      setState(() => _code = code);
      await Clipboard.setData(ClipboardData(text: code.userCode));
      unawaited(launchUrl(Uri.parse(code.url), mode: LaunchMode.externalApplication).catchError((_) => false));
      final token = await MicrosoftAuth.poll(clientId, code, cancelled: () => _disposed);
      if (!mounted) return;
      setState(() {
        _oauthSecret = MailService.oauthSecret(clientId, token);
        _oauthClientId = clientId;
        _code = null;
      });
      await _runTest();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = null;
        _test = _Test.failed;
        _problem = MailProblem(MailProblemKind.unknown, 'Microsoft sign-in didn\'t finish', '$e');
      });
    }
  }

  Future<void> _save() async {
    final secret = _secret();
    if (secret == null) return;
    setState(() => _saving = true);
    final db = context.db;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final c = _draft().toCompanion(false);
      final id = await db.saveMailAccount(widget.existing == null ? c.copyWith(id: const Value.absent()) : c);
      final accountId = widget.existing?.id ?? id;
      await MailService.instance.forget(accountId);
      await MailService.instance.savePassword(accountId, secret);
      if (_microsoft && _oauthClientId != null) await MailService.instance.saveMicrosoftClientId(_oauthClientId!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = 'Couldn\'t save the account: $e';
      });
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(widget.existing == null ? 'Account added' : 'Account saved')));
    navigator.pop(true);
  }

  Future<void> _remove() async {
    final a = widget.existing!;
    final db = context.db;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text('${a.email} is removed from Hub. Nothing is deleted from your mailbox.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await MailService.instance.forget(a.id);
    await db.deleteMailAccount(a.id);
    navigator.pop(true);
  }

  void _setSecurity({required bool incoming, required String value}) {
    // Moving between SSL and STARTTLS usually means the matching standard port too.
    const swap = {
      'imap': {'ssl': (143, 993), 'starttls': (993, 143)},
      'smtp': {'ssl': (587, 465), 'starttls': (465, 587)},
    };
    final port = incoming ? _imapPort : _smtpPort;
    final (from, to) = swap[incoming ? 'imap' : 'smtp']![value]!;
    setState(() {
      if (incoming) {
        _imapSecurity = value;
      } else {
        _smtpSecurity = value;
      }
      if (port.text.trim() == '$from') port.text = '$to';
    });
    _untested();
  }

  List<String> get _steps {
    if (!_microsoft) return _preset.steps;
    if (_savedClientId != null && !_changeClientId) {
      return const [
        'Tap "Sign in with Microsoft". Your browser opens.',
        'Paste the code Hub shows (it\'s already copied) and approve with your Microsoft account.',
        'Come back to Hub. It tests the connection by itself.',
      ];
    }
    return const [
      'Once only: Hub needs its own free app registration with Microsoft. Open App registrations and choose '
          '"New registration".',
      'Name it "Hub", choose "Accounts in any organizational directory and personal Microsoft accounts", then '
          'Register.',
      'Open Authentication, set "Allow public client flows" to Yes, and Save.',
      'Copy the "Application (client) ID" from Overview and paste it below.',
    ];
  }

  List<MailHelpLink> get _links {
    if (!_microsoft) return _preset.links;
    if (_savedClientId != null && !_changeClientId) return const [];
    return const [MailHelpLink('Open App registrations', _appRegistrationsUrl)];
  }

  bool get _onPhone =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final busy = _test == _Test.running || _saving;
    final editing = widget.existing != null;
    return Scaffold(
      appBar: HubBar(title: Text(editing ? 'Edit account' : _preset.label)),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Row(
              children: [
                _ProviderBadge(_preset, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing ? widget.existing!.email : _preset.label,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(editing ? _preset.label : _preset.tagline, style: TextStyle(color: p.muted, fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
            if (_preset.microsoftSignIn) ...[
              const SizedBox(height: 16),
              PillToggle<bool>(
                options: const [(true, 'Microsoft sign-in'), (false, 'App password')],
                value: _microsoft,
                onChanged: (v) => setState(() {
                  _microsoft = v;
                  _formError = null;
                  _test = _Test.idle;
                  _problem = null;
                }),
              ),
            ],
            const SizedBox(height: 16),
            _StepsCard(
              steps: _steps,
              links: _links,
              notes: [
                ?widget.note,
                if (_preset.id == 'proton' && _onPhone)
                  'Bridge only runs on a computer. To use it on this phone, the computer has to share Bridge on '
                      'your network (for example with Tailscale). Then enter its address under Advanced.',
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: _preset.id == 'proton' ? 'Email (as shown in Bridge)' : 'Email address',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name (optional)',
                hintText: 'Shown to people you write to',
              ),
            ),
            const SizedBox(height: 10),
            if (_microsoft)
              if (_savedClientId == null || _changeClientId)
                TextField(
                  controller: _clientId,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Application (client) ID',
                    hintText: 'Looks like 1a2b3c4d-…',
                  ),
                )
              else
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: p.positive, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _oauthSecret != null ? 'Signed in with Microsoft' : 'Hub app registration saved',
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => setState(() => _changeClientId = true),
                      child: const Text('Change'),
                    ),
                  ],
                )
            else
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _preset.passwordLabel,
                  hintText: _saved?.password != null ? 'Leave empty to keep the saved one' : null,
                  floatingLabelBehavior: _saved?.password != null ? FloatingLabelBehavior.always : null,
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide' : 'Show',
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            if (_code != null) _DeviceCodeCard(code: _code!),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: Icon(_advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                label: const Text('Advanced'),
              ),
            ),
            if (_advanced) _advancedFields(p),
            if (_test != _Test.idle) ...[const SizedBox(height: 8), _resultCard(p)],
            if (_formError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4),
                child: Text(_formError!, style: TextStyle(color: p.danger)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : _test == _Test.passed
                  ? _save
                  : (_microsoft && _oauthSecret == null)
                  ? _signInMicrosoft
                  : _runTest,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      _test == _Test.passed
                          ? 'Save account'
                          : (_microsoft && _oauthSecret == null)
                          ? 'Sign in with Microsoft'
                          : 'Test connection',
                    ),
            ),
            if (_microsoft && _oauthSecret != null && _test != _Test.passed)
              TextButton(onPressed: busy ? null : _signInMicrosoft, child: const Text('Sign in with Microsoft again')),
            if (_test == _Test.failed) TextButton(onPressed: busy ? null : _save, child: const Text('Save anyway')),
            if (editing) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: p.danger),
                child: const Text('Remove account'),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Passwords and sign-ins stay in this device\'s secure storage (Windows Credential Manager, Android '
              'Keystore or iOS Keychain), never in Hub\'s database or backups.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedFields(Palette p) {
    Widget server(String label, TextEditingController host, TextEditingController port, bool incoming) {
      final security = incoming ? _imapSecurity : _smtpSecurity;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: SectionLabel(label)),
          TextField(
            controller: host,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Server'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: port,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillToggle<String>(
                    dense: true,
                    options: const [('ssl', 'SSL/TLS'), ('starttls', 'STARTTLS')],
                    value: security,
                    onChanged: (v) => _setSecurity(incoming: incoming, value: v),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        server('Incoming mail (IMAP)', _imapHost, _imapPort, true),
        const SizedBox(height: 18),
        server('Sending mail (SMTP)', _smtpHost, _smtpPort, false),
        if (!_microsoft) ...[
          const SizedBox(height: 18),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Login name (optional)',
              hintText: 'Only if it isn\'t your email address',
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: _selfSigned,
            onChanged: (v) {
              setState(() => _selfSigned = v);
              _untested();
            },
            title: const Text('Trust the server\'s own certificate'),
            subtitle: Text(
              'Only works for a server on this computer or your home network, like Proton Mail Bridge.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _resultCard(Palette p) {
    final (IconData icon, Color color, String title, String message) = switch (_test) {
      _Test.running => (
        Icons.sync_rounded,
        p.muted,
        switch (_step) {
          'microsoft' => 'Waiting for Microsoft…',
          'outgoing' => 'Checking sending mail…',
          _ => 'Checking incoming mail…',
        },
        _step == 'microsoft' ? 'Approve the sign-in in your browser.' : 'This takes a few seconds.',
      ),
      _Test.passed => (
        Icons.check_circle_rounded,
        p.positive,
        'Connected',
        'Hub can read and send mail with this account.',
      ),
      _ => (
        Icons.error_outline_rounded,
        p.danger,
        _problem?.title ?? 'Couldn\'t connect',
        [
          if (_problem?.outgoing ?? false) 'Reading mail works, but sending doesn\'t.',
          _problem?.message ?? '',
        ].join(' '),
      ),
    };
    final kind = _problem?.kind;
    final fixServer = const {
      MailProblemKind.securityMismatch,
      MailProblemKind.serverNotFound,
      MailProblemKind.unreachable,
      MailProblemKind.certificate,
      MailProblemKind.bridgeNotRunning,
    }.contains(kind);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _test == _Test.running
              ? const Padding(
                  padding: EdgeInsets.all(2),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(message, style: TextStyle(color: p.muted, height: 1.4)),
                if (_test == _Test.failed)
                  Wrap(
                    spacing: 4,
                    children: [
                      if (kind == MailProblemKind.appPasswordNeeded && _preset.links.isNotEmpty)
                        TextButton(
                          onPressed: () => _openLink(context, _preset.links.last.url),
                          child: Text(_preset.links.last.label),
                        ),
                      if (kind == MailProblemKind.microsoftSignInNeeded)
                        TextButton(
                          onPressed: () => setState(() {
                            _microsoft = true;
                            _test = _Test.idle;
                            _problem = null;
                          }),
                          child: const Text('Use Microsoft sign-in'),
                        ),
                      if (fixServer && !_advanced)
                        TextButton(
                          onPressed: () => setState(() => _advanced = true),
                          child: const Text('Show server settings'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The numbered "what you need" steps, with buttons for the pages they mention.
class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.steps, required this.links, this.notes = const []});
  final List<String> steps;
  final List<MailHelpLink> links;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('What you need'),
            const SizedBox(height: 10),
            for (final (i, s) in steps.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s, style: const TextStyle(height: 1.4))),
                  ],
                ),
              ),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: p.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(n, style: TextStyle(color: p.muted, height: 1.4)),
                    ),
                  ],
                ),
              ),
            if (links.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final l in links)
                    OutlinedButton.icon(
                      onPressed: () => _openLink(context, l.url),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(l.label),
                    ),
                ],
              ),
            if (links.isNotEmpty) const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _DeviceCodeCard extends StatelessWidget {
  const _DeviceCodeCard({required this.code});
  final DeviceCode code;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Text('Enter this code at ${code.url}', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          SelectableText(
            code.userCode,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 4),
          ),
          const SizedBox(height: 4),
          Text('Copied. Waiting for you to approve…', style: TextStyle(color: p.muted, fontSize: 13.5)),
          TextButton(onPressed: () => _openLink(context, code.url), child: const Text('Open the page again')),
        ],
      ),
    );
  }
}

/// Every connected mailbox; tap one to change or remove it.
class MailAccountsPage extends StatelessWidget {
  const MailAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: HubBar(title: const Text('Mail accounts')),
      body: StreamBuilder<List<MailboxAccount>>(
        stream: context.db.watchMailAccounts(),
        builder: (context, snap) {
          final list = snap.data ?? const <MailboxAccount>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final a in list) ...[
                        Press(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: _ProviderBadge(presetFor(a.provider)),
                            title: Text(a.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              presetFor(a.provider).label,
                              style: TextStyle(color: p.muted, fontSize: 13.5),
                            ),
                            trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
                            onTap: () => openAccountSetup(context, existing: a),
                          ),
                        ),
                        Divider(height: 1, indent: 72, color: p.line),
                      ],
                      Press(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: p.raised, shape: BoxShape.circle),
                            child: Icon(Icons.add_rounded, color: p.ink),
                          ),
                          title: const Text('Add account', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Gmail, Outlook, Proton, iCloud, Yahoo or any other',
                            style: TextStyle(color: p.muted, fontSize: 13.5),
                          ),
                          onTap: () => openAccountSetup(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
