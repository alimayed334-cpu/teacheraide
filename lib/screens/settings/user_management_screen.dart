import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../../providers/auth_provider.dart';
import 'package:arabic_font/arabic_font.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;

  Future<void> _editUserRole(BuildContext context, Map<String, dynamic> user) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.userRole != UserRole.admin) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الميزة للأدمن فقط')),
      );
      return;
    }

    final uid = (user['id'] ?? '').toString();
    if (uid.isEmpty) return;

    final myUid = fb.FirebaseAuth.instance.currentUser?.uid;
    final isSelf = myUid != null && uid == myUid;
    if (isSelf) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن تغيير صلاحيتك')),
      );
      return;
    }

    final roleStr = (user['role']?.toString().toLowerCase() ?? 'assistant');
    UserRole selectedRole = switch (roleStr) {
      'admin' => UserRole.admin,
      'banned' => UserRole.banned,
      _ => UserRole.assistant,
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تغيير الصلاحية'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return DropdownButtonFormField<UserRole>(
                value: selectedRole,
                items: const [
                  DropdownMenuItem(value: UserRole.admin, child: Text('أدمن')),
                  DropdownMenuItem(value: UserRole.assistant, child: Text('مساعد')),
                  DropdownMenuItem(value: UserRole.banned, child: Text('محظور')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => selectedRole = v);
                },
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;

    final ok = await authProvider.updateUserRole(userId: uid, role: selectedRole);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل تحديث الصلاحية (تأكد من صلاحيات الأدمن وقواعد Firestore)')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تحديث الصلاحية بنجاح')),
    );
    await _loadUsers();
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final users = await authProvider.getAllUsers();
      setState(() => _users = users);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل المستخدمين: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'إدارة المستخدمين',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFFFD700)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFFFFD700)),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFFD700),
              ),
            )
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 80,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'لا يوجد مستخدمون',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final role = (user['role']?.toString() ?? 'user');
                    final uid = (user['id'] ?? '').toString();
                    final myUid = fb.FirebaseAuth.instance.currentUser?.uid;
                    final isSelf = myUid != null && uid == myUid;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF404040),
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        onTap: () => _editUserRole(context, user),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFFD700).withOpacity(0.2),
                          child: Text(
                            user['name']?.toString().substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        title: Text(
                          user['name']?.toString() ?? '',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              user['email']?.toString() ?? '',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'تاريخ الإنشاء: ${_formatDate(user['createdAt'])}',
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFD700).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFFD700).withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                _roleLabel(role),
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: const Color(0xFFFFD700),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.edit,
                              color: isSelf ? Colors.grey : const Color(0xFFFFD700),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'أدمن';
      case 'assistant':
      case 'user':
        return 'مساعد';
      case 'banned':
        return 'محظور';
      default:
        return 'مساعد';
    }
  }

  String _formatDate(dynamic value) {
    try {
      if (value == null) return '';

      DateTime date;
      if (value is DateTime) {
        date = value;
      } else if (value is String) {
        date = DateTime.parse(value);
      } else {
        // Firestore Timestamp has toDate()
        final dynamic maybeDate = (value as dynamic).toDate();
        if (maybeDate is DateTime) {
          date = maybeDate;
        } else {
          return value.toString();
        }
      }
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return value?.toString() ?? '';
    }
  }
}
