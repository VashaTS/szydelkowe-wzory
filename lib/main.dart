import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const double kCanvas = 1500;
const kColors = <int>[
  0xFF000000,
  0xFF616161,
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF5E35B1,
  0xFF1E88E5,
  0xFF00ACC1,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFFDD835,
  0xFFFB8C00,
  0xFF6D4C41,
  0xFFF48FB1,
  0xFF90CAF9,
];

class Stitch {
  final String id, name, src;
  final double w, h, ax, ay;
  Stitch(this.id, this.name, this.w, this.h, this.ax, this.ay, this.src);
  factory Stitch.fromJson(Map<String, dynamic> j) => Stitch(
    j['id'],
    j['name'],
    (j['w'] as num).toDouble(),
    (j['h'] as num).toDouble(),
    (j['ax'] as num).toDouble(),
    (j['ay'] as num).toDouble(),
    j['src'],
  );
  String get asset => 'assets/stitches/$id.svg';
}

class Item {
  String stitch;
  double x, y, rot, scale;
  int color;
  Item(
    this.stitch,
    this.x,
    this.y, {
    this.rot = 0,
    this.scale = 1,
    this.color = 0xFF000000,
  });
  Map<String, dynamic> toJson() => {
    's': stitch,
    'x': x,
    'y': y,
    'r': rot,
    'k': scale,
    'c': color,
  };
  factory Item.fromJson(Map<String, dynamic> j) => Item(
    j['s'],
    (j['x'] as num).toDouble(),
    (j['y'] as num).toDouble(),
    rot: (j['r'] as num).toDouble(),
    scale: (j['k'] as num).toDouble(),
    color: (j['c'] as num?)?.toInt() ?? 0xFF000000,
  );
}

Future<List<Stitch>> loadStitches() async {
  final s = await rootBundle.loadString('assets/stitches/stitches.json');
  return (jsonDecode(s) as List).map((e) => Stitch.fromJson(e)).toList();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Szydełkowe Wzory',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
    home: const Editor(),
  );
}

class Editor extends StatefulWidget {
  const Editor({super.key});
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  List<Stitch> stitches = [];
  Map<String, Stitch> byId = {};
  Stitch? selectedStitch;
  List<Item> items = [];
  int? sel;
  final List<String> undo = [];
  bool grid = true, snap = true, circle = false, moveMode = false;
  double gridSize = 30;
  int curColor = 0xFF000000;
  String? bgPath;
  double bgOpacity = 0.35;
  String name = 'Mój wzór';
  final boundaryKey = GlobalKey();
  final tc = TransformationController();

  @override
  void initState() {
    super.initState();
    loadStitches().then(
      (l) => setState(() {
        stitches = l;
        byId = {for (final s in l) s.id: s};
        selectedStitch = l.firstWhere(
          (s) => s.id == 'dc',
          orElse: () => l.first,
        );
      }),
    );
    tc.value = Matrix4.identity()
      ..translateByDouble(-kCanvas / 2 + 180, -kCanvas / 2 + 300, 0, 1);
  }

  String snapshot() => jsonEncode({
    'name': name,
    'bg': bgPath,
    'items': items.map((e) => e.toJson()).toList(),
  });
  void restore(String s) {
    final j = jsonDecode(s);
    name = j['name'] ?? 'Mój wzór';
    bgPath = j['bg'];
    if (bgPath != null && !File(bgPath!).existsSync()) bgPath = null;
    items = (j['items'] as List).map((e) => Item.fromJson(e)).toList();
    sel = null;
  }

  void push() {
    undo.add(snapshot());
    if (undo.length > 100) undo.removeAt(0);
  }

  void doUndo() {
    if (undo.isEmpty) return;
    setState(() => restore(undo.removeLast()));
  }

  Offset snapPt(Offset p) {
    if (circle) {
      const c = Offset(kCanvas / 2, kCanvas / 2);
      final d = p - c;
      final r = d.distance;
      if (snap && r > 1) {
        final rr = (r / gridSize).round() * gridSize;
        return c + d / r * rr;
      }
      return p;
    }
    if (!snap) return p;
    double s(double v) => (v / gridSize).round() * gridSize;
    return Offset(s(p.dx), s(p.dy));
  }

  double autoRot(Offset p) {
    if (!circle) return 0;
    final d = p - const Offset(kCanvas / 2, kCanvas / 2);
    if (d.distance < 1) return 0;
    // symbol top points away from center
    final a = math.atan2(d.dy, d.dx) * 180 / math.pi + 90;
    return snap ? (a / 15).round() * 15.0 : a;
  }

