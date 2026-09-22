import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class BackcourtApiClient {
  BackcourtApiClient({FirebaseAuth? auth, http.Client? client, String? baseUrl})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? defaultBaseUrl;

  static const defaultBaseUrl = String.fromEnvironment(
    'BACKCOURT_API_URL',
    defaultValue: 'https://backcourt.kro.kr',
  );

  final FirebaseAuth _auth;
  final http.Client _client;
  final String _baseUrl;

  Future<void> deletePost(String postId) => _delete('/api/posts/$postId');

  Future<void> deleteAccount() => _delete('/api/account');

  Future<void> _delete(String path) async {
    final user = _auth.currentUser;
    if (user == null) throw const BackcourtApiException('로그인이 필요해요.');
    final token = await user.getIdToken();
    final response = await _client
        .delete(
          Uri.parse('${_baseUrl.replaceFirst(RegExp(r'/$'), '')}$path'),
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer $token',
            HttpHeaders.contentTypeHeader: 'application/json',
          },
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String? detail;
    try {
      final body = jsonDecode(response.body);
      if (body is Map) detail = body['detail']?.toString();
    } catch (_) {}
    throw BackcourtApiException(detail ?? '서버 요청을 처리하지 못했어요.');
  }
}

class BackcourtApiException implements Exception {
  const BackcourtApiException(this.message);

  final String message;
}
