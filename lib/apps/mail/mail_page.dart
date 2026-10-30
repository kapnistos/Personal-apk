import 'package:drift/drift.dart' show Value;
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';
import 'mail_service.dart';
import 'microsoft_auth.dart';

class MailPage extends StatefulWidget {
  const MailPage({super.key});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  List<MailItem>? _items;
  List<MailError> _errors = [];
  List<MailboxAccount> _accounts = [];
  int? _accountFilter;
  bool _loading = false;

  Future<void> _refresh(List<MailboxAccount> accounts) async {
    if (accounts.isEmpty) return;
    setState(() => _loading = true);
    final (items, errors) = await MailService.instance.inbox(accounts);
    if (!mounted) return;
    setState(() {
      _items = items;
      _errors = errors;
      _loading = false;
    });
  }

  String _time(DateTime d) {
    final now = DateTime.now();
    if (dateOnly(d) == dateOnly(now)) return DateFormat.Hm().format(d);
    if (now.difference(d).inDays < 6) return DateFormat.E().format(d);
    return DateFormat('d MMM').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<MailboxAccount>>(
      stream: context.db.watchMailAccounts(),
      builder: (context, snap) {
        final accounts = snap.data;
        if (accounts != null && !_sameAccounts(accounts)) {
          _accounts = accounts;
          WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(accounts));
        }
        final items = (_items ?? const <MailItem>[])
            .where((i) => _accountFilter == null || i.account.id == _accountFilter)
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Mail'),
            actions: [
              IconButton(
                tooltip: 'Accounts',
                icon: const Icon(Icons.manage_accounts_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MailAccountsPage())),
              ),
              const SizedBox(width: 4),
            ],
          ),
          floatingActionButton: (accounts?.isEmpty ?? true)
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => openCompose(context, accounts!),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Write'),
                ),
          body: accounts == null
              ? const SizedBox.shrink()
              : accounts.isEmpty
                  ? EmptyState(
                      icon: Icons.mail_outline_rounded,
                      title: 'No mail accounts',
                      message: 'Add Gmail, Proton (through Proton Bridge) or any IMAP account.',
                      action: FilledButton.icon(
                        onPressed: () => openAccountSetup(context),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add account'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _refresh(accounts),
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 96),
                        children: [
                          if (accounts.length > 1)
                            SizedBox(
                              height: 48,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                children: [
                                  for (final a in [null, ...accounts])
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        showCheckmark: false,
                                        label: Text(a == null ? 'All inboxes' : a.email),
                                        selected: _accountFilter == a?.id,
                                        onSelected: (_) => setState(() => _accountFilter = a?.id),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          for (final e in _errors)
                            ContentWidth(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: p.danger.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(children: [
                                    Icon(Icons.error_outline_rounded, color: p.danger, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text('${e.account.email}: ${e.message}')),
                                  ]),
                                ),
                              ),
                            ),
                          if (_loading && _items == null)
                            const Padding(
                              padding: EdgeInsets.all(48),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                            ),
                          if (_items != null && items.isEmpty && _errors.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 80),
                              child: EmptyState(
                                icon: Icons.inbox_outlined,
                                title: 'Inbox zero',
                                message: 'Nothing here right now.',
                              ),
                            ),
                          for (final item in items)
                            ContentWidth(child: _MailRow(item: item, time: _time(item.date), showAccount: accounts.length > 1)),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  bool _sameAccounts(List<MailboxAccount> next) =>
      next.length == _accounts.length && next.every((a) => _accounts.any((b) => b == a));
}

