import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gct/src/features/vision_analyzer/vision_analyzer_screen.dart';

void main() {
  testWidgets('Vision Analyzer: structure, scenario switching, and tabs', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: VisionAnalyzerScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // AppBar title present (in shell and screen header)
    expect(find.text('AI Vision Analyzer'), findsWidgets);

    // All 4 scenarios visible
    expect(find.text('Spine & Posture'), findsOneWidget);
    expect(find.text('Joint ROM'), findsOneWidget);
    expect(find.text('Dermatology'), findsOneWidget);
    expect(find.text('Facial Palsy'), findsOneWidget);

    // Tab bar tabs present
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);

    // Scan tab: slider label visible
    expect(find.text('Spine Deviation Angle'), findsOneWidget);

    // Tap Joint ROM scenario
    await tester.tap(find.text('Joint ROM'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Knee Flexion Angle'), findsOneWidget);
  });
}
