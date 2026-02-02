/// Service for real-time sync of HiveStudent data to Firestore.
class FirestoreService {
  /// Initialize Firebase (only once). Call from main() or early.
  static Future<void> init() async {}

  static Future<void> ensureAuth() async {}

  static Future<void> syncStudent(dynamic student) async {}

  /// Save a generic person (student or parent) with role.
  static Future<void> savePerson({
    required String id,
    required String name,
    required String phone,
    required String role, 
    String? grade,
    String? classId,
    String? address,
    String? imageUrl,
    int? age,
  }) async {}

  /// Called when a student is deleted from Hive.
  static Future<void> deleteStudent(String studentId) async {}
}
