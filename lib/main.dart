import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stroke_matcher.dart';
import 'calligraphy_brush.dart';

const ink = Color(0xff293f36),
    red = Color(0xff187b78),
    paper = Color(0xffffffff),
    panel = Color(0xfff6f8fa),
    textPrimary = Color(0xff172b38),
    muted = Color(0xff687984);
void main() => runApp(const HanziApp());

class HanziApp extends StatelessWidget {
  const HanziApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Mực • Luyện Hán tự',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: paper,
      colorScheme: const ColorScheme.light(
        primary: red,
        secondary: Color(0xff527da1),
        surface: panel,
        onSurface: textPrimary,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerColor: const Color(0xffe2e8ed),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        hintStyle: const TextStyle(color: muted, fontSize: 14),
        prefixIconColor: muted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffe2e8ed)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: red),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: red,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: red,
          disabledForegroundColor: const Color(0xffbac5cb),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: const Color(0xffe2f2ef),
        side: const BorderSide(color: Color(0xffd9e6e2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: panel,
        showDragHandle: true,
      ),
    ),
    home: const PracticePage(),
  );
}

class PracticePage extends StatefulWidget {
  const PracticePage({super.key});
  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> words = [];
  Map<String, dynamic>? word;
  int level = 1, character = 0, generation = 0;
  double speechSpeed = 1.1;
  bool originalAudio = false;
  FlutterTts? tts;
  final homeScroll = ScrollController();
  bool penOnly = false, guide = true, loading = false, speaking = false;
  String? error;
  final learned = <String>{};
  final writtenCharacters = <String, Set<String>>{};
  final strokes = <List<Offset>>[];
  final matchedIndices = <int>[];
  final brushSamples = <List<Offset>, List<BrushPoint>>{};
  List<Path> outlines = [];
  List<List<Offset>> medians = [];
  SharedPreferences? prefs;
  AudioPlayer? player;
  StreamSubscription<void>? audioCompletion;
  int? pointer;
  String? strokeHint;
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  String get current => String.fromCharCode(
    (word!['hanzi'] as String).runes.elementAt(character),
  );
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data =
          jsonDecode(await rootBundle.loadString('assets/words.json')) as List;
      prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        words = data.cast<Map<String, dynamic>>();
        learned.addAll(prefs!.getStringList('learned') ?? []);
      });
      setState(() {
        speechSpeed = prefs!.getDouble('speechSpeed') ?? 1.1;
        originalAudio = prefs!.getBool('originalAudio') ?? false;
        penOnly = prefs!.getBool('penOnly') ?? false;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'Không thể tải dữ liệu từ vựng. Hãy mở lại ứng dụng.',
        );
      }
    }
  }

  void choose(Map<String, dynamic> w) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      word = w;
      character = 0;
    });
    loadCharacter();
  }

  Future<void> loadCharacter() async {
    final id = ++generation;
    final char = current;
    animation.stop();
    animation.value = 0;
    setState(() {
      strokes.clear();
      brushSamples.clear();
      matchedIndices.clear();
      strokeHint = null;
      pointer = null;
      outlines = [];
      medians = [];
      loading = true;
      error = null;
    });
    try {
      var raw = prefs?.getString('char_$char');
      if (raw == null) {
        final response = await http
            .get(
              Uri.parse(
                'https://cdn.jsdelivr.net/npm/hanzi-writer-data@2.0.1/${Uri.encodeComponent(char)}.json',
              ),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) throw Exception('missing');
        raw = utf8.decode(response.bodyBytes);
        jsonDecode(raw);
        await prefs?.setString('char_$char', raw);
      }
      final data = jsonDecode(raw);
      final paths = (data['strokes'] as List)
          .map((s) => parseSvgPathData(s))
          .toList();
      final lines = (data['medians'] as List)
          .map(
            (l) => (l as List)
                .map(
                  (p) => Offset(
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  ),
                )
                .toList(),
          )
          .toList();
      if (!mounted || generation != id) return;
      setState(() {
        outlines = paths;
        medians = lines;
        loading = false;
      });
    } catch (e) {
      if (mounted && generation == id) {
        setState(() {
          loading = false;
          error = 'Chưa tải được nét mẫu. Bạn vẫn có thể viết tự do; kiểm tra mạng rồi thử lại.';
        });
      }
    }
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> stopAudio() async {
    await player?.stop();
    await tts?.stop();
    if (mounted) setState(() => speaking = false);
  }

  Future<void> speak() async {
    if (speaking) {
      await stopAudio();
      return;
    }
    final text = word!['hanzi'] as String;
    setState(() => speaking = true);
    try {
      if (originalAudio) {
        final audio = player ??= AudioPlayer();
        audioCompletion ??= audio.onPlayerComplete.listen((_) {
          if (mounted) setState(() => speaking = false);
        });
        await audio.stop();
        await audio.setPlaybackRate(speechSpeed);
        await audio
            .play(UrlSource(word!['tts_url']))
            .timeout(const Duration(seconds: 15));
      } else {
        final voice = tts ??= FlutterTts();
        voice.setCompletionHandler(() {
          if (mounted) setState(() => speaking = false);
        });
        voice.setErrorHandler((message) {
          if (mounted) {
            setState(() => speaking = false);
            toast(
              'Không đọc được tiếng Trung. Kiểm tra giọng zh-CN trong cài đặt thiết bị.',
            );
          }
        });
        if (await voice.isLanguageAvailable('zh-CN') != true) {
          throw StateError('missing Chinese voice');
        }
        await voice.setLanguage('zh-CN');
        await voice.setSpeechRate(0.5 * speechSpeed);
        await voice.setPitch(1.0);
        final result = await voice.speak(text);
        if (result != 1) throw StateError('speech rejected');
      }
    } catch (e) {
      if (mounted) setState(() => speaking = false);
      toast(
        originalAudio
            ? 'Không tải được âm thanh gốc. Hãy thử giọng thiết bị trong cài đặt.'
            : 'Chưa có giọng Quan thoại (zh-CN). Hãy tải giọng tiếng Trung trên thiết bị hoặc chọn âm thanh gốc trong cài đặt.',
      );
    }
  }

  void closePractice() {
    generation++;
    animation.stop();
    stopAudio();
    setState(() {
      word = null;
      strokes.clear();
      brushSamples.clear();
      matchedIndices.clear();
      strokeHint = null;
      pointer = null;
      error = null;
    });
  }

  void settings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cài đặt', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 16),
                DropdownButtonFormField<bool>(
                  initialValue: originalAudio,
                  decoration: const InputDecoration(labelText: 'Giọng đọc'),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('Quan thoại · giọng thiết bị'),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text('Âm thanh gốc HSK'),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await stopAudio();
                    setState(() => originalAudio = v);
                    update(() {});
                    await prefs?.setBool('originalAudio', v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<double>(
                  initialValue: speechSpeed,
                  decoration: const InputDecoration(labelText: 'Tốc độ đọc'),
                  items: [0.85, 1.0, 1.1, 1.25]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text('$v×')),
                      )
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    await stopAudio();
                    setState(() => speechSpeed = v);
                    update(() {});
                    await prefs?.setDouble('speechSpeed', v);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Giọng thiết bị đọc trực tiếp chữ Hán. Chất lượng tùy giọng tiếng Trung đã cài trên Android/iOS.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hiện chữ mẫu'),
                  value: guide,
                  onChanged: (v) {
                    setState(() => guide = v);
                    update(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Chỉ nhận bút cảm ứng'),
                  subtitle: const Text(
                    'Bật với Apple Pencil; tắt với bút điện dung thường.',
                  ),
                  value: penOnly,
                  onChanged: (v) {
                    setState(() => penOnly = v);
                    update(() {});
                    prefs?.setBool('penOnly', v);
                  },
                ),
                const Divider(),
                const Text(
                  '5.000 từ · willfliaw/hsk-dataset · CC BY 4.0\nNét chữ: Hanzi Writer Data / Make Me a Hanzi · Arphic Public License',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> complete() async {
    setState(() => learned.add(word!['hanzi']));
    try {
      await prefs?.setStringList('learned', learned.toList());
      toast('Đã lưu từ vào danh sách đã luyện.');
    } catch (e) {
      toast('Chưa lưu được tiến độ trên thiết bị.');
    }
  }

  Future<void> recordWrittenCharacter() async {
    final hanzi = word!['hanzi'] as String;
    final completed = writtenCharacters.putIfAbsent(
      hanzi,
      () => (prefs?.getStringList('written_$hanzi') ?? []).toSet(),
    );
    completed.add('$character');
    final finished = completed.length == hanzi.runes.length;
    final newlyFinished = finished && !learned.contains(hanzi);
    if (finished) setState(() => learned.add(hanzi));
    try {
      await prefs?.setStringList('written_$hanzi', completed.toList());
      if (finished) await prefs?.setStringList('learned', learned.toList());
      if (newlyFinished) toast('Đã viết $hanzi');
    } catch (e) {
      toast('Chưa lưu được tiến độ trên thiết bị.');
    }
  }

  void explain() {
    const vi = {
      '好': 'tốt; khỏe; hay',
      '爱': 'yêu; yêu thích',
      '八': 'tám',
      '爸爸': 'bố; ba',
      '人': 'người',
      '大': 'to; lớn',
      '小': 'nhỏ; bé',
      '水': 'nước',
      '我': 'tôi; mình',
      '你': 'bạn',
      '中国': 'Trung Quốc',
      '学习': 'học tập',
      '汉语': 'tiếng Trung',
      '谢谢': 'cảm ơn',
    };
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${word!['hanzi']}  ${word!['pinyin_tone']}',
                style: const TextStyle(fontSize: 30, color: textPrimary),
              ),
              const SizedBox(height: 16),
              if (vi.containsKey(word!['hanzi']))
                Text(vi[word!['hanzi']]!, style: const TextStyle(fontSize: 22)),
              Text(
                'Nghĩa gốc tiếng Anh: ${word!['english']}',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text('HSK ${word!['level']} • Từ loại gốc: ${word!['pos']}'),
              const Divider(height: 32),
              const Text(
                'Cách luyện viết',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Chọn từng chữ trong từ rồi nhấn "Hướng dẫn viết" để xem thứ tự và chiều đi của nét. Chữ đang luyện: $current${outlines.isEmpty ? '' : ' · ${outlines.length} nét'}.\n\nViết theo mẫu nhạt. Khi nhấc bút, nét gần đúng sẽ tô vào nét mẫu còn trống; app vẫn nhận khi bạn viết khác thứ tự. Để học đúng, hãy theo hoạt ảnh. Nét chưa khớp sẽ được xóa để thử lại.\n\nHoàn thành tất cả chữ trong từ để tự lưu trạng thái “Đã viết”. Đây là hỗ trợ tô nét, không đánh giá thư pháp.',
              ),
              const SizedBox(height: 24),
              const Text(
                'Ghi chú · Quy tắc viết',
                key: ValueKey('writing-rules'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '1. Trên trước, dưới sau (先上后下)\n'
                'Viết phần phía trên rồi xuống dưới. Ví dụ: 三.\n\n'
                '2. Trái trước, phải sau (先左后右)\n'
                'Với chữ ghép trái–phải, viết phần trái trước. Ví dụ: 好 viết 女 rồi 子.\n\n'
                '3. Ngang trước, sổ sau (先横后竖)\n'
                'Khi hai nét giao nhau, thường viết ngang trước nét dọc. Ví dụ: 十.\n\n'
                '4. Phẩy trước, mác sau (先撇后捺)\n'
                'Nét chéo xuống trái thường đi trước nét chéo xuống phải. Ví dụ: 人.\n\n'
                '5. Ngoài trước, trong sau (先外后内)\n'
                'Với khung bao ở trên và hai bên, viết phần khung trước rồi phần bên trong. Ví dụ: 同.\n\n'
                '6. Vào trong rồi mới đóng khung (先里头后封口)\n'
                'Nếu có nét ngang đóng đáy, để nét ấy cuối cùng. Ví dụ: 日.\n\n'
                '7. Giữa trước, hai bên sau (先中间后两边)\n'
                'Một số chữ đối xứng viết nét giữa trước. Ví dụ: 小.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Áp dụng với “${word!['hanzi']}”: luyện từng chữ theo thứ tự từ trái sang phải trong từ. Trong mỗi chữ, theo thứ tự nét của nút “Hướng dẫn viết”.\n\nNgang thường đi từ trái sang phải; sổ thường đi từ trên xuống dưới. Nhấc bút giữa hai nét, nhưng viết liền nét gập hoặc móc nếu mẫu thể hiện đó là một nét.\n\nCác quy tắc trên là nguyên tắc thường gặp, có ngoại lệ và khác biệt theo chuẩn chữ. Ưu tiên hoạt ảnh nét của chữ đang luyện.',
                  style: const TextStyle(height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              const SelectableText(
                'Tham khảo quy tắc: Bộ Giáo dục Đài Loan · Basic Rules of Stroke Order\nhttps://stroke-order.learningweb.moe.edu.tw/page.jsp?ID=46&la=1',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nguồn từ và âm thanh: willfliaw/hsk-dataset (CC BY 4.0). Nét: Hanzi Writer Data / Make Me a Hanzi (Arphic Public License). Nghĩa Việt được biên soạn cho một số từ; còn lại giữ nghĩa tiếng Anh gốc.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get filteredWords {
    final items = words.where((w) => w['level'] == '$level').toList();
    // Stable partition: keep the dataset order within each progress group.
    return [
      ...items.where((w) => !learned.contains(w['hanzi'])),
      ...items.where((w) => learned.contains(w['hanzi'])),
    ];
  }

  Widget library() => LayoutBuilder(
    builder: (context, bounds) {
      final items = filteredWords;
      final phone = MediaQuery.sizeOf(context).shortestSide < 600;
      final columns = phone ? 2 : (bounds.maxWidth / 180).floor().clamp(3, 8);
      final done = items.where((w) => learned.contains(w['hanzi'])).length;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xffe9f4f1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '墨',
                    style: TextStyle(fontSize: 28, color: red),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Luyện chữ',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.6,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Từng nét, mỗi ngày.',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: settings,
                  tooltip: 'Cài đặt',
                  icon: const Icon(Icons.tune_rounded, size: 22),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, b) => Wrap(
                spacing: 6,
                runSpacing: 8,
                children: List.generate(
                  6,
                  (i) => SizedBox(
                    width: (b.maxWidth - 30) / 6,
                    child: ChoiceChip(
                      key: ValueKey('hsk-${i + 1}'),
                      showCheckmark: false,
                      padding: EdgeInsets.zero,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      label: Text(
                        'HSK ${i + 1}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: level == i + 1,
                      onSelected: (_) {
                        setState(() => level = i + 1);
                        if (homeScroll.hasClients) homeScroll.jumpTo(0);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '${items.length} từ',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$done đã viết · ${items.length - done} chưa viết',
                        key: const ValueKey('progress-summary'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: items.isEmpty ? 0 : done / items.length,
                    minHeight: 3,
                    backgroundColor: const Color(0xffedf1f3),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('Không tìm thấy từ phù hợp.'))
                : GridView.builder(
                    key: const ValueKey('word-grid'),
                    controller: homeScroll,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 172,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final w = items[i];
                      return Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xffe2e8ed)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('word-${w['hanzi']}'),
                          onTap: () => choose(w),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        w['hanzi'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w500,
                                          color: textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  w['pinyin_tone'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: red,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Text(
                                    w['english'],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      learned.contains(w['hanzi'])
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      size: 12,
                                      color: learned.contains(w['hanzi'])
                                          ? red
                                          : muted,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      learned.contains(w['hanzi'])
                                          ? 'Đã viết'
                                          : 'Chưa viết',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: learned.contains(w['hanzi'])
                                            ? red
                                            : muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );

  void removeLastStroke() {
    brushSamples.remove(strokes.removeLast());
  }

  BrushPoint brushPoint(
    PointerEvent event,
    double side, {
    bool lifted = false,
  }) {
    double? pressure;
    final stylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final range = event.pressureMax - event.pressureMin;
    if (stylus && range > 0 && !lifted) {
      pressure = ((event.pressure - event.pressureMin) / range).clamp(0.0, 1.0);
    } else if (lifted && strokes.isNotEmpty) {
      pressure = brushSamples[strokes.last]?.last.pressure;
    }
    return BrushPoint(
      event.localPosition / side,
      pressure,
      event.timeStamp.inMicroseconds,
    );
  }

  Widget board() => LayoutBuilder(
    builder: (context, b) => Listener(
      onPointerDown: (e) {
        if (loading ||
            pointer != null ||
            (penOnly &&
                e.kind != PointerDeviceKind.stylus &&
                e.kind != PointerDeviceKind.invertedStylus)) {
          return;
        }
        if (outlines.isNotEmpty && strokes.length >= outlines.length) return;
        animation.stop();
        animation.value = 0;
        setState(() {
          strokeHint = null;
          pointer = e.pointer;
          strokes.add([e.localPosition / b.maxWidth]);
          brushSamples[strokes.last] = [brushPoint(e, b.maxWidth)];
        });
      },
      onPointerMove: (e) {
        if (pointer == e.pointer) {
          setState(() {
            strokes.last.add(e.localPosition / b.maxWidth);
            brushSamples[strokes.last]!.add(brushPoint(e, b.maxWidth));
          });
        }
      },
      onPointerUp: (e) {
        if (pointer != e.pointer) return;
        setState(() {
          strokes.last.add(e.localPosition / b.maxWidth);
          brushSamples[strokes.last]!.add(
            brushPoint(e, b.maxWidth, lifted: true),
          );
          if (medians.isNotEmpty) {
            final candidates = List.generate(
              medians.length,
              (i) => i,
            ).where((i) => !matchedIndices.contains(i));
            final match = candidates
                .where((i) => StrokeMatcher.matches(strokes.last, medians[i]))
                .firstOrNull;
            if (match == null) {
              removeLastStroke();
              strokeHint = 'Thử lại gần nét mẫu hơn';
            } else {
              matchedIndices.add(match);
            }
          }
          pointer = null;
        });
        if (outlines.isNotEmpty && matchedIndices.length == outlines.length) {
          recordWrittenCharacter();
        }
      },
      onPointerCancel: (e) {
        if (pointer == e.pointer) {
          setState(() {
            removeLastStroke();
            pointer = null;
          });
        }
      },
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          painter: WritingPainter(
            strokes,
            outlines,
            medians,
            guide,
            animation.value,
            animation.isAnimating,
            brushSamples: brushSamples,
            acceptedIndices: List.of(matchedIndices),
            acceptedCount: outlines.isEmpty
                ? 0
                : strokes.length - (pointer == null ? 0 : 1),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
  void nextWord() {
    final list = filteredWords;
    if (list.isEmpty) return;
    stopAudio();
    choose(list[(list.indexOf(word!) + 1) % list.length]);
  }

  void practiceMenu(String action) {
    switch (action) {
      case 'explain':
        explain();
      case 'clear':
        setState(() {
          strokes.clear();
          brushSamples.clear();
          matchedIndices.clear();
          pointer = null;
          strokeHint = null;
          animation.stop();
          animation.value = 0;
        });
      case 'save':
        complete();
      case 'settings':
        settings();
    }
  }

  Widget practice() => LayoutBuilder(
    builder: (context, bounds) {
      final multi = (word!['hanzi'] as String).runes.length > 1;
      final side = math.min(
        640.0,
        math.min(
          bounds.maxWidth - 32,
          math.max(140.0, bounds.maxHeight - (multi ? 166 : 120)),
        ),
      );
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: bounds.maxHeight,
            minWidth: bounds.maxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (multi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      children: List.generate(
                        (word!['hanzi'] as String).runes.length,
                        (i) => ChoiceChip(
                          label: Text(
                            String.fromCharCode(
                              (word!['hanzi'] as String).runes.elementAt(i),
                            ),
                          ),
                          selected: character == i,
                          onSelected: (_) {
                            setState(() => character = i);
                            loadCharacter();
                          },
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  width: side,
                  height: side,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xffd7e3df)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0b187b78),
                          blurRadius: 32,
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Color(0x0d243b45),
                          blurRadius: 20,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: GestureDetector(
                        onPanStart: (_) {},
                        onPanUpdate: (_) {},
                        child: board(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (loading)
                  SizedBox(
                    width: side,
                    child: const LinearProgressIndicator(minHeight: 2),
                  ),
                if (error != null)
                  SizedBox(
                    width: side,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(color: red, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: loadCharacter,
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
                Text(
                  strokeHint ??
                      (outlines.isEmpty
                          ? 'Viết tự do'
                          : '${strokes.length} / ${outlines.length} nét'),
                  style: TextStyle(
                    fontSize: 12,
                    color: strokeHint == null ? muted : red,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: outlines.isEmpty
                          ? null
                          : () {
                              animation.duration = Duration(
                                milliseconds: medians.length * 900,
                              );
                              animation.forward(from: 0);
                            },
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: const Text('Hướng dẫn viết'),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: strokes.isEmpty || pointer != null
                          ? null
                          : () => setState(() {
                              removeLastStroke();
                              if (matchedIndices.isNotEmpty) {
                                matchedIndices.removeLast();
                              }
                              strokeHint = null;
                              animation.stop();
                              animation.value = 0;
                            }),
                      tooltip: 'Hoàn tác',
                      icon: const Icon(Icons.undo, size: 22),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: nextWord,
                      tooltip: 'Từ tiếp theo',
                      icon: const Icon(Icons.arrow_forward, size: 22),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: word == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && word != null) closePractice();
    },
    child: Scaffold(
      appBar: word == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: word == null
                  ? null
                  : IconButton(
                      onPressed: closePractice,
                      tooltip: 'Về danh sách',
                      icon: const Icon(Icons.arrow_back),
                    ),
              title: Text(
                word == null
                    ? 'Hán tự'
                    : '${word!['hanzi']} · ${word!['pinyin_tone']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
              actions: [
                if (word == null)
                  IconButton(
                    onPressed: settings,
                    tooltip: 'Cài đặt',
                    icon: const Icon(Icons.tune, size: 21),
                  ),
                if (word != null)
                  IconButton(
                    onPressed: speak,
                    tooltip: speaking ? 'Dừng phát âm' : 'Nghe phát âm',
                    icon: Icon(
                      speaking
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      size: 22,
                    ),
                  ),
                if (word != null)
                  PopupMenuButton<String>(
                    tooltip: 'Tùy chọn',
                    onSelected: practiceMenu,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'explain',
                        child: Text('Giải thích'),
                      ),
                      const PopupMenuItem(
                        value: 'clear',
                        child: Text('Viết lại'),
                      ),
                      PopupMenuItem(
                        value: 'save',
                        enabled:
                            strokes.isNotEmpty &&
                            (outlines.isEmpty ||
                                strokes.length == outlines.length),
                        child: const Text('Đã luyện'),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Text('Cài đặt'),
                      ),
                    ],
                  ),
              ],
            ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [paper, paper, Color(0xfff7faf9)],
          ),
        ),
        child: SafeArea(
          top: word == null,
          child: words.isEmpty
              ? Center(
                  child: error == null
                      ? const CircularProgressIndicator()
                      : Text(error!),
                )
              : word == null
              ? library()
              : practice(),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    generation++;
    animation.dispose();
    audioCompletion?.cancel();
    player?.dispose();
    tts?.stop();
    homeScroll.dispose();
    super.dispose();
  }
}

class WritingPainter extends CustomPainter {
  final List<List<Offset>> strokes, medians;
  final List<Path> outlines;
  final bool guide, animating;
  final double progress;
  final int acceptedCount;
  final List<int> acceptedIndices;
  final Map<List<Offset>, List<BrushPoint>> brushSamples;
  WritingPainter(
    this.strokes,
    this.outlines,
    this.medians,
    this.guide,
    this.progress,
    this.animating, {
    this.acceptedCount = 0,
    this.acceptedIndices = const [],
    this.brushSamples = const {},
  });
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffc4d6d3)
      ..strokeWidth = 1;
    for (final ends in [
      [Offset(0, size.height / 2), Offset(size.width, size.height / 2)],
      [Offset(size.width / 2, 0), Offset(size.width / 2, size.height)],
      [Offset.zero, Offset(size.width, size.height)],
      [Offset(size.width, 0), Offset(0, size.height)],
    ]) {
      final length = (ends[1] - ends[0]).distance;
      for (double d = 0; d < length; d += 10) {
        canvas.drawLine(
          Offset.lerp(ends[0], ends[1], d / length)!,
          Offset.lerp(ends[0], ends[1], math.min(d + 5, length) / length)!,
          grid,
        );
      }
    }
    canvas.save();
    canvas.scale(size.width / 1024, -size.height / 1024);
    canvas.translate(0, -900);
    if (guide) {
      for (final path in outlines) {
        canvas.drawPath(path, Paint()..color = const Color(0xffdce8e4));
      }
    }
    for (final index in acceptedIndices) {
      canvas.drawPath(outlines[index], Paint()..color = ink);
    }
    if ((animating || progress == 1) && medians.isNotEmpty) {
      final step = progress * medians.length;
      for (int i = 0; i < outlines.length; i++) {
        if (i < step.floor()) {
          canvas.drawPath(
            outlines[i],
            Paint()..color = const Color(0xff147d78),
          );
        } else if (i == step.floor()) {
          final line = medians[i];
          if (line.isEmpty) continue;
          final path = Path()..moveTo(line.first.dx, line.first.dy);
          for (final p in line.skip(1)) {
            path.lineTo(p.dx, p.dy);
          }
          canvas.save();
          canvas.clipPath(outlines[i]);
          for (final metric in path.computeMetrics()) {
            canvas.drawPath(
              metric.extractPath(0, metric.length * (step - i)),
              Paint()
                ..color = const Color(0xff147d78)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 140
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round,
            );
          }
          canvas.restore();
          final point =
              line[math.min(
                ((step - i) * line.length).floor(),
                line.length - 1,
              )];
          canvas.drawCircle(point, 14, Paint()..color = ink);
        }
      }
    }
    canvas.restore();
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final line in strokes.skip(acceptedCount)) {
      final samples =
          brushSamples[line] ??
          line.indexed
              .map((p) => BrushPoint(p.$2, null, p.$1 * 16000))
              .toList();
      CalligraphyBrush.paint(canvas, samples, size.width, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WritingPainter oldDelegate) => true;
}
