import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveScope,
    ],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  // Initialize the service
  Future<void> initialize() async {
    // Try silent sign in first
    await _silentSignIn();
  }

  // Silent sign in
  Future<void> _silentSignIn() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      if (_currentUser != null) {
        await _initializeDriveApi();
      }
    } catch (e) {
      debugPrint('Silent sign in failed: $e');
    }
  }

  // Sign in with Google
  Future<bool> signIn() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        _currentUser = _googleSignIn.currentUser;
      } else {
        _currentUser = await _googleSignIn.signIn();
      }

      if (_currentUser != null) {
        await _initializeDriveApi();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('google_drive_signed_in', true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Google Drive sign in error: $e');
      return false;
    }
  }

  // Initialize Drive API
  Future<void> _initializeDriveApi() async {
    if (_currentUser == null) return;

    final authHeaders = await _currentUser!.authHeaders;
    final client = GoogleHttpClient(authHeaders);
    _driveApi = drive.DriveApi(client);
  }

  // Sign out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_drive_signed_in');
    _currentUser = null;
    _driveApi = null;
  }

  // Check if signed in
  bool get isSignedIn => _currentUser != null;

  // Upload file to Google Drive
  Future<String?> uploadFileToGoogleDrive(
    File file, {
    String? folderId,
    bool shareWithAnyone = true,
  }) async {
    try {
      if (_driveApi == null) {
        debugPrint('Drive API not initialized');
        return null;
      }

      final fileName = path.basename(file.path);
      final fileSize = await file.length();

      // Create file metadata
      final driveFile = drive.File()
        ..name = fileName
        ..parents = folderId != null ? [folderId] : null;

      // Upload file
      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: drive.Media(
          file.openRead(),
          fileSize,
        ),
      );

      debugPrint('File uploaded successfully: ${uploadedFile.id}');

      // Make file publicly accessible if requested
      if (shareWithAnyone) {
        await _makeFilePublic(uploadedFile.id!);
      }

      return uploadedFile.id;
    } catch (e) {
      debugPrint('Error uploading file to Google Drive: $e');
      return null;
    }
  }

  // Upload file from bytes
  Future<String?> uploadBytesToGoogleDrive(
    Uint8List bytes,
    String fileName, {
    String? folderId,
    bool shareWithAnyone = true,
  }) async {
    try {
      if (_driveApi == null) {
        debugPrint('Drive API not initialized');
        return null;
      }

      // Create file metadata
      final driveFile = drive.File()
        ..name = fileName
        ..parents = folderId != null ? [folderId] : null;

      // Upload file
      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: drive.Media(
          Stream.fromIterable([bytes]),
          bytes.length,
        ),
      );

      debugPrint('File uploaded successfully: ${uploadedFile.id}');

      // Make file publicly accessible if requested
      if (shareWithAnyone) {
        await _makeFilePublic(uploadedFile.id!);
      }

      return uploadedFile.id;
    } catch (e) {
      debugPrint('Error uploading bytes to Google Drive: $e');
      return null;
    }
  }

  // Make file public
  Future<void> _makeFilePublic(String fileId) async {
    try {
      if (_driveApi == null) return;

      // Create permission for anyone with the link
      final permission = drive.Permission()
        ..role = 'reader'
        ..type = 'anyone';

      await _driveApi!.permissions.create(permission, fileId);
      debugPrint('File made public: $fileId');
    } catch (e) {
      debugPrint('Error making file public: $e');
    }
  }

  // Get direct download link that opens file directly in browser
  String getDirectLink(String fileId) {
    // Use Google Drive direct link format that opens files in browser
    return 'https://drive.google.com/uc?export=view&id=$fileId';
  }

  // Get shareable link
  String? getShareableLink(String fileId) {
    if (fileId.isEmpty) return null;
    return 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
  }

  // Create folder
  Future<String?> createFolder(String folderName, {String? parentId}) async {
    try {
      if (_driveApi == null) {
        debugPrint('Drive API not initialized');
        return null;
      }

      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = parentId != null ? [parentId] : null;

      final createdFolder = await _driveApi!.files.create(folder);
      
      // Make folder accessible
      await _makeFilePublic(createdFolder.id!);
      
      return createdFolder.id;
    } catch (e) {
      debugPrint('Error creating folder: $e');
      return null;
    }
  }

  // List files
  Future<List<drive.File>> listFiles({String? folderId}) async {
    try {
      if (_driveApi == null) return [];

      String query = '';
      if (folderId != null) {
        query = "'$folderId' in parents";
      }

      final response = await _driveApi!.files.list(
        q: query.isNotEmpty ? query : null,
        orderBy: 'modifiedTime desc',
      );

      return response.files ?? [];
    } catch (e) {
      debugPrint('Error listing files: $e');
      return [];
    }
  }

  // Delete file
  Future<bool> deleteFile(String fileId) async {
    try {
      if (_driveApi == null) return false;

      await _driveApi!.files.delete(fileId);
      return true;
    } catch (e) {
      debugPrint('Error deleting file: $e');
      return false;
    }
  }
}

// Custom HTTP client for Google APIs
class GoogleHttpClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _client = http.Client();

  GoogleHttpClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
