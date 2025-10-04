import 'package:diagnoplus/features/profile/presentation/pages/supportScreen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

// افتراضياً لديك شاشة تعديل وسجل مواعيد جاهزين
import '../../../appointments/presentation/appointments_screen.dart';
import '../../../appointments/presentation/pages/appointments_list_screen.dart';
import '../../../doctor/presentation/appointments_management_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? userId;
  bool isLoading = true;

  // بيانات المستخدم
  String fullName = '';
  String email = '';
  String phone = '';
  String gender = '';
  int? age;
  String workPlace = '';
  String? profileImageUrl;
  bool isDoctor = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    userId = user.uid;
    email = user.email ?? '';

    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    final data = doc.data()!;
    setState(() {
      fullName = data['fullName'] ?? '';
      phone = data['phone'] ?? '';
      gender = data['gender'] ?? '';
      age = int.tryParse(data['age']?.toString() ?? '');
      workPlace = data['workPlace'] ?? '';
      profileImageUrl = data['photoURL'];
      isDoctor = data['accountType'] == 'doctor';
      isLoading = false;
    });
  }

  void _logout() async {
    await _auth.signOut();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }


  Future<void> _NavigatorSupportScreen() async{
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SupportScreen()),
    );
  }



  Future<void> _launchSupportEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@diagnoplus.com',
      queryParameters: {
        'subject': 'طلب دعم فني - $fullName',
        'body': 'السلام عليكم،\n\nأحتاج إلى مساعدة بخصوص...',
      },
    );

    if (await canLaunch(emailLaunchUri.toString())) {
      await launch(emailLaunchUri.toString());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن فتح تطبيق البريد')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 2,
        title: const Text('الملف الشخصي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            tooltip: 'تعديل الملف الشخصي',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditProfileScreen(
                    userId: userId!,
                  ),
                ),
              ).then((_) {
                _loadUserProfile();
              });
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // صورة المستخدم
            CircleAvatar(
              radius: 60,
              backgroundImage: profileImageUrl != null && profileImageUrl!.isNotEmpty
                  ? NetworkImage(profileImageUrl!)
                  : null,
              child: profileImageUrl == null || profileImageUrl!.isEmpty
                  ? const Icon(Icons.person, size: 60)
                  : null,
            ),
            const SizedBox(height: 16),

            // الاسم والبريد
            Text(
              fullName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(email, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),

            // معلومات الملف الشخصي
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text(phone.isNotEmpty ? phone : 'غير محدد'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(gender.isNotEmpty ? gender : 'غير محدد'),
            ),
            ListTile(
              leading: const Icon(Icons.cake),
              title: Text(age != null ? '$age سنة' : 'غير محدد'),
            ),

            if (isDoctor)
              ListTile(
                leading: const Icon(Icons.work),
                title: Text(workPlace.isNotEmpty ? workPlace : 'غير محدد'),
              ),

            const SizedBox(height: 24),

            // بطاقات الخيارات
            if (isDoctor)
              _buildOptionCard(
                icon: Icons.dashboard,
                color: Colors.teal,
                title: 'لوحة تحكم الطبيب',
                onTap: () => Navigator.pushNamed(context, '/doctorDashboard'),
              ),

            _buildOptionCard(
              icon: Icons.calendar_today,
              color: Colors.blue,
              title: 'سجل المواعيد',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AppointmentsListScreen()),
              ),
            ),

            // بطاقة الدعم الفني الجديدة
            _buildOptionCard(
              icon: Icons.support_agent,
              color: Colors.purple,
              title: 'الدعم الفني',
              onTap: _NavigatorSupportScreen,
            ),

            // بطاقة الإعدادات الجديدة
            _buildOptionCard(
              icon: Icons.settings,
              color: Colors.orange,
              title: 'الإعدادات',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AppointmentsManagementScreen(),)),
            ),

            _buildOptionCard(
              icon: Icons.logout,
              color: Colors.red,
              title: 'تسجيل الخروج',
              onTap: _logout,
              showTrailingIcon: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
    bool showTrailingIcon = true,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: showTrailingIcon
            ? const Icon(Icons.arrow_forward_ios, size: 18)
            : null,
        onTap: onTap,
      ),
    );
  }
}