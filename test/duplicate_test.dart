import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:szydelkowe_wzory/main.dart';

Future<void> boot(WidgetTester t, Map<String, dynamic> pattern) async {
  t.view.physicalSize = const Size(1080, 1920);
  t.view.devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    await t.pumpWidget(App(home: Editor(initialPattern: jsonEncode(pattern))));
    await Future.delayed(const Duration(milliseconds: 200));
  });
  await t.pump();
}

// placed symbols are drawn with BoxFit.fill, palette ones with contain
int placed(WidgetTester t) => t
    .widgetList(
      find.byWidgetPredicate((w) => w is SvgPicture && w.fit == BoxFit.fill),
    )
    .length;

void main() {
  testWidgets('circle: 8 elements over full circle', (t) async {
    await boot(t, {
      'name': 't',
      'circle': true,
      'selected': 0,
      'items': [
        {'s': 'dc', 'x': 750, 'y': 690, 'r': 0, 'k': 1, 'c': 0xFF000000},
      ],
    });
    expect(placed(t), 1);
    await t.tap(find.byTooltip('Powiel'));
    await t.pumpAndSettle();
    expect(find.text('Liczba elementów w segmencie'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, '8');
    await t.tap(find.text('Powiel').last);
    await t.pumpAndSettle();
    expect(placed(t), 8);
    // single undo removes the whole batch
    await t.tap(find.byTooltip('Cofnij'));
    await t.pumpAndSettle();
    expect(placed(t), 1);
  });

  testWidgets('grid: 4 x 3 and validation', (t) async {
    await boot(t, {
      'name': 't',
      'selected': 0,
      'items': [
        {'s': 'sc-cross', 'x': 600, 'y': 900, 'r': 0, 'k': 1, 'c': 0xFF000000},
      ],
    });
    await t.tap(find.byTooltip('Powiel'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), '500');
    await t.tap(find.text('Powiel').last);
    await t.pump();
    expect(find.textContaining('Podaj liczby'), findsOneWidget);
    await t.enterText(find.byType(TextField).at(0), '4');
    await t.enterText(find.byType(TextField).at(1), '3');
    await t.tap(find.text('Powiel').last);
    await t.pumpAndSettle();
    expect(placed(t), 12);
  });
}
