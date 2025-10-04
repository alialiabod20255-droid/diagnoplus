import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  Future<void> _markAsRead(String docId) async {
    await FirebaseFirestore.instance.collection('notifications').doc(docId).update({
      'isRead': true,
    });
  }

  Future<void> _deleteNotification(String docId, BuildContext context) async {
    await FirebaseFirestore.instance.collection('notifications').doc(docId).delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف الإشعار')),
    );
  }

  Future<void> _deleteAllNotifications(BuildContext context) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final collection = FirebaseFirestore.instance.collection('notifications');
    final snapshots = await collection.where('userId', isEqualTo: currentUserId).get();

    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حذف جميع الإشعارات')),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} - ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('يرجى تسجيل الدخول لعرض الإشعارات')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 2,
        title: const Text('الإشعارات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'حذف جميع الإشعارات',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تأكيد الحذف'),
                  content: const Text('هل أنت متأكد من حذف جميع الإشعارات؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('حذف'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await _deleteAllNotifications(context);
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: currentUserId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('حدث خطأ في تحميل الإشعارات'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('لا توجد إشعارات'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] ?? false;

              return ListTile(
                tileColor: isRead ? theme.dividerColor : theme.cardColor,
                title: Text(data['title'] ?? ''),
                subtitle: Text(data['body'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTimestamp(data['createdAt']),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'حذف الإشعار',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('تأكيد الحذف'),
                            content: const Text('هل تريد حذف هذا الإشعار؟'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('إلغاء'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _deleteNotification(doc.id, context);
                        }
                      },
                    ),
                  ],
                ),
                onTap: () async {
                  if (!isRead) {
                    await _markAsRead(doc.id);
                  }
                  // اضافة أي إجراء آخر عند الضغط مثل التنقل لصفحة تفاصيل الاشعار
                },
              );
            },
          );
        },
      ),
    );
  }
}
