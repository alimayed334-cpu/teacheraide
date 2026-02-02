import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/student_model.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../theme/app_theme.dart';
import 'add_student_screen.dart';
import 'student_assignments_screen.dart';

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
            final className = classProvider.getClassById(widget.student.classId)?.name ?? 'فصل غير محدد';
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
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareStudentInfo,
          ),
        ],
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
            if (widget.student.primaryGuardian != null) ...[
              _buildGuardianSection(
                guardian: widget.student.primaryGuardian!,
                title: 'ولي الأمر الأول',
                iconColor: Colors.yellow,
              ),
              const SizedBox(height: 16),
            ],
            
            // قسم ولي الأمر الثاني
            if (widget.student.secondaryGuardian != null) ...[
              _buildGuardianSection(
                guardian: widget.student.secondaryGuardian!,
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
          'Edit',
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
              child: widget.student.photo != null
                  ? ClipOval(
                      child: Image.network(
                        widget.student.photo!,
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
                  widget.student.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFFD700),
                  ),
                ),
                const SizedBox(width: 8),
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
              'ID: ${widget.student.studentId ?? 'غير محدد'}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            
            // تاريخ الميلاد
            if (widget.student.birthDate != null) ...[
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
                      'مواليد الطالب: ${_formatDate(widget.student.birthDate!)}',
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
        widget.student.name.isNotEmpty ? widget.student.name.substring(0, 1).toUpperCase() : '?',
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.call, color: Colors.amber, size: 24),
                Icon(Icons.message, color: Colors.amber, size: 24),
                Icon(Icons.email, color: Colors.amber, size: 24),
                Icon(Icons.location_on_outlined, color: Colors.amber, size: 24),
              ],
            ),
          ),
          
          // معلومات الاتصال
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                if (widget.student.phone != null && widget.student.phone!.isNotEmpty) ...[
                  _buildContactItem(
                    icon: Icons.phone,
                    text: widget.student.phone!,
                    isPhone: true,
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.student.email != null && widget.student.email!.isNotEmpty) ...[
                  _buildContactItem(
                    icon: Icons.email_outlined,
                    text: widget.student.email!,
                  ),
                  const SizedBox(height: 12),
                ],
                _buildContactItem(
                  icon: Icons.location_on_outlined,
                  text: widget.student.location ?? 'موقع الطالب الذي أدخلته',
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
        if (isPhone) ...[
          _buildMessagingOptions(text),
        ],
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
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    
    Uri url;
    switch (method) {
      case 'whatsapp':
        url = Uri.parse('https://wa.me/$cleanPhone');
        break;
      case 'telegram':
        url = Uri.parse('https://t.me/$cleanPhone');
        break;
      case 'sms':
        url = Uri.parse('sms:$cleanPhone');
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.call, color: Colors.yellow, size: 24),
                Icon(Icons.message, color: Colors.yellow, size: 24),
                Icon(Icons.email, color: Colors.yellow, size: 24),
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
    final className = context.read<ClassProvider>().getClassById(widget.student.classId)?.name ?? 'فصل غير محدد';
    final studentInfo = '''
معلومات الطالب:
الاسم: ${widget.student.name}
ID: ${widget.student.studentId ?? 'غير محدد'}
الفصل: $className
${widget.student.phone != null && widget.student.phone!.isNotEmpty ? 'رقم الهاتف: ${widget.student.phone}' : ''}
${widget.student.email != null && widget.student.email!.isNotEmpty ? 'البريد الإلكتروني: ${widget.student.email}' : ''}
${widget.student.birthDate != null ? 'مواليد الطالب: ${_formatDate(widget.student.birthDate!)}' : ''}
${widget.student.location != null && widget.student.location!.isNotEmpty ? 'الموقع: ${widget.student.location}' : ''}
${widget.student.primaryGuardian != null ? 'ولي الأمر الأول: ${widget.student.primaryGuardian!.name}' : ''}
${widget.student.secondaryGuardian != null ? 'ولي الأمر الثاني: ${widget.student.secondaryGuardian!.name}' : ''}
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
          student: widget.student,
        ),
      ),
    );
    
    // إذا تم تحديث البيانات، قم بتحديث الصفحة الحالية
    if (result == true && mounted) {
      // تحديث بيانات الطالب الحالية
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final updatedStudent = await studentProvider.getStudentById(widget.student.id!);
      
      if (updatedStudent != null && mounted) {
        setState(() {
          // سيتم تحديث الواجهة تلقائياً عند العودة
        });
      }
    }
  }

  void _navigateToAssignments() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAssignmentsScreen(
          student: widget.student,
        ),
      ),
    );
  }
}
