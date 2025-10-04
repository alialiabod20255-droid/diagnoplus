import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'dart:io';

import 'call_page.dart';

class ConsultationScreen extends StatefulWidget {
  final String consultationId;
  final String doctorUid;
  final String patientUid;
  // ✅ أضف هذين السطرين
  final String doctorName;
  final String patientName;

  final bool isDoctor;
  final String doctorImage;
  final String userImage;

  const ConsultationScreen({
    Key? key,
    required this.consultationId,
    required this.doctorUid,
    required this.patientUid,
    required this.isDoctor,
    required this.doctorImage,
    required this.userImage,
    required this.doctorName, // ✅ هنا
    required this.patientName, // ✅ وهنا
  }) : super(key: key);

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final picker = ImagePicker();
  bool _zegoInitialized = false;

  Map<String, dynamic>? doctorData;
  Map<String, dynamic>? patientData;
  File? selectedMedia;
  String? mediaType;
  String? fileName;
  DocumentSnapshot? replyToMessage;
  bool isSending = false;
  final Map<String, GlobalKey> _messageKeys = {};
  String? _replyingToMessageId;
  String? _highlightedMessageId;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  DocumentSnapshot? _lastMessage;
  DocumentSnapshot? _lastLoadedMessage;
  final Set<String> _visibleMessages = {};
  bool _shouldScrollToBottom = true;

