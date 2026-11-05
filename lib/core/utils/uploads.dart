import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// A file the vendor chose, ready to be sent as a real multipart part.
class PickedUpload {
  const PickedUpload({required this.path, required this.name, required this.sizeBytes});

  final String path;
  final String name;
  final int sizeBytes;

  String get mimeType => mimeTypeForName(name);
  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => mimeType.startsWith('image/');

  /// Reads the file from disk when the request is sent.
  Future<MultipartFile> toMultipart() =>
      MultipartFile.fromFile(path, filename: name, contentType: DioMediaType.parse(mimeType));

  /// Why this file cannot be sent, or null when it is fine.
  String? validate(UploadRules rules) {
    if (!rules.allowedMimeTypes.contains(mimeType)) {
      return '"$name" is not a supported file. Use ${rules.allowedLabel}.';
    }
    if (sizeBytes > rules.maxBytes) {
      return '"$name" is too large (max ${rules.maxBytes ~/ (1024 * 1024)} MB).';
    }
    if (sizeBytes <= 0) return '"$name" is empty.';
    return null;
  }
}

/// What the backend accepts for one kind of upload (`config.vendor.uploads`).
class UploadRules {
  const UploadRules({required this.maxBytes, required this.allowedMimeTypes, required this.allowedLabel});

  final int maxBytes;
  final Set<String> allowedMimeTypes;
  final String allowedLabel;

  static const _mb = 1024 * 1024;
  static const _images = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};

  /// Menu photos, profile and banner updates: images up to 5 MB.
  static const UploadRules image = UploadRules(
    maxBytes: 5 * _mb,
    allowedMimeTypes: _images,
    allowedLabel: 'a JPG, PNG, WebP or GIF image',
  );

  /// Banner chosen at registration (images; the request limit is 10 MB).
  static const UploadRules registrationBanner = UploadRules(
    maxBytes: 10 * _mb,
    allowedMimeTypes: _images,
    allowedLabel: 'a JPG, PNG, WebP or GIF image',
  );

  /// Verification documents: JPG/PNG/WebP/PDF up to 10 MB, at most 10 files.
  static const UploadRules document = UploadRules(
    maxBytes: 10 * _mb,
    allowedMimeTypes: {'image/jpeg', 'image/png', 'image/webp', 'application/pdf'},
    allowedLabel: 'a JPG, PNG, WebP image or a PDF',
  );

  static const int maxDocuments = 10;
}

String mimeTypeForName(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  switch (extension) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'pdf':
      return 'application/pdf';
  }
  return 'application/octet-stream';
}

/// Native photo / file selection, behind an interface so screens can be tested.
abstract interface class MediaPicker {
  Future<PickedUpload?> pickImage({required bool fromCamera});
  Future<List<PickedUpload>> pickDocuments();
}

class DeviceMediaPicker implements MediaPicker {
  DeviceMediaPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<PickedUpload?> pickImage({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 88,
    );
    if (file == null) return null;
    final name = file.name.isNotEmpty ? file.name : file.path.split('/').last;
    return PickedUpload(path: file.path, name: name, sizeBytes: await file.length());
  }

  @override
  Future<List<PickedUpload>> pickDocuments() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    final picked = <PickedUpload>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      picked.add(PickedUpload(path: path, name: file.name, sizeBytes: await file.length() ?? 0));
    }
    return picked;
  }
}
