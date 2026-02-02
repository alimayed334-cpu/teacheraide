import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class LatestViewModeService {
  LatestViewModeService._();

  static final LatestViewModeService instance = LatestViewModeService._();

  static const String _prefsKey = 'latest_view_mode_enabled';

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  Stream<bool> get changes => _controller.stream;

  Future<bool> getValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }

  Future<void> setValue(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    _controller.add(value);
  }
}
