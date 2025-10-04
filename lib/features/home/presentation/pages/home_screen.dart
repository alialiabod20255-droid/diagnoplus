import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diagnoplus/features/consultations/presentation/pages/instant_consultation_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/widgets/upcoming_appointments_widget.dart';
import '../../../../services/appointment_service.dart';
import '../../../../services/health_News_Service.dart';
import '../../../../services/internet_checker_service.dart';
import '../../../../services/medication_service.dart';
import '../../../appointments/presentation/pages/appointments_list_screen.dart';
import '../../../appointments/presentation/pages/book_appointment_screen.dart';
import '../../../doctor/presentation/doctorsListScreen.dart';
import '../../../doctor/presentation/doctorsListWidget.dart';
import '../../../healthNews/medical_news_widget.dart';
import '../../../healthNews/medical_tips_widget.dart';
import '../../../medications/presentation/pages/medications_screen.dart';
import '../../../model.dart';
import '../../../profile/presentation/pages/profile_screen.dart';
import 'package:http/http.dart' as http;

import 'UpcomingMedicationsSection.dart';

import 'notificationsScreen.dart'; // ← مهم لتحويل JSON

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  bool isLoadingNews = true;

  String userName = "";
  String userType = "patient";
  String selectedMood = "";
  int unreadNotifications = 0;
  bool hasCriticalAlert = false;
  bool hasInternet = true;
  bool isLoading = true;
  bool isLoadingAppointments = false;
  bool isLoadingMedications = false;
  int _currentIndex = 0;
  UserModel? currentUserModel;

  List<Appointment> appointments = [];
  List<Map<String, dynamic>> medications = [];
  List<Map<String, dynamic>> healthNews = [];
  Map<String, dynamic> healthStats = {
    'bloodPressure': '120/80',
    'bloodSugar': '110',
    'steps': '6500'
  };
  List<HealthNewsItem> chronicTips = [], nutritionTips = [], preventionTips = [], medicalNews = [];

  bool isLoadingNewsTips = true;

  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _checkConnection();
    print('Current UID=================: ${FirebaseAuth.instance.currentUser!.uid}');
  }

// ستدعاء دالة التحقق من الاتصال ب الانترنت
  Future<void> _checkConnection() async {
    final hasConnection = await InternetCheckerService.hasInternet();
    setState(() {
      _isConnected = hasConnection;
    });
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      _fetchUserData(),
      _fetchAppointments(),
      _fetchMedications(),
      _fetchHealthNews(),
      _fetchHealthStats(),
      _fetchCurrentUser(),
      _loadTipsAndNews(),
      _fetchHealthNewss()

    ]);
  }

  Future<void> _fetchCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    setState(() {
      currentUserModel = UserModel.fromFirestore(doc);
    });
  }

  Future<void> _loadTipsAndNews() async {
    final tips1 = await HealthNewsService.fetchChronicDiseaseTips();
    final tips2 = await HealthNewsService.fetchNutritionTips();
    final tips3 = await HealthNewsService.fetchPreventionTips();
    final newsList = await HealthNewsService.fetchNutritionTips();
    if (!mounted) return;
    setState(() {
      chronicTips = tips1;
      nutritionTips = tips2;
      preventionTips = tips3;
      medicalNews = newsList;
    });
  }

  Future<void> _fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            userName = doc.data()?['fullName']?.toString() ?? "مستخدم";
            userType = doc.data()?['accountType']?.toString() ?? "patient";
            selectedMood = doc.data()?['mood']?.toString() ?? "";
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  String formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

