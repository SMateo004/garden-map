import 'package:flutter/material.dart';
import 'package:face_liveness_detector/face_liveness_detector.dart';

Widget buildLivenessWidget({
  required String sessionId,
  required VoidCallback onComplete,
  required void Function(String) onError,
}) {
  return SizedBox.expand(
    child: FaceLivenessDetector(
      sessionId: sessionId,
      region: 'us-east-1',
      onComplete: onComplete,
      onError: onError,
    ),
  );
}
