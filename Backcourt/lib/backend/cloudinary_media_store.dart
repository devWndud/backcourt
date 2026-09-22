import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'models.dart';

class CloudinarySettings {
  const CloudinarySettings._();

  static const cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'djrcsqpux',
  );
  static const uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'Backcourt',
  );
}

class CloudinaryMediaStore {
  CloudinaryMediaStore({
    http.Client? client,
    this.cloudName = CloudinarySettings.cloudName,
    this.uploadPreset = CloudinarySettings.uploadPreset,
  }) : _client = client ?? http.Client();

  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxVideoBytes = 100 * 1024 * 1024;

  final http.Client _client;
  final String cloudName;
  final String uploadPreset;

  bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;

  Future<MediaItem> upload({
    required XFile file,
    required String type,
    required String folder,
  }) async {
    if (!isConfigured) {
      throw const CloudinaryMediaException(
        '미디어 저장소 설정이 필요해요. Cloudinary 연결값을 확인해주세요.',
      );
    }

    final isVideo = type == 'video';
    final size = await file.length();
    final maxBytes = isVideo ? maxVideoBytes : maxImageBytes;
    if (size > maxBytes) {
      throw CloudinaryMediaException(
        isVideo ? '영상은 최대 100MB까지 올릴 수 있어요.' : '사진은 최대 10MB까지 올릴 수 있어요.',
      );
    }
    if (isVideo) {
      final controller = VideoPlayerController.file(File(file.path));
      try {
        await controller.initialize();
        if (controller.value.duration > const Duration(seconds: 30)) {
          throw const CloudinaryMediaException('영상은 30초까지 올릴 수 있어요.');
        }
      } finally {
        await controller.dispose();
      }
    }

    final resourceType = isVideo ? 'video' : 'image';
    final uri = Uri.https(
      'api.cloudinary.com',
      '/v1_1/${cloudName.trim().toLowerCase()}/$resourceType/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset.trim()
      ..fields['folder'] = 'backcourt/$folder'
      ..files.add(
        http.MultipartFile('file', file.openRead(), size, filename: file.name),
      );

    try {
      final response = await _client
          .send(request)
          .timeout(const Duration(minutes: 3));
      final body = await response.stream.bytesToString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = data['error'];
        final message = error is Map<String, dynamic>
            ? error['message'] as String?
            : null;
        throw CloudinaryMediaException(
          message == null
              ? '미디어 업로드에 실패했어요. (${response.statusCode})'
              : '미디어 업로드에 실패했어요. ($message)',
        );
      }

      final url = data['secure_url'] as String?;
      final publicId = data['public_id'] as String?;
      if (url == null || publicId == null) {
        throw const CloudinaryMediaException('업로드 결과를 확인하지 못했어요.');
      }
      return MediaItem(
        url: url,
        type: resourceType,
        storagePath: 'cloudinary:$resourceType:$publicId',
      );
    } on CloudinaryMediaException {
      rethrow;
    } catch (_) {
      throw const CloudinaryMediaException('미디어를 올리지 못했어요. 네트워크 연결을 확인해주세요.');
    }
  }
}

class CloudinaryMediaException implements Exception {
  const CloudinaryMediaException(this.message);

  final String message;
}
