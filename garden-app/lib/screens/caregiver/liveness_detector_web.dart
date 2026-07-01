import 'package:flutter/material.dart';

// Web stub — FaceLivenessDetector (face_liveness_detector package) is iOS/Android only.
// Immediately signals an error so the caller can show an appropriate fallback.
Widget buildLivenessWidget({
  required String sessionId,
  required VoidCallback onComplete,
  required void Function(String) onError,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    onError('PLATFORM_NOT_SUPPORTED');
  });
  return const SizedBox.shrink();
}
