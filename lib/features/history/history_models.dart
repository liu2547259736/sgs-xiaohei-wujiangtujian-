// 三国史料学习模块 · 数据模型。
// 覆盖 seed/history 下 index / books / contents / cards / compare / quiz 的真实结构。
// 约定：所有 fromJson 对缺字段、异型字段一律降级取值，绝不因某个字段缺失抛异常。

// ---------- 标签字典（与主程序 history.js 保持同一口径）----------
const Map<String, String> kSrcLabel = <String, String>{
  'sanguozhi': '《三国志》正文',
  'sgz': '《三国志》正文',
  'peizhu': '裴松之注',
  'yanyi': '《三国演义》',
  'houhanshu': '《后汉书》',
  'jinshu': '《晋书》',
  'tongjian': '《资治通鉴》',
  'chenshou': '陈寿专题',
};

const Map<String, String> kKindLabel = <String, String>{
  'shishu': '纪传体史书',
  'biannian': '编年体史书',
  'xiaoshuo': '章回小说',
};

const Map<String, String> kDiffLabel = <String, String>{
  'beginner': '入门',
  'intermediate': '进阶',
  'advanced': '深度',
};

const Map<String, String> kQTypeLabel = <String, String>{
  'single': '单选',
  'multi': '多选',
  'judge': '判断',
  'short': '简答',
};

String srcLabel(String? key) => key == null ? '' : (kSrcLabel[key] ?? key);
String kindLabel(String? key) => key == null ? '' : (kKindLabel[key] ?? key);
String diffLabel(String? key) => key == null ? '' : (kDiffLabel[key] ?? key);
String qTypeLabel(String? key) => key == null ? '' : (kQTypeLabel[key] ?? key);

