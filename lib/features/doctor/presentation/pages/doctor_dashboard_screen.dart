import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/theme.dart';
import '../../../appointments/presentation/pages/appointment_details_screen.dart';
import '../../../home/presentation/pages/home_screen.dart';
import '../../../model.dart';
import '../../dashboard/appointments_screen.dart';
import '../../dashboard/bookings_screen.dart';
import '../../dashboard/performance_screen.dart';

class DoctorDashboardScreen extends StatefulWidget {
  const DoctorDashboardScreen({super.key});

  @override
  State<DoctorDashboardScreen> createState() => _DoctorDashboardScreenState();
}

class _DoctorDashboardScreenState extends State<DoctorDashboardScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  int todayAppointments = 0;
  int newBookings = 0;
  double monthlyPerformance = 0.0;

  List<Map<String, dynamic>> appointmentsList = [];
  List<Map<String, dynamic>> urgentMessages = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final doctorId = _auth.currentUser?.uid;
    if (doctorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تسجيل الدخول لعرض البيانات'),
          backgroundColor: AppTheme.alertRed,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day, 0, 0, 0); // بداية اليوم
    final endOfDay = startOfDay.add(const Duration(days: 1)); // نهاية اليوم
    final monthStart = DateTime(now.year, now.month, 1);

    try {
      // مواعيد اليوم
      final todaySnap = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .orderBy('date', descending: true) // ترتيب المواعيد حسب التاريخ
          .get();

      // تصحيح: طباعة عدد المواعيد وبياناتها
      print('عدد مواعيد اليوم: ${todaySnap.size}');
      for (var doc in todaySnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final date = (data['date'] as Timestamp?)?.toDate();
        print('موعد ID: ${doc.id}, التاريخ: $date, الحالة: ${data['status']}, المريض: ${data['userName']}');
      }

      // الحجوزات الجديدة
      final newSnap = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      // الأداء الشهري
      final monthSnap = await _firestore
          .collection('appointments')
          .where('doctorId', isEqualTo: doctorId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .get();

      // الرسائل العاجلة
      final msgSnap = await _firestore
          .collection('consultations')
          .where('doctorId', isEqualTo: doctorId)
          .where('type', isEqualTo: 'instant')
          .where('hasNewMessage', isEqualTo: true)
          .get();

      setState(() {
        todayAppointments = todaySnap.size;
        newBookings = newSnap.size;
        monthlyPerformance = monthSnap.size == 0
            ? 0
            : (monthSnap.docs.where((doc) => doc['status'] == 'attended').length /
            monthSnap.size) *
            100;
        appointmentsList = todaySnap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();
        urgentMessages =
            msgSnap.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      });
    } catch (e) {
      print('خطأ في تحميل البيانات: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل البيانات: $e'),
          backgroundColor: AppTheme.alertRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 2,
        title: const Text('لوحة تحكم الطبيب'),
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              // TODO: الانتقال إلى صفحة الإشعارات
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatsSection(),
              const SizedBox(height: 24),
              _buildTodayAppointments(),
              const SizedBox(height: 24),
              _buildUrgentMessages(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatCard(
          'مواعيد اليوم',
          '$todayAppointments',
          Icons.calendar_today,
          AppTheme.primaryBlue,
              () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AppointmentsScreen())),
        ),
        _buildStatCard(
          'حجوزات جديدة',
          '$newBookings',
          Icons.notifications,
          AppTheme.positiveGreen,
              () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const BookingsScreen())),
        ),
        _buildStatCard(
          'الأداء الشهري',
          '${monthlyPerformance.toStringAsFixed(1)}%',
          Icons.bar_chart,
          Colors.orange,
              () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const PerformanceScreen())),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayAppointments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'مواعيد اليوم',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppointmentsScreen()));
              },
              child: const Text('عرض الكل', style: TextStyle(color: AppTheme.primaryBlue)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (appointmentsList.isEmpty)
          const Text('لا توجد مواعيد اليوم'),
        ...appointmentsList.take(3).map((data) {
          final patientName = data['userName'] ?? 'مريض';
          final reason = data['reason'] ?? 'سبب غير معروف';
          final time = data['date'] != null
              ? DateFormat('hh:mm a', 'ar').format((data['date'] as Timestamp).toDate())
              : 'بدون وقت';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage:
                data['userImageUrl'] != null ? NetworkImage(data['userImageUrl']) : null,
                child: data['userImageUrl'] == null ? const Icon(Icons.person) : null,
              ),
              title: Text(patientName),
              subtitle: Text('$time - $reason'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                try {
                  final appointment = Appointment(
                    id: data['id'] ?? '',
                    userId: data['userId'] ?? '',
                    userName: data['userName'] ?? 'مريض',
                    userImageUrl: data['userImageUrl'],
                    userPhone: data['userPhone'],
                    doctorId: data['doctorId'] ?? '',
                    doctorName: data['doctorName'] ?? 'طبيب',
                    doctorImageUrl: data['doctorImageUrl'],
                    doctorPhone: data['doctorPhone'],
                    specialtyName: data['specialtyName'] ?? '',
                    date: data['date'] ?? Timestamp.now(),
                    time: data['time'] ?? '',
                    workplace: data['workplace'] ?? '',
                    payment: data['payment'] ?? '',
                    status: data['status'] ?? 'pending',
                    createdAt: data['createdAt'] ?? Timestamp.now(),
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AppointmentDetailsScreen(appointment: appointment),
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('خطأ في عرض تفاصيل الموعد: $e'),
                      backgroundColor: AppTheme.alertRed,
                    ),
                  );
                }
              },
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildUrgentMessages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'رسائل عاجلة من المرضى',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (urgentMessages.isEmpty)
          const Text('لا توجد رسائل عاجلة حالياً'),
        ...urgentMessages.take(3).map((msg) {
          final userName = msg['userName'] ?? 'مريض';
          final specialty = msg['specialty'] ?? '';
          final createdAt = msg['createdAt'] != null
              ? DateFormat('hh:mm a', 'ar').format((msg['createdAt'] as Timestamp).toDate())
              : '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.message, color: AppTheme.alertRed),
              title: Text('استشارة عاجلة - $userName'),
              subtitle: Text('$specialty - $createdAt'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                // TODO: فتح المحادثة
              },
            ),
          );
        }).toList(),
      ],
    );
  }
}