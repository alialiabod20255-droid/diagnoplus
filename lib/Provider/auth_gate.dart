import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:diagnoplus/Provider/underReviewScreen.dart';
import 'package:diagnoplus/features/auth/presentation/pages/login_screen.dart';
import 'package:diagnoplus/features/home/presentation/pages/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

/// 🔁 نستخدم هذا المتغير لمنع التهيئة المتكررة لـ Zego
bool _zegoInitialized = false;

/// ✅ دالة تهيئة Zego لمرة واحدة فقط
Future<void> initZegoIfNeeded({
  required String userID,
  required String userName,
}) async {
  if (_zegoInitialized) return;
  _zegoInitialized = true;

  ZegoUIKitPrebuiltCallInvitationService().init(
    appID: 2139824177, // App ID من ZegoCloud
    appSign:
    'c99b75f989d29f61806908358a1e2b023e70f5388fa1fa6626f6f0d9474cc315', // App Sign من ZegoCloud
    userID: userID,
    userName: userName,
    plugins: [ZegoUIKitSignalingPlugin()],
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('حدث خطأ ما. حاول مرة أخرى.',
                  style: TextStyle(color: Colors.red)),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }

            if (userSnapshot.hasError ||
                !userSnapshot.hasData ||
                !userSnapshot.data!.exists) {
              return const LoginScreen();
            }

            final userData =
            userSnapshot.data!.data() as Map<String, dynamic>;
            final accountType = userData['accountType'] ?? 'patient';
            final userName =
                userData['fullName'] ?? 'User_${user.uid.substring(0, 5)}';

            /// ✅ تهيئة Zego لمرة واحدة
            initZegoIfNeeded(userID: user.uid, userName: userName);

            if (accountType == 'doctor') {
              final isVerified = userData['isVerified'] == true;
              final hasLicense = userData['hasLicenseDocuments'] == true;

              if (!isVerified || !hasLicense) {
                return const UnderReviewScreen(); // طبيب غير موثق
              }

              return const HomeScreen(); // طبيب موثق
            }

            return const HomeScreen(); // مريض
          },
        );
      },
    );
  }
}
