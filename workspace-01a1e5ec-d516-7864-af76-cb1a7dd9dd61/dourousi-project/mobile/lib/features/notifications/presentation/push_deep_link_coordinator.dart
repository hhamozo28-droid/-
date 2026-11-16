import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../auth/data/auth_repository.dart';

/// Coordinates both:
/// 1. Native Android App Links / iOS Universal Links (`https://dourousi.app/m/ELE0701` or `dourousi://m/ELE0701`)
/// 2. Firebase Cloud Messaging (FCM) Push Notifications (foreground local banners + tap navigation)
class PushAndDeepLinkCoordinator {
  final Ref _ref;
  final AppLinks _appLinks = AppLinks();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<Uri>? _linkSub;

  PushAndDeepLinkCoordinator(this._ref);

  Future<void> initialize(GoRouter router) async {
    // 1. Listen to incoming Universal Links / App Links
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _navigateFromDeepLink(router, initialUri);
      }
      _linkSub = _appLinks.uriLinkStream.listen((uri) {
        _navigateFromDeepLink(router, uri);
      });
    } catch (_) {
      // Safe fallback when running on desktop/test environments
    }

    // 2. Initialize Local Notification Channel for foreground FCM alerts
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) {
        final code = details.payload;
        if (code != null && code.isNotEmpty) {
          router.push('/m/$code');
        }
      },
    );

    // 3. Initialize Firebase Cloud Messaging gracefully (works even before google-services.json is added)
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final fcmToken = await messaging.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _ref
            .read(authRepositoryProvider)
            .syncPreferences(fcmToken: fcmToken);
      }

      messaging.onTokenRefresh.listen((newToken) {
        _ref.read(authRepositoryProvider).syncPreferences(fcmToken: newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        final materialCode = (message.data['materialCode'] ?? '').toString();
        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'dourousi_updates_channel',
                'Dourousi Material Updates',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            payload: materialCode,
          );
        }
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        final code = (message.data['materialCode'] ?? '').toString();
        if (code.isNotEmpty) {
          router.push('/m/$code');
        }
      });
    } catch (_) {
      // Firebase config files are optional in local dev until publisher attaches google-services.json
    }
  }

  void _navigateFromDeepLink(GoRouter router, Uri uri) {
    // Supports https://dourousi.app/m/ELE0701 and dourousi://m/ELE0701
    String? materialCode;
    if (uri.scheme == 'dourousi' && uri.host == 'm' && uri.pathSegments.isNotEmpty) {
      materialCode = uri.pathSegments.first;
    } else if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'm') {
      materialCode = uri.pathSegments[1];
    }

    if (materialCode != null && materialCode.isNotEmpty) {
      router.push('/m/${materialCode.toUpperCase()}');
    }
  }

  void dispose() {
    _linkSub?.cancel();
  }
}

final pushAndDeepLinkCoordinatorProvider =
    Provider<PushAndDeepLinkCoordinator>((ref) {
  final coordinator = PushAndDeepLinkCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
