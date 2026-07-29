import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/token_service.dart';

/// A CircleAvatar that gracefully handles 404/broken image URLs.
///
/// Fetches image bytes via HTTP (with authentication) instead of using
/// NetworkImage, so a 404 or other network error is caught silently — no
/// `NetworkImageLoadException` is ever thrown. Falls back to showing the
/// user's initial letter.
///
/// Sending the auth token ensures profile pictures are accessible even when
/// media files are served behind authentication (e.g. the /api/media/ endpoint).
class ProfileAvatar extends StatefulWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const ProfileAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 30,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Uint8List? _imageBytes;
  bool _loadFailed = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-fetch when the URL changes (including cache-busting query params)
    if (widget.imageUrl != oldWidget.imageUrl) {
      _imageBytes = null;
      _loadFailed = false;
      _isLoading = true;
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() { _loadFailed = true; _isLoading = false; });
      return;
    }

    try {
      // Build headers — include auth token so protected media endpoints work
      final headers = <String, String>{};
      final tokenService = TokenService();
      final token = await tokenService.getAccessToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http.get(Uri.parse(url), headers: headers);
      if (!mounted) return;

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        setState(() {
          _imageBytes = response.bodyBytes;
          _loadFailed = false;
          _isLoading = false;
        });
      } else {
        // 404 or other non-200 status — show initials silently
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
    } catch (_) {
      // Network error, timeout, etc. — show initials silently
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.isNotEmpty
        ? widget.name.substring(0, 1).toUpperCase()
        : '?';
    final bgColor = widget.backgroundColor ?? Theme.of(context).primaryColor;
    final fgColor = widget.foregroundColor ?? Colors.white;
    final fontSize = widget.radius * 0.8;

    // No URL, load failed, or loading: show initials
    if (_loadFailed || _isLoading) {
      return CircleAvatar(
        radius: widget.radius,
        backgroundColor: bgColor,
        child: _isLoading && (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fgColor,
                ),
              )
            : Text(
                initial,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: fgColor),
              ),
      );
    }

    // Image loaded successfully — display from memory bytes (no NetworkImage)
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bgColor,
      child: ClipOval(
        child: Image.memory(
          _imageBytes!,
          width: widget.radius * 2,
          height: widget.radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Image bytes were corrupt — show initials
            return Container(
              width: widget.radius * 2,
              height: widget.radius * 2,
              color: bgColor,
              child: Text(
                initial,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: fgColor),
              ),
            );
          },
        ),
      ),
    );
  }
}