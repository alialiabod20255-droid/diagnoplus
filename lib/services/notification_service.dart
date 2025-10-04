import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    final InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_navigateToNotification);
  }

  Future<String?> getDeviceToken() async {
    return await _firebaseMessaging.getToken();
  }

  Future<void> sendNotification({
    required String token,
    required String title,
    required String body,
    String? consultationId,
  }) async {
    try {
      // الطريقة الصحيحة لإرسال إشعار عبر FCM
      await _firebaseMessaging.sendMessage(
        to: token,
        data: {
          'title': title,
          'body': body,
          'consultationId': consultationId ?? '',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );

      // أو يمكنك استخدام هذا البديل إذا أردت إرسال إشعار مباشر
      /*
      await _firebaseMessaging.sendMessage(
        to: token,
        notification: RemoteNotification(
          title: title,
          body: body,
        ),
        data: {
          'consultationId': consultationId ?? '',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      );
      */
    } catch (e) {
      print('Error sending notification: $e');
      // يمكنك هنا إرسال الإشعار عبر Firestore كبديل
      await _sendNotificationViaFirestore(
        token: token,
        title: title,
        body: body,
        consultationId: consultationId,
      );
    }
  }

  Future<void> _sendNotificationViaFirestore({
    required String token,
    required String title,
    required String body,
    String? consultationId,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'to': token,
        'title': title,
        'body': body,
        'consultationId': consultationId,
        'createdAt': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      print('Error saving notification to Firestore: $e');
    }
  }

  void _showNotification(RemoteMessage message) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'consultation_channel',
      'استشارات طبية',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    _flutterLocalNotificationsPlugin.show(
      0,
      message.notification?.title ?? message.data['title'],
      message.notification?.body ?? message.data['body'],
      platformChannelSpecifics,
      payload: message.data['consultationId'],
    );
  }

  void _navigateToNotification(RemoteMessage message) {
    // Handle navigation when notification is tapped
    final consultationId = message.data['consultationId'];
    if (consultationId != null && consultationId.isNotEmpty) {
      // يمكنك استخدام Navigator هنا للانتقال إلى شاشة الاستشارة
    }
  }
}