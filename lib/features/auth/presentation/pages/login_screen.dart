import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:diagnoplus/features/auth/presentation/pages/register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. التحقق من الاتصال بالإنترنت
      final isConnected = await InternetConnectionChecker().hasConnection;
      if (!isConnected) {
        throw FirebaseAuthException(
          code: 'network-request-failed',
          message: 'لا يوجد اتصال بالإنترنت',
        );
      }

      // 2. تعيين اللغة العربية
      await FirebaseAuth.instance.setLanguageCode('ar');

      // 3. تسجيل الدخول
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // 4. جلب بيانات المستخدم من Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      // 5. التحقق من وجود المستند
      if (!userDoc.exists) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'لم يتم العثور على بيانات الحساب',
        );
      }

      // 6. استخراج بيانات المستخدم
      final userData = userDoc.data()!;
      final accountType = userData['accountType'] as String? ?? 'patient';
      final isVerified = userData['isVerified'] as bool? ?? false;
      final hasLicenseDocuments = userData['hasLicenseDocuments'] as bool? ?? false;
      final fullName = userData['fullName'] as String? ?? '';

      // 7. التحقق من حالة حساب الطبيب
      if (accountType == 'doctor') {
        if (!isVerified || !hasLicenseDocuments) {
          throw FirebaseAuthException(
            code: 'unverified-doctor',
            message: 'حساب الطبيب قيد المراجعة',
          );
        }
      }

      // 8. تسجيل بيانات الدخول (لأغراض التتبع)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      // 9. توجيه المستخدم حسب نوع الحساب
      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        accountType == 'doctor' ? '/doctor_dashboard' : '/home',
            (route) => false,
      );

      // 10. إظهار رسالة ترحيبية
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('مرحباً بك ${fullName.isNotEmpty ? fullName : 'عزيزي المستخدم'}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

    } on FirebaseAuthException catch (e) {
      _handleLoginError(e.code);
    } catch (e) {
      _handleLoginError('unknown-error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _handleLoginError(String errorCode) {
    if (!mounted) return;

    final errorMessage = _getFirebaseErrorMessage(errorCode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getFirebaseErrorMessage(String code) {
    switch (code) {
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة';
      case 'user-not-found':
        return 'البريد الإلكتروني غير مسجل';
      case 'invalid-email':
        return 'بريد إلكتروني غير صالح';
      case 'user-disabled':
        return 'هذا الحساب معطل';
      case 'too-many-requests':
        return 'تم تجاوز عدد المحاولات، حاول لاحقاً';
      case 'network-request-failed':
        return 'فشل الاتصال بالخادم';
      case 'unverified-doctor':
        return 'حساب الطبيب قيد المراجعة ولم يتم تفعيله بعد';
      default:
        return 'حدث خطأ غير متوقع (كود: $code)';
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال بريد إلكتروني صحيح')),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.setLanguageCode('ar');
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال رابط استعادة كلمة المرور إلى بريدك الإلكتروني'),
        ),
      );
    } catch (e) {
      String errorMessage = 'فشل إرسال رابط الاستعادة، الرجاء المحاولة لاحقاً';
      if (e is FirebaseAuthException) {
        errorMessage = e.message ?? errorMessage;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                // شعار التطبيق
                Center(
                  child: CircleAvatar(
                    radius: 100,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(40)),
                        image: DecorationImage(image: AssetImage(
                          'assets/images/logo.png',
                          // width: 200,
                          // height: 200,
                          // fit: BoxFit.cover,
                        ) as AssetImage)
                      ),

                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // عنوان التطبيق
                const Text(
                  'مرحباً بك في DiagnoPlus',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'تطبيقك الصحي الشامل',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                // حقل البريد الإلكتروني
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال البريد الإلكتروني';
                    }
                    if (!value.contains('@')) {
                      return 'الرجاء إدخال بريد إلكتروني صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // حقل كلمة المرور
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.grey[600],
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'الرجاء إدخال كلمة المرور';
                    }
                    if (value.length < 6) {
                      return 'يجب أن تكون كلمة المرور 6 أحرف على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // نسيت كلمة المرور
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _isLoading ? null : _resetPassword,
                    child: const Text('نسيت كلمة المرور؟'),
                  ),
                ),
                const SizedBox(height: 24),
                // زر تسجيل الدخول
                ElevatedButton(
                  onPressed: _isLoading ? null : _loginUser,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text(
                    'تسجيل الدخول',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 16),
                // رابط إنشاء حساب جديد
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('ليس لديك حساب؟'),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      ),
                      child: const Text('إنشاء حساب جديد'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}