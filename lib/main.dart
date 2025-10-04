import 'package:diagnoplus/features/auth/presentation/pages/login_screen.dart';
import 'package:diagnoplus/features/auth/presentation/pages/register_screen.dart';
import 'package:diagnoplus/features/consultations/presentation/pages/consultation_screen.dart';
import 'package:diagnoplus/features/home/presentation/pages/home_screen.dart';
import 'package:diagnoplus/features/medications/presentation/pages/medications_screen.dart';
import 'package:diagnoplus/features/medical_records/presentation/pages/medical_records_screen.dart';
import 'package:diagnoplus/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:diagnoplus/features/profile/presentation/pages/profile_screen.dart';
import 'package:diagnoplus/features/appointments/presentation/pages/appointments_list_screen.dart';
import 'package:diagnoplus/features/appointments/presentation/pages/book_appointment_screen.dart';
import 'package:diagnoplus/firebase_options.dart';
import 'package:diagnoplus/services/appointmentNotificationService.dart';
import 'package:diagnoplus/services/appointment_service.dart';
import 'package:diagnoplus/services/medication_service.dart';
import 'package:diagnoplus/services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'Provider/auth_gate.dart';
import 'core/config/theme.dart';
import 'features/auth/presentation/pages/verification_pending_screen.dart';
import 'features/doctor/presentation/pages/doctor_dashboard_screen.dart';


final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ✅ هذا هو معالج الإشعارات عندما يكون التطبيق في الخلفية أو مغلقًا
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('🔔 رسالة من FCM في الخلفية أو الإغلاق: ${message.messageId}');
}

/// ✅ تهيئة الإشعارات المحلية
Future<void> initializeNotifications() async {
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, badge: true, sound: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await initializeNotifications();

  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    AppointmentNotificationService().listenToAppointments(user.uid);
  }

  await Hive.initFlutter();

  final notificationService = NotificationService();
  await notificationService.initialize();

  // ✅ تعيين مفتاح التنقل لظهور شاشة الاتصال عند استقبال مكالمة
  ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

  ZegoUIKit().initLog().then((_) {
    ZegoUIKitPrebuiltCallInvitationService().useSystemCallingUI(
      [ZegoUIKitSignalingPlugin()],
    );

    runApp(
      MultiProvider(
        providers: [
          Provider(create: (_) => AppointmentService()),
          Provider(create: (_) => MedicationService()),
        ],
        child: MyApp(navigatorKey: navigatorKey),
      ),
    );
  });
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'DiagnoPlus',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'SA'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ar', 'SA'),
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/verification_pending': (context) => const VerificationPendingScreen(),
        '/medicalrecords': (context) => const MedicalRecordsScreen(),
        '/medications': (context) => const MedicationsScreen(),
        '/appointments': (context) => AppointmentsListScreen(),
        '/book_appointment': (context) => const BookAppointmentScreen(),
        '/doctorDashboard': (context) => const DoctorDashboardScreen(),
        '/profill': (context) => const ProfileScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/consultation') {
          final args = settings.arguments as Map<String, dynamic>?;

          if (args != null &&
              args.containsKey('consultationId') &&
              args.containsKey('doctorImage') &&
              args.containsKey('userImage') &&
              args.containsKey('isDoctor')) {
            return MaterialPageRoute(
              builder: (_) => ConsultationScreen(
                consultationId: args['consultationId'],
                doctorUid: args['doctorId'] ?? '',
                patientUid: args['userId'] ?? '',
                doctorName: args['doctorName'] ?? 'الطبيب',
                patientName: args['patientName'] ?? 'المريض',
                doctorImage: args['doctorImage'],
                userImage: args['userImage'],
                isDoctor: args['isDoctor'],
              ),
            );

          } else {
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text('بيانات الاستشارة غير مكتملة')),
              ),
            );
          }
        }

        if (settings.name == '/edit_profile') {
          final args = settings.arguments as Map<String, dynamic>?;

          if (args != null && args.containsKey('userId')) {
            return MaterialPageRoute(
              builder: (_) => EditProfileScreen(userId: args['userId']),
            );
          }

          return MaterialPageRoute(
            builder: (_) => EditProfileScreen(userId: ''),
          );
        }

        return null;
      },
    );
  }
}
