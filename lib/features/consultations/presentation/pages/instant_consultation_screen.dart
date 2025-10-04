import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'consultation_screen.dart';
import '../../../../core/config/presenceService.dart';
import '../../../../services/notification_service.dart';
import 'package:diagnoplus/features/model.dart';

import 'groupConsultationScreen.dart';

class InstantConsultationScreen extends StatefulWidget {
  const InstantConsultationScreen({super.key});

  @override
  State<InstantConsultationScreen> createState() => _InstantConsultationScreenState();
}

class _InstantConsultationScreenState extends State<InstantConsultationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _selectedSpecialty;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final List<String> _specialties = ['الكل','القلب','الأسنان','العيون','الباطنة','الجلدية','العظام'];
  String? accountType;

  @override
  void initState() {
    super.initState();
    _setupPresence();
    _loadAccountType();
  }

  Future<void> _setupPresence() async {
    await PresenceService().setOnline();
  }

  Future<void> _loadAccountType() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      setState(() {
        accountType = userDoc.data()!['accountType'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (accountType == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Scaffold(

      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 2,
        title: const Text('الاستشارة الفورية'),
        // actions: [
        //   IconButton(
        //
        //     icon: const Icon(Icons.group),
        //     onPressed: () {
        //       // استشارات جماعية (إن وجدت)
        //       Navigator.push(
        //         context,
        //         MaterialPageRoute(
        //           builder: (_) => GroupConsultationScreen(),
        //         ),
        //       );
        //     },
        //   ),
        // ],
      ),
      body: accountType == 'doctor' ? _buildPatientConsultations() : _buildDoctorsSelection(),

      floatingActionButton: FloatingActionButton(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.blue[500],
        onPressed: (){
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const GroupConsultationScreen(),
            ),
          );
        },
        tooltip: 'الاستشارة الجماعية',
        child: const Icon(Icons.group),

      ),
    );
  }

  Widget _buildDoctorsSelection() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'ابحث عن طبيب...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              })
                  : null,
            ),
            onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedSpecialty ?? 'الكل',
            items: _specialties.map((sp) => DropdownMenuItem(value: sp, child: Text(sp))).toList(),
            onChanged: (value) =>
                setState(() => _selectedSpecialty = (value == 'الكل' ? null : value)),
            decoration: const InputDecoration(labelText: 'اختر التخصص', border: OutlineInputBorder()),
          ),
        ]),
      ),
      Expanded(child: _buildDoctorsList()),
    ]);
  }

  Widget _buildDoctorsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .where('accountType', isEqualTo: 'doctor')
          .where('isVerified', isEqualTo: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('لا يوجد أطباء متاحين حالياً'));
        final doctors = docs.map((d) => UserModel.fromFirestore(d))
            .where((dr) =>
        (_selectedSpecialty == null || dr.specialtyName == _selectedSpecialty) &&
            dr.fullName.toLowerCase().contains(_searchQuery)
        ).toList();
        if (doctors.isEmpty) return const Center(child: Text('لا توجد نتائج مطابقة للبحث'));
        return ListView.builder(
          itemCount: doctors.length,
          itemBuilder: (ctx, i) => _buildDoctorCard(doctors[i]),
        );
      },
    );
  }

  Widget _buildDoctorCard(UserModel doctor) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 30,
          backgroundImage: doctor.photoURL != null
              ? NetworkImage(doctor.photoURL!)
              : const AssetImage('assets/images/doctor_placeholder.png') as ImageProvider,
        ),
        title: Text(doctor.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doctor.specialtyName ?? 'تخصص عام'),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.star, color: Colors.amber, size: 16),
            const SizedBox(width: 4),
            Text('${doctor.rating?.toStringAsFixed(1) ?? '5.0'} (${doctor.consultationCount ?? 0})'),
          ]),
        ]),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => _startConsultation(doctor),
          child: const Text('استشارة'),
        ),
      ),
    );
  }

  ImageProvider _getUserImage(dynamic imageUrl) {
    if (imageUrl == null || imageUrl.toString().isEmpty) {
      return const AssetImage('assets/images/doctor_placeholder.png');
    }
    return NetworkImage(imageUrl.toString());
  }


  /// قائمة المرضى للطبيب
  Widget _buildPatientConsultations() {
    final doctor = _auth.currentUser;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('consultations')
          .where('doctorId', isEqualTo: doctor!.uid)
          .where('type', isEqualTo: 'instant')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('لا يوجد مرضى حاليًا'));

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final id = docs[i].id;
            final userId = data['userId'];

            return FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('users').doc(userId).get(),
              builder: (context, snapshot) {
                String? userPhoto;
                if (snapshot.hasData && snapshot.data!.exists) {
                  final userData = snapshot.data!.data() as Map<String, dynamic>;
                  userPhoto = userData['photoURL'];
                }

                return ListTile(
                  leading: CircleAvatar(
                    radius: 30,
                    backgroundImage: (userPhoto != null && userPhoto.isNotEmpty)
                        ? NetworkImage(userPhoto)
                        : const AssetImage('assets/images/doctor_placeholder.png') as ImageProvider,
                  ),
                  title: Text(data['userName'] ?? 'مريض'),
                  subtitle: Text(data['specialty'] ?? ''),
                  trailing: const Icon(Icons.chat),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) =>
                        ConsultationScreen(
                          doctorUid: data['doctorId'] ?? '',
                          patientUid: data['userId'] ?? '',
                          doctorName: data['doctorName'] ?? '',
                          patientName: data['userName'] ?? '',
                          consultationId: id,
                          doctorImage: data['doctorImage'] ?? '',
                          userImage: userPhoto ?? '',
                          isDoctor: true,
                        ),
                    ));
                  },
                );
              },
            );
          },
        );
      },
    );
  }


  Future<void> _startConsultation(UserModel doctor) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final userDataDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDataDoc.data() ?? {};
      final existing = await _firestore
          .collection('consultations')
          .where('userId', isEqualTo: user.uid)
          .where('doctorId', isEqualTo: doctor.uid)
          .where('type', isEqualTo: 'instant')
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final doc = existing.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        Navigator.push(context, MaterialPageRoute(builder: (_) =>
            ConsultationScreen(
              consultationId: doc.id,
              doctorUid: data['doctorId'] ?? '',
              patientUid: data['userId'] ?? '',
              doctorName: data['doctorName'] ?? '',
              patientName: data['userName'] ?? '',
              doctorImage: data['doctorImage'] ?? '',
              userImage: data['userImage'] ?? '',
              isDoctor: false,
            ),
        ));
        return;
      }

      final userFcmToken = await NotificationService().getDeviceToken();
      final consultationRef = await _firestore.collection('consultations').add({
        'type': 'instant',
        'doctorId': doctor.uid,
        'doctorName': doctor.fullName,
        'doctorImage': doctor.photoURL,
        'doctorFcmToken': doctor.fcmToken,
        'userId': user.uid,
        'userName': userData['fullName'] ?? (user.displayName ?? 'مستخدم'),
        'userImage': userData['profilePicture'] ?? user.photoURL,
        'userFcmToken': userFcmToken,
        'specialty': doctor.specialtyName,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'isActive': true,
        'seenBy': [user.uid],
        'hasNewMessage': false,
      });

      if (doctor.fcmToken != null) {
        await _sendNotification(
          token: doctor.fcmToken!,
          title: 'استشارة جديدة',
          body: 'لديك استشارة جديدة من ${userData['fullName'] ?? user.displayName}',
          consultationId: consultationRef.id,
        );
      }

      Navigator.push(context, MaterialPageRoute(builder: (_) =>
          ConsultationScreen(
            consultationId: consultationRef.id,
            doctorUid: userData['doctorId'] ?? '',
            patientUid: userData['userId'] ?? '',
            doctorName: userData['doctorName'] ?? '',
            patientName: userData['userName'] ?? '',
            doctorImage: doctor.photoURL ?? '',
            userImage: userData['photoURL'] ?? user.photoURL ?? '',
            isDoctor: false,
          ),
      ));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: ${e.toString()}')));
    }
  }

  Future<void> _sendNotification({
    required String token,
    required String title,
    required String body,
    required String consultationId,
  }) async {
    await _firestore.collection('notifications').add({
      'to': token,
      'title': title,
      'body': body,
      'consultationId': consultationId,
      'createdAt': FieldValue.serverTimestamp(),
      'isRead': false,
    });
  }
}