  @override
  void initState() {
    super.initState();
    _loadUsersData();
    _markDeliveredMessages();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: false));

  }

  void _scrollListener() {
    if (_scrollController.offset < _scrollController.position.maxScrollExtent - 100) {
      _shouldScrollToBottom = false;
    }
  }

  Future<void> _loadUsersData() async {
    try {
      final doctorSnap = await _firestore.collection('users').doc(widget.doctorUid).get();
      final patientSnap = await _firestore.collection('users').doc(widget.patientUid).get();

      if (mounted) {
        setState(() {
          doctorData = doctorSnap.data();
          patientData = patientSnap.data();
        });
      }
    } catch (e) {
      _showErrorSnackbar('فشل في تحميل بيانات المستخدم');
    }
  }

  void _setupRealTimeUpdates() {
    _markDeliveredMessages();

    _firestore
        .collection('consultations')
        .doc(widget.consultationId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final lastMsg = snapshot.docs.first;
        final data = lastMsg.data() as Map<String, dynamic>;

        if (data['senderId'] != _auth.currentUser?.uid) {
          if (data['status'] == 'sent') {
            lastMsg.reference.update({'status': 'delivered'});
          }

          if (_isNearBottom()) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom();
            });
          }
        }
      }
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 200;
  }

  Future<void> _markDeliveredMessages() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final unread = await _firestore
          .collection('consultations')
          .doc(widget.consultationId)
          .collection('messages')
          .where('senderId', isNotEqualTo: user.uid)
          .where('status', isEqualTo: 'sent')
          .get();

      final batch = _firestore.batch();
      for (var doc in unread.docs) {
        batch.update(doc.reference, {'status': 'delivered'});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Error marking messages as delivered: $e');
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    try {
      final query = _firestore
          .collection('consultations')
          .doc(widget.consultationId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastLoadedMessage ?? _lastMessage!)
          .limit(15);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        setState(() => _hasMoreMessages = false);
      } else {
        _lastLoadedMessage = snapshot.docs.last;
      }
    } catch (e) {
      _showErrorSnackbar('فشل في تحميل المزيد من الرسائل');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _scrollToBottom({bool animated = true}) async {
    if (!_scrollController.hasClients) return;

    if (animated) {
      await _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _scrollToMessage(String messageId) async {
    if (_messageKeys.containsKey(messageId)) {
      final context = _messageKeys[messageId]!.currentContext;
      if (context != null) {
        await Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.35,
        );
        return;
      }
    }

    bool found = false;
    while (!found && _hasMoreMessages) {
      await _loadMoreMessages();
      await Future.delayed(const Duration(milliseconds: 300));

      if (_messageKeys.containsKey(messageId)) {
        final context = _messageKeys[messageId]!.currentContext;
        if (context != null) {
          await Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            alignment: 0.35,
          );
          found = true;
        }
      }
    }

    if (mounted) {
      setState(() => _highlightedMessageId = messageId);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _highlightedMessageId = null);
    }
  }

  String? getUserImageUrl(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    return userData['photoURL'] as String? ?? userData['profileImageUrl'] as String?;
  }

  String getUserName(Map<String, dynamic>? userData, bool isDoctor) {
    if (userData == null) return isDoctor ? 'مريض' : 'طبيب';
    return userData['fullName'] as String? ?? (isDoctor ? 'مريض' : 'طبيب');
  }

  String getUserStatus(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    if (userData['isOnline'] as bool? ?? false) return 'متصل الآن';
    if (userData['lastSeen'] != null) {
      final lastSeen = (userData['lastSeen'] as Timestamp).toDate();
      return 'آخر ظهور ${DateFormat('hh:mm a', 'ar').format(lastSeen)}';
    }
    return '';
  }

  void _onReplyToMessage(DocumentSnapshot message) {
    setState(() {
      replyToMessage = message;
      _replyingToMessageId = message.id;
    });
  }

  Future<void> _handleLongPress(DocumentSnapshot msg) async {
    final data = msg.data() as Map<String, dynamic>;
    if (data['senderId'] != _auth.currentUser?.uid) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الرسالة'),
        content: const Text('هل تريد حذف الرسالة من الطرفين؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await msg.reference.delete();
      } catch (e) {
        _showErrorSnackbar('فشل في حذف الرسالة');
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty && selectedMedia == null) return;
    if (isSending) return;

    setState(() {
      isSending = true;
      _shouldScrollToBottom = true;
    });

    final user = _auth.currentUser;
    if (user == null) {
      setState(() => isSending = false);
      return;
    }

    String? downloadUrl;
    String type = 'text';

    try {
      if (selectedMedia != null && mediaType != null) {
        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
        });

        final ref = FirebaseStorage.instance.ref(
          'consultations/${widget.consultationId}/files/${DateTime.now().millisecondsSinceEpoch}_$fileName',
        );

        final uploadTask = ref.putFile(selectedMedia!);
        uploadTask.snapshotEvents.listen((snapshot) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        });

        await uploadTask;
        downloadUrl = await ref.getDownloadURL();
        type = mediaType!;

        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }

      await _firestore
          .collection('consultations')
          .doc(widget.consultationId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'senderName': getUserName(widget.isDoctor ? doctorData : patientData, widget.isDoctor),
        'senderImage': getUserImageUrl(widget.isDoctor ? doctorData : patientData),
        'text': _messageController.text.trim(),
        'fileUrl': downloadUrl,
        'fileName': fileName,
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'replyTo': replyToMessage?.id,
      });

      await _firestore
          .collection('consultations')
          .doc(widget.consultationId)
          .update({
        'lastMessage': _messageController.text.trim().isNotEmpty
            ? _messageController.text.trim()
            : fileName ?? 'ملف مرفق',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      setState(() {
        _messageController.clear();
        selectedMedia = null;
        mediaType = null;
        fileName = null;
        replyToMessage = null;
        isSending = false;
      });

      await Future.delayed(const Duration(milliseconds: 100));
      await _scrollToBottom();
    } catch (e) {
      setState(() => isSending = false);
      _showErrorSnackbar('فشل في إرسال الرسالة');
    }
  }
  void _handleMessageVisibility(String messageId, bool isVisible) {
    if (isVisible) {
      _visibleMessages.add(messageId);
      _markMessageAsRead(messageId);
    } else {
      _visibleMessages.remove(messageId);
    }
  }

  Future<void> _markMessageAsRead(String messageId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final messageRef = _firestore
        .collection('consultations')
        .doc(widget.consultationId)
        .collection('messages')
        .doc(messageId);

    final message = await messageRef.get();
    final data = message.data() as Map<String, dynamic>?;

    if (data != null &&
        data['senderId'] != user.uid &&
        data['status'] != 'read') {
      await messageRef.update({'status': 'read'});
    }
  }

  Future<void> _pickMedia(String type) async {
    try {
      if (type == 'image') {
        final picked = await picker.pickImage(source: ImageSource.gallery);
        if (picked != null) {
          setState(() {
            selectedMedia = File(picked.path);
            mediaType = 'image';
            fileName = picked.name;
          });
        }
      } else if (type == 'video') {
        final picked = await picker.pickVideo(source: ImageSource.gallery);
        if (picked != null) {
          setState(() {
            selectedMedia = File(picked.path);
            mediaType = 'video';
            fileName = picked.name;
          });
        }
      } else if (type == 'file') {
        final result = await FilePicker.platform.pickFiles();
        if (result != null && result.files.single.path != null) {
          setState(() {
            selectedMedia = File(result.files.single.path!);
            mediaType = 'file';
            fileName = result.files.single.name;
          });
        }
      } else if (type == 'camera') {
        final picked = await picker.pickImage(source: ImageSource.camera);
        if (picked != null) {
          setState(() {
            selectedMedia = File(picked.path);
            mediaType = 'image';
            fileName = picked.name;
          });
        }
      }
    } catch (e) {
      _showErrorSnackbar('فشل في اختيار الملف');
    }
  }

  Widget _buildStatusIcon(String? status, bool isMe, ThemeData theme) {
    final color = isMe ? theme.disabledColor : theme.disabledColor;
    switch (status) {
      case 'read':
        return Icon(Icons.done_all, size: 16, color: Colors.blue[200]);
      case 'delivered':
        return Icon(Icons.done_all, size: 16, color: color);
      default:
        return Icon(Icons.done, size: 16, color: color);
    }
  }

  Widget _buildReplyPreview(DocumentSnapshot? replyMsg, ThemeData theme, bool isDarkMode) {
    if (replyMsg == null) return const SizedBox.shrink();
    final data = replyMsg.data() as Map<String, dynamic>;
    final type = data['type'] as String? ?? 'text';
    final content = data['text'] as String? ?? data['fileName'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? theme.primaryColor.withOpacity(0.1)
            : theme.primaryColor.withOpacity(0.05),
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 20, color: theme.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              type == 'text' ? content : '📎 $content',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.primaryColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: theme.disabledColor),
            onPressed: () => setState(() => replyToMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _previewMedia(ThemeData theme, bool isDarkMode) {
    if (selectedMedia == null || mediaType == null) return const SizedBox();

    Widget preview;
    if (mediaType == 'image') {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(selectedMedia!, height: 100, fit: BoxFit.cover),
      );
    } else if (mediaType == 'video') {
      preview = Row(
        children: [
          Icon(Icons.videocam, size: 30, color: theme.primaryColor),
          const SizedBox(width: 8),
          Text('فيديو مرفق', style: theme.textTheme.bodyMedium),
        ],
      );
    } else {
      preview = Row(
        children: [
          Icon(Icons.insert_drive_file, size: 30, color: theme.primaryColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fileName ?? 'ملف مرفق',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (_isUploading)
          LinearProgressIndicator(
            value: _uploadProgress,
            backgroundColor: Colors.grey[300],
            color: theme.primaryColor,
          ),
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(child: preview),
              IconButton(
                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.error),
                onPressed: () {
                  setState(() {
                    selectedMedia = null;
                    mediaType = null;
                    fileName = null;
                    _isUploading = false;
                    _uploadProgress = 0.0;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageInput(ThemeData theme, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[900] : Colors.white,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file_outlined, color: theme.primaryColor),
            onPressed: () => _showAttachmentMenu(context),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.disabledColor,
                        ),
                      ),
                      style: theme.textTheme.bodyMedium,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isSending ? Icons.hourglass_top : Icons.send,
                      color: isSending
                          ? theme.disabledColor
                          : theme.primaryColor,
                    ),
                    onPressed: isSending ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAttachmentMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.image, color: Colors.blue),
                  ),
                  title: const Text('صورة من المعرض'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia('image');
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.videocam, color: Colors.purple),
                  ),
                  title: const Text('فيديو من المعرض'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia('video');
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.insert_drive_file, color: Colors.green),
                  ),
                  title: const Text('ملف من الجهاز'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia('file');
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, color: Colors.orange),
                  ),
                  title: const Text('التقاط صورة'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia('camera');
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFullScreenImage(String imageUrl, BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 3,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showVideoDialog(String videoUrl, BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فيديو مرفق'),
        content: const Text('سيتم فتح الفيديو في متصفح خارجي'),
        actions: [
          TextButton(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('فتح'),
            onPressed: () {
              launchUrl(Uri.parse(videoUrl));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }



  void _showFeatureNotAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('هذه الميزة غير متوفرة حالياً'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _handleAppBarMenuSelection(String value, BuildContext context) {
    switch (value) {
      case 'info':
        _showUserInfoDialog(context);
        break;
      case 'search':
        _showSearchDialog(context);
        break;
      case 'notifications':
        _showNotificationSettings(context);
        break;
      case 'delete':
        _showDeleteConfirmationDialog(context);
        break;
    }
  }

  void _showUserInfoDialog(BuildContext context) {
    final userData = widget.isDoctor ? patientData : doctorData;
    final contactName = getUserName(userData, widget.isDoctor);
    final userImageUrl = getUserImageUrl(userData);
    final userStatus = getUserStatus(userData);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('معلومات $contactName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: userImageUrl != null
                  ? NetworkImage(userImageUrl)
                  : const AssetImage('assets/default_profile.png') as ImageProvider,
            ),
            const SizedBox(height: 16),
            Text(contactName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              userStatus,
              style: TextStyle(
                color: userStatus.contains('متصل الآن') ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('إغلاق'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بحث في المحادثة'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'ابحث في الرسائل...'),
          onChanged: (query) {
            // TODO: Implement search functionality
          },
        ),
        actions: [
          TextButton(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('بحث'),
            onPressed: () {
              // TODO: Execute search
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات الإشعارات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('تشغيل الإشعارات'),
              value: true,
              onChanged: (value) {},
            ),
            SwitchListTile(
              title: const Text('صوت الإشعارات'),
              value: true,
              onChanged: (value) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('حفظ'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المحادثة'),
        content: const Text('هل أنت متأكد أنك تريد حذف هذه المحادثة؟'),
        actions: [
          TextButton(
            child: const Text('إلغاء'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف المحادثة')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(DocumentSnapshot doc, ThemeData theme, bool isDarkMode) {
    final them  = Theme.of(context).colorScheme;
    final msg = doc.data() as Map<String, dynamic>;
    final msgId = doc.id;
    final isMe = msg['senderId'] == _auth.currentUser?.uid;
    final status = msg['status'] as String?;
    final senderImage = msg['senderImage'] as String? ?? '';
    final text = msg['text'] as String? ?? '';
    final type = msg['type'] as String? ?? 'text';
    final fileUrl = msg['fileUrl'] as String?;
    final fileName = msg['fileName'] as String? ?? '';
    final time = msg['timestamp'] != null
        ? DateFormat('hh:mm a', 'ar').format((msg['timestamp'] as Timestamp).toDate())
        : '';
    final dynamic replyToField = msg['replyTo'];
    final String? replyToId = (replyToField is String) ? replyToField : null;

    final isReplyingToThisMessage = _replyingToMessageId == msgId;
    final isHighlighted = _highlightedMessageId == msgId;

    if (!_messageKeys.containsKey(msgId)) {
      _messageKeys[msgId] = GlobalKey();
    }

    Widget content;
    if ((type == 'image' || type == 'video' || type == 'file') && fileUrl != null) {
      List<Widget> contentWidgets = [];

      if (text.isNotEmpty) {
        contentWidgets.add(Text(text, style: theme.textTheme.bodyMedium));
        contentWidgets.add(const SizedBox(height: 8));
      }

      if (type == 'image') {
        contentWidgets.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _showFullScreenImage(fileUrl, context),
              child: Image.network(
                fileUrl,
                width: 250,
                height: 200,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 250,
                    height: 200,
                    color: Colors.grey[200],
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 250,
                  height: 200,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image, size: 50),
                ),
              ),
            ),
          ),
        );
      } else if (type == 'video') {
        contentWidgets.add(
          InkWell(
            onTap: () => _showVideoDialog(fileUrl, context),
            child: Container(
              width: 250,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_filled,
                      size: 50,
                      color: theme.primaryColor),
                  const SizedBox(height: 8),
                  Text('فيديو مرفق',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.primaryColor,
                      )),
                ],
              ),
            ),
          ),
        );
      } else if (type == 'file') {
        contentWidgets.add(
          InkWell(
            onTap: () async => await launchUrl(Uri.parse(fileUrl)),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insert_drive_file,
                      size: 30,
                      color: theme.primaryColor),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fileName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium),
                        Text('اضغط لفتح الملف',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.disabledColor,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: contentWidgets,
      );
    } else {
      content = Text(text, style: theme.textTheme.bodyMedium);
    }

    return VisibilityDetector(
      key: Key(msgId),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5) {
          _handleMessageVisibility(msgId, true);
        } else {
          _handleMessageVisibility(msgId, false);
        }
      },
      child: FutureBuilder<DocumentSnapshot?>(
        future: replyToId != null
            ? _firestore
            .collection('consultations')
            .doc(widget.consultationId)
            .collection('messages')
            .doc(replyToId)
            .get()
            : Future.value(null),
        builder: (context, snapshot) {
          final replyData = snapshot.data?.data() as Map<String, dynamic>?;
          final replyText = replyData?['text'] as String? ?? '';
          final replyFileName = replyData?['fileName'] as String? ?? '';

          final replyWidget = snapshot.hasData
              ? GestureDetector(
            onTap: () async {
              if (replyToId == null) return;

              setState(() => _highlightedMessageId = replyToId);
              await _scrollToMessage(replyToId);
              await Future.delayed(const Duration(seconds: 3));
              if (mounted && _highlightedMessageId == replyToId) {
                setState(() => _highlightedMessageId = null);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? theme.primaryColor.withOpacity(0.2)
                    : theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.primaryColor.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      replyText.isNotEmpty ? replyText : replyFileName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          )
              : const SizedBox.shrink();

          return GestureDetector(
            onLongPress: () => _handleLongPress(doc),
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
                _onReplyToMessage(doc);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Align(
                key: _messageKeys[msgId],
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: isHighlighted
                              ? theme.primaryColor.withOpacity(0.2)
                              : isMe
                              ? them.primary
                              : isDarkMode
                              ? Colors.grey[800]
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                          boxShadow: [
                            if (!isDarkMode && !isMe)
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 1,
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            replyWidget,
                            if (text.isNotEmpty || fileUrl != null) content,
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  time,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isMe
                                        ? theme.disabledColor
                                        : theme.disabledColor,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 6),
                                  _buildStatusIcon(status, isMe, theme),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDarkMode) {
    final userData = widget.isDoctor ? patientData : doctorData;
    final contactName = getUserName(userData, widget.isDoctor);
    final userImageUrl = getUserImageUrl(userData);

    return AppBar(
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      elevation: 1,
      iconTheme: IconThemeData(color: isDarkMode ? Colors.white : Colors.blue),
      titleSpacing: 0,
      title: InkWell(
        onTap: () => _showUserInfoDialog(context),
        child: Row(
          children: [
            Hero(
              tag: 'user-${widget.isDoctor ? widget.patientUid : widget.doctorUid}',
              child: CircleAvatar(
                radius: 20,
                backgroundColor: theme.primaryColor.withOpacity(0.2),
                backgroundImage: (userImageUrl != null && userImageUrl.isNotEmpty)
                    ? NetworkImage(userImageUrl)
                    : const AssetImage('assets/images/default_profile.png') as ImageProvider,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(widget.isDoctor ? widget.patientUid : widget.doctorUid).snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contactName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                        Text('',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.disabledColor,
                            )),
                      ],
                    );
                  }

                  final userData = snapshot.data!.data() as Map<String, dynamic>?;
                  final isOnline = userData?['isOnline'] as bool? ?? false;
                  final lastSeen = userData?['lastSeen'];
                  DateTime? lastSeenTime;

                  if (lastSeen != null) {
                    if (lastSeen is Timestamp) {
                      lastSeenTime = lastSeen.toDate();
                    } else if (lastSeen is Map) {
                      final seconds = lastSeen['seconds'] as int?;
                      final nanoseconds = lastSeen['nanoseconds'] as int?;
                      if (seconds != null) {
                        lastSeenTime = DateTime.fromMillisecondsSinceEpoch(
                          seconds * 1000 + (nanoseconds ?? 0) ~/ 1000000,
                        );
                      }
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contactName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                      Text(
                        isOnline
                            ? 'متصل الآن'
                            : lastSeenTime != null
                            ? 'آخر ظهور ${DateFormat('hh:mm a', 'ar').format(lastSeenTime)}'
                            : '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isOnline ? Colors.green : theme.disabledColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call),
          tooltip: 'مكالمة صوتية',
          onPressed: () => _showFeatureNotAvailable(context),
        ),
        IconButton(
          icon: const Icon(Icons.videocam),
          tooltip: 'مكالمة فيديو',
          onPressed: () {
            if (widget.isDoctor) {
              if (patientData != null) {
                ZegoUIKitPrebuiltCallInvitationService().send(
                  invitees: [
                    ZegoCallUser(
                      widget.patientUid,
                      widget.patientName, // تأكد أنه معرف في widget
                    ),
                  ],
                  isVideoCall: true,
                  callID: widget.consultationId,
                );
              }
            } else {
              if (doctorData != null) {
                ZegoUIKitPrebuiltCallInvitationService().send(
                  invitees: [
                    ZegoCallUser(
                      widget.doctorUid,
                      widget.doctorName, // تأكد أنه معرف في widget
                    ),
                  ],
                  isVideoCall: true,
                  callID: widget.consultationId,
                );
              }
            }
          },
        ),




        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) => _handleAppBarMenuSelection(value, context),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'info',
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('معلومات الجهة'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'search',
              child: Row(
                children: [
                  Icon(Icons.search, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('بحث في المحادثة'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'notifications',
              child: Row(
                children: [
                  Icon(Icons.notifications_none, color: theme.primaryColor),
                  const SizedBox(width: 8),
                  const Text('إعدادات الإشعارات'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, color: Colors.red[400]),
                  const SizedBox(width: 8),
                  const Text('حذف المحادثة'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: _buildAppBar(theme, isDarkMode),
      body: Column(
        children: [
          Expanded(
              child: Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[900] : Colors.grey[50],
                  ),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollEndNotification &&
                          _scrollController.position.pixels ==
                              _scrollController.position.minScrollExtent &&
                          _hasMoreMessages &&
                          !_isLoadingMore) {
                        _loadMoreMessages();
                      }
                      return false;
                    },
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('consultations')
                          .doc(widget.consultationId)
                          .collection('messages')
                          .orderBy('timestamp')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(theme.primaryColor),
                            ),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    size: 60,
                                    color: theme.disabledColor),
                                const SizedBox(height: 16),
                                Text('ابدأ المحادثة الآن',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: theme.disabledColor,
                                    )),
                              ],
                            ),
                          );
                        }

                        final docs = snapshot.data!.docs;
                        if (_lastMessage == null && docs.isNotEmpty) {
                          _lastMessage = docs.last;
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          itemCount: docs.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == docs.length) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(
                                    valueColor:
                                    AlwaysStoppedAnimation(theme.primaryColor),
                                  ),
                                ),
                              );
                            }
                            final doc = docs[index];
                            return _buildMessage(doc, theme, isDarkMode );
                          },
                          addAutomaticKeepAlives: true,
                          cacheExtent: 1000,
                        );
                      },
                    ),
                  ))),
              if (replyToMessage != null)
          _buildReplyPreview(replyToMessage, theme, isDarkMode),
          if (selectedMedia != null) _previewMedia(theme, isDarkMode),
          _buildMessageInput(theme, isDarkMode),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    selectedMedia?.delete();
    super.dispose();
  }
}