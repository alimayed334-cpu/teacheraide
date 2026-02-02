import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/class_provider.dart';
import '../providers/student_provider.dart';
import '../providers/exam_provider.dart';
import '../models/class_model.dart';
import '../theme/app_theme.dart';
import 'attendance/new_attendance_screen.dart';
import 'exams/exams_screen.dart';
import 'settings/settings_screen_new.dart';
import 'settings/user_management_screen.dart';
import 'reports/reports_screen.dart';
import 'at_risk/at_risk_students_screen.dart';
import 'excellent/excellent_students_screen.dart';
import 'notes/class_notes_screen.dart';
import 'notes/student_notes_main_screen.dart';
import 'exports/export_files_screen.dart';
import 'at_risk/at_risk_students_screen.dart';
import 'messaging/messaging_screen.dart';
import 'financial/financial_dashboard_screen.dart';
// import '../utils/sample_data_helper.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  ClassModel? _selectedClass;
  int _currentTabIndex = 0;
  List<ClassModel> _classes = [];
  final ValueNotifier<int> _studentCountNotifier = ValueNotifier<int>(0);
  bool _isDisposed = false;
  ClassProvider? _classProvider;
  VoidCallback? _classProviderListener;
  List<int> _lastClassIds = const [];

  bool _sameIds(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _attachClassProviderListener() {
    if (_classProviderListener != null) return;

    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    _classProvider = classProvider;

    _lastClassIds = classProvider.classes
        .map((c) => c.id ?? -1)
        .toList()
      ..sort();

    _classProviderListener = () {
      if (!mounted || _isDisposed) return;

      final current = classProvider.classes;
      final ids = current.map((c) => c.id ?? -1).toList()..sort();
      if (_sameIds(ids, _lastClassIds)) return;
      _lastClassIds = ids;

      setState(() {
        _classes = current;
      });

      ClassModel? nextSelected = _selectedClass;
      if (current.isEmpty) {
        nextSelected = null;
      } else if (nextSelected == null) {
        nextSelected = current.first;
      } else {
        final stillExists = current.any((c) => c.id != null && c.id == nextSelected!.id);
        if (!stillExists) {
          nextSelected = current.first;
        }
      }

      if ((nextSelected?.id) != (_selectedClass?.id)) {
        Future.microtask(() async {
          if (!mounted || _isDisposed) return;
          await _setSelectedClass(nextSelected);
        });
      }
    };

    classProvider.addListener(_classProviderListener!);
  }

  void _setSelectedClassStateOnly(ClassModel? value) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _selectedClass = value;
    });
  }

  Future<void> _setSelectedClass(ClassModel? value) async {
    if (!mounted || _isDisposed) return;

    setState(() {
      _selectedClass = value;
    });

    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    final cid = _selectedClass?.id;
    if (cid != null) {
      await studentProvider.loadStudentsByClass(cid);
      await examProvider.loadExamsByClass(cid);
      await _updateStudentCount();
    }
  }

  @override
  void initState() {
    super.initState();
    // استخدام addPostFrameCallback لتجنب setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachClassProviderListener();
      _loadClasses();
    });
  }

  Future<void> _loadClasses() async {
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    await classProvider.loadClasses();

    if (!mounted || _isDisposed) return;

    final loaded = classProvider.classes;
    ClassModel? nextSelected = _selectedClass;

    if (loaded.isEmpty) {
      nextSelected = null;
    } else if (nextSelected == null) {
      nextSelected = loaded.first;
    } else {
      final stillExists = loaded.any((c) => c.id != null && c.id == nextSelected!.id);
      if (!stillExists) {
        nextSelected = loaded.first;
      }
    }

    if (!mounted || _isDisposed) return;
    setState(() {
      _classes = loaded;
    });

    await _setSelectedClass(nextSelected);
  }

  Future<void> _reloadClassesListOnly() async {
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    await classProvider.loadClasses();
    if (!mounted || _isDisposed) return;
    setState(() {
      _classes = classProvider.classes;
    });
  }

  Future<int> _getStudentCount(int classId) async {
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    return await classProvider.getStudentCount(classId);
  }

  Future<void> _updateStudentCount() async {
    if (_selectedClass == null) return;
    if (!mounted || _isDisposed) return;

    final count = await _getStudentCount(_selectedClass!.id!);
    _studentCountNotifier.value = count;
  }

  Future<void> _refreshAllProviders() async {
    if (!mounted || _isDisposed) return;
    
    // Refresh all providers to ensure data consistency
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    
    await classProvider.loadClasses();
    if (_selectedClass != null) {
      await studentProvider.loadStudentsByClass(_selectedClass!.id!);
      await examProvider.loadExamsByClass(_selectedClass!.id!);
    }
    
    await _updateStudentCount();
  }

  @override
  void dispose() {
    _isDisposed = true;
    final listener = _classProviderListener;
    if (listener != null) {
      try {
        _classProvider?.removeListener(listener);
      } catch (_) {}
      _classProviderListener = null;
    }
    _studentCountNotifier.dispose();
    super.dispose();
  }

  void _showClassSelector() async {
    // إعادة تحميل الفصول في كل مرة لضمان عرض جميع الفصول
    await _reloadClassesListOnly();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('اختر الفصل'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _classes.length + 1,
            itemBuilder: (context, index) {
              if (index == _classes.length) {
                return ListTile(
                  leading: const Icon(Icons.add_circle, color: AppTheme.primaryColor),
                  title: const Text('إضافة فصل جديد'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddClassDialog();
                  },
                );
              }
              
              final classModel = _classes[index];
              return FutureBuilder<int>(
                future: _getStudentCount(classModel.id!),
                builder: (context, snapshot) {
                  final studentCount = snapshot.data ?? 0;
                  return ListTile(
                    leading: Icon(
                      Icons.class_,
                      color: _selectedClass?.id == classModel.id 
                          ? AppTheme.primaryColor 
                          : Colors.grey,
                    ),
                    title: Text(classModel.name),
                    subtitle: Text('${classModel.subject} - ${classModel.year}\n$studentCount طالب'),
                    isThreeLine: true,
                    selected: _selectedClass?.id == classModel.id,
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      tooltip: 'حذف الفصل',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('تأكيد الحذف'),
                            content: Text('هل أنت متأكد من حذف الفصل "${classModel.name}"؟\nسيتم حذف جميع الطلاب والبيانات المرتبطة به نهائياً.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('إلغاء'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('حذف'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed != true) return;

                        try {
                          final id = classModel.id;
                          if (id == null) return;

                          final deletingSelected = _selectedClass?.id == id;

                          // Choose a fallback class BEFORE deletion to avoid UI briefly pointing to a deleted class.
                          ClassModel? fallback;
                          for (final c in _classes) {
                            if (c.id == null) continue;
                            if (c.id == id) continue;
                            fallback ??= c;
                            break;
                          }
                          // Important: do not load providers while deleting, to avoid transient empty states
                          // if DB is locked / mid-transaction.
                          if (deletingSelected) {
                            _setSelectedClassStateOnly(fallback);
                          }

                          final classProvider = Provider.of<ClassProvider>(context, listen: false);
                          final ok = await classProvider.deleteClassCascade(id);
                          if (!ok) {
                            if (!mounted) return;
                            final msg = classProvider.error ?? 'فشل في حذف الفصل';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                            return;
                          }

                          // Keep local list in sync with provider after deletion.
                          await _reloadClassesListOnly();

                          ClassModel? nextSelected = _selectedClass;
                          if (_classes.isEmpty) {
                            nextSelected = null;
                          } else {
                            final stillExists = nextSelected != null &&
                                _classes.any((c) => c.id != null && c.id == nextSelected!.id);
                            if (!stillExists) {
                              nextSelected = _classes.first;
                            }
                          }

                          // Finalize selection only if it actually changed.
                          // If we deleted a non-selected class, keep current selection to avoid
                          // unnecessary refreshes that can momentarily clear UI state.
                          if ((nextSelected?.id) != (_selectedClass?.id)) {
                            await _setSelectedClass(nextSelected);
                            // Force refresh of all providers after class change
                            await _refreshAllProviders();
                          } else {
                            await _updateStudentCount();
                          }

                          if (!mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم حذف الفصل: ${classModel.name}')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('خطأ في حذف الفصل: $e')),
                          );
                        }
                      },
                    ),
                    onTap: () {
                      _setSelectedClass(classModel);
                      Navigator.pop(context);
                      
                      // إشعار بتغيير الفصل
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم التبديل إلى فصل: ${classModel.name}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAddClassDialog() {
    final nameController = TextEditingController();
    final subjectController = TextEditingController();
    final yearController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة فصل جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الفصل',
                hintText: 'مثال: الفصل 1-أ',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: subjectController,
              decoration: const InputDecoration(
                labelText: 'الموقع',
                hintText: 'مثال: بنوك',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: yearController,
              decoration: const InputDecoration(
                labelText: 'السنة الدراسية',
                hintText: 'مثال: 2024-2025',
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
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                try {
                  // إنشاء فصل جديد وحفظه في قاعدة البيانات
                  final classProvider = Provider.of<ClassProvider>(context, listen: false);
                  final success = await classProvider.addClass(
                    nameController.text,
                    subjectController.text.isEmpty ? 'بنوك' : subjectController.text,
                    yearController.text.isEmpty ? '2024-2025' : yearController.text,
                  );
                  
                  if (success) {
                    // إعادة تحميل الفصول بدون استدعاء _setSelectedClass مرتين
                    await classProvider.loadClasses();

                    if (!mounted || _isDisposed) return;
                    setState(() {
                      _classes = classProvider.classes;
                    });

                    // تحديد الفصل الجديد كفصل حالي (أعلى id)
                    ClassModel? newClass;
                    for (final c in _classes) {
                      if (c.id == null) continue;
                      if (newClass == null || (c.id ?? 0) > (newClass!.id ?? 0)) {
                        newClass = c;
                      }
                    }
                    if (newClass != null) {
                      await _setSelectedClass(newClass);
                    } else {
                      await _setSelectedClass(_selectedClass);
                    }
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم إضافة الفصل: ${nameController.text}')),
                      );
                    }
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('فشل في إضافة الفصل')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }


  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('الإعدادات'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsScreenNew()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Color(0xFFFFD700)),
              title: const Text('إدارة المستخدمين'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: GestureDetector(
          onTap: _showClassSelector,
          child: _selectedClass != null
              ? ValueListenableBuilder<int>(
                  valueListenable: _studentCountNotifier,
                  builder: (context, studentCount, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectedClass?.name ?? 'اختر فصل'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                        Text(
                          '$studentCount طالب',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    );
                  },
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedClass?.name ?? 'اختر فصل'),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
        ),
        actions: [
          PopupMenuButton(
            icon: const Icon(Icons.note_alt_outlined),
            tooltip: 'ملاحظات الفصول',
            offset: const Offset(0, 40),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.book, color: Colors.blue),
                  title: const Text('ملاحظات الفصول'),
                  subtitle: const Text('إدارة ملاحظات المحاضرات والامتحانات'),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () {
                  if (_selectedClass != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClassNotesScreen(classModel: _selectedClass!),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى اختيار فصل أولاً')),
                    );
                  }
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.file_download, color: Colors.green),
                  title: const Text('تصدير الملفات'),
                  subtitle: const Text('تصدير معلومات الطلاب والحضور'),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () {
                  if (_selectedClass != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExportFilesScreen(classModel: _selectedClass!),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى اختيار فصل أولاً')),
                    );
                  }
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.warning, color: Colors.red),
                  title: const Text('الطلاب في خطر'),
                  subtitle: const Text('عرض الطلاب المتجاوزين للمعايير'),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AtRiskStudentsScreen(),
                    ),
                  );
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.message, color: Colors.amber),
                  title: const Text('المراسلة'),
                  subtitle: const Text('إرسال رسائل للطلاب'),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MessagingScreen(),
                    ),
                  );
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: const Text('الطلاب المميزين'),
                  subtitle: const Text('عرض الطلاب المتفوقين'),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExcellentStudentsScreen(),
                    ),
                  );
                },
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.settings, color: Colors.blue),
                  title: const Text('الإعدادات'),
                  subtitle: const Text('إعدادات التطبيق والمستخدم'),
                  contentPadding: EdgeInsets.zero,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsScreenNew(),
                    ),
                  );
                },
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showMoreMenu,
          ),
        ],
      ),
      body: _selectedClass == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.class_, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'لا يوجد فصول',
                    style: TextStyle(fontSize: 20, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _showAddClassDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة فصل جديد'),
                  ),
                ],
              ),
            )
          : _currentTabIndex == 0
              ? NewAttendanceScreen(
                  key: ValueKey('attendance_${_selectedClass!.id ?? 0}'),
                  classModel: _selectedClass!,
                  onStudentAdded: _updateStudentCount,
                  onDataChanged: () {
                    if (!mounted || _isDisposed) return;
                    _updateStudentCount();
                  },
                )
              : _currentTabIndex == 1
                  ? ExamsScreen(
                      key: ValueKey('exams_${_selectedClass!.id ?? 0}'),
                      classModel: _selectedClass!,
                    )
                  : FinancialDashboardScreen(
                      key: ValueKey('financial_${_selectedClass!.id ?? 0}'),
                      classModel: _selectedClass!,
                    ),
      bottomNavigationBar: _selectedClass != null
          ? BottomNavigationBar(
              currentIndex: _currentTabIndex,
              onTap: (index) {
                // Don't do anything if pressing the same tab
                if (index == _currentTabIndex) {
                  return;
                }
                final previousIndex = _currentTabIndex;
                setState(() {
                  _currentTabIndex = index;
                });
                
                // إذا كان الانتقال من الامتحانات إلى الحضور، قم بتحديث البيانات
                if (previousIndex == 1 && index == 0 && _selectedClass != null) {
                  // تحديث بيانات الطلاب عند العودة من الامتحانات
                  WidgetsBinding.instance.addPostFrameCallback((_) async {
                    // تحديث بيانات الطلاب أولاً
                    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
                    await studentProvider.loadStudentsByClass(_selectedClass!.id!);
                    
                    // تحديث جميع بيانات الفصل لضمان تحديث النقاط الحمراء
                    final classProvider = Provider.of<ClassProvider>(context, listen: false);
                    await classProvider.loadClasses();
                    await _updateStudentCount();
                  });
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.check_circle_outline),
                  label: 'الحضور',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.assignment),
                  label: 'الامتحانات',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.account_balance),
                  label: 'المالية',
                ),
              ],
            )
          : null,
    );
  }
}
