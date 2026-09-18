import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'backcourt_repository.dart';

typedef PushOpenHandler = void Function(Map<String, dynamic> data);

class PushNotificationService {
  PushNotificationService({
    required this.repository,
    required this.onOpen,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    http.Client? httpClient,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin(),
       _httpClient = httpClient ?? http.Client();

  static const apiBaseUrl = String.fromEnvironment('BACKCOURT_API_URL');
  static const _channelId = 'backcourt_activity';

  final BackcourtRepository repository;
  final PushOpenHandler onOpen;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final http.Client _httpClient;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _started = false;

  bool get isConfigured => apiBaseUrl.trim().isNotEmpty;

  Future<void> start() async {
    if (_started || !isConfigured) return;
    _started = true;
    try {
      await _initializeLocalNotifications();
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      _tokenSubscription = _messaging.onTokenRefresh.listen(
        (token) => unawaited(_registerWithRetry(token)),
      );
      _messageSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedMessage,
      );

      final token = await _getTokenWithRetry();
      if (token != null) unawaited(_registerWithRetry(token));

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) _handleOpenedMessage(initialMessage);
    } catch (error) {
      debugPrint('Push initialization failed: $error');
    }
  }

  Future<void> unregister() async {
    if (!isConfigured) return;
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      final request = http.Request('DELETE', _endpoint('/api/push/devices'))
        ..headers.addAll(await _headers())
        ..body = jsonEncode({'token': token});
      final response = await _httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Push token unregister failed: ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('Push token unregister failed: $error');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('ic_stat_backcourt');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: android, iOS: iOS),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = Map<String, dynamic>.from(
            jsonDecode(payload) as Map,
          );
          _open(data);
        } catch (error) {
          debugPrint('Push payload parse failed: $error');
        }
      },
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              '빽코트 활동',
              description: 'LIVE, 약속, 댓글과 제보 처리 알림',
              importance: Importance.high,
            ),
          );
    }
  }

  Future<String?> _getTokenWithRetry() async {
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final token = await _messaging.getToken();
        if (token != null && token.isNotEmpty) return token;
      } catch (error) {
        if (attempt == 3) debugPrint('FCM token unavailable: $error');
      }
      await Future<void>.delayed(Duration(seconds: attempt + 1));
    }
    return null;
  }

  Future<void> _registerWithRetry(String token) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _httpClient.post(
          _endpoint('/api/push/devices'),
          headers: await _headers(),
          body: jsonEncode({
            'token': token,
            'platform': Platform.isIOS ? 'ios' : 'android',
          }),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) return;
        if (response.statusCode == 401) return;
        throw HttpException('Push API ${response.statusCode}');
      } catch (error) {
        if (attempt == 2) {
          debugPrint('Push token registration failed: $error');
          return;
        }
        await Future<void>.delayed(Duration(seconds: (attempt + 1) * 3));
      }
    }
  }

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const HttpException('Authentication required');
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const HttpException('Firebase ID token unavailable');
    }
    return {
      HttpHeaders.authorizationHeader: 'Bearer $idToken',
      HttpHeaders.contentTypeHeader: 'application/json',
    };
  }

  Uri _endpoint(String path) => Uri.parse(
    '${apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '')}$path',
  );

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (!Platform.isAndroid || message.notification == null) return;
    final notification = message.notification!;
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification.title ?? '빽코트',
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          '빽코트 활동',
          channelDescription: 'LIVE, 약속, 댓글과 제보 처리 알림',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_backcourt',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleOpenedMessage(RemoteMessage message) => _open(message.data);

  void _open(Map<String, dynamic> data) {
    final notificationId = data['notificationId']?.toString();
    if (notificationId?.isNotEmpty == true) {
      unawaited(repository.markNotificationRead(notificationId!));
    }
    onOpen(data);
  }

  void dispose() {
    _tokenSubscription?.cancel();
    _messageSubscription?.cancel();
    _openedSubscription?.cancel();
    _httpClient.close();
  }
}
