import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class EditProfileScreen extends StatefulWidget {
  final String userId;

  const EditProfileScreen({super.key, required this.userId});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _workPlaceController = TextEditingController();

  bool _isLoading = true;
  bool _isDoctor = false;

  String? _photoURL; // رابط الصورة الحالية
  File? _newImageFile; // الصورة الجديدة بعد اختيار المستخدم

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc = await _firestore.collection('users').doc(widget.userId).get();
    final data = doc.data();
    if (data != null) {
      setState(() {
        _nameController.text = data['fullName'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _genderController.text = data['gender'] ?? '';
        _ageController.text = (data['age'] ?? '').toString();
        _workPlaceController.text = data['workPlace'] ?? '';
        _isDoctor = data['accountType'] == 'doctor';
        _photoURL = data['photoURL']; // جلب رابط الصورة إن وجد
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على بيانات المستخدم')),
      );
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (pickedFile != null) {
      setState(() {
        _newImageFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage(File image) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_profile_images')
          .child('${widget.userId}.jpg');

      await ref.putFile(image);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? uploadedPhotoURL = _photoURL;

      // إذا اختار المستخدم صورة جديدة، ارفعها وحدث الرابط
      if (_newImageFile != null) {
        final url = await _uploadImage(_newImageFile!);
        if (url != null) {
          uploadedPhotoURL = url;
        }
      }

      Map<String, dynamic> updatedData = {
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'gender': _genderController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'photoURL': uploadedPhotoURL,
      };

      if (_isDoctor) {
        updatedData['workPlace'] = _workPlaceController.text.trim();
      }

      await _firestore.collection('users').doc(widget.userId).update(updatedData);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث الملف الشخصي بنجاح')),
      );

      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدث خطأ أثناء التحديث')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _ageController.dispose();
    _workPlaceController.dispose();
    super.dispose();
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
        title: const Text('تعديل الملف الشخصي'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // عرض الصورة الشخصية الحالية أو الصورة الجديدة مع زر اختيار صورة جديدة
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      radius: 60,
                      backgroundImage: _newImageFile != null
                          ? FileImage(_newImageFile!)
                          : (_photoURL != null && _photoURL!.isNotEmpty
                          ? NetworkImage(_photoURL!)
                          : const AssetImage('assets/images/profile_tab.png') as ImageProvider),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue,
                          child: const Icon(Icons.camera_alt, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
                validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال الاسم' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال رقم الهاتف' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _genderController,
                decoration: const InputDecoration(labelText: 'الجنس'),
                validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال الجنس' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: 'العمر'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء إدخال العمر';
                  }
                  final age = int.tryParse(value);
                  if (age == null || age <= 0) {
                    return 'الرجاء إدخال عمر صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              if (_isDoctor)
                TextFormField(
                  controller: _workPlaceController,
                  decoration: const InputDecoration(labelText: 'مكان العمل'),
                  validator: (value) => value == null || value.isEmpty ? 'الرجاء إدخال مكان العمل' : null,
                ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save),
                label: const Text('حفظ التعديلات'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blueAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
