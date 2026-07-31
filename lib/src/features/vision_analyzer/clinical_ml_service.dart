import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// 3D Landmark Point representation
class Landmark3D {
  final double x;
  final double y;
  final double z;
  final double likelihood;

  const Landmark3D({
    required this.x,
    required this.y,
    this.z = 0.0,
    this.likelihood = 1.0,
  });
}

/// Specialized Clinical ML Landmark Service for Gonstead Chiropractic Vision AI
class ClinicalMLService {
  static final ClinicalMLService _instance = ClinicalMLService._internal();
  factory ClinicalMLService() => _instance;
  ClinicalMLService._internal();

  /// Calculate 2D angle in degrees between three landmark points (A -> B -> C)
  double calculateAngle(Landmark3D first, Landmark3D mid, Landmark3D last) {
    final rad = math.atan2(last.y - mid.y, last.x - mid.x) -
                math.atan2(first.y - mid.y, first.x - mid.x);
    double angle = (rad * 180.0 / math.pi).abs();
    if (angle > 180.0) {
      angle = 360.0 - angle;
    }
    return angle;
  }

  /// Calculate Spinal Column Deviation Angle (C7 -> T12 -> L5)
  double calculateSpinalDeviation({
    required Landmark3D c7,
    required Landmark3D t12,
    required Landmark3D l5,
  }) {
    final straightY = l5.y - c7.y;
    final straightX = l5.x - c7.x;
    final midX = c7.x + straightX / 2.0;
    final devX = (t12.x - midX).abs();
    return math.min((devX / straightY) * 90.0, 45.0);
  }

  /// Calculate Knee Flexion Goniometer Angle (Hip -> Knee -> Ankle)
  double calculateKneeGoniometer({
    required Landmark3D hip,
    required Landmark3D knee,
    required Landmark3D ankle,
  }) {
    return calculateAngle(hip, knee, ankle);
  }

  /// Calculate Facial Asymmetry Index from Eye and Mouth Mesh Landmarks (%)
  double calculateFacialAsymmetry({
    required Landmark3D noseTip,
    required Landmark3D leftEye,
    required Landmark3D rightEye,
    required Landmark3D leftMouth,
    required Landmark3D rightMouth,
  }) {
    final leftEyeDist = math.sqrt(math.pow(leftEye.x - noseTip.x, 2) + math.pow(leftEye.y - noseTip.y, 2));
    final rightEyeDist = math.sqrt(math.pow(rightEye.x - noseTip.x, 2) + math.pow(rightEye.y - noseTip.y, 2));
    final leftMouthDist = math.sqrt(math.pow(leftMouth.x - noseTip.x, 2) + math.pow(leftMouth.y - noseTip.y, 2));
    final rightMouthDist = math.sqrt(math.pow(rightMouth.x - noseTip.x, 2) + math.pow(rightMouth.y - noseTip.y, 2));

    final eyeAsym = ((leftEyeDist - rightEyeDist).abs() / math.max(leftEyeDist, rightEyeDist)) * 100.0;
    final mouthAsym = ((leftMouthDist - rightMouthDist).abs() / math.max(leftMouthDist, rightMouthDist)) * 100.0;

    return math.min((eyeAsym + mouthAsym) / 2.0, 99.0);
  }

  /// Estimate Gonstead Listing (PRS, PLS, PRI, PLI) from Spinal Spinous Rotation
  Map<String, dynamic> computeGonsteadListing({
    required double spinousRotationDeg,
    required double openWedgeDeg,
    required bool isOpenRight,
  }) {
    final isPosterior = true; // All subluxations start with P
    final isRightRotation = spinousRotationDeg > 0;
    final dir = isRightRotation ? 'R' : 'L';
    final wedgeDir = isOpenRight ? 'S' : 'I';

    final listingCode = 'P$dir$wedgeDir';
    final lod = isRightRotation
        ? 'P-to-A, Right-to-Left, ${isOpenRight ? "I-to-S" : "S-to-I"}'
        : 'P-to-A, Left-to-Right, ${isOpenRight ? "I-to-S" : "S-to-I"}';
    final contactPoint = isRightRotation ? 'Right Mammillary / Spinous Process' : 'Left Mammillary / Spinous Process';

    return {
      'listing': listingCode,
      'rotation': spinousRotationDeg,
      'openWedge': openWedgeDeg,
      'lod': lod,
      'contactPoint': contactPoint,
    };
  }
}
