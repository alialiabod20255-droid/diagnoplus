import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

class CallPage extends StatelessWidget {
  final String callID;
  final String doctorID;
  final String patientID;
  final bool isDoctor;
  final String userName; // أضف هذا المتغير

  const CallPage({
    super.key,
    required this.callID,
    required this.doctorID,
    required this.patientID,
    required this.isDoctor,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    final userID = isDoctor ? doctorID : patientID;

    return ZegoUIKitPrebuiltCall(
      appID: 472822999,
      appSign: 'ce9c9c64bb1ec7a06fcdb15e4fe94fa6e4ff221b9630569c3e362913ce9d0286',
      userID: userID, // معرف المستخدم الحالي
      userName: userName,
      callID: callID,
      config: ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall(),
    );
  }
}
