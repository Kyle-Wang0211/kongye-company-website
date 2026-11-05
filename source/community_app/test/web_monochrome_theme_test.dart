import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketworld_flutter/main_community_web.dart';
import 'package:pocketworld_flutter/ui/design_system.dart';

void main() {
  test('web theme keeps control and selection roles monochrome', () {
    final theme = communityWebTheme();
    final scheme = theme.colorScheme;
    for (final color in [
      scheme.primary,
      scheme.onPrimary,
      scheme.primaryContainer,
      scheme.onPrimaryContainer,
      scheme.secondary,
      scheme.onSecondary,
      scheme.secondaryContainer,
      scheme.onSecondaryContainer,
      scheme.tertiary,
      scheme.onTertiary,
      scheme.tertiaryContainer,
      scheme.onTertiaryContainer,
      scheme.surface,
      scheme.onSurface,
      scheme.surfaceContainer,
      scheme.surfaceTint,
      theme.focusColor,
      theme.hoverColor,
      theme.textSelectionTheme.cursorColor!,
      theme.textSelectionTheme.selectionColor!,
      theme.textSelectionTheme.selectionHandleColor!,
    ]) {
      expect(color.r, color.g, reason: '$color must be grayscale');
      expect(color.g, color.b, reason: '$color must be grayscale');
    }
    expect(scheme.primary, AetherColors.primary);
    expect(scheme.error, AetherColors.danger);
    expect(theme.textSelectionTheme.cursorColor, AetherColors.primary);
    expect(theme.textSelectionTheme.selectionHandleColor, AetherColors.primary);
  });

  testWidgets('web input and selected controls use the web theme', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Selected text');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: communityWebTheme(),
        home: Scaffold(
          body: Column(
            children: [
              TextField(controller: controller, autofocus: true),
              Checkbox(value: true, onChanged: (_) {}),
              Switch(value: true, onChanged: (_) {}),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('One')),
                  ButtonSegment(value: 2, label: Text('Two')),
                ],
                selected: const {1},
                onSelectionChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.cursorColor, AetherColors.primary);
    expect(editable.selectionColor, const Color(0x33111111));
    final controlTheme = Theme.of(tester.element(find.byType(Checkbox)));
    expect(controlTheme.colorScheme.primary, AetherColors.primary);
    final segmentTheme = Theme.of(
      tester.element(find.byType(SegmentedButton<int>)),
    );
    final selectedFill = segmentTheme.colorScheme.secondaryContainer;
    expect(selectedFill.r, selectedFill.g);
    expect(selectedFill.g, selectedFill.b);
    expect(tester.takeException(), isNull);
  });
}
