import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../apps/ai/claude_code.dart';
import '../db/database.dart';
import 'sync_engine.dart';

const syncPort = 8787;

/// Runs Hub's sync, either as the server (the always-on laptop) or as a
/// client (phone, other PCs). Status changes are published through [status].
class SyncService {
  SyncService._();
  static final instance = SyncService._();

  final status = ValueNotifier<String>('Off');
  HttpServer? _server;
  Timer? _timer;
  StreamSubscription? _changes;
  Timer? _debounce;
  bool _running = false;

  static String newToken() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Applies the saved configuration. Safe to call again after settings change.
  Future<void> configure(AppDatabase db, {required String mode, required String url, required String token}) async {
    await stop();
    final engine = SyncEngine(db);
    if (mode == 'server' && token.isNotEmpty) {
      await engine.setRole('server');
      await _startServer(engine, token);
    } else if (mode == 'client' && url.isNotEmpty && token.isNotEmpty) {
      await engine.setRole('client');
      _startClient(engine, url, token);
    } else {
      await engine.setRole('none');
      status.value = 'Off';
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _debounce?.cancel();
    await _changes?.cancel();
    _changes = null;
    await _server?.close(force: true);
    _server = null;
  }

  // Server

  Future<void> _startServer(SyncEngine engine, String token) async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, syncPort);
    } catch (e) {
      status.value = 'Could not open port $syncPort: $e';
      return;
    }
    final ips = await localAddresses();
    status.value = 'Serving on ${ips.isEmpty ? 'port $syncPort' : ips.map((ip) => '$ip:$syncPort').join(', ')}';
    _server!.listen((req) => handle(req, engine, token));
  }

  /// Answers one request to the server. Every path needs the sync key.
  @visibleForTesting
  Future<void> handle(HttpRequest req, SyncEngine engine, String token) async {
    final res = req.response..headers.contentType = ContentType.json;
    try {
      if (req.headers.value('authorization') != 'Bearer $token') {
        res.statusCode = HttpStatus.unauthorized;
        res.write(jsonEncode({'error': 'wrong token'}));
        return;
      }
      if (req.method == 'GET' && req.uri.path == '/ping') {
        res.write(jsonEncode({'app': 'hub', 'time': SyncEngine.now()}));
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/sync') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        await engine.apply((body['changes'] as Map).cast<String, dynamic>());
        final now = SyncEngine.now();
        final changes = await engine.collect((body['since'] as num?)?.toInt() ?? 0);
        res.write(jsonEncode({'now': now, 'changes': changes}));
        status.value = 'Last device synced at ${_hm(DateTime.now())}';
        return;
      }
      // Your Claude plan through Claude Code on this laptop, for phones.
      if (req.method == 'POST' && req.uri.path == '/ai') {
        final raw = await _readCapped(req, ClaudeCodeRunner.maxPromptChars * 4 + 4096);
        final (code, body) = raw == null
            ? (
                HttpStatus.requestEntityTooLarge,
                <String, Object?>{'error': 'That question is too long for Claude Code.'},
              )
            : await ClaudePlan.serve(_tryJson(raw));
        res.statusCode = code;
        res.write(jsonEncode(body));
        return;
      }
      res.statusCode = HttpStatus.notFound;
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode({'error': '$e'}));
    } finally {
      await res.close();
    }
  }

  /// The request body as text, or null when it is longer than [maxBytes].
  static Future<String?> _readCapped(HttpRequest req, int maxBytes) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in req) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) return null;
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  static Object? _tryJson(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> localAddresses() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final all = [
        for (final i in list)
          for (final a in i.addresses) a.address,
      ];
      // Tailscale addresses first: they work from anywhere.
      all.sort((a, b) => (b.startsWith('100.') ? 1 : 0) - (a.startsWith('100.') ? 1 : 0));
      return all;
    } catch (_) {
      return [];
    }
  }

  // Client

  void _startClient(SyncEngine engine, String url, String token) {
    status.value = 'Waiting for first sync';
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => syncNow());
    _changes = engine.db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            engine.db.notes,
            engine.db.todos,
            engine.db.events,
            engine.db.calendars,
            engine.db.entries,
            engine.db.subscriptions,
            engine.db.budgets,
            engine.db.cities,
          ]),
        )
        .listen((_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 4), syncNow);
        });
    _client = (engine, url, token);
    unawaited(syncNow());
  }

  (SyncEngine, String, String)? _client;

  static Uri endpoint(String base, String path) {
    var b = base.trim();
    if (!b.contains('://')) b = 'http://$b';
    final u = Uri.parse(b);
    return u.replace(port: u.hasPort ? u.port : syncPort, path: path);
  }

  /// One round trip: send local changes, receive everyone else's.
  Future<void> syncNow() async {
    final c = _client;
    if (c == null || _running) return;
    final (engine, url, token) = c;
    _running = true;
    try {
      final state = await engine.state();
      final pushStart = SyncEngine.now();
      final changes = await engine.collect(state['lastPush']!);
      final res = await http
          .post(
            endpoint(url, '/sync'),
            headers: {'authorization': 'Bearer $token', 'content-type': 'application/json'},
            body: jsonEncode({'since': state['lastPull'], 'changes': changes}),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 401) throw 'The server refused the sync key.';
      if (res.statusCode != 200) throw 'Server answered ${res.statusCode}.';
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await engine.apply((body['changes'] as Map).cast<String, dynamic>());
      await engine.saveState(lastPull: (body['now'] as num).toInt(), lastPush: pushStart);
      status.value = 'Synced at ${_hm(DateTime.now())}';
    } on SocketException {
      status.value = 'Server not reachable. Is the laptop on and Tailscale connected?';
    } on TimeoutException {
      status.value = 'Server not reachable (timed out).';
    } catch (e) {
      status.value = 'Sync failed: $e';
    } finally {
      _running = false;
    }
  }

  /// Checks a server address and key before saving them.
  static Future<String?> test(String url, String token) async {
    try {
      final res = await http
          .get(endpoint(url, '/ping'), headers: {'authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) return 'The server refused this sync key.';
      if (res.statusCode != 200 || !res.body.contains('"hub"')) return 'That address is not a Hub server.';
      return null;
    } catch (_) {
      return 'Could not reach the server. Check the address and that Tailscale is connected.';
    }
  }

  static String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
