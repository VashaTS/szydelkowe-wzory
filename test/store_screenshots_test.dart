// Renders Play Store screenshots (synthetic, rendered by Flutter test engine).
// Run: flutter test --update-goldens test/store_screenshots_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:szydelkowe_wzory/main.dart';

const c = 750.0;
Map<String, dynamic> it(
  String s,
  double x,
  double y, {
  double r = 0,
  double k = 1,
  int col = 0xFF000000,
}) => {'s': s, 'x': x, 'y': y, 'r': r, 'k': k, 'c': col};

String circular() {
  final items = <Map<String, dynamic>>[it('magic-ring', c, c, col: 0xFFD81B60)];
  void ring(String s, double r, int n, int col, {double off = 0}) {
    for (var i = 0; i < n; i++) {
      final a = (i * 360 / n + off) * math.pi / 180;
      final x = c + r * math.cos(a), y = c + r * math.sin(a);
      items.add(it(s, x, y, r: (i * 360 / n + off + 90) % 360, col: col));
    }
  }

  ring('dc', 30, 12, 0xFF8E24AA);
  ring('chain', 100, 12, 0xFF1E88E5, off: 15);
  ring('5-dc-shell', 125, 6, 0xFFD81B60);
  ring('ch-3-picot', 200, 12, 0xFF00897B, off: 15);
  return jsonEncode({
    'name': 'Serwetka – kółko',
    'items': items,
    'circle': true,
    'stitch': 'dc',
  });
}

String rows() {
  final items = <Map<String, dynamic>>[];
  const x0 = 600.0;
  for (var i = 0; i < 6; i++) {
    items.add(it('chain', x0 + i * 60, 900, col: 0xFF616161));
  }
  for (var i = 0; i < 12; i++) {
    items.add(it('sc-cross', x0 - 15 + i * 30, 870));
  }
  for (var i = 0; i < 12; i++) {
    items.add(
      it(
        i.isEven ? 'fpdc' : 'bpdc',
        x0 - 15 + i * 30,
        840,
        col: i.isEven ? 0xFFD81B60 : 0xFF8E24AA,
      ),
    );
  }
  for (var i = 0; i < 3; i++) {
    items.add(it('5-dc-shell', x0 + 30 + i * 120, 765, col: 0xFF1E88E5));
  }
  for (var i = 0; i < 12; i++) {
    items.add(
      it(
        i % 3 == 1 ? 'spike-sc' : 'hdc',
        x0 - 15 + i * 30,
        695,
        col: i % 3 == 1 ? 0xFF00897B : 0xFF000000,
      ),
    );
  }
  for (var i = 0; i < 4; i++) {
    items.add(it('5-dc-popcorn', x0 + 15 + i * 90, 615, col: 0xFFFB8C00));
  }
  return jsonEncode({
    'name': 'Bordiura z muszelkami',
    'items': items,
    'stitch': 'fpdc',
    'selected': 30,
  });
}

Future<void> loadFonts() async {
  final base =
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter'}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular', 'Roboto-Medium', 'Roboto-Bold']) {
    roboto.addFont(
      Future.value(
        ByteData.sublistView(File('$base/$f.ttf').readAsBytesSync()),
      ),
    );
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$base/MaterialIcons-Regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

void main() {
  setUpAll(loadFonts);
  Future<void> shot(
    WidgetTester t,
    Widget home,
    String file, {
    Future<void> Function()? after,
  }) async {
    debugDisableShadows = false;
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await t.pumpWidget(App(home: home));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    if (after != null) await after();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screenshots/$file'),
    );
    debugDisableShadows = true;
  }

  testWidgets(
    '1 circle',
    (t) => shot(t, Editor(initialPattern: circular()), '1-kolko.png'),
  );
  testWidgets(
    '2 rows',
    (t) => shot(t, Editor(initialPattern: rows()), '2-rzedy.png'),
  );
  testWidgets(
    '3 menu',
    (t) => shot(
      t,
      Editor(initialPattern: rows()),
      '3-menu.png',
      after: () async {
        await t.tap(find.byIcon(Icons.more_vert));
        await t.pumpAndSettle();
      },
    ),
  );
  testWidgets(
    '4 about',
    (t) => shot(t, const AboutPage(), '4-o-aplikacji.png'),
  );
}