// تستخدم هذا لتعريب التاريخ
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

  Future<void> _fetchAppointments() async {
    setState(() => isLoadingAppointments = true);

    try {
      final appointmentService = Provider.of<AppointmentService>(context, listen: false);
      final userAppointments = await appointmentService.getAppointments().first;

      setState(() {
        appointments = userAppointments; // <-- أصبح List<Appointment>
        for (var appointment in appointments) {
          debugPrint('Appointment ID: ${appointment.id}');
          debugPrint('DoctorId: ${appointment.doctorId}, UserId: ${appointment.userId}');
          debugPrint('Date: ${appointment.date.toDate()}');
        }

      });

      debugPrint('Loaded appointments: ${appointments.length}');
      if (appointments.isNotEmpty) {
        debugPrint('First appointment: ${appointments.first}');
      }
    } catch (e) {
      debugPrint('Error fetching appointments: $e');
      setState(() => appointments = []);
    } finally {
      setState(() => isLoadingAppointments = false);
    }
  }

  Future<void> _fetchMedications() async {
    setState(() => isLoadingMedications = true);
    try {
      final medicationService =
      Provider.of<MedicationService>(context, listen: false);

      // استدعاء قائمة الأدوية من المزود
      final userMedications = await medicationService.getMedications().first;

      // تحويل كل دواء إلى خريطة (Map) تحتوي على جميع الخصائص المطلوبة
      setState(() {
        medications = userMedications
            .take(2)
            .map((medication) => {
          "id": medication.id,
          "name": medication.name,
          "dose": medication.dose,
          "schedule": medication.schedule,
          "next": medication.next,
          "userId": medication.userId,
          "history": medication.history,
          "times": medication.times, // ✅ تم الإضافة
        })
            .toList();
      });
    } catch (e) {
      debugPrint('Error fetching medications: $e');
      setState(() => medications = []);
    } finally {
      setState(() => isLoadingMedications = false);
    }
  }

  Future<void> _fetchHealthNewss() async {
    try {
      chronicTips = await HealthNewsService.fetchChronicDiseaseTips();
      medicalNews = await HealthNewsService.fetchNutritionTips();
      // أضف المزيد إذا أردت التغذية والوقاية
      if (mounted) setState(() {});
    } catch (e) {
      print('خطأ أثناء تحميل الأخبار: $e');
    }
  }

  Future<void> _fetchHealthNews() async {
    const apiKey = '549d849192e84b2d9c96d5e29f8ff3c5'; // ← تأكد من صلاحية المفتاح
    final url = Uri.parse(
      'https://newsapi.org/v2/everything?q=الصحة OR الطب OR الوقاية OR العلاج&language=ar&sortBy=publishedAt&apiKey=$apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List articles = data['articles'];

        setState(() {
          healthNews = articles.map((e) {
            return {
              'title': e['title'] ?? 'بدون عنوان',
              'source': e['source']['name'] ?? 'مصدر غير معروف',
              'image': e['urlToImage'],
              'url': e['url'], // إن أردت فتح الخبر في المتصفح
              'description': e['description'] ?? '',
              'content': e['content'] ?? '',
            };
          }).toList();
          isLoadingNews = false;
        });
      } else {
        setState(() => isLoadingNews = false);
        print('فشل في جلب الأخبار: ${response.statusCode}');
      }
    } catch (e) {
      print('خطأ في جلب الأخبار: $e');
      setState(() => isLoadingNews = false);
    }
  }

  Future<void> _fetchHealthStats() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc =
            await _firestore.collection('healthStats').doc(user.uid).get();

        if (doc.exists) {
          setState(() {
            healthStats = {
              'bloodPressure':
                  doc.data()?['bloodPressure']?.toString() ?? '--/--',
              'bloodSugar': doc.data()?['bloodSugar']?.toString() ?? '--',
              'steps': doc.data()?['steps']?.toString() ?? '0'
            };
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching health stats: $e');
    }
  }

  Future<void> updateMood(String mood) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'mood': mood,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        setState(() => selectedMood = mood);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث حالتك المزاجية بنجاح')),
        );
      }
    } catch (e) {
      debugPrint('Error updating mood: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء تحديث الحالة المزاجية: $e')),
      );
    }
  }

  Future<void> confirmMedication(String medId) async {
    try {
      await _firestore.collection('medications').doc(medId).update({
        'lastTaken': FieldValue.serverTimestamp(),
        'nextDoseTime': FieldValue.serverTimestamp(),
      });

      await _fetchMedications();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد تناول الدواء بنجاح')),
      );
    } catch (e) {
      debugPrint('Error confirming medication: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء تأكيد تناول الدواء: $e')),
      );
    }
  }

  PreferredSizeWidget buildAppBar() {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return AppBar(
      backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
      elevation: 2,
      title: const Text(
        "DiagnoPlus",
        style: TextStyle(color: Color(0xFF3A86FF)),
      ),
      centerTitle: false,
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications, color: Color(0xFF3A86FF)),
              onPressed: showNotificationsPopup,
            ),
            if (unreadNotifications > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadNotifications.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void showNotificationsPopup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationsScreen()),
    );
  }


  @override
  Widget build(BuildContext context) {


    return Scaffold(
      appBar: _currentIndex == 0 ? buildAppBar() : null,


      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _currentIndex,
              children: [
                RefreshIndicator(
                  onRefresh: _loadInitialData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        _buildWelcomeMoodSection(),
                        UpcomingAppointmentsWidget(appointments: appointments.cast<Appointment>()),
                       // _buildUpcomingAppointmentsSection(appointments.cast<Appointment>()),
                        UpcomingMedicationsSection( medications: medications,),

                        const SizedBox(
                          height: 20,
                        ),


                        SizedBox(
                          height: currentUserModel!.isPatient ?260 :0,
                          child: currentUserModel!.isPatient
                              ? const DoctorsListWidget()
                              : const SizedBox(height: 0,), // لا شيء إذا كان طبيب
                        ),


                        const SizedBox(
                          height: 20,
                        ),

                        // أقسام أخرى
                        // في HomeScreen داخل Column:


                          const MedicalTipsWidget(),
                          const SizedBox(height: 20),
                          const MedicalNewsWidget(),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                 currentUserModel!.isPatient ?const BookAppointmentScreen(): const AppointmentsListScreen(),
                const InstantConsultationScreen(),
                const MedicationsScreen(),
                const ProfileScreen(),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: const Color(0xFF3A86FF),
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: 'المواعيد'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble), label: 'استشارة'),
          BottomNavigationBarItem(
              icon: Icon(Icons.medication), label: 'الأدوية'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }


  Widget _buildWelcomeMoodSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A86FF), Color(0xFF4CC9F0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          userType== 'patient'?
          Text(
            "مرحباً، ${userName.isNotEmpty ? userName : 'مستخدم'}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ):
          Text(
            "مرحباً، دكتور ${userName.isNotEmpty ? userName : 'مستخدم'}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "كيف تشعر اليوم؟",
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMoodButton(Icons.sentiment_very_satisfied, "ممتاز"),
              const SizedBox(width: 8),
              _buildMoodButton(Icons.sentiment_satisfied, "جيد"),
              const SizedBox(width: 8),
              _buildMoodButton(Icons.sentiment_neutral, "عادي"),
              const SizedBox(width: 8),
              _buildMoodButton(Icons.sentiment_dissatisfied, "سيء"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoodButton(IconData icon, String label) {
    final isSelected = selectedMood == label;
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: () => updateMood(label),
        icon: Icon(icon, color: isSelected ? Colors.white : Colors.blue),
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.blue,
            fontSize: 14,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? Colors.blue[800] : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

}
