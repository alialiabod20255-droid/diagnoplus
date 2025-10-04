import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../model.dart';

class AppointmentDetailsScreen extends StatefulWidget {
  final Appointment appointment;

  const AppointmentDetailsScreen({Key? key, required this.appointment}) : super(key: key);

  @override
  State<AppointmentDetailsScreen> createState() => _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState extends State<AppointmentDetailsScreen> {
  bool isDoctor = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkUserType();
  }

  Future<void> _markInSession() async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointment.id)
          .update({'status': 'in_session'});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إدخال المريض إلى المعاينة')),
      );

      setState(() {
        widget.appointment.status = 'in_session';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل في التحديث: $e')),
      );
    }
  }


  Future<void> _checkUserType() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserId).get();
      final userData = userDoc.data() as Map<String, dynamic>;
      setState(() {
        isDoctor = userData['accountType'] == 'doctor';
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Error checking user type: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.appointment.date.toDate();
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 2,
        title: const Text('تفاصيل الموعد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // بطاقة بيانات المستخدم
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundImage: NetworkImage(
                          isDoctor
                              ? widget.appointment.userImageUrl ?? ''
                              : widget.appointment.doctorImageUrl ?? '',
                        ),
                        onBackgroundImageError: (_, __) {},
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDoctor
                                  ? widget.appointment.userName
                                  : widget.appointment.doctorName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'رقم الهاتف: ${isDoctor ? widget.appointment.userPhone ?? "غير متوفر" : widget.appointment.doctorPhone ?? "غير متوفر"}',
                            ),
                            const SizedBox(height: 4),
                            if (!isDoctor)
                              Text('المؤهل: ${widget.appointment.specialtyName}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // بطاقة التفاصيل
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTile('المكان', widget.appointment.workplace),
                      const Divider(),
                      _buildTile('التاريخ', formatArabicDate(date)),
                      const Divider(),
                      _buildTile('الوقت', widget.appointment.time),
                      const Divider(),
                      _buildTile('الحالة', _translateStatus(widget.appointment.status)),
                      const Divider(),
                      _buildTile('طريقة الدفع', widget.appointment.payment),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // أزرار الإجراءات
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () => _confirmCancel(context),
                    icon: const Icon(Icons.cancel),
                    label: const Text('إلغاء الموعد'),
                  ),

                  // زر الموافقة على الموعد
                  if (isDoctor && widget.appointment.status == 'pending')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _confirmAppointment,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('الموافقة'),
                    ),

                ],
              ),

              SizedBox(height: 5,),
              // زر دخول المعاينة
              if (isDoctor && widget.appointment.status == 'confirmed')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _markInSession,
                  icon: const Icon(Icons.medical_services),
                  label: const Text('المريض داخل المعاينة'),
                ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTile(String title, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(value.isNotEmpty ? value : '—'),
    );
  }

  String formatArabicDate(DateTime date) {
    return '${date.day} ${getArabicMonthName(date.month)} ${date.year}';
  }

  String getArabicMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[month - 1];
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'confirmed':
        return 'مؤكد';
      case 'in_session':
        return 'داخل المعاينة';
      case 'canceled':
        return 'ملغي';
      default:
        return 'قيد الانتظار';
    }
  }


  void _confirmCancel(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإلغاء'),
        content: const Text('هل أنت متأكد أنك تريد إلغاء هذا الموعد؟'),
        actions: [
          TextButton(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('نعم، إلغاء'),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('appointments')
                    .doc(widget.appointment.id)
                    .delete();

                Navigator.pop(ctx); // إغلاق مربع الحوار
                Navigator.pop(context); // الرجوع للخلف
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم إلغاء الموعد بنجاح')),
                );
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('فشل في إلغاء الموعد: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAppointment() async {
    try {
      await FirebaseFirestore.instance
          .collection('appointments')
          .doc(widget.appointment.id)
          .update({'status': 'confirmed'});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الموافقة على الموعد')),
      );

      setState(() {
        widget.appointment.status = 'confirmed'; // محدث فقط للعرض الحالي
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل في الموافقة: $e')),
      );
    }
  }
}
