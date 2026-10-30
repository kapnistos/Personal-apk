import 'dart:async';
import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:http/http.dart' as http;

/// Microsoft sign-in for Outlook.com and Microsoft 365 mail, using the device
/// code flow: Hub shows a short code, you enter it at microsoft.com/devicelogin.
class MicrosoftAuth {
  static const scopes =
      'https://outlook.office.com/IMAP.AccessAsUser.All '
      'https://outlook.office.com/SMTP.Send offline_access';
  static const _base = 'https://login.microsoftonline.com/common/oauth2/v2.0';

  static Future<DeviceCode> start(String clientId) async {
    final res = await _post('$_base/devicecode', {'client_id': clientId, 'scope': scopes});
    final j = _json(res);
    if (res.statusCode != 200) throw _message(j);
    return DeviceCode(
      deviceCode: j['device_code'] as String,
      userCode: j['user_code'] as String,
      url: j['verification_uri'] as String,
      interval: (j['interval'] as num?)?.toInt() ?? 5,
      expiresIn: (j['expires_in'] as num?)?.toInt() ?? 900,
    );
  }

  /// Waits until the code is approved in the browser.
  static Future<OauthToken> poll(String clientId, DeviceCode code, {bool Function()? cancelled}) async {
    final deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
    var interval = code.interval;
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) throw 'Cancelled';
      final http.Response res;
      try {
        res = await _post('$_base/token', {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': clientId,
          'device_code': code.deviceCode,
        });
      } catch (_) {
        continue; // A dropped connection while waiting; ask again next round.
      }
      final j = _json(res);
      if (res.statusCode == 200) return OauthToken.fromText(res.body, provider: 'microsoft');
      switch (j['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        default:
          throw _message(j);
      }
    }
    throw 'The code expired. Try again.';
  }

  static Future<OauthToken> refresh(String clientId, OauthToken token) async {
    final res = await _post('$_base/token', {
      'grant_type': 'refresh_token',
      'client_id': clientId,
      'refresh_token': token.refreshToken,
      'scope': scopes,
    });
    if (res.statusCode != 200) throw _message(_json(res));
    return OauthToken.fromText(res.body, provider: 'microsoft', refreshToken: token.refreshToken);
  }

  static Future<http.Response> _post(String url, Map<String, String> body) async {
    try {
      return await http.post(Uri.parse(url), body: body).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw 'Microsoft sign-in is not answering. Check your connection and try again.';
    }
  }

  /// The answer as JSON; an error page or captive portal becomes a readable message.
  static Map<String, dynamic> _json(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw 'Microsoft sign-in answered ${res.statusCode}. Check your connection and try again.';
    }
  }

  static String _message(Map<String, dynamic> j) {
    final d = (j['error_description'] as String?)?.split('\n').first ?? j['error']?.toString() ?? 'Unknown error';
    if (d.contains('AADSTS700016')) return 'Microsoft does not know this client ID. Check it in your app registration.';
    if (d.contains('AADSTS7000218')) return 'Turn on "Allow public client flows" in your app registration.';
    return d;
  }
}

class DeviceCode {
  DeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.url,
    required this.interval,
    required this.expiresIn,
  });
  final String deviceCode;
  final String userCode;
  final String url;
  final int interval;
  final int expiresIn;
}
