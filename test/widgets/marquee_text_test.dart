import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/widgets/marquee_text.dart';

void main() {
  group('MarqueeText Unit Tests', () {
    const style = TextStyle(fontSize: 16);
    const scaler = TextScaler.noScaling;

    test('isOverflowing returns false for short text', () {
      final result = MarqueeText.isOverflowing(
        text: 'Hello',
        style: style,
        maxWidth: 200,
        scaler: scaler,
      );
      expect(result, isFalse);
    });

    test('isOverflowing returns true for long text', () {
      final result = MarqueeText.isOverflowing(
        text: 'This is a very long text that overlaps 50 pixels',
        style: style,
        maxWidth: 50,
        scaler: scaler,
      );
      expect(result, isTrue);
    });

    test('isOverflowing handles empty text', () {
      expect(MarqueeText.isOverflowing(text: '', maxWidth: 100, scaler: scaler), isFalse);
    });

    test('isOverflowing respects TextScaler', () {
      const largeScaler = TextScaler.linear(2.0);
      const word = 'NormalWord'; // 10 chars
      const baseStyle = TextStyle(fontSize: 16);
      
      // At fontSize 16, 10 chars are roughly 160px in tests (Ahem font is square)
      // We use a maxWidth that fits the base but overflows with scaler
      const maxWidth = 250.0; 
      
      final overflowsNormal = MarqueeText.isOverflowing(text: word, style: baseStyle, maxWidth: maxWidth, scaler: scaler);
      final overflowsLarge = MarqueeText.isOverflowing(text: word, style: baseStyle, maxWidth: maxWidth, scaler: largeScaler);
      
      expect(overflowsNormal, isFalse, reason: 'Should fit at 1.0 scale (160px < 250px)');
      expect(overflowsLarge, isTrue, reason: 'Should overflow at 2.0 scale (320px > 250px)');
    });
  });

  group('MarqueeText Widget Tests', () {
    testWidgets('shows Text with ellipsis when no overflow', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: MarqueeText(text: 'Short'),
            ),
          ),
        ),
      );

      // Verify it renders a standard Text widget with the expected text
      final textFinder = find.text('Short');
      expect(textFinder, findsOneWidget);
      
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('activates marquee when overflow occurs', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 50,
              child: MarqueeText(text: 'Very long text that overflows narrow container'),
            ),
          ),
        ),
      );

      // Animation starts in post-frame callback
      await tester.pump(); 
      
      // We check for the presence of two Text widgets, which signifies the marquee logic is active
      expect(find.text('Very long text that overflows narrow container'), findsNWidgets(2));
    });

    testWidgets('resets animation when text changes', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 50,
              child: MarqueeText(text: 'Initial very long text'),
            ),
          ),
        ),
      );
      await tester.pump();
      
      // Change text
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 50,
              child: MarqueeText(text: 'New different long text'),
            ),
          ),
        ),
      );
      
      await tester.pump();
      expect(find.text('New different long text'), findsNWidgets(2));
    });
  });
}
