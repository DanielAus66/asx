import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the current user's public identity and who they follow.
///
/// Handles are unique within the app's user space.
/// Format: @{name_slug}{4_digit_suffix}  e.g. @alextrader2847
/// The suffix makes it unique without requiring a backend uniqueness check
/// at this stage — when Firebase is added, enforce at write time.
///
/// Following is a local set of publisher IDs for now.
/// Backend: write to users/{uid}/following/{publisherId} on subscribe.
class UserProfileService with ChangeNotifier {
  static const String _nameKey = 'user_profile_name';
  static const String _handleKey = 'user_profile_handle';
  static const String _bioKey = 'user_profile_bio';
  static const String _followingKey = 'user_profile_following_ids';

  String? _displayName;
  String? _handle;  // includes the @ prefix
  String? _bio;
  Set<String> _followingIds = {};

  bool _initialized = false;

  String? get displayName => _displayName;
  String? get handle => _handle;
  String? get bio => _bio;
  bool get hasProfile => _displayName != null && _displayName!.isNotEmpty;
  Set<String> get followingIds => Set.unmodifiable(_followingIds);
  bool isFollowing(String publisherId) => _followingIds.contains(publisherId);

  /// Number of people this user follows
  int get followingCount => _followingIds.length;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_nameKey);
    _handle = prefs.getString(_handleKey);
    _bio = prefs.getString(_bioKey);
    final saved = prefs.getStringList(_followingKey) ?? [];
    _followingIds = saved.toSet();
    notifyListeners();
  }

  /// Set or update the user's display name.
  /// If this is the first time a name is being set, auto-generate a handle.
  /// If the name changes, the handle stays the same (handle is identity).
  Future<void> setDisplayName(String name) async {
    _displayName = name.trim();
    if (_handle == null || _handle!.isEmpty) {
      _handle = _generateHandle(name);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, _displayName!);
    await prefs.setString(_handleKey, _handle!);
    notifyListeners();
  }

  /// Explicitly set a custom handle (user-chosen).
  /// Caller should validate uniqueness via backend before calling.
  Future<void> setHandle(String handle) async {
    // Normalise: lowercase, strip spaces, ensure @ prefix
    var h = handle.trim().toLowerCase().replaceAll(' ', '_');
    if (!h.startsWith('@')) h = '@$h';
    _handle = h;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handleKey, _handle!);
    notifyListeners();
  }

  Future<void> setBio(String bio) async {
    _bio = bio.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bioKey, _bio!);
    notifyListeners();
  }

  Future<void> follow(String publisherId) async {
    _followingIds.add(publisherId);
    await _persistFollowing();
    notifyListeners();
  }

  Future<void> unfollow(String publisherId) async {
    _followingIds.remove(publisherId);
    await _persistFollowing();
    notifyListeners();
  }

  Future<void> _persistFollowing() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_followingKey, _followingIds.toList());
  }

  /// Generates a handle from a display name + random 4-digit suffix.
  /// e.g. "Alex Trader" → @alextrader2847
  static String _generateHandle(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .substring(0, name.replaceAll(RegExp(r'[^a-z0-9]'), '').length.clamp(0, 12));
    final suffix = (1000 + Random().nextInt(8999)).toString(); // 1000–9999
    return '@$slug$suffix';
  }
}
