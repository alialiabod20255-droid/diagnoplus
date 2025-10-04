import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:io';

class Workplace {
  final String name;
  final Map<String, List<WorkTime>> workDays;

  Workplace({required this.name, required this.workDays});

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'workDays': workDays.map((key, value) =>
          MapEntry(key, value.map((time) => time.toMap()).toList())),
    };
  }

  factory Workplace.fromMap(Map<String, dynamic> map) {
    return Workplace(
        name: map['name'],
        workDays: (map['workDays'] as Map).map((key, value) =>
        MapEntry(key, (value as List).map((e) => WorkTime.fromMap(e)).toList()),
    )
    );
  }
}

class WorkTime {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  WorkTime({required this.startTime, required this.endTime});

  Map<String, dynamic> toMap() {
    return {
      'startHour': startTime.hour,
      'startMinute': startTime.minute,
      'endHour': endTime.hour,
      'endMinute': endTime.minute,
    };
  }

  factory WorkTime.fromMap(Map<String, dynamic> map) {
    return WorkTime(
      startTime: TimeOfDay(hour: map['startHour'], minute: map['startMinute']),
      endTime: TimeOfDay(hour: map['endHour'], minute: map['endMinute']),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _confirmObscurePassword = true;
  String _selectedAccountType = 'patient';
  String? _selectedGender;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _specialtyNameController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _workplaceNameController = TextEditingController();
  final _phoneController = TextEditingController();

  PlatformFile? _licenseDocument;
  PlatformFile? _profileImage;
  bool _termsAccepted = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isUploading = false;
  bool _isProfileUploading = false;
  String? _photoURL;

  final List<String> specialtiesList = [
    'القلب',
    'الأسنان',
    'العيون',
    'الباطنة',
    'الجلدية',
    'العظام',
  ];

  List<Workplace> _workplaces = [];
  final Map<String, bool> _selectedDays = {
    'الأحد': false,
    'الاثنين': false,
    'الثلاثاء': false,
    'الأربعاء': false,
    'الخميس': false,
    'الجمعة': false,
    'السبت': false,
  };
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    _checkFirebaseConnection();
    _loadDataLocally();
  }

  Future<void> _checkFirebaseConnection() async {
    try {
      await FirebaseFirestore.instance.disableNetwork();
      await FirebaseFirestore.instance.enableNetwork();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('جارٍ التحقق من اتصال قاعدة البيانات...')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _specialtyController.dispose();
    _licenseNumberController.dispose();
    _workplaceNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null) {
        if (result.files.single.size > 2 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('حجم الصورة يجب أن يكون أقل من 2MB')),
            );
          }
          return;
        }

