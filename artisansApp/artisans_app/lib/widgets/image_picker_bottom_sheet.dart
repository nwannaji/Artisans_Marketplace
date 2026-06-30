// lib/widgets/image_picker_bottom_sheet.dart
//
// A reusable bottom sheet for picking images from gallery or camera.
// Replaces 4 duplicated implementations across screens.

import 'package:flutter/material.dart';
import 'drag_handle.dart';

class ImagePickerBottomSheet extends StatelessWidget {
  final VoidCallback onGallery;
  final VoidCallback onCamera;
  final VoidCallback? onRemove;
  final String title;

  const ImagePickerBottomSheet({
    super.key,
    required this.onGallery,
    required this.onCamera,
    this.onRemove,
    this.title = 'Change Profile Picture',
  });

  /// Convenience method to show this bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGallery,
    required VoidCallback onCamera,
    VoidCallback? onRemove,
    String title = 'Change Profile Picture',
  }) {
    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ImagePickerBottomSheet(
        onGallery: onGallery,
        onCamera: onCamera,
        onRemove: onRemove,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DragHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.blue),
            title: const Text('Choose from Gallery'),
            onTap: () {
              Navigator.pop(context);
              onGallery();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.green),
            title: const Text('Take a Photo'),
            onTap: () {
              Navigator.pop(context);
              onCamera();
            },
          ),
          if (onRemove != null) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Remove Photo'),
              onTap: () {
                Navigator.pop(context);
                onRemove!();
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}