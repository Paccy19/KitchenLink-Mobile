import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../utils/uploads.dart';
import 'feedback.dart';

/// Asks camera or gallery, picks a photo and checks it against [rules]
/// before it is ever sent. Returns null when cancelled or rejected (the
/// reason is shown).
Future<PickedUpload?> chooseImage(
  BuildContext context,
  MediaPicker picker, {
  UploadRules rules = UploadRules.image,
}) async {
  final fromCamera = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_rounded),
          title: const Text('Take a photo'),
          onTap: () => Navigator.pop(context, true),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_rounded),
          title: const Text('Choose from gallery'),
          onTap: () => Navigator.pop(context, false),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (fromCamera == null || !context.mounted) return null;
  try {
    final file = await picker.pickImage(fromCamera: fromCamera);
    if (file == null) return null;
    final problem = file.validate(rules);
    if (problem != null) {
      if (context.mounted) showError(context, problem);
      return null;
    }
    return file;
  } catch (_) {
    if (context.mounted) {
      showError(context, 'Could not open the ${fromCamera ? 'camera' : 'gallery'}. Check the app permissions.');
    }
    return null;
  }
}

/// A rectangle showing the chosen local image, or a placeholder to tap.
class ImagePickerBox extends StatelessWidget {
  const ImagePickerBox({
    super.key,
    required this.onTap,
    this.picked,
    this.existingWidget,
    this.label = 'Add a photo',
    this.height = 150,
    this.onRemove,
  });

  final VoidCallback onTap;
  final PickedUpload? picked;

  /// Shown when nothing new was picked (the current server image).
  final Widget? existingWidget;
  final String label;
  final double height;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content;
    if (picked != null) {
      content = _PickedImage(picked: picked!, height: height);
    } else if (existingWidget != null) {
      content = SizedBox(width: double.infinity, height: height, child: existingWidget);
    } else {
      content = SizedBox(
        width: double.infinity,
        height: height,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_a_photo_rounded, size: 32, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ]),
      );
    }
    return Stack(children: [
      Material(
        color: theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
      if (picked != null && onRemove != null)
        Positioned(
          right: 6,
          top: 6,
          child: IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Remove',
          ),
        ),
    ]);
  }
}

/// A just-picked photo. Shown from its bytes, read once, so it works where
/// the file has no path on disk (Android content addresses, the web).
class _PickedImage extends StatefulWidget {
  const _PickedImage({required this.picked, required this.height});

  final PickedUpload picked;
  final double height;

  @override
  State<_PickedImage> createState() => _PickedImageState();
}

class _PickedImageState extends State<_PickedImage> {
  late Future<Uint8List> _bytes = _read();

  Future<Uint8List> _read() => (widget.picked.readBytes ?? () => XFile(widget.picked.path).readAsBytes())();

  @override
  void didUpdateWidget(_PickedImage old) {
    super.didUpdateWidget(old);
    if (old.picked.path != widget.picked.path) _bytes = _read();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: widget.height,
        child: FutureBuilder<Uint8List>(
          future: _bytes,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: widget.height);
            if (snapshot.hasError) return const Center(child: Icon(Icons.broken_image_outlined));
            return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          },
        ),
      );
}
