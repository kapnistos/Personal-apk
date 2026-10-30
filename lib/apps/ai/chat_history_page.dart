import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'ai_usage.dart';
import 'ai_widgets.dart';
import 'chat_memory.dart';

/// What the history list hands back: the mode, and the conversation to open (null for a new chat).
class ChatPick {
  const ChatPick(this.agent, this.id);
  final bool agent;
  final String? id;
}

/// Every saved conversation of one mode, newest first and grouped by day. Tap to reopen; the menu
/// renames or deletes (with Undo).
class ChatHistoryPage extends StatefulWidget {
  const ChatHistoryPage({super.key, required this.agent});
  final bool agent;

  @override
  State<ChatHistoryPage> createState() => _ChatHistoryPageState();
}

class _ChatHistoryPageState extends State<ChatHistoryPage> {
  late bool _agent = widget.agent;
  final _search = TextEditingController();
  String _query = '';

  ChatMemory get _memory => ChatMemory(context.settings);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _group(DateTime d, DateTime now) {
    final days = daysBetween(dateOnly(d), dateOnly(now));
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return 'Previous 7 days';
    if (days < 30) return 'Previous 30 days';
    return d.year == now.year ? DateFormat.MMMM().format(d) : DateFormat.yMMMM().format(d);
  }

  Future<void> _rename(ChatSummary c) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: c.name),
    );
    if (title == null || !mounted) return;
    await _memory.rename(c.id, title);
    if (mounted) setState(() {});
  }

  Future<void> _delete(ChatSummary c) async {
    final messenger = ScaffoldMessenger.of(context);
    final memory = _memory;
    final gone = await memory.delete(c.id);
    if (!mounted) return;
    setState(() {});
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Chat deleted'),
        action: gone == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () async {
                  await memory.restore(gone);
                  if (mounted) setState(() {});
                },
              ),
      ),
    );
  }

  Future<void> _menu(ChatSummary c) async {
    final p = Palette.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                c.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: p.danger),
              title: Text('Delete', style: TextStyle(color: p.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'rename') await _rename(c);
    if (choice == 'delete') await _delete(c);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final now = DateTime.now();
    final all = _memory.list(agent: _agent);
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? all : all.where((c) => '${c.name} ${c.preview}'.toLowerCase().contains(q)).toList();
    final rows = <Widget>[];
    String? group;
    for (final c in shown) {
      final g = _group(c.updated, now);
      if (g != group) {
        group = g;
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, rows.isEmpty ? 4 : 20, 4, 4),
            child: Text(
              g,
              style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      rows.add(ChatRow(chat: c, onTap: () => Navigator.pop(context, ChatPick(_agent, c.id)), onMore: () => _menu(c)));
    }
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    AiRoundButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('History', style: Theme.of(context).textTheme.headlineMedium)),
                    AiPill(
                      label: 'New chat',
                      icon: Icons.edit_square,
                      filled: true,
                      onTap: () => Navigator.pop(context, ChatPick(_agent, null)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PillToggle<bool>(
                    options: const [(false, 'Chat'), (true, 'Hub agent')],
                    value: _agent,
                    onChanged: (v) => setState(() => _agent = v),
                  ),
                ),
              ),
              if (all.length > 5)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search chats',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            q.isNotEmpty
                                ? 'No chats match "$_query".'
                                : _agent
                                ? 'No Hub agent chats yet. They are saved here as you go.'
                                : 'No chats yet. They are saved here as you go.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 15, height: 1.4),
                          ),
                        ),
                      )
                    : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: rows),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One saved conversation: its name, the last line and what it used.
class ChatRow extends StatelessWidget {
  const ChatRow({super.key, required this.chat, required this.onTap, this.onMore});
  final ChatSummary chat;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final when = relativeTime(chat.updated);
    final used = [
      '${chat.messages} message${chat.messages == 1 ? '' : 's'}',
      if (chat.tokens > 0) '${formatTokens(chat.tokens)} tokens',
      if (chat.cost != null) formatUsd(chat.cost!),
    ].join(' · ');
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onMore,
        child: Pressable(
          scale: 0.98,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(when, style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ],
                      ),
                      if (chat.preview.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          chat.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 14),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(used, style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                if (onMore != null)
                  IconButton(
                    tooltip: 'More',
                    icon: Icon(Icons.more_horiz_rounded, color: p.muted),
                    onPressed: onMore,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for a new name; owns its text field, so nothing is used after the dialog closes.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename chat'),
    content: TextField(
      controller: _c,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(hintText: 'Name'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}
