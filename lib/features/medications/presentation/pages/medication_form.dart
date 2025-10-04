import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MedicationFormScreen extends StatefulWidget {
  final String userId;
  final DocumentSnapshot? doc;

  const MedicationFormScreen({super.key, required this.userId, this.doc});

  @override
  State<MedicationFormScreen> createState() => _MedicationFormScreenState();
}

class _MedicationFormScreenState extends State<MedicationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameController;
  late TextEditingController doseController;
  late TextEditingController scheduleController;
  late TextEditingController notesController;
  late TextEditingController durationController;
  late TextEditingController typeController;

  List<TimeOfDay> selectedTimes = [];

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() as Map<String, dynamic>?;

    nameController = TextEditingController(text: data?['name'] ?? '');
    doseController = TextEditingController(text: data?['dose'] ?? '');
    scheduleController = TextEditingController(text: data?['schedule'] ?? '');
    notesController = TextEditingController(text: data?['notes'] ?? '');
    durationController = TextEditingController(text: data?['duration'] ?? '');
    typeController = TextEditingController(text: data?['type'] ?? '');

    selectedTimes = data?['times'] != null
        ? List<String>.from(data!['times']).map((t) {
      final date = DateFormat('hh:mm a').parse(t);
      return TimeOfDay(hour: date.hour, minute: date.minute);
    }).toList()
        : [];
  }

  String formatTimeOfDayTo12Hour(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt);
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      setState(() {
        selectedTimes.add(time);
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    doseController.dispose();
    scheduleController.dispose();
    notesController.dispose();
    durationController.dispose();
    typeController.dispose();
    super.dispose();
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) return;

    final medicationData = {
      'name': nameController.text.trim(),
      'dose': doseController.text.trim(),
      'schedule': scheduleController.text.trim(),
      'userId': widget.userId,
      'createdAt': FieldValue.serverTimestamp(),
      'notes': notesController.text.trim(),
      'duration': durationController.text.trim(),
      'type': typeController.text.trim(),
      'times': selectedTimes.map((t) => formatTimeOfDayTo12Hour(t)).toList(),
      'history': widget.doc?.get('history') ?? [],
    };

    if (widget.doc != null) {
      await widget.doc!.reference.update(medicationData);
    } else {
      await FirebaseFirestore.instance.collection('medications').add(medicationData);
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.doc != null;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode? Colors.grey[900]: Colors.white,
        foregroundColor: Colors.blue,
        elevation: 2,
        title: Text(isEditing ? 'تعديل الدواء' : 'إضافة دواء جديد'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              _buildInputField(
                controller: nameController,
                label: 'اسم الدواء',
                icon: Icons.medical_services,
                validator: (v) => v == null || v.isEmpty ? 'يرجى إدخال اسم الدواء' : null,
              ),
              _buildInputField(
                controller: doseController,
                label: 'الجرعة',
                icon: Icons.local_pharmacy,
              ),
              _buildInputField(
                controller: scheduleController,
                label: 'جدول الجرعات',
                icon: Icons.schedule,
              ),
              _buildInputField(
                controller: durationController,
                label: 'مدة العلاج',
                icon: Icons.timelapse,
              ),
              _buildInputField(
                controller: typeController,
                label: 'نوع الدواء',
                icon: Icons.category,
              ),
              _buildInputField(
                controller: notesController,
                label: 'ملاحظات الطبيب',
                icon: Icons.note_alt,
              ),
              const SizedBox(height: 8),
              const Text('أوقات تناول الدواء:'),
              Wrap(
                spacing: 8,
                children: selectedTimes.map((time) {
                  return Chip(
                    label: Text(time.format(context)),
                    onDeleted: () {
                      setState(() {
                        selectedTimes.remove(time);
                      });
                    },
                  );
                }).toList(),
              ),
              TextButton.icon(
                icon: const Icon(Icons.access_time),
                label: const Text('إضافة وقت'),
                onPressed: _selectTime,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: _saveMedication,
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