        setState(() {
          _profileImage = result.files.single;
        });
      }
    } catch (e) {
      _handleError('image-picker-error', e);
    }
  }

  Future<String?> _uploadProfileImage(String userId) async {
    if (_profileImage == null) return null;

    if (!mounted) return null;
    setState(() => _isProfileUploading = true);

    try {
      final String filePath = 'profile_images/$userId/${_profileImage!.name}';
      final Reference storageRef = FirebaseStorage.instance.ref().child(filePath);
      final File file = File(_profileImage!.path!);

      final UploadTask uploadTask = storageRef.putFile(file);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع الصورة الشخصية بنجاح')),
        );
      }

      return downloadUrl;
    } catch (e) {
      _handleError('profile-upload-error', e);
      return null;
    } finally {
      if (mounted) {
        setState(() => _isProfileUploading = false);
      }
    }
  }

  Future<void> _registerWithGoogle() async {
    if (!mounted) return;

    setState(() => _isGoogleLoading = true);

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      if (_profileImage == null && googleUser.photoUrl != null) {
        _photoURL = googleUser.photoUrl;
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _saveUserDataToFirestore(
          userCredential.user!.uid,
          googleUser.displayName ?? 'مستخدم جديد',
          googleUser.email,
        );

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            _selectedAccountType == 'doctor' ? '/verification_pending' : '/home',
                (route) => false,
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      _handleError('google-auth-error', e);
    } catch (e) {
      _handleError('google-general-error', e);
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  Future<void> _registerWithApple() async {
    if (!mounted) return;

    setState(() => _isAppleLoading = true);

    try {
      final AuthorizationCredentialAppleID appleCredential =
      await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final AuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        final fullName = appleCredential.givenName != null &&
            appleCredential.familyName != null
            ? '${appleCredential.givenName} ${appleCredential.familyName}'
            : 'مستخدم جديد';

        await _saveUserDataToFirestore(
          userCredential.user!.uid,
          fullName,
          appleCredential.email ?? userCredential.user!.email,
        );

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            _selectedAccountType == 'doctor' ? '/verification_pending' : '/home',
                (route) => false,
          );
        }
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        _handleError('apple-auth-error', e);
      }
    } on FirebaseAuthException catch (e) {
      _handleError('apple-firebase-error', e);
    } catch (e) {
      _handleError('apple-general-error', e);
    } finally {
      if (mounted) {
        setState(() => _isAppleLoading = false);
      }
    }
  }

  void _handleError(String errorType, dynamic error) {
    if (!mounted) return;

    String errorMessage = 'حدث خطأ أثناء التسجيل';
    switch (errorType) {
      case 'google-auth-error':
      case 'apple-firebase-error':
        errorMessage = _getFirebaseErrorText(error as FirebaseAuthException);
        break;
      case 'apple-auth-error':
        errorMessage = 'خطأ في تسجيل آبل: ${error.message}';
        break;
      case 'firestore-error':
        errorMessage = 'خطأ في حفظ البيانات: ${error.message}';
        break;
      case 'storage-error':
        errorMessage = 'خطأ في رفع الملف: ${error.message}';
        break;
      case 'profile-upload-error':
        errorMessage = 'خطأ في رفع الصورة الشخصية: ${error.toString()}';
        break;
      case 'workplace-error':
        errorMessage = 'خطأ في إدارة أماكن العمل: ${error.toString()}';
        break;
      default:
        errorMessage = 'حدث خطأ غير متوقع: ${error.toString()}';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _pickLicenseDocument() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (result != null) {
        if (result.files.single.size > 5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('حجم الملف يجب أن يكون أقل من 5MB')),
            );
          }
          return;
        }

        setState(() {
          _licenseDocument = result.files.single;
        });
      }
    } catch (e) {
      _handleError('file-picker-error', e);
    }
  }

  Future<void> _saveDataLocally() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', _nameController.text.trim());
      await prefs.setString('email', _emailController.text.trim());
      await prefs.setString('accountType', _selectedAccountType);
      if (_selectedGender != null) {
        await prefs.setString('gender', _selectedGender!);
      }
    } catch (e) {
      _handleError('local-storage-error', e);
    }
  }

  Future<void> _loadDataLocally() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      setState(() {
        _nameController.text = prefs.getString('name') ?? '';
        _emailController.text = prefs.getString('email') ?? '';
        _selectedAccountType = prefs.getString('accountType') ?? 'patient';
        _selectedGender = prefs.getString('gender');
      });
    } catch (e) {
      _handleError('local-load-error', e);
    }
  }

  Future<void> _uploadLicenseDocument(String userId) async {
    if (_licenseDocument == null) return;

    setState(() => _isUploading = true);

    try {
      final String filePath = 'license_docs/$userId/${_licenseDocument!.name}';
      final Reference storageRef = FirebaseStorage.instance.ref().child(filePath);
      final File file = File(_licenseDocument!.path!);

      final UploadTask uploadTask = storageRef.putFile(file);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'licenseDocumentUrl': downloadUrl,
        'hasLicenseDocuments': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع وثيقة الترخيص بنجاح')),
        );
      }
    } catch (e) {
      _handleError('storage-error', e);
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _saveUserDataToFirestore(String uid, String fullName, String? email) async {
    if (!mounted) return;

    try {
      final bool isVerified = _selectedAccountType == 'patient';

      Map<String, dynamic> userData = {
        'uid': uid,
        'fullName': fullName,
        'email': email,
        'phone': _phoneController.text.trim(),
        'gender': _selectedGender,
        'accountType': _selectedAccountType,
        'isVerified': isVerified,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'photoURL': _photoURL,
      };

      if (_selectedAccountType == 'doctor') {
        userData.addAll({
          'specialtyName': _specialtyController.text.trim(),
          'specialty': _specialtyNameController.text.trim(),
          'licenseNumber': _licenseNumberController.text.trim(),
          'workplaces': _workplaces.map((wp) => wp.toMap()).toList(),
          'licenseDocument': _licenseDocument?.name ?? '',
          'hasLicenseDocuments': _licenseDocument != null,
          'verificationStatus': 'pending',
        });
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ البيانات بنجاح')),
        );
      }
    } on FirebaseException catch (e) {
      _handleError('firestore-error', e);
      rethrow;
    } catch (e) {
      _handleError('firestore-general-error', e);
      rethrow;
    }
  }

  Future<void> _selectStartTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  void _addWorkplace() {
    if (_workplaceNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال اسم المكان')),
      );
      return;
    }

    final selectedDays = _selectedDays.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار يوم عمل واحد على الأقل')),
      );
      return;
    }

    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد وقت العمل')),
      );
      return;
    }

    final workDays = <String, List<WorkTime>>{};
    for (var day in selectedDays) {
      workDays[day] = [WorkTime(startTime: _startTime!, endTime: _endTime!)];
    }

    setState(() {
      _workplaces.add(Workplace(
        name: _workplaceNameController.text,
        workDays: workDays,
      ));
      _workplaceNameController.clear();
      _selectedDays.updateAll((key, value) => false);
      _startTime = null;
      _endTime = null;
    });
  }

  void _removeWorkplace(int index) {
    setState(() {
      _workplaces.removeAt(index);
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب الموافقة على الشروط والأحكام')),
        );
      }
      return;
    }

    if (_selectedGender == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب اختيار الجنس')),
        );
      }
      return;
    }

    if (_selectedAccountType == 'doctor') {
      if (_licenseDocument == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يجب تحميل وثيقة الترخيص للأطباء')),
          );
        }
        return;
      }

      if (_workplaces.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يجب إضافة مكان عمل واحد على الأقل')),
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (_profileImage != null) {
        _photoURL = await _uploadProfileImage(userCredential.user!.uid);
      }

      await _saveDataLocally();

      await _saveUserDataToFirestore(
        userCredential.user!.uid,
        _nameController.text.trim(),
        _emailController.text.trim(),
      );

      if (_selectedAccountType == 'doctor' && _licenseDocument != null) {
        await _uploadLicenseDocument(userCredential.user!.uid);
      }

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        _selectedAccountType == 'doctor' ? '/verification_pending' : '/home',
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _handleError('auth-error', e);
    } on FirebaseException catch (e) {
      _handleError('firestore-error', e);
    } catch (e) {
      _handleError('general-error', e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getFirebaseErrorText(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'البريد الإلكتروني مستخدم بالفعل';
      case 'invalid-email':
        return 'بريد إلكتروني غير صالح';
      case 'operation-not-allowed':
        return 'عملية غير مسموح بها';
      case 'weak-password':
        return 'كلمة المرور ضعيفة جداً';
      case 'account-exists-with-different-credential':
        return 'الحساب موجود بالفعل بمعلومات مختلفة';
      default:
        return 'حدث خطأ: ${e.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء حساب جديد'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: _profileImage != null
                              ? FileImage(File(_profileImage!.path!))
                              : _photoURL != null
                              ? NetworkImage(_photoURL!)
                              : const AssetImage('assets/images/default_profile.png')
                          as ImageProvider,
                          child: _profileImage == null && _photoURL == null
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),
                        if (_isProfileUploading)
                          const Positioned.fill(
                            child: CircularProgressIndicator(),
                          ),
                        const Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 15,
                            child: Icon(Icons.camera_alt, size: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'املأ النموذج لإنشاء حساب جديد',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty || value.trim().split(' ').length < 2) {
                      return 'يرجى إدخال اسمين على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty || !value.contains('@')) {
                      return 'يرجى إدخال بريد إلكتروني صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال رقم الهاتف';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
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
                    if (value == null || value.length < 8) {
                      return 'يجب أن تحتوي كلمة المرور على 8 أحرف على الأقل';
                    }
                    if (!RegExp(r'[0-9]').hasMatch(value) || !RegExp(r'[!@#\$&*~]').hasMatch(value)) {
                      return 'يجب أن تحتوي على رقم ورمز خاص واحد على الأقل';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _confirmObscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.grey[600],
                      ),
                      onPressed: () =>
                          setState(() => _confirmObscurePassword = !_confirmObscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: _confirmObscurePassword,
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'كلمات المرور غير متطابقة';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'الجنس',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('ذكر'),
                        value: 'male',
                        groupValue: _selectedGender,
                        onChanged: (value) => setState(() => _selectedGender = value),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('أنثى'),
                        value: 'female',
                        groupValue: _selectedGender,
                        onChanged: (value) => setState(() => _selectedGender = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'نوع الحساب',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                RadioListTile<String>(
                  title: const Text('مريض'),
                  value: 'patient',
                  groupValue: _selectedAccountType,
                  onChanged: (value) => setState(() => _selectedAccountType = value!),
                ),
                RadioListTile<String>(
                  title: const Text('طبيب'),
                  value: 'doctor',
                  groupValue: _selectedAccountType,
                  onChanged: (value) => setState(() => _selectedAccountType = value!),
                ),
                if (_selectedAccountType == 'doctor') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: specialtiesList.contains(_specialtyController.text)
                        ? _specialtyController.text
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'التخصص',
                      border: OutlineInputBorder(),
                    ),
                    items: specialtiesList
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (val) => setState(() => _specialtyController.text = val ?? ''),
                    validator: (value) {
                      if (_selectedAccountType == 'doctor' && (value == null || value.isEmpty)) {
                        return 'يرجى اختيار التخصص';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _specialtyNameController,
                    decoration: const InputDecoration(
                      labelText: 'المؤهل، التخصص، الجامعة، المكان',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_selectedAccountType == 'doctor' && (value == null || value.isEmpty)) {
                        return 'يرجى إدخال التخصص';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _licenseNumberController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الرخصة',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_selectedAccountType == 'doctor' && (value == null || value.isEmpty)) {
                        return 'يرجى إدخال رقم الرخصة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickLicenseDocument,
                    icon: const Icon(Icons.upload),
                    label: const Text('تحميل وثيقة الترخيص'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  if (_licenseDocument != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'تم اختيار الملف: ${_licenseDocument!.name}',
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'أماكن العمل',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (_workplaces.isNotEmpty) ...[
                    ..._workplaces.asMap().entries.map((entry) {
                      final index = entry.key;
                      final workplace = entry.value;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    workplace.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _removeWorkplace(index),
                                  ),
                                ],
                              ),
                              ...workplace.workDays.entries.map((dayEntry) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      Text(dayEntry.key),
                                      const SizedBox(width: 8),
                                      ...dayEntry.value.map((workTime) {
                                        return Text(
                                          '${workTime.startTime.format(context)} - ${workTime.endTime.format(context)}',
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _workplaceNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المكان (مستشفى/عيادة)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('أيام العمل:'),
                  Wrap(
                    children: _selectedDays.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: FilterChip(
                          label: Text(entry.key),
                          selected: entry.value,
                          onSelected: (selected) {
                            setState(() {
                              _selectedDays[entry.key] = selected;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectStartTime,
                          child: Text(
                            _startTime == null
                                ? 'حدد وقت البدء'
                                : 'البدء: ${_startTime!.format(context)}',
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectEndTime,
                          child: Text(
                            _endTime == null
                                ? 'حدد وقت الانتهاء'
                                : 'الانتهاء: ${_endTime!.format(context)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _addWorkplace,
                    child: const Text('إضافة مكان عمل'),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _termsAccepted,
                      onChanged: (value) => setState(() => _termsAccepted = value!),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // TODO: عرض شروط الخدمة
                        },
                        child: const Text(
                          'أوافق على شروط الخدمة وسياسة الخصوصية',
                          style: TextStyle(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('إنشاء حساب'),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(child: Text('أو')),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isGoogleLoading ? null : _registerWithGoogle,
                    icon: const Icon(Icons.g_mobiledata),
                    label: _isGoogleLoading
                        ? const CircularProgressIndicator()
                        : const Text('التسجيل عبر جوجل'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isAppleLoading ? null : _registerWithApple,
                    icon: const Icon(Icons.apple),
                    label: _isAppleLoading
                        ? const CircularProgressIndicator()
                        : const Text('التسجيل عبر آبل'),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                    child: const Text('لديك حساب بالفعل؟ تسجيل الدخول'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}