class _MailRow extends StatelessWidget {
  const _MailRow({required this.item, required this.time, required this.showAccount});
  final MailItem item;
  final String time;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final unread = item.unread;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MessagePage(item: item))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Color(item.account.color).withValues(alpha: 0.16),
            child: Text(
              item.sender.characters.first.toUpperCase(),
              style: TextStyle(color: Color(item.account.color), fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(item.sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                ),
                Text(time,
                    style: TextStyle(
                        fontSize: 13,
                        color: unread ? p.accent : p.muted,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: Text(item.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: unread ? p.ink : p.muted, fontWeight: unread ? FontWeight.w600 : FontWeight.w400)),
                ),
                if (showAccount)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(color: Color(item.account.color), shape: BoxShape.circle),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MessagePage extends StatefulWidget {
  const _MessagePage({required this.item});
  final MailItem item;

  @override
  State<_MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<_MessagePage> {
  MimeMessage? _full;
  String? _error;

  @override
  void initState() {
    super.initState();
    MailService.instance.open(widget.item).then((m) {
      if (mounted) setState(() => _full = m);
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final item = widget.item;
    final text = _full == null ? null : messageText(_full!);
    final from = item.message.from?.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (text != null)
            IconButton(
              tooltip: 'Ask Claude about this email',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () => ClaudeBridge.ask(
                context,
                'Summarise this email and suggest a short reply.\n\nFrom: ${item.sender}\nSubject: ${item.subject}\n\n'
                '${text.length > 3000 ? '${text.substring(0, 3000)}…' : text}',
              ),
            ),
          if (_full != null)
            IconButton(
              tooltip: 'Reply',
              icon: const Icon(Icons.reply_rounded),
              onPressed: () => openCompose(context, [item.account], replyTo: _full),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            SelectableText(item.subject, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color(item.account.color).withValues(alpha: 0.16),
                child: Text(item.sender.characters.first.toUpperCase(),
                    style: TextStyle(color: Color(item.account.color), fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.sender, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${from?.email ?? ''} · to ${item.account.email}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 13.5),
                  ),
                ]),
              ),
              Text(DateFormat('d MMM, HH:mm').format(item.date), style: TextStyle(color: p.muted, fontSize: 13.5)),
            ]),
            const SizedBox(height: 20),
            if (_error != null) Text(_error!, style: TextStyle(color: p.danger)),
            if (text == null && _error == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
            if (text != null) SelectableText(text.isEmpty ? '(no text)' : text, style: const TextStyle(fontSize: 15.5, height: 1.55)),
          ],
        ),
      ),
    );
  }
}

Future<void> openCompose(BuildContext context, List<MailboxAccount> accounts, {MimeMessage? replyTo}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _Compose(accounts: accounts, replyTo: replyTo),
  ));
}

class _Compose extends StatefulWidget {
  const _Compose({required this.accounts, this.replyTo});
  final List<MailboxAccount> accounts;
  final MimeMessage? replyTo;

  @override
  State<_Compose> createState() => _ComposeState();
}

class _ComposeState extends State<_Compose> {
  late MailboxAccount _from = widget.accounts.first;
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final r = widget.replyTo;
    if (r != null) {
      final sender = r.replyTo?.firstOrNull ?? r.from?.firstOrNull;
      _to.text = sender?.email ?? '';
      final s = r.decodeSubject() ?? '';
      _subject.text = s.toLowerCase().startsWith('re:') ? s : 'Re: $s';
      final quoted = messageText(r).split('\n').map((l) => '> $l').join('\n');
      _body.text = '\n\nOn ${DateFormat('d MMM y, HH:mm').format(r.decodeDate()?.toLocal() ?? DateTime.now())}, '
          '${sender?.personalName ?? sender?.email ?? ''} wrote:\n$quoted';
    }
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final recipients = _to.text
        .split(RegExp(r'[,;\s]+'))
        .where((s) => s.contains('@'))
        .map((s) => MailAddress(null, s.trim()))
        .toList();
    if (recipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one recipient.')));
      return;
    }
    setState(() => _sending = true);
    final builder = MessageBuilder.prepareMultipartAlternativeMessage(plainText: _body.text)
      ..from = [MailService.addressOf(_from)]
      ..to = recipients
      ..subject = _subject.text.trim();
    final r = widget.replyTo;
    if (r != null) {
      final id = r.decodeHeaderValue('message-id');
      if (id != null) {
        builder.setHeader('In-Reply-To', id);
        builder.setHeader('References', [r.decodeHeaderValue('references'), id].whereType<String>().join(' '));
      }
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await MailService.instance.send(_from, builder.buildMimeMessage());
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Sent')));
    } catch (e) {
      setState(() => _sending = false);
      messenger.showSnackBar(SnackBar(content: Text('Not sent: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final line = InputDecoration(
      filled: false,
      border: InputBorder.none,
      focusedBorder: InputBorder.none,
      hintStyle: TextStyle(color: p.muted),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(widget.replyTo == null ? 'New email' : 'Reply'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send'),
            ),
          ),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            if (widget.accounts.length > 1)
              DropdownButtonFormField<int>(
                initialValue: _from.id,
                decoration: line.copyWith(prefixText: 'From  '),
                items: [for (final a in widget.accounts) DropdownMenuItem(value: a.id, child: Text(a.email))],
                onChanged: (v) => setState(() => _from = widget.accounts.firstWhere((a) => a.id == v)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('From  ${_from.email}', style: TextStyle(color: p.muted)),
              ),
            Divider(color: p.line),
            TextField(
              controller: _to,
              keyboardType: TextInputType.emailAddress,
              decoration: line.copyWith(hintText: 'To'),
            ),
            Divider(color: p.line),
            TextField(
              controller: _subject,
              textCapitalization: TextCapitalization.sentences,
              decoration: line.copyWith(hintText: 'Subject'),
            ),
            Divider(color: p.line),
            TextField(
              controller: _body,
              autofocus: widget.replyTo != null,
              minLines: 12,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(height: 1.5),
              decoration: line.copyWith(hintText: 'Write your message'),
            ),
          ],
        ),
      ),
    );
  }
}

