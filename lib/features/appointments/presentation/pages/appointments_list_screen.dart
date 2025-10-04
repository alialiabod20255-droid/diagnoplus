import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../../../services/appointment_service.dart';
import '../../../model.dart';
import 'appointment_details_screen.dart';

class AppointmentsListScreen extends StatefulWidget {
  const AppointmentsListScreen({super.key});

  @override
  State<AppointmentsListScreen> createState() => _AppointmentsListScreenState();
}

class _AppointmentsListScreenState extends State<AppointmentsListScreen> {
  String selectedStatus = 'الكل';
  DateTime? selectedDate;

  bool _isDeleting = false; // حالة حذف الموعد

  @override
  Widget build(BuildContext context) {
    final appointmentService = Provider.of<AppointmentService>(context);
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 1,
        title: const Text('جميع المواعيد'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(currentUserId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final accountType = userData['accountType'];

          return StreamBuilder<List<Appointment>>(
            stream: appointmentService.getAppointments(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return const Center(child: Text('حدث خطأ أثناء تحميل المواعيد'));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('لا توجد مواعيد'));
              }

              var appointments = snapshot.data!
                  .where((appointment) => accountType == 'doctor'
                  ? appointment.doctorId == currentUserId
                  : appointment.userId == currentUserId)
                  .toList();

              if (selectedStatus != 'الكل') {
                appointments = appointments.where((a) => a.status == selectedStatus).toList();
              }

              if (selectedDate != null) {
                appointments = appointments.where((a) {
                  final date = a.date.toDate(); // ✅ تحويل Timestamp إلى DateTime
                  return date.year == selectedDate!.year &&
                      date.month == selectedDate!.month &&
                      date.day == selectedDate!.day;
                }).toList();
              }


              if (appointments.isEmpty) {
                return const Center(child: Text('لا توجد مواعيد مطابقة'));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                itemCount: appointments.length,
                itemBuilder: (context, index) {
                  final appointment = appointments[index];

                  final displayName = accountType == 'doctor'
                      ? (appointment.userName ?? 'مريض')
                      : (appointment.doctorName ?? 'طبيب');

                  final displayImageUrl = accountType == 'doctor'
                      ? (appointment.userImageUrl ?? '')
                      : (appointment.doctorImageUrl ?? '');

                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundImage: displayImageUrl.isNotEmpty
                            ? NetworkImage(displayImageUrl)
                            : const AssetImage('assets/images/user_placeholder.png')
                        as ImageProvider,
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      subtitle: Text('${appointment.formattedDate} الساعة ${appointment.formattedTime}'),
                      trailing: Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(Icons.circle, color: _statusColor(appointment.status), size: 14),
                          IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            tooltip: 'إلغاء الموعد',
                            onPressed: _isDeleting
                                ? null
                                : () => _confirmDelete(context, appointment.id),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AppointmentDetailsScreen(appointment: appointment),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, String appointmentId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإلغاء'),
        content: const Text('هل أنت متأكد من إلغاء هذا الموعد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _deleteAppointment(appointmentId);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAppointment(String appointmentId) async {
    setState(() => _isDeleting = true);
    try {
      await FirebaseFirestore.instance.collection('appointments').doc(appointmentId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء الموعد بنجاح')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الإلغاء: $e')),
      );
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  final Map<String, String> statusLabels = {
    'الكل': 'الكل',
    'pending': 'قيد الانتظار',
    'confirmed': 'مؤكد',
    'in_session': 'داخل المعاينة',
    'canceled': 'ملغي',
  };

  void _showFilterDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('تصفية حسب الحالة:', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: statusLabels.entries.map((entry) {
                final statusKey = entry.key;
                final statusLabel = entry.value;

                return ChoiceChip(
                  label: Text(statusLabel),
                  selected: selectedStatus == statusKey,
                  onSelected: (_) {
                    setState(() => selectedStatus = statusKey);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('تصفية حسب التاريخ:', style: TextStyle(fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              icon: const Icon(Icons.date_range),
              label: const Text('اختر التاريخ'),
              onPressed: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (pickedDate != null) {
                  setState(() => selectedDate = pickedDate);
                }
                Navigator.pop(context);
              },
            ),
            if (selectedDate != null)
              TextButton(
                onPressed: () => setState(() => selectedDate = null),
                child: const Text('إزالة تاريخ التصفية'),
              )
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
