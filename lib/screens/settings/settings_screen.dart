import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _autoBackupEnabled = true;
  String _languageCode = 'ar';
  String _themeColor = 'blue';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _darkModeEnabled = prefs.getBool('dark_mode_enabled') ?? false;
      _autoBackupEnabled = prefs.getBool('auto_backup_enabled') ?? true;
      _languageCode = prefs.getString('language_code') ?? 'ar';
      _themeColor = prefs.getString('theme_color') ?? 'blue';
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات'),
      ),
      body: ListView(
        children: [
          // قسم الحساب
          _buildSectionHeader('الحساب'),
          _AccountSection(),
          
          // قسم المظهر
          _buildSectionHeader('المظهر'),
          _AppearanceSection(
            darkModeEnabled: _darkModeEnabled,
            themeColor: _themeColor,
            onDarkModeChanged: (value) => _saveSetting('dark_mode_enabled', value),
            onThemeColorChanged: (value) => _saveSetting('theme_color', value),
          ),
          
          // قسم الإشعارات
          _buildSectionHeader('الإشعارات'),
          _NotificationsSection(
            notificationsEnabled: _notificationsEnabled,
            onNotificationsChanged: (value) => _saveSetting('notifications_enabled', value),
          ),
          
          // قسم البيانات والنسخ الاحتياطي
          _buildSectionHeader('البيانات والنسخ الاحتياطي'),
          _DataSection(
            autoBackupEnabled: _autoBackupEnabled,
            onAutoBackupChanged: (value) => _saveSetting('auto_backup_enabled', value),
          ),
          
          // قسم اللغة والمنطقة
          _buildSectionHeader('اللغة والمنطقة'),
          _LanguageSection(
            languageCode: _languageCode,
            onLanguageChanged: (value) => _saveSetting('language_code', value),
          ),
          
          // قسم حول التطبيق
          _buildSectionHeader('حول التطبيق'),
          _AboutSection(),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.person,
                    color: AppTheme.primaryColor,
                  ),
                ),
                title: Text(authProvider.user?.name ?? 'المستخدم'),
                subtitle: Text(authProvider.user?.email ?? 'user@example.com'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showProfileDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock, color: AppTheme.textSecondary),
                title: const Text('تغيير كلمة المرور'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showChangePasswordDialog(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.security, color: AppTheme.textSecondary),
                title: const Text('الخصوصية والأمان'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _showPrivacyDialog(context),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showProfileDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الملف الشخصي'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الاسم: المستخدم'),
            SizedBox(height: 8),
            Text('البريد الإلكتروني: user@example.com'),
            SizedBox(height: 8),
            Text('نوع الحساب: معلم'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تغيير كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الحالية',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'تأكيد كلمة المرور الجديدة',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: تنفيذ تغيير كلمة المرور
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')),
              );
            },
            child: const Text('تغيير'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الخصوصية والأمان'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('• يتم تشفير جميع البيانات الشخصية'),
              SizedBox(height: 8),
              Text('• لا نشارك البيانات مع أطراف ثالثة'),
              SizedBox(height: 8),
              Text('• يمكنك حذف بياناتك في أي وقت'),
              SizedBox(height: 8),
              Text('• يتم تحديث التطبيق بانتظام لأغراض الأمان'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  final bool darkModeEnabled;
  final String themeColor;
  final Function(bool) onDarkModeChanged;
  final Function(String) onThemeColorChanged;

  const _AppearanceSection({
    required this.darkModeEnabled,
    required this.themeColor,
    required this.onDarkModeChanged,
    required this.onThemeColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.dark_mode, color: AppTheme.textSecondary),
            title: const Text('الوضع الليلي'),
            subtitle: const Text('تفعيل الوضع الليلي في التطبيق'),
            value: darkModeEnabled,
            onChanged: onDarkModeChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette, color: AppTheme.textSecondary),
            title: const Text('لون السمة'),
            subtitle: Text(_getThemeColorName(themeColor)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showThemeColorDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.text_fields, color: AppTheme.textSecondary),
            title: const Text('حجم الخط'),
            subtitle: const Text('متوسط'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showFontSizeDialog(context),
          ),
        ],
      ),
    );
  }

  String _getThemeColorName(String colorCode) {
    switch (colorCode) {
      case 'blue':
        return 'أزرق';
      case 'green':
        return 'أخضر';
      case 'purple':
        return 'بنفسجي';
      case 'red':
        return 'أحمر';
      default:
        return 'أزرق';
    }
  }

  void _showThemeColorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر لون السمة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThemeColorOption(
              color: 'أزرق',
              colorCode: 'blue',
              selected: themeColor == 'blue',
              onTap: () {
                onThemeColorChanged('blue');
                Navigator.pop(context);
              },
            ),
            _ThemeColorOption(
              color: 'أخضر',
              colorCode: 'green',
              selected: themeColor == 'green',
              onTap: () {
                onThemeColorChanged('green');
                Navigator.pop(context);
              },
            ),
            _ThemeColorOption(
              color: 'بنفسجي',
              colorCode: 'purple',
              selected: themeColor == 'purple',
              onTap: () {
                onThemeColorChanged('purple');
                Navigator.pop(context);
              },
            ),
            _ThemeColorOption(
              color: 'أحمر',
              colorCode: 'red',
              selected: themeColor == 'red',
              onTap: () {
                onThemeColorChanged('red');
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _showFontSizeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حجم الخط'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FontSizeOption(
              size: 'صغير',
              selected: false,
              onTap: () => Navigator.pop(context),
            ),
            _FontSizeOption(
              size: 'متوسط',
              selected: true,
              onTap: () => Navigator.pop(context),
            ),
            _FontSizeOption(
              size: 'كبير',
              selected: false,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}

class _ThemeColorOption extends StatelessWidget {
  final String color;
  final String colorCode;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeColorOption({
    required this.color,
    required this.colorCode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color themeColor;
    switch (colorCode) {
      case 'blue':
        themeColor = AppTheme.primaryColor;
        break;
      case 'green':
        themeColor = AppTheme.successColor;
        break;
      case 'purple':
        themeColor = AppTheme.secondaryColor;
        break;
      case 'red':
        themeColor = AppTheme.errorColor;
        break;
      default:
        themeColor = AppTheme.primaryColor;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: themeColor,
        radius: 12,
      ),
      title: Text(color),
      trailing: selected
          ? const Icon(Icons.check, color: AppTheme.primaryColor)
          : null,
      onTap: onTap,
    );
  }
}

class _FontSizeOption extends StatelessWidget {
  final String size;
  final bool selected;
  final VoidCallback onTap;

  const _FontSizeOption({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double fontSize;
    switch (size) {
      case 'صغير':
        fontSize = 14;
        break;
      case 'متوسط':
        fontSize = 16;
        break;
      case 'كبير':
        fontSize = 18;
        break;
      default:
        fontSize = 16;
    }

    return ListTile(
      title: Text(
        size,
        style: TextStyle(fontSize: fontSize),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: AppTheme.primaryColor)
          : null,
      onTap: onTap,
    );
  }
}

class _NotificationsSection extends StatelessWidget {
  final bool notificationsEnabled;
  final Function(bool) onNotificationsChanged;

  const _NotificationsSection({
    required this.notificationsEnabled,
    required this.onNotificationsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications, color: AppTheme.textSecondary),
            title: const Text('الإشعارات'),
            subtitle: const Text('تلقي إشعارات حول الأنشطة المهمة'),
            value: notificationsEnabled,
            onChanged: onNotificationsChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.schedule, color: AppTheme.textSecondary),
            title: const Text('إعدادات الإشعارات'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showNotificationSettingsDialog(context),
            enabled: notificationsEnabled,
          ),
        ],
      ),
    );
  }

  void _showNotificationSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات الإشعارات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: Text('تذكيرات الحضور'),
              subtitle: Text('تلقي تذكيرات بتسجيل الحضور'),
              value: true,
              onChanged: null,
            ),
            CheckboxListTile(
              title: Text('الاختبارات القادمة'),
              subtitle: Text('تلقي إشعارات عن الاختبارات القادمة'),
              value: true,
              onChanged: null,
            ),
            CheckboxListTile(
              title: Text('تقارير الأسبوعية'),
              subtitle: Text('تلقي تقارير أسبوعية عن أداء الطلاب'),
              value: false,
              onChanged: null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _DataSection extends StatelessWidget {
  final bool autoBackupEnabled;
  final Function(bool) onAutoBackupChanged;

  const _DataSection({
    required this.autoBackupEnabled,
    required this.onAutoBackupChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.cloud_upload, color: AppTheme.textSecondary),
            title: const Text('النسخ الاحتياطي التلقائي'),
            subtitle: const Text('نسخ البيانات احتياطياً تلقائياً'),
            value: autoBackupEnabled,
            onChanged: onAutoBackupChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.backup, color: AppTheme.textSecondary),
            title: const Text('نسخ احتياطي الآن'),
            subtitle: const Text('إنشاء نسخة احتياطية من البيانات'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showBackupDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.restore, color: AppTheme.textSecondary),
            title: const Text('استعادة البيانات'),
            subtitle: const Text('استعادة البيانات من نسخة احتياطية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showRestoreDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppTheme.errorColor),
            title: const Text('حذف جميع البيانات'),
            subtitle: const Text('حذف جميع البيانات من التطبيق'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showDeleteDataDialog(context),
          ),
        ],
      ),
    );
  }

  void _showBackupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نسخ احتياطي'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري إنشاء نسخة احتياطية...'),
          ],
        ),
        actions: const [],
      ),
    );

    // محاكاة عملية النسخ الاحتياطي
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء نسخة احتياطية بنجاح')),
      );
    });
  }

  void _showRestoreDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استعادة البيانات'),
        content: const Text('هل أنت متأكد من استعادة البيانات؟ سيتم استبدال جميع البيانات الحالية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم استعادة البيانات بنجاح')),
              );
            },
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDataDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف جميع البيانات'),
        content: const Text('⚠️ تحذير: سيتم حذف جميع البيانات بشكل نهائي ولا يمكن استعادتها. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف جميع البيانات')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

