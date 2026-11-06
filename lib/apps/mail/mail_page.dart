import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/format.dart';
import '../../core/press.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';
import 'account_setup.dart';
import 'mail_service.dart';

export 'account_setup.dart' show MailAccountsPage, openAccountSetup;

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

  // Kept so a redraw doesn't start a new database query.
  late final _accountsStream = context.db.watchMailAccounts();

  Future<void> _refresh(List<MailboxAccount> accounts) async {
    if (accounts.isEmpty || !mounted) return;
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
    // Calendar days, so last week's same weekday never shows as just "Sat" next to today's mail.
    final ago = daysBetween(d, now);
    if (ago > 0 && ago < 7) return DateFormat.E().format(d);
    return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return StreamBuilder<List<MailboxAccount>>(
      stream: _accountsStream,
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
          appBar: HubBar(
            title: const Text('Mail'),
            actions: [
              IconButton(
                tooltip: 'Accounts',
                icon: const Icon(Icons.manage_accounts_outlined),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MailAccountsPage())),
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
                  message:
                      'Connect Gmail, Outlook, Proton, iCloud, Yahoo or any other mailbox. Hub walks you through it.',
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
                              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, color: p.danger, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text('${e.account.email}: ${e.message}')),
                                  TextButton(
                                    onPressed: () => openAccountSetup(context, existing: e.account),
                                    child: const Text('Fix'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_loading && _items == null)
                        const Skeleton(lines: 6, padding: EdgeInsets.fromLTRB(16, 8, 16, 8)),
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
                        ContentWidth(
                          child: _MailRow(item: item, time: _time(item.date), showAccount: accounts.length > 1),
                        ),
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
    return Press(
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MessagePage(item: item))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Color(item.account.color),
                child: Text(
                  item.sender.characters.first.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread ? p.accent : p.muted,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread ? p.ink : p.muted,
                              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (showAccount)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(color: Color(item.account.color), shape: BoxShape.circle),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    MailService.instance
        .open(widget.item)
        .then(
          (m) {
            if (mounted) setState(() => _full = m);
          },
          onError: (e) {
            if (mounted) setState(() => _error = '$e');
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final item = widget.item;
    final text = _full == null ? null : messageText(_full!);
    final from = item.message.from?.firstOrNull;
    return Scaffold(
      appBar: HubBar(
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
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(item.account.color),
                  child: Text(
                    item.sender.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.sender, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${from?.email ?? ''} · to ${item.account.email}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
                Text(DateFormat('d MMM, HH:mm').format(item.date), style: TextStyle(color: p.muted, fontSize: 13.5)),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null) Text(_error!, style: TextStyle(color: p.danger)),
            if (text == null && _error == null) const Skeleton(lines: 4, leading: false, padding: EdgeInsets.zero),
            if (text != null)
              SelectableText(text.isEmpty ? '(no text)' : text, style: const TextStyle(fontSize: 15.5, height: 1.55)),
          ],
        ),
      ),
    );
  }
}

Future<void> openCompose(BuildContext context, List<MailboxAccount> accounts, {MimeMessage? replyTo}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _Compose(accounts: accounts, replyTo: replyTo),
    ),
  );
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
      _body.text =
          '\n\nOn ${DateFormat('d MMM y, HH:mm').format(r.decodeDate()?.toLocal() ?? DateTime.now())}, '
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
      if (mounted) setState(() => _sending = false);
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
      appBar: HubBar(
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