  void place(Offset p) {
    // 1) something selected -> empty tap only deselects
    if (sel != null) {
      setState(() => sel = null);
      return;
    }
    // 2) no palette stitch chosen -> nothing to place
    final st = selectedStitch;
    if (st == null) {
      toast('Wybierz ścieg z palety, aby go postawić');
      return;
    }
    push();
    final q = snapPt(p);
    setState(
      () =>
          items.add(Item(st.id, q.dx, q.dy, rot: autoRot(q), color: curColor)),
    );
  }

  void rotate(double d) {
    if (sel == null) return;
    push();
    setState(() => items[sel!].rot = (items[sel!].rot + d) % 360);
  }

  void scale(double f) {
    if (sel == null) return;
    push();
    setState(() => items[sel!].scale = (items[sel!].scale * f).clamp(0.3, 4));
  }

  void delete() {
    if (sel == null) return;
    push();
    setState(() {
      items.removeAt(sel!);
      sel = null;
    });
  }

  void duplicate() {
    if (sel == null) return;
    push();
    final o = items[sel!];
    double nx = o.x + gridSize, ny = o.y, nrot = o.rot;
    if (circle) {
      const c = Offset(kCanvas / 2, kCanvas / 2);
      final d = Offset(o.x, o.y) - c;
      final r = d.distance;
      if (r > 1) {
        final s = byId[o.stitch];
        final w = (s?.w ?? 30) * o.scale;
        // one stitch width along the arc (+ small gap), clamped 5..45 deg
        var stepDeg = ((w + 4) / r) * 180 / math.pi;
        stepDeg = stepDeg.clamp(5.0, 45.0);
        if (snap) stepDeg = (stepDeg / 5).ceil() * 5.0;
        final a = stepDeg * math.pi / 180;
        nx = c.dx + d.dx * math.cos(a) - d.dy * math.sin(a);
        ny = c.dy + d.dx * math.sin(a) + d.dy * math.cos(a);
        nrot = (o.rot + stepDeg) % 360;
      }
    }
    setState(() {
      items.add(
        Item(o.stitch, nx, ny, rot: nrot, scale: o.scale, color: o.color),
      );
      sel = items.length - 1;
    });
  }