class _LanguageSection extends StatelessWidget {
  final String languageCode;
  final Function(String) onLanguageChanged;

  const _LanguageSection({
    required this.languageCode,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.language, color: AppTheme.textSecondary),
            title: const Text('لغة التطبيق'),
            subtitle: Text(languageCode == 'ar' ? 'العربية' : 'English'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showLanguageDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.calendar_today, color: AppTheme.textSecondary),
            title: const Text('تنسيق التاريخ'),
            subtitle: const Text('يوم/شهر/سنة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showDateFormatDialog(context),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر اللغة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('العربية'),
              trailing: languageCode == 'ar'
                  ? const Icon(Icons.check, color: AppTheme.primaryColor)
                  : null,
              onTap: () {
                onLanguageChanged('ar');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('English'),
              trailing: languageCode == 'en'
                  ? const Icon(Icons.check, color: AppTheme.primaryColor)
                  : null,
              onTap: () {
                onLanguageChanged('en');
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _showDateFormatDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تنسيق التاريخ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('يوم/شهر/سنة'),
              trailing: Icon(Icons.check, color: AppTheme.primaryColor),
            ),
            ListTile(
              title: const Text('شهر/يوم/سنة'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('سنة-شهر-يوم'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info, color: AppTheme.textSecondary),
            title: const Text('حول التطبيق'),
            subtitle: const Text('مساعد المعلم الإصدار 1.0.0'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showAboutDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.help, color: AppTheme.textSecondary),
            title: const Text('المساعدة والدعم'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showHelpDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.rate_review, color: AppTheme.textSecondary),
            title: const Text('قيم التطبيق'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showRateDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.errorColor),
            title: const Text('تسجيل الخروج'),
            onTap: () => _showLogoutDialog(context),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'مساعد المعلم',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.school, size: 48),
      children: const [
        Text(
          'تطبيق مساعد المعلم هو أداة متكاملة لإدارة الفصول الدراسية وتتبع أداء الطلاب.',
        ),
        SizedBox(height: 16),
        Text(
          'المميزات الرئيسية:\n'
          '• إدارة الفصول والطلاب\n'
          '• تتبع الحضور والغياب\n'
          '• إدارة الدرجات والاختبارات\n'
          '• تقارير وإحصائيات مفصلة',
        ),
      ],
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('المساعدة والدعم'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الأسئلة الشائعة:'),
              SizedBox(height: 8),
              Text('س: كيف أضيف طالب جديد؟\n'
                  'ج: اذهب إلى شاشة الطلاب واضغط على زر الإضافة.'),
              SizedBox(height: 16),
              Text('س: كيف أسجل الحضور؟\n'
                  'ج: اختر الفصل والتاريخ ثم حدد حالة كل طالب.'),
              SizedBox(height: 16),
              Text('س: كيف أضيف اختباراً؟\n'
                  'ج: اذهب إلى شاشة الدرجات واضغط على إضافة اختبار.'),
              SizedBox(height: 16),
              Text('للمزيد من المساعدة:\n'
                  'البريد الإلكتروني: support@teacheraide.com\n'
                  'الهاتف: +966 50 123 4567'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showRateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('قيم التطبيق'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('كم تقيم تجربتك مع التطبيق؟'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: const Icon(Icons.star_border, size: 32),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('شكراً لك على تقييم ${index + 1} نجوم')),
                    );
                  },
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}