class MailAccountsPage extends StatelessWidget {
  const MailAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mail accounts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openAccountSetup(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: StreamBuilder<List<MailboxAccount>>(
        stream: context.db.watchMailAccounts(),
        builder: (context, snap) {
          final list = snap.data ?? const <MailboxAccount>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final a in list)
                ContentWidth(
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Color(a.color), radius: 8),
                      title: Text(a.email),
                      subtitle: Text('${presetFor(a.provider).label} · ${a.imapHost}'),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: Icon(Icons.delete_outline_rounded, color: p.danger),
                        onPressed: () async {
                          final db = context.db;
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('Remove account?'),
                              content: Text('${a.email} is removed from Hub. Nothing is deleted on the server.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Remove')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await MailService.instance.forget(a.id);
                            await db.deleteMailAccount(a.id);
                          }
                        },
                      ),
                      onTap: () => openAccountSetup(context, existing: a),
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

Future<void> openAccountSetup(BuildContext context, {MailboxAccount? existing}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AccountSetup(existing: existing)));

class _AccountSetup extends StatefulWidget {
  const _AccountSetup({this.existing});
  final MailboxAccount? existing;

  @override
  State<_AccountSetup> createState() => _AccountSetupState();
}

class _AccountSetupState extends State<_AccountSetup> {
  late MailPreset _preset = presetFor(widget.existing?.provider ?? 'gmail');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _password = TextEditingController();
  late final _imapHost = TextEditingController(text: widget.existing?.imapHost ?? _preset.imapHost);
  late final _imapPort = TextEditingController(text: '${widget.existing?.imapPort ?? _preset.imapPort}');
  late final _smtpHost = TextEditingController(text: widget.existing?.smtpHost ?? _preset.smtpHost);
  late final _smtpPort = TextEditingController(text: '${widget.existing?.smtpPort ?? _preset.smtpPort}');
  final _clientId = TextEditingController();
  bool _advanced = false;
  bool _busy = false;
  String? _error;
  DeviceCode? _code;
  String? _oauthSecret;
  bool _disposed = false;

  bool get _isOutlook => _preset.id == 'outlook';

