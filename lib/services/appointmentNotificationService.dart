import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:hive/hive.dart';
import '../features/model.dart';

class AppointmentNotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  void listenToAppointments(String userId) {
    _firestore
        .collection('appointments')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'];
        final approvedNotified = data['notified'] == true;
        final date = data['date'];
        final timeStr = data['time'];
        final docId = doc.id;

        if (status == 'approved' && !approvedNotified) {
          _scheduleAppointmentNotifications(data, docId);
          doc.reference.update({'notified': true});
        } else if (status == 'cancelled' && !approvedNotified) {
          final reason = data['cancelReason'] ?? 'لم يتم تحديد سبب.';
          _showCancelledNotification(reason);
          doc.reference.update({'notified': true});
        }
      }
    });
  }

  Future<void> _scheduleAppointmentNotifications(Map<String, dynamic> data, String docId) async {
    final date = (data['date'] as Timestamp).toDate();
    final time = _parseTimeOfDay(data['time']);
    final scheduledDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final title = 'موعد مع الطبيب';
    final body = 'لديك موعد مع الدكتور ${data['doctorName']} في ${data['workplace']}';

    final scheduleTimes = [
      Duration(days: -1),      // قبل بيوم
      Duration(hours: -6),     // قبل 6 ساعات
      Duration(hours: -1),     // قبل ساعة
      Duration.zero,           // في الوقت نفسه
    ];

    for (int i = 0; i < scheduleTimes.length; i++) {
      final tzTime = tz.TZDateTime.from(scheduledDateTime.add(scheduleTimes[i]), tz.local);
      final id = (docId.hashCode + i) & 0x7FFFFFFF;

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'appointment_channel',
            'تنبيهات المواعيد',
            channelDescription: 'إشعارات تنبيهية بمواعيد الطبيب',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );

      // حفظ في Hive لعرضه لاحقًا
      final box = await Hive.openBox('local_notifications');
      await box.add(LocalNotificationModel(
        title: title,
        body: body,
        scheduledTime: tzTime.toLocal(),
        type: 'appointment',
      ).toMap());
    }
  }

  Future<void> _showCancelledNotification(String reason) async {
    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'تم إلغاء الموعد',
      reason,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'appointment_channel',
          'تنبيهات المواعيد',
          channelDescription: 'إشعارات تنبيهية بمواعيد الطبيب',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );

    final box = await Hive.openBox('local_notifications');
    await box.add(LocalNotificationModel(
      title: 'تم إلغاء الموعد',
      body: reason,
      scheduledTime: DateTime.now(),
      type: 'cancelled',
    ).toMap());
  }

  TimeOfDay _parseTimeOfDay(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}
