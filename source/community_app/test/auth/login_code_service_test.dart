import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketworld_flutter/auth/auth_models.dart';
import 'package:pocketworld_flutter/auth/auth_error.dart';
import 'package:pocketworld_flutter/auth/supabase_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

void main() {
  const phone = '+8613800000000';
  const password = 'synthetic-password';
  const id = '00000000-0000-4000-8000-000000000123';
  final authUser = {
    'id': id,
    'aud': 'authenticated',
    'created_at': '2026-11-09T00:00:00Z',
    'phone': phone,
  };
  SupabaseAuthServiceImpl service(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final client = sb.SupabaseClient(
      'https://example.invalid',
      'synthetic',
      authOptions: const sb.AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: sb.AuthFlowType.implicit,
      ),
      httpClient: MockClient((r) async {
        final response = await handler(r);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    return SupabaseAuthServiceImpl(client: client);
  }

  test('phone login code sends cannot create new accounts', () async {
    final requests = <http.Request>[];
    final svc = service((r) async {
      requests.add(r);
      return http.Response('{}', 200);
    });
    await svc.startPhoneVerification(phone);
    expect(requests, hasLength(1));
    for (final r in requests) {
      expect(r.url.path, '/auth/v1/otp');
      final body = jsonDecode(r.body) as Map;
      expect(body['create_user'], false);
      expect(body.containsKey('password'), false);
    }
    expect((jsonDecode(requests.first.body) as Map)['phone'], phone);
  });
  test(
    'signup sends password and selected nickname before SMS verification',
    () async {
      final requests = <http.Request>[];
      final svc = service((r) async {
        requests.add(r);
        return http.Response(jsonEncode({'user': authUser}), 200);
      });
      final challenge = await svc.startPhoneSignup(
        phoneNumber: phone,
        password: password,
        displayName: 'chosen nickname',
      );
      expect(challenge.phoneNumber, phone);
      expect(requests, hasLength(1));
      final r = requests.single;
      expect(r.url.path, '/auth/v1/signup');
      final body = jsonDecode(r.body) as Map;
      expect(body['phone'], phone);
      expect(body['password'], password);
      expect(body['data']['display_name'], 'chosen nickname');
      expect(body['channel'], 'sms');
    },
  );
  test(
    'weak signup password and legacy signup OTP flag cannot send SMS',
    () async {
      var requests = 0;
      final svc = service((r) async {
        requests++;
        return http.Response('{}', 200);
      });
      await expectLater(
        svc.startPhoneSignup(
          phoneNumber: phone,
          password: 'short',
          displayName: 'chosen',
        ),
        throwsA(isA<AuthException>()),
      );
      await expectLater(
        svc.startPhoneVerification(phone, forSignUp: true),
        throwsA(isA<AuthException>()),
      );
      expect(requests, 0);
    },
  );
  test(
    'phone code login verifies SMS purpose and hydrates the canonical profile',
    () async {
      final requests = <http.Request>[];
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      final claims = base64Url.encode(utf8.encode(jsonEncode({'exp': exp})));
      final session = {
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': authUser,
      };
      final svc = service((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.url.path == '/auth/v1/verify'
                ? session
                : [
                    {'id': id, 'display_name': 'canonical'},
                  ],
          ),
          200,
        );
      });
      final user = await svc.signIn(
        const SignInRequest.phone(
          phoneNumber: phone,
          verificationID: phone,
          code: '123456',
        ),
      );
      expect(user.id.rawValue, id);
      expect(user.displayName, 'canonical');
      final r = requests.first;
      expect(r.url.path, '/auth/v1/verify');
      final body = jsonDecode(r.body) as Map;
      expect(body['type'], 'sms');
      expect(body['phone'], phone);
      expect(body['token'], '123456');
      expect(
        requests.any(
          (r) =>
              r.url.path.contains('signup') ||
              r.url.path.contains('password-recovery'),
        ),
        false,
      );
    },
  );
}