  @override
  void dispose() {
    _disposed = true;
    for (final c in [_email, _name, _password, _imapHost, _imapPort, _smtpHost, _smtpPort, _clientId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signInMicrosoft() async {
    final clientId = _clientId.text.trim();
    if (clientId.isEmpty) {
      setState(() => _error = 'Paste the Application (client) ID from your app registration first.');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final code = await MicrosoftAuth.start(clientId);
      if (!mounted) return;
      setState(() => _code = code);
      await Clipboard.setData(ClipboardData(text: code.userCode));
      await launchUrl(Uri.parse(code.url), mode: LaunchMode.externalApplication);
      final token = await MicrosoftAuth.poll(clientId, code, cancelled: () => _disposed);
      if (!mounted) return;
      setState(() {
        _oauthSecret = MailService.oauthSecret(clientId, token);
        _code = null;
        _busy = false;
      });
      await _save();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _code = null;
        _error = '$e';
      });
    }
  }

  void _pick(MailPreset p) => setState(() {
        _preset = p;
        _imapHost.text = p.imapHost;
        _imapPort.text = '${p.imapPort}';
        _smtpHost.text = p.smtpHost;
        _smtpPort.text = '${p.smtpPort}';
        _advanced = p.id == 'imap' || p.id == 'proton';
        _error = null;
      });

  MailboxAccount _draft(int id) => MailboxAccount(
        id: id,
        provider: _preset.id,
        name: _name.text.trim().isEmpty ? _email.text.trim() : _name.text.trim(),
        email: _email.text.trim(),
        imapHost: _imapHost.text.trim(),
        imapPort: int.tryParse(_imapPort.text) ?? _preset.imapPort,
        imapSecurity: _preset.imapSecurity,
        smtpHost: _smtpHost.text.trim(),
        smtpPort: int.tryParse(_smtpPort.text) ?? _preset.smtpPort,
        smtpSecurity: _preset.smtpSecurity,
        color: _preset.color,
        allowSelfSigned: _preset.allowSelfSigned,
      );

  Future<void> _save() async {
    final secret = _isOutlook ? _oauthSecret : _password.text;
    if (!_email.text.contains('@') || secret == null || secret.isEmpty || _imapHost.text.trim().isEmpty) {
      setState(() => _error = _isOutlook
          ? 'Fill in the email address, then sign in with Microsoft.'
          : 'Fill in the email address, ${_preset.passwordLabel.toLowerCase()} and server.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final db = context.db;
    final draft = _draft(widget.existing?.id ?? 0);
    try {
      await MailService.instance.test(draft, secret);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
      return;
    }
    final c = draft.toCompanion(false);
    final id = await db.saveMailAccount(widget.existing == null ? c.copyWith(id: const Value.absent()) : c);
    final accountId = widget.existing?.id ?? id;
    await MailService.instance.forget(accountId);
    await MailService.instance.savePassword(accountId, secret);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add mail account' : 'Edit account')),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final preset in mailPresets)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(preset.label),
                  selected: _preset.id == preset.id,
                  onSelected: preset.available ? (_) => _pick(preset) : null,
                ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(12)),
              child: Text(_preset.help, style: TextStyle(color: p.muted, height: 1.45)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  hintText: _preset.id == 'proton' ? 'Email (as shown in Bridge)' : 'Email address'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: const InputDecoration(hintText: 'Your name, shown to recipients')),
            const SizedBox(height: 10),
            if (_isOutlook)
              TextField(controller: _clientId, decoration: const InputDecoration(hintText: 'Application (client) ID'))
            else
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(hintText: _preset.passwordLabel),
              ),
            if (_code != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text('Enter this code at ${_code!.url}', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  SelectableText(_code!.userCode,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 4)),
                  const SizedBox(height: 4),
                  Text('Copied to the clipboard. Waiting for you to approve…', style: TextStyle(color: p.muted, fontSize: 13.5)),
                ]),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _advanced = !_advanced),
                child: Text(_advanced ? 'Hide server settings' : 'Server settings'),
              ),
            ),
            if (_advanced) ...[
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _imapHost, decoration: const InputDecoration(labelText: 'IMAP server'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _imapPort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port'))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _smtpHost, decoration: const InputDecoration(labelText: 'SMTP server'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _smtpPort, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port'))),
              ]),
              const SizedBox(height: 6),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: TextStyle(color: p.danger)),
              ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _busy ? null : (_isOutlook ? _signInMicrosoft : _save),
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_isOutlook ? 'Sign in with Microsoft' : 'Connect and save'),
            ),
            const SizedBox(height: 12),
            Text(
              'Passwords are stored in the Windows Credential Manager or the Android keystore, never in the app database.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