  Future<void> pickColor() async {
    final c = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sel != null
                    ? 'Kolor zaznaczonego symbolu'
                    : 'Kolor nowych symboli',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final k in kColors)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, k),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(k),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: k == curColor ? Colors.pink : Colors.black26,
                            width: k == curColor ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (c == null) return;
    setState(() {
      curColor = c;
      if (sel != null) {
        push();
        items[sel!].color = c;
      }
    });
  }

  Future<Directory> patternsDir() async {
    final d = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/wzory',
    );
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  void toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> save() async {
    final c = TextEditingController(text: name);
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zapisz wzór'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nazwa'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    if (n == null || n.isEmpty) return;
    name = n;
    final safe = n.replaceAll(RegExp(r'[^\w\-ąćęłńóśźżĄĆĘŁŃÓŚŹŻ ]'), '_');
    final f = File('${(await patternsDir()).path}/$safe.json');
    await f.writeAsString(snapshot());
    setState(() {});
    toast('Zapisano „$n”');
  }

  Future<void> open() async {
    final d = await patternsDir();
    final files =
        d
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => files.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak zapisanych wzorów'),
              )
            : ListView(
                children: [
                  const ListTile(
                    title: Text(
                      'Zapisane wzory',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final f in files)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                        f.uri.pathSegments.last.replaceAll('.json', ''),
                      ),
                      onTap: () {
                        push();
                        setState(() => restore(f.readAsStringSync()));
                        Navigator.pop(ctx);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          f.deleteSync();
                          ss(() => files.remove(f));
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> exportPng() async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    setState(() => sel = null);
    await Future.delayed(const Duration(milliseconds: 50));
    await WidgetsBinding.instance.endOfFrame;
    final ro =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await ro.toImage(pixelRatio: dpr);
    // export exactly the visible viewport (current zoom/pan)
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/${name.replaceAll(RegExp(r'[^\w]'), '_')}.png');
    await f.writeAsBytes(bytes!.buffer.asUint8List());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: "image/png")],
        text: name,
      ),
    );
  }

  Future<void> pickBg() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final f = await File(x.path).copy(
      '${dir.path}/tlo_${DateTime.now().millisecondsSinceEpoch}${x.path.contains('.') ? x.path.substring(x.path.lastIndexOf('.')) : '.jpg'}',
    );
    setState(() => bgPath = f.path);
  }

  void about() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const AboutPage()),
  );

  Widget itemWidget(int i) {
    final it = items[i];
    final s = byId[it.stitch];
    if (s == null) return const SizedBox();
    final w = s.w * it.scale, h = s.h * it.scale;
    final selected = sel == i;
    return Positioned(
      left: it.x - s.ax * it.scale,
      top: it.y - s.ay * it.scale,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: it.rot * math.pi / 180,
        alignment: Alignment(s.ax / s.w * 2 - 1, s.ay / s.h * 2 - 1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => sel = selected ? null : i),
          onPanStart: (_) {
            push();
            setState(() => sel = i);
          },
          onPanUpdate: (d) {
            final a = it.rot * math.pi / 180;
            final dx = d.delta.dx * math.cos(a) - d.delta.dy * math.sin(a);
            final dy = d.delta.dx * math.sin(a) + d.delta.dy * math.cos(a);
            setState(() {
              it.x += dx;
              it.y += dy;
            });
          },
          onPanEnd: (_) {
            final q = snapPt(Offset(it.x, it.y));
            setState(() {
              it.x = q.dx;
              it.y = q.dy;
              if (circle) it.rot = autoRot(q);
            });
          },
          child: Container(
            decoration: selected
                ? BoxDecoration(
                    border: Border.all(color: Colors.pink, width: 1.5),
                    color: Colors.pink.withValues(alpha: 0.08),
                  )
                : null,
            child: SvgPicture.asset(
              s.asset,
              fit: BoxFit.fill,
              colorFilter: ColorFilter.mode(Color(it.color), BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSel = sel != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Cofnij',
            icon: const Icon(Icons.undo),
            onPressed: undo.isEmpty ? null : doUndo,
          ),
          IconButton(
            tooltip: 'Zapisz',
            icon: const Icon(Icons.save_outlined),
            onPressed: save,
          ),
          IconButton(
            tooltip: 'Otwórz',
            icon: const Icon(Icons.folder_open),
            onPressed: open,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'new':
                  push();
                  setState(() {
                    items = [];
                    sel = null;
                    name = 'Mój wzór';
                    bgPath = null;
                  });
                case 'png':
                  exportPng();
                case 'bg':
                  pickBg();
                case 'bgoff':
                  setState(() => bgPath = null);
                case 'grid':
                  setState(() => grid = !grid);
                case 'snap':
                  setState(() => snap = !snap);
                case 'circle':
                  setState(() => circle = !circle);
                case 'about':
                  about();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('Nowy wzór')),
              const PopupMenuItem(
                value: 'png',
                child: Text('Eksportuj PNG / udostępnij'),
              ),
              const PopupMenuItem(
                value: 'bg',
                child: Text('Tło z obrazu (do odrysowania)'),
              ),
              if (bgPath != null)
                const PopupMenuItem(value: 'bgoff', child: Text('Usuń tło')),
              CheckedPopupMenuItem(
                value: 'grid',
                checked: grid,
                child: const Text('Pokaż siatkę'),
              ),
              CheckedPopupMenuItem(
                value: 'snap',
                checked: snap,
                child: const Text('Przyciąganie'),
              ),
              CheckedPopupMenuItem(
                value: 'circle',
                checked: circle,
                child: const Text('Tryb okrągły'),
              ),
              const PopupMenuItem(value: 'about', child: Text('O aplikacji')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: RepaintBoundary(
                key: boundaryKey,
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: tc,
                    constrained: false,
                    minScale: 0.3,
                    maxScale: 6,
                    boundaryMargin: const EdgeInsets.all(400),
                    child: GestureDetector(
                      onTapUp: (d) => place(d.localPosition),
                      child: RepaintBoundary(
                        child: SizedBox(
                          width: kCanvas,
                          height: kCanvas,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Container(color: Colors.white),
                              ),
                              if (bgPath != null)
                                Positioned.fill(
                                  child: Center(
                                    child: Opacity(
                                      opacity: bgOpacity,
                                      child: Image.file(
                                        File(bgPath!),
                                        width: kCanvas * 0.7,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              if (grid || circle)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: GuidePainter(
                                      gridSize,
                                      grid && !circle,
                                      circle,
                                    ),
                                  ),
                                ),
                              for (int i = 0; i < items.length; i++)
                                itemWidget(i),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (bgPath != null)
              Row(
                children: [
                  const SizedBox(width: 12),
                  const Text('Tło'),
                  Expanded(
                    child: Slider(
                      value: bgOpacity,
                      min: 0.05,
                      max: 1,
                      onChanged: (v) => setState(() => bgOpacity = v),
                    ),
                  ),
                ],
              ),
            Material(
              elevation: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Kolor',
                      icon: Icon(
                        Icons.palette,
                        color: Color(hasSel ? items[sel!].color : curColor),
                      ),
                      onPressed: pickColor,
                    ),
                    IconButton(
                      tooltip: 'Obróć w lewo 15°',
                      icon: const Icon(Icons.rotate_left),
                      onPressed: hasSel ? () => rotate(-15) : null,
                    ),
                    IconButton(
                      tooltip: 'Obróć w prawo 15°',
                      icon: const Icon(Icons.rotate_right),
                      onPressed: hasSel ? () => rotate(15) : null,
                    ),
                    IconButton(
                      tooltip: 'Pomniejsz',
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: hasSel ? () => scale(1 / 1.15) : null,
                    ),
                    IconButton(
                      tooltip: 'Powiększ',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: hasSel ? () => scale(1.15) : null,
                    ),
                    IconButton(
                      tooltip: 'Powiel',
                      icon: const Icon(Icons.copy),
                      onPressed: hasSel ? duplicate : null,
                    ),
                    IconButton(
                      tooltip: 'Odznacz',
                      icon: const Icon(Icons.deselect),
                      onPressed: hasSel
                          ? () => setState(() => sel = null)
                          : null,
                    ),
                    IconButton(
                      tooltip: 'Usuń',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: hasSel ? delete : null,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              // keep palette above Android nav bar (gesture or 3-button)
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom,
              ),
              height: 104 + MediaQuery.viewPaddingOf(context).bottom,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: stitches.length,
                itemBuilder: (_, i) {
                  final s = stitches[i];
                  final on = selectedStitch?.id == s.id;
                  return GestureDetector(
                    onTap: () => setState(() {
                      // tap the active stitch again to un-choose it
                      selectedStitch = selectedStitch?.id == s.id ? null : s;
                      sel = null;
                    }),
                    child: Container(
                      width: 84,
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: on ? Colors.pink.shade100 : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: on ? Colors.pink : Colors.black12,
                          width: on ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: SvgPicture.asset(
                              s.asset,
                              fit: BoxFit.contain,
                            ),
                          ),
                          Text(
                            s.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GuidePainter extends CustomPainter {
  final double g;
  final bool grid, circle;
  GuidePainter(this.g, this.grid, this.circle);
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (grid) {
      for (double x = 0; x <= s.width; x += g) {
        c.drawLine(Offset(x, 0), Offset(x, s.height), p);
      }
      for (double y = 0; y <= s.height; y += g) {
        c.drawLine(Offset(0, y), Offset(s.width, y), p);
      }
    }
    if (circle) {
      final ctr = Offset(s.width / 2, s.height / 2);
      for (double r = g; r < s.width / 2; r += g) {
        c.drawCircle(ctr, r, p);
      }
      for (int a = 0; a < 360; a += 15) {
        final t = a * math.pi / 180;
        c.drawLine(
          ctr,
          ctr + Offset(math.cos(t), math.sin(t)) * s.width / 2,
          p,
        );
      }
      c.drawCircle(ctr, 4, Paint()..color = Colors.pink.shade200);
    }
  }

  @override
  bool shouldRepaint(GuidePainter o) =>
      o.grid != grid || o.circle != circle || o.g != g;
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('O aplikacji')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Text(
            'Szydełkowe Wzory',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Układaj własne schematy szydełkowe z pojedynczych symboli ściegów.',
          ),
          SizedBox(height: 16),
          Text('Jak używać', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            '• Wybierz ścieg z palety na dole i stuknij w płótno, aby go postawić.\n'
            '• Stuknij symbol, aby go zaznaczyć; przeciągnij, aby przesunąć.\n'
            '• Przyciski: obrót o 15°, zmiana rozmiaru, powielenie, usunięcie.\n'
            '• Dwa palce: przybliżanie i przesuwanie płótna.\n'
            '• Menu: siatka, przyciąganie, tryb okrągły (symbole obracają się od środka), tło z obrazu, eksport PNG.',
          ),
          SizedBox(height: 16),
          Text('Źródło symboli', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(
            'Symbole ściegów szydełkowych według standardu Craft Yarn Council '
            '(www.craftyarncouncil.com). Pliki SVG pochodzą z projektu cyc-svgs autorstwa Leifa Rogersa '
            '(github.com/leifrogers/cyc-svgs, licencja MIT). Dziękujemy!',
          ),
          SizedBox(height: 8),
          Text(
            'Dodatkowe symbole (oczko ścisłe wydłużone, słupek wydłużony, półsłupki reliefowe, '
            'słupki podwójne reliefowe, 2 półsłupki razem, magiczne kółko) narysowano w tym samym stylu na potrzeby aplikacji.',
          ),
        ],
      ),
    ),
  );
}
