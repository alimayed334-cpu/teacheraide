import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/student_model.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/student_status_indicator.dart';
import 'add_student_screen.dart';
import 'student_assignments_screen.dart';
import 'student_attendance_screen.dart';
import '../notes/student_notes_main_screen.dart';

class StudentDetailsScreen extends StatefulWidget {
  final StudentModel student;

  const StudentDetailsScreen({
    super.key,
    required this.student,
  });

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  late StudentModel _currentStudent;

  @override
  void initState() {
    super.initState();
    _currentStudent = widget.student;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Consumer<ClassProvider>(
          builder: (context, classProvider, child) {
            final className = classProvider.getClassById(_currentStudent.classId)?.name ?? 'فصل غير محدد';
            return Text(
              'الفصل : $className',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            );
          },
        ),
        actions: [],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // قسم صورة الحساب
            _buildProfileSection(),
            const SizedBox(height: 24),
            
            // قسم معلومات الاتصال
            _buildContactInfoSection(),
            const SizedBox(height: 16),
            
            // قسم ولي الأمر الأول
            if (_currentStudent.primaryGuardian != null) ...[
              _buildGuardianSection(
                guardian: _currentStudent.primaryGuardian!,
                title: 'ولي الأمر الأول',
                iconColor: Colors.yellow,
              ),
              const SizedBox(height: 16),
            ],
            
            // قسم ولي الأمر الثاني
            if (_currentStudent.secondaryGuardian != null) ...[
              _buildGuardianSection(
                guardian: _currentStudent.secondaryGuardian!,
                title: 'ولي الأمر الثاني',
                iconColor: Colors.yellow,
              ),
              const SizedBox(height: 32),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _editStudent,
        backgroundColor: const Color(0xFFFFD700),
        icon: const Icon(Icons.edit, color: Colors.black),
        label: const Text(
          'تعديل',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildProfileSection() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2A2A2A),
            const Color(0xFF1E1E1E),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // صورة الطالب
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withValues(alpha: 0.1),
                    AppTheme.primaryColor.withValues(alpha: 0.2),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFFFFD700),
                  width: 2,
                ),
              ),
              child: _currentStudent.photoPath != null
                  ? ClipOval(
                      child: Image.file(
                        File(_currentStudent.photoPath!),
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildDefaultAvatar();
                        },
                      ),
                    )
                  : _currentStudent.photo != null
                      ? ClipOval(
                          child: Image.network(
                            _currentStudent.photo!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildDefaultAvatar();
                            },
                          ),
                        )
                      : _buildDefaultAvatar(),
            ),
            const SizedBox(height: 16),
            
            // اسم الطالب
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentStudent.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(width: 8),
                StudentStatusIndicator(student: _currentStudent),
                const SizedBox(width: 8),
                // أيقونة الواجبات
                GestureDetector(
                  onTap: _navigateToAssignments,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFFFD700),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.assignment,
                      color: Color(0xFFFFD700),
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            
            // ID الطالب
            Text(
              'ID: ${_currentStudent.studentId ?? 'غير محدد'}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            
            // تاريخ الميلاد
            if (_currentStudent.birthDate != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cake,
                      color: Colors.amber,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'مواليد الطالب: ${_formatDate(_currentStudent.birthDate!)}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return CircleAvatar(
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      child: Text(
        _currentStudent.name.isNotEmpty ? _currentStudent.name.substring(0, 1).toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildContactInfoSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // أيقونات الاتصال
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // أيقونة الاتصال
                _buildContactIcon(
                  icon: Icons.call,
                  color: Colors.green,
                  onTap: () => _makePhoneCall(_currentStudent.phone),
                ),
                // أيقونة المراسلة
                _buildContactIcon(
                  icon: Icons.message,
                  color: Colors.blue,
                  onTap: () => _showMessageOptions(_currentStudent.phone, _currentStudent.name),
                ),
                // أيقونة الإيميل
                _buildContactIcon(
                  icon: Icons.email,
                  color: Colors.red,
                  onTap: () => _openEmail(_currentStudent.email ?? ''),
                ),
              ],
            ),
          ),
          
          // معلومات الاتصال
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (_currentStudent.phone != null && _currentStudent.phone!.isNotEmpty) ...[
                  _buildContactItem(
                    icon: Icons.phone,
                    text: _currentStudent.phone!,
                    isPhone: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (_currentStudent.email != null && _currentStudent.email!.isNotEmpty) ...[
                  _buildContactItem(
                    icon: Icons.email_outlined,
                    text: _currentStudent.email!,
                  ),
                  const SizedBox(height: 12),
                ],
                _buildContactItem(
                  icon: Icons.location_on_outlined,
                  text: _currentStudent.location ?? 'موقع الطالب الذي أدخلته',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  
  String _formatDate(DateTime date) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildContactItem({
    required IconData icon,
    required String text,
    bool isPhone = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          color: Colors.amber,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessagingOptions(String phoneNumber) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.message,
        color: Colors.green,
        size: 20,
      ),
      color: const Color(0xFF2A2A2A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onSelected: (String method) {
        _handleMessagingAction(method, phoneNumber);
      },
      itemBuilder: (BuildContext context) => [
        PopupMenuItem<String>(
          value: 'whatsapp',
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.message,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'WhatsApp',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'telegram',
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Telegram',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'sms',
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sms,
                  color: Colors.white,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'SMS',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleMessagingAction(String method, String phoneNumber) async {
    final cleanE164 = _normalizePhoneE164(phoneNumber);
    final cleanWa = _phoneForWaMe(phoneNumber);
    if (cleanE164.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رقم الهاتف غير صالح'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    Uri url;
    switch (method) {
      case 'whatsapp':
        if (cleanWa.isEmpty) return;
        url = Uri.parse('https://wa.me/$cleanWa');
        break;
      case 'telegram':
        url = Uri.https('t.me', '/share/url', {'text': ''});
        break;
      case 'sms':
        url = Uri(scheme: 'sms', path: cleanE164);
        break;
      default:
        return;
    }

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('لا يمكن فتح $method'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  
  Widget _buildGuardianSection({
    required GuardianModel guardian,
    required String title,
    required Color iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // أيقونات ولي الأمر
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // أيقونة الاتصال بولي الأمر
                _buildContactIcon(
                  icon: Icons.call,
                  color: Colors.green,
                  onTap: () => _makePhoneCall(guardian.phone),
                ),
                // أيقونة المراسلة لولي الأمر
                _buildContactIcon(
                  icon: Icons.message,
                  color: Colors.blue,
                  onTap: () => _showMessageOptions(guardian.phone, guardian.name),
                ),
                // أيقونة الإيميل لولي الأمر
                _buildContactIcon(
                  icon: Icons.email,
                  color: Colors.red,
                  onTap: () => _openEmail(guardian.email ?? ''),
                ),
              ],
            ),
          ),
          
          // معلومات ولي الأمر
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title - ${guardian.name}',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (guardian.phone != null && guardian.phone!.isNotEmpty) ...[
                  _buildContactItem(
                    icon: Icons.phone,
                    text: guardian.phone!,
                    isPhone: true,
                  ),
                  const SizedBox(height: 8),
                ],
                if (guardian.email != null && guardian.email!.isNotEmpty) ...[
                  _buildContactItem(
                    icon: Icons.email_outlined,
                    text: guardian.email!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _shareStudentInfo() {
    final className = context.read<ClassProvider>().getClassById(_currentStudent.classId)?.name ?? 'فصل غير محدد';
    final studentInfo = '''
معلومات الطالب:
الاسم: ${_currentStudent.name}
ID: ${_currentStudent.studentId ?? 'غير محدد'}
الفصل: $className
${_currentStudent.phone != null && _currentStudent.phone!.isNotEmpty ? 'رقم الهاتف: ${_currentStudent.phone}' : ''}
${_currentStudent.email != null && _currentStudent.email!.isNotEmpty ? 'البريد الإلكتروني: ${_currentStudent.email}' : ''}
${_currentStudent.birthDate != null ? 'مواليد الطالب: ${_formatDate(_currentStudent.birthDate!)}' : ''}
${_currentStudent.location != null && _currentStudent.location!.isNotEmpty ? 'الموقع: ${_currentStudent.location}' : ''}
${_currentStudent.primaryGuardian != null ? 'ولي الأمر الأول: ${_currentStudent.primaryGuardian!.name}' : ''}
${_currentStudent.secondaryGuardian != null ? 'ولي الأمر الثاني: ${_currentStudent.secondaryGuardian!.name}' : ''}
''';

    Clipboard.setData(ClipboardData(text: studentInfo));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ معلومات الطالب'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _editStudent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddStudentScreen(
          student: _currentStudent,
        ),
      ),
    );
    
    // إذا تم تحديث البيانات، قم بتحديث الصفحة الحالية
    if (result == true && mounted) {
      // تحديث بيانات الطالب الحالية
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final updatedStudent = await studentProvider.getStudentById(_currentStudent.id!);
      
      if (updatedStudent != null && mounted) {
        setState(() {
          _currentStudent = updatedStudent;
        });
      }
    }
  }

  void _navigateToAssignments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAssignmentsScreen(
          student: _currentStudent,
        ),
      ),
    ).then((_) {
      // تحديث بيانات الطالب عند العودة
      _refreshStudentData();
    });
  }

  void _navigateToAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAttendanceScreen(
          student: _currentStudent,
          classModel: Provider.of<ClassProvider>(context, listen: false)
              .getClassById(_currentStudent.classId)!,
        ),
      ),
    ).then((_) {
      // تحديث بيانات الطالب عند العودة
      _refreshStudentData();
    });
  }

  void _navigateToNotes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentNotesMainScreen(
          student: _currentStudent,
          classModel: Provider.of<ClassProvider>(context, listen: false)
              .getClassById(_currentStudent.classId)!,
        ),
      ),
    );
  }

  Widget _buildNavItem(String title, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _refreshStudentData() async {
    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final updatedStudent = await studentProvider.getStudentById(_currentStudent.id!);
      if (updatedStudent != null && mounted) {
        setState(() {
          _currentStudent = updatedStudent;
        });
      }
    } catch (e) {
      print('Error refreshing student data: $e');
    }
  }

  // بناء أيقونة الاتصال التفاعلية
  Widget _buildContactIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: color,
          size: 24,
        ),
      ),
    );
  }

  // الاتصال بالطالب
  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _showSnackBar('لا يوجد رقم هاتف للطالب', Colors.orange);
      return;
    }

    try {
      final clean = _normalizePhoneE164(phoneNumber);
      if (clean.isEmpty) {
        _showSnackBar('رقم الهاتف غير صالح', Colors.red);
        return;
      }

      final Uri phoneUri = Uri(scheme: 'tel', path: clean);
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('لا يمكن فتح تطبيق الاتصال', Colors.red);
      }
    } catch (e) {
      _showSnackBar('حدث خطأ: $e', Colors.red);
    }
  }

  // عرض خيارات المراسلة
  void _showMessageOptions(String? phoneNumber, String studentName) {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      _showSnackBar('لا يوجد رقم هاتف للطالب', Colors.orange);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'اختر طريقة المراسلة مع $studentName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildMessageOption(
                  icon: Icons.telegram,
                  label: 'Telegram',
                  color: Colors.blue,
                  onTap: () => _openTelegram(phoneNumber),
                ),
                _buildMessageOption(
                  icon: Icons.message,
                  label: 'WhatsApp',
                  color: Colors.green,
                  onTap: () => _openWhatsApp(phoneNumber),
                ),
                _buildMessageOption(
                  icon: Icons.sms,
                  label: 'SMS',
                  color: Colors.orange,
                  onTap: () => _openSMS(phoneNumber),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _normalizePhoneE164(String input, {String defaultCountryCode = '+964'}) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    final hasPlus = raw.startsWith('+');
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return '';

    if (hasPlus) {
      return '+$digitsOnly';
    }

    // Remove leading zeros
    var local = digitsOnly;
    while (local.startsWith('0')) {
      local = local.substring(1);
    }

    final ccDigits = defaultCountryCode.replaceAll('+', '');
    if (local.startsWith(ccDigits)) {
      return '+$local';
    }

    return '$defaultCountryCode$local';
  }

  String _phoneForWaMe(String input) {
    final e164 = _normalizePhoneE164(input);
    if (e164.isEmpty) return '';
    return e164.replaceAll('+', '');
  }

  // بناء خيار المراسلة
  Widget _buildMessageOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // فتح Telegram
  Future<void> _openTelegram(String phoneNumber) async {
    try {
      final clean = _normalizePhoneE164(phoneNumber);
      if (clean.isEmpty) {
        _showSnackBar('رقم الهاتف غير صالح', Colors.red);
        return;
      }

      // فتح مشاركة داخل تيليكرام (أفضل تجربة، ولا تعتمد على user/username)
      final tgShare = Uri.https('t.me', '/share/url', {'text': ''});
      final ok = await launchUrl(tgShare, mode: LaunchMode.externalApplication);
      if (ok) return;

      _showSnackBar('لا يمكن فتح Telegram', Colors.red);
    } catch (e) {
      _showSnackBar('خطأ في فتح Telegram: $e', Colors.red);
    }
  }

  // فتح WhatsApp
  Future<void> _openWhatsApp(String phoneNumber) async {
    try {
      final wa = _phoneForWaMe(phoneNumber);
      if (wa.isEmpty) {
        _showSnackBar('رقم الهاتف غير صالح', Colors.red);
        return;
      }

      final Uri whatsappUri = Uri.parse('https://wa.me/$wa');
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('لا يمكن فتح WhatsApp', Colors.red);
      }
    } catch (e) {
      _showSnackBar('حدث خطأ: $e', Colors.red);
    }
  }

  // فتح SMS
  Future<void> _openSMS(String phoneNumber) async {
    try {
      final clean = _normalizePhoneE164(phoneNumber);
      if (clean.isEmpty) {
        _showSnackBar('رقم الهاتف غير صالح', Colors.red);
        return;
      }

      final Uri smsUri = Uri(scheme: 'sms', path: clean);
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('لا يمكن فتح تطبيق الرسائل', Colors.red);
      }
    } catch (e) {
      _showSnackBar('حدث خطأ: $e', Colors.red);
    }
  }

  // إرسال إيميل
  Future<void> _openEmail(String email) async {
    if (email.trim().isEmpty) {
      _showSnackBar('لا يوجد بريد إلكتروني', Colors.red);
      return;
    }

    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: email.trim(),
      );

      final okExternal = await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      if (okExternal) return;

      final okDefault = await launchUrl(emailUri, mode: LaunchMode.platformDefault);
      if (okDefault) return;

      _showSnackBar('لا يمكن فتح تطبيق الإيميل', Colors.red);
    } catch (e) {
      _showSnackBar('خطأ في فتح الإيميل: $e', Colors.red);
    }
  }

  // عرض رسالة
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

}