// ---------- 容错取值 ----------
String _s(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

bool _b(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

Map<String, dynamic> _m(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _ml(Object? v) {
  if (v is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final e in v) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}

/// list 字段兼容：正常是 List，也接受单个字符串（如某个 id 被写成标量）。
List<String> _sl(Object? v) {
  if (v is List) {
    return v.map(_s).where((e) => e.isNotEmpty).toList(growable: false);
  }
  if (v is String && v.trim().isNotEmpty) return <String>[v.trim()];
  return const <String>[];
}

// ---------- index.json ----------
class HistoryBook {
  const HistoryBook({
    this.id = '',
    this.title = '',
    this.author = '',
    this.kind = '',
    this.coverage = '',
    this.catalog = '',
    this.isCore = false,
    this.accent = '',
    this.rel = '',
  });

  factory HistoryBook.fromJson(Map<String, dynamic> json) => HistoryBook(
        id: _s(json['id']),
        title: _s(json['title']),
        author: _s(json['author']),
        kind: _s(json['kind']),
        coverage: _s(json['coverage']),
        catalog: _s(json['catalog']),
        isCore: _b(json['is_core']),
        accent: _s(json['accent']),
        rel: _s(json['rel']),
      );

  final String id;
  final String title;
  final String author;
  final String kind;
  final String coverage;
  final String catalog;
  final bool isCore;
  final String accent;
  final String rel;

  /// 书库分组：优先用 rel，缺省时按 is_core 推导（对齐主程序 renderShelf）。
  String get relKey => rel.isNotEmpty ? rel : (isCore ? 'core' : 'related');
}

/// 学习路线条目。数据被解析保留，但本次迁移不渲染该板块。
class HistoryRouteStep {
  const HistoryRouteStep({
    this.id = '',
    this.title = '',
    this.difficulty = '',
    this.priority = 0,
    this.summary = '',
    this.cardIds = const <String>[],
    this.bookRefs = const <Map<String, dynamic>>[],
    this.estimatedMin = 0,
  });

  factory HistoryRouteStep.fromJson(Map<String, dynamic> json) =>
      HistoryRouteStep(
        id: _s(json['id']),
        title: _s(json['title']),
        difficulty: _s(json['difficulty']),
        priority: _i(json['priority']),
        summary: _s(json['summary']),
        cardIds: _sl(json['card_ids']),
        bookRefs: _ml(json['book_refs']),
        estimatedMin: _i(json['estimated_min']),
      );

  final String id;
  final String title;
  final String difficulty;
  final int priority;
  final String summary;
  final List<String> cardIds;
  final List<Map<String, dynamic>> bookRefs;
  final int estimatedMin;
}

class HistoryIndex {
  const HistoryIndex({
    this.module = '',
    this.dataType = '',
    this.version = 0,
    this.disclaim = '',
    this.books = const <HistoryBook>[],
    this.route = const <HistoryRouteStep>[],
  });

  factory HistoryIndex.fromJson(Map<String, dynamic> json) => HistoryIndex(
        module: _s(json['module']),
        dataType: _s(json['data_type']),
        version: _i(json['version']),
        disclaim: _s(json['disclaim']),
        books: _ml(json['books'])
            .map(HistoryBook.fromJson)
            .toList(growable: false),
        route: _ml(json['route'])
            .map(HistoryRouteStep.fromJson)
            .toList(growable: false),
      );

  final String module;
  final String dataType;
  final int version;
  final String disclaim;
  final List<HistoryBook> books;
  final List<HistoryRouteStep> route;
}

// ---------- books/<id>.json ----------
class Chapter {
  const Chapter({
    this.id = '',
    this.bookId = '',
    this.globalNo = 0,
    this.part = '',
    this.partNo = 0,
    this.volNo = '',
    this.title = '',
    this.status = '',
    this.sourceType = '',
    this.sourceNote = '',
    this.chars = 0,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        id: _s(json['id']),
        bookId: _s(json['book_id']),
        globalNo: _i(json['global_no']),
        part: _s(json['part']),
        partNo: _i(json['part_no']),
        volNo: _s(json['vol_no']),
        title: _s(json['title']),
        status: _s(json['status']),
        sourceType: _s(json['source_type']),
        sourceNote: _s(json['source_note']),
        chars: _i(json['chars']),
      );

  final String id;
  final String bookId;
  final int globalNo;
  final String part;
  final int partNo;
  final String volNo;
  final String title;
  final String status;
  final String sourceType;
  final String sourceNote;
  final int chars;

  bool get isReady => status == 'ready';
}

const List<String> _cnNumbers = <String>[
  '一', '二', '三', '四', '五', '六', '七', '八', '九', '十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '二十一', '二十二', '二十三', '二十四', '二十五', '二十六', '二十七',
  '二十八', '二十九', '三十',
];

/// 卷/篇标签：三国志用「卷X」并带分卷书名，其余书用原卷号或「第N卷」。
/// 对齐主程序 history.js 的 volLabel / volLabelOf。
String chapterVolLabel(Chapter c, {bool withPart = false}) {
  if (c.part.isNotEmpty && c.partNo > 0 && c.partNo <= _cnNumbers.length) {
    final vol = '卷${_cnNumbers[c.partNo - 1]}';
    return withPart ? '${c.part} $vol' : vol;
  }
  if (c.volNo.isNotEmpty) return c.volNo;
  return '第${c.globalNo}卷';
}

class BookCatalog {
  const BookCatalog({
    this.id = '',
    this.title = '',
    this.author = '',
    this.kind = '',
    this.isCore = false,
    this.intro = '',
    this.chapters = const <Chapter>[],
  });

  factory BookCatalog.fromJson(Map<String, dynamic> json) => BookCatalog(
        id: _s(json['id']),
        title: _s(json['title']),
        author: _s(json['author']),
        kind: _s(json['kind']),
        isCore: _b(json['is_core']),
        intro: _s(json['intro']),
        chapters: _ml(json['chapters'])
            .map(Chapter.fromJson)
            .toList(growable: false),
      );

  final String id;
  final String title;
  final String author;
  final String kind;
  final bool isCore;
  final String intro;
  final List<Chapter> chapters;

  int get readyCount => chapters.where((c) => c.isReady).length;
}

// ---------- contents/<id>.json ----------
/// 裴松之注 / 异说条目。真实数据是 {text, source} 对象；兼容纯字符串写法。
class PeizhuNote {
  const PeizhuNote({this.text = '', this.source = ''});

  factory PeizhuNote.fromJson(Object? raw) {
    if (raw is String) return PeizhuNote(text: raw);
    final m = _m(raw);
    return PeizhuNote(text: _s(m['text']), source: _s(m['source']));
  }

  final String text;
  final String source;
}

class ChapterContent {
  const ChapterContent({
    this.id = '',
    this.bookId = '',
    this.chapterId = '',
    this.part = '',
    this.volNo = '',
    this.title = '',
    this.original = const <String>[],
    this.peizhu = const <PeizhuNote>[],
  });

  factory ChapterContent.fromJson(Map<String, dynamic> json) {
    final rawPz = json['peizhu'];
    return ChapterContent(
      id: _s(json['id']),
      bookId: _s(json['book_id']),
      chapterId: _s(json['chapter_id']),
      part: _s(json['part']),
      volNo: _s(json['vol_no']),
      title: _s(json['title']),
      original: _sl(json['original']),
      peizhu: rawPz is List
          ? rawPz.map(PeizhuNote.fromJson).toList(growable: false)
          : const <PeizhuNote>[],
    );
  }

  final String id;
  final String bookId;
  final String chapterId;
  final String part;
  final String volNo;
  final String title;
  final List<String> original;
  final List<PeizhuNote> peizhu;
}

// ---------- cards.json ----------
class KnowledgeCard {
  const KnowledgeCard({
    this.id = '',
    this.title = '',
    this.category = '',
    this.dataType = '',
    this.sourceType = '',
    this.reliabilityLevel = '',
    this.difficulty = '',
    this.priority = 0,
    this.summary = '',
    this.contentText = '',
    this.quote = '',
    this.quoteSource = '',
    this.reference = '',
    this.relatedIds = const <String>[],
    this.relatedSgsCharacterId = const <String>[],
    this.tags = const <String>[],
    this.isFiction = false,
    this.pitfall = '',
  });

  factory KnowledgeCard.fromJson(Map<String, dynamic> json) => KnowledgeCard(
        id: _s(json['id']),
        title: _s(json['title']),
        category: _s(json['category']),
        dataType: _s(json['data_type']),
        sourceType: _s(json['source_type']),
        reliabilityLevel: _s(json['reliability_level']),
        difficulty: _s(json['difficulty']),
        priority: _i(json['priority']),
        summary: _s(json['summary']),
        contentText: _s(json['content_text']),
        quote: _s(json['quote']),
        quoteSource: _s(json['quote_source']),
        reference: _s(json['reference']),
        relatedIds: _sl(json['related_ids']),
        relatedSgsCharacterId: _sl(json['related_sgs_character_id']),
        tags: _sl(json['tags']),
        isFiction: _b(json['is_fiction']),
        pitfall: _s(json['pitfall']),
      );

  final String id;
  final String title;
  final String category;
  final String dataType;
  final String sourceType;
  final String reliabilityLevel;
  final String difficulty;
  final int priority;
  final String summary;
  final String contentText;
  final String quote;
  final String quoteSource;
  final String reference;
  final List<String> relatedIds;
  final List<String> relatedSgsCharacterId;
  final List<String> tags;
  final bool isFiction;
  final String pitfall;
}

// ---------- compare.json ----------
/// fiction_side 真实数据里没有 source_type，故缺省为空串。
class CompareSide {
  const CompareSide({
    this.sourceType = '',
    this.text = '',
    this.reference = '',
  });

  factory CompareSide.fromJson(Map<String, dynamic> json) => CompareSide(
        sourceType: _s(json['source_type']),
        text: _s(json['text']),
        reference: _s(json['reference']),
      );

  final String sourceType;
  final String text;
  final String reference;
}

class CompareItem {
  const CompareItem({
    this.id = '',
    this.title = '',
    this.difficulty = '',
    this.priority = 0,
    this.historySide = const CompareSide(),
    this.fictionSide = const CompareSide(),
    this.relatedIds = const <String>[],
    this.relatedSgsCharacterId = const <String>[],
    this.isFiction = false,
    this.verdict = '',
  });

  factory CompareItem.fromJson(Map<String, dynamic> json) => CompareItem(
        id: _s(json['id']),
        title: _s(json['title']),
        difficulty: _s(json['difficulty']),
        priority: _i(json['priority']),
        historySide: CompareSide.fromJson(_m(json['history_side'])),
        fictionSide: CompareSide.fromJson(_m(json['fiction_side'])),
        relatedIds: _sl(json['related_ids']),
        relatedSgsCharacterId: _sl(json['related_sgs_character_id']),
        isFiction: _b(json['is_fiction']),
        verdict: _s(json['verdict']),
      );

  final String id;
  final String title;
  final String difficulty;
  final int priority;
  final CompareSide historySide;
  final CompareSide fictionSide;
  final List<String> relatedIds;
  final List<String> relatedSgsCharacterId;
  final bool isFiction;
  final String verdict;
}

// ---------- quiz.json ----------
class QuizScope {
  const QuizScope({this.id = '', this.label = '', this.source = ''});

  factory QuizScope.fromJson(Map<String, dynamic> json) => QuizScope(
        id: _s(json['id']),
        label: _s(json['label']),
        source: _s(json['source']),
      );

  final String id;
  final String label;
  final String source;
}

/// 把 answer 的多种写法归一化为「正确选项索引集合」。
/// 兼容：索引数组 [1] / [0,1,2]、布尔数组 [false]（判断题）、
/// 以及整体就是 bool / int / 字符串、字符串元素（"B" / "正确" / "2"）。
int? _answerToIndex(Object? v) {
  if (v is bool) return v ? 0 : 1; // 判断题：正确=0，错误=1
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null) return n;
    final lower = s.toLowerCase();
    const truthy = <String>{
      'true', 't', 'yes', 'y', '正确', '对', '是', '√',
    };
    const falsy = <String>{
      'false', 'f', 'no', 'n', '错误', '错', '否', '×', 'x',
    };
    if (truthy.contains(lower)) return 0;
    if (falsy.contains(lower)) return 1;
    if (s.length == 1) {
      final code = s.toUpperCase().codeUnitAt(0);
      if (code >= 0x41 && code <= 0x5A) return code - 0x41; // A/B/C -> 0/1/2
    }
  }
  return null;
}

List<int> _parseAnswerIndices(Object? raw) {
  final items = <Object?>[];
  if (raw is List) {
    items.addAll(raw);
  } else if (raw != null) {
    items.add(raw);
  }
  final set = <int>{};
  for (final v in items) {
    final idx = _answerToIndex(v);
    if (idx != null) set.add(idx);
  }
  final list = set.toList()..sort();
  return list;
}

class QuizQuestion {
  const QuizQuestion({
    this.id = '',
    this.scopeId = '',
    this.type = '',
    this.difficulty = '',
    this.stem = '',
    this.options = const <String>[],
    this.answerIndices = const <int>[],
    this.explanation = '',
    this.examSource = '',
    this.answerText = '',
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        id: _s(json['id']),
        scopeId: _s(json['scope_id']),
        type: _s(json['type']),
        difficulty: _s(json['difficulty']),
        stem: _s(json['stem']),
        options: _sl(json['options']),
        answerIndices: _parseAnswerIndices(json['answer']),
        explanation: _s(json['explanation']),
        examSource: _s(json['exam_source']),
        answerText: _s(json['answer_text']),
      );

  final String id;
  final String scopeId;
  final String type;
  final String difficulty;
  final String stem;
  final List<String> options;
  final List<int> answerIndices;
  final String explanation;
  final String examSource;
  final String answerText;

  bool get isSingle => type == 'single';
  bool get isMulti => type == 'multi';
  bool get isJudge => type == 'judge';
  bool get isShort => type == 'short';

  /// 客观题判分：选项索引集合相等即正确；简答题返回 null（不自动判分）。
  bool? grade(List<int> picked) {
    if (isShort) return null;
    final correct = answerIndices.toSet();
    final selected = picked.toSet();
    if (correct.length != selected.length) return false;
    return correct.every(selected.contains);
  }

  /// 简答题参考答案：优先 answer_text，退化到 explanation。
  String get referenceAnswer =>
      answerText.isNotEmpty ? answerText : explanation;
}

class QuizBank {
  const QuizBank({
    this.scopes = const <QuizScope>[],
    this.items = const <QuizQuestion>[],
  });

  factory QuizBank.fromJson(Map<String, dynamic> json) => QuizBank(
        scopes: _ml(json['scopes'])
            .map(QuizScope.fromJson)
            .toList(growable: false),
        items: _ml(json['items'])
            .map(QuizQuestion.fromJson)
            .toList(growable: false),
      );

  final List<QuizScope> scopes;
  final List<QuizQuestion> items;
}
