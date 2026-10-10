import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/state_persistence.dart';
import 'package:player/widgets/epicenter_engine_selector.dart';

void main() {
  testWidgets('selects the requested engine at compact and landscape sizes',
      (tester) async {
    for (final size in [const Size(320, 640), const Size(800, 360)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      var selected = EpicenterEngineMode.hybrid;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: EpicenterEngineSelector(
            value: selected,
            onChanged: (engine) async => setState(() => selected = engine),
          ),
        ),
      ))));
      await tester.tap(find.text('LEGACY'));
      await tester.pumpAndSettle();
      expect(selected, EpicenterEngineMode.legacy);
      await tester.tap(find.text('SMART'));
      await tester.pumpAndSettle();
      expect(selected, EpicenterEngineMode.smart);
      await tester.tap(find.text('HYBRID'));
      await tester.pumpAndSettle();
      expect(selected, EpicenterEngineMode.hybrid);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets(
      'reports a failed native selection without showing it as selected',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EpicenterEngineSelector(
      value: EpicenterEngineMode.hybrid,
      onChanged: (_) async => throw StateError('channel failure'),
    ))));
    await tester.tap(find.text('LEGACY'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo cambiar el motor'), findsOneWidget);
    final button = tester.widget<SegmentedButton<EpicenterEngineMode>>(
        find.byType(SegmentedButton<EpicenterEngineMode>));
    expect(button.selected, {EpicenterEngineMode.hybrid});
    expect(tester.takeException(), isNull);
  });
}
