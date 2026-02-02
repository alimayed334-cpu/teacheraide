import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'screens/auth/auth_wrapper.dart';
import 'providers/class_provider.dart';
import 'providers/student_provider.dart';
import 'providers/attendance_provider.dart';
import 'providers/grade_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/exam_provider.dart';
import 'database/database_helper.dart';
import 'services/hive_service.dart';
import 'firebase_options.dart';

// استيراد شرطي للمكتبات حسب المنصة
import 'database_init.dart' if (dart.library.io) 'database_init_io.dart' if (dart.library.html) 'database_init_web.dart';

void main() async {
  // تهيئة Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة الأصول
  await _initializeAssets();

  // Firebase (Android/iOS). Keep Windows/local development working if Firebase isn't configured.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on UnsupportedError {
    // Unsupported platform or missing config; app can still run locally.
  } catch (e) {
    // Do not block startup; auth provider will fallback to local auth if needed.
    print('Firebase init error: $e');
  }

  runApp(const TeacherAideApp());
}

Future<void> _initializeAssets() async {
  try {
    // تأخير بسيط لضمان تهيئة الأصول
    await Future.delayed(const Duration(milliseconds: 200));
    
    // محاولة تحميل AssetManifest
    try {
      await rootBundle.loadString('AssetManifest.json');
      print('AssetManifest.json loaded successfully');
    } catch (e) {
      print('AssetManifest.json not found: $e');
      // لا نوقف التطبيق إذا فشل تحميل الأصول
    }
    
    print('Assets initialized successfully');
  } catch (e) {
    print('Asset initialization error: $e');
    // لا نوقف التطبيق إذا فشل تحميل الأصول
  }
}

class TeacherAideApp extends StatelessWidget {
  const TeacherAideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ClassProvider()),
        ChangeNotifierProvider(create: (_) => StudentProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
        ChangeNotifierProvider(create: (_) => GradeProvider()),
        ChangeNotifierProvider(create: (_) => ExamProvider()),
      ],
      child: MaterialApp(
        title: 'مساعد المعلم',
        debugShowCheckedModeBanner: false,
        
        // الثيم - استخدام الثيم الداكن دائماً
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        
        // اللغة العربية
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [
          Locale('ar', 'SA'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        
        home: const _StartupGate(),
        
        // إعدادات إضافية
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          );
        },
      ),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    await _initializeAssets();

    await initializeDatabase();

    // Fresh install: start with an empty database (no pre-existing data).
    // This runs only once per app install.
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasInitialized = prefs.getBool('db_first_run_initialized') ?? false;
      if (!hasInitialized) {
        final dbHelper = DatabaseHelper();
        await dbHelper.resetDatabaseFile();
        await dbHelper.forceReinit();
        await prefs.setBool('db_first_run_initialized', true);
      }
    } catch (_) {
      // Ignore first-run init failures; app can still start.
    }

    final dbHelper = DatabaseHelper();
    await dbHelper.cleanDuplicateData();

    await HiveService.init();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          final errorText = snapshot.error.toString();
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'حدث خطأ أثناء تشغيل التطبيق',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      errorText,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _initFuture = _init();
                        });
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const AuthWrapper();
      },
    );
  }
}
