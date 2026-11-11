// 三国史料学习模块 · Repository 集成测试。
// 用真实随包 seed（不 mock 任何 JSON）验证：索引 / 卷目录 / 正文 /
// 知识卡片 / 正史vs演义 / 题库 的解析契约，以及题库答案可判定。
import 'package:flutter_test/flutter_test.dart';
import 'package:sgs_heroes/features/history/history_models.dart';
import 'package:sgs_heroes/features/history/history_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HistoryRepository repo;

  setUp(() {
    repo = HistoryRepository(); // 默认 BundleOnlySource，真读随包 seed
  });

  test('索引能读出 4 部书，字段与免责声明完整', () async {
    final idx = await repo.loadIndex();

    expect(idx.module, 'history');
    expect(idx.version, greaterThan(0));
    expect(idx.disclaim, isNotEmpty);
    expect(idx.books.length, 4);
    expect(idx.route, isNotEmpty);
    expect(
      idx.books.map((b) => b.id),
      containsAll(<String>['sgz', 'tongjian', 'houhanshu', 'jinshu']),
    );
    for (final b in idx.books) {
      expect(b.title, isNotEmpty);
      expect(b.author, isNotEmpty);
      expect(b.coverage, isNotEmpty);
      expect(b.catalog, isNotEmpty);
      expect(kKindLabel.containsKey(b.kind), isTrue);
    }
    // 核心/辅助分组键来自真实 rel 字段
    expect(idx.books.where((b) => b.relKey == 'core').length, 2);
    expect(idx.books.where((b) => b.relKey == 'related').length, 2);
  });

  test('卷目录 chapters 非空，part / 卷号 / 字数 / 状态可解析', () async {
    final sgz = await repo.loadBook('sgz');
    expect(sgz.title, '三国志');
    expect(sgz.intro, isNotEmpty);
    expect(sgz.chapters.length, 65);
    expect(sgz.readyCount, 65);

    final first = sgz.chapters.first;
    expect(first.id, 'sgz-001');
    expect(first.bookId, 'sgz');
    expect(first.part, '魏书');
    expect(first.partNo, 1);
    expect(first.chars, greaterThan(0));
    expect(first.isReady, isTrue);
    expect(chapterVolLabel(first), '卷一');
    expect(chapterVolLabel(first, withPart: true), '魏书 卷一');
    // 三国志按 part 分成魏/蜀/吴三组
    expect(sgz.chapters.map((c) => c.part).toSet(),
        <String>{'魏书', '蜀书', '吴书'});

    final tj = await repo.loadBook('tongjian');
    expect(tj.chapters.length, 19);
    expect(tj.chapters.every((c) => c.isReady), isTrue);
    // 其余书无 part，卷目录走单组 + 原卷号
    expect(tj.chapters.every((c) => c.part.isEmpty), isTrue);
    expect(chapterVolLabel(tj.chapters.first), isNotEmpty);
  });

  test('指定卷正文 original 非空，peizhu 可解析，无注卷不抛异常', () async {
    final withNote = await repo.loadContent('sgz-001');
    expect(withNote.id, 'sgz-001');
    expect(withNote.title, isNotEmpty);
    expect(withNote.original, isNotEmpty);
    expect(withNote.original.first, isNotEmpty);
    expect(withNote.peizhu, isNotEmpty);
    expect(withNote.peizhu.any((n) => n.text.isNotEmpty), isTrue);
    // peizhu 元素是 {text, source} 对象
    expect(withNote.peizhu.first.text, isNotEmpty);
    expect(withNote.peizhu.first.source, isNotEmpty);

    final noNote = await repo.loadContent('tongjian-019');
    expect(noNote.original, isNotEmpty);
    expect(noNote.peizhu, isEmpty); // 空列表而非解析异常
  });

  test('cards / compare / quiz 都能解析且数量 > 0', () async {
    final cards = await repo.loadCards();
    final compares = await repo.loadCompares();
    final quiz = await repo.loadQuiz();

    expect(cards.length, greaterThan(0));
    expect(compares.length, greaterThan(0));
    expect(quiz.items.length, greaterThan(0));
    expect(quiz.scopes.length, greaterThan(0));

    final card = cards.first;
    expect(card.title, isNotEmpty);
    expect(card.summary, isNotEmpty);
    expect(card.contentText, isNotEmpty);
    expect(card.reliabilityLevel, isNotEmpty);
    expect(card.quote, isNotEmpty);

    final cmp = compares.first;
    expect(cmp.historySide.text, isNotEmpty);
    expect(cmp.fictionSide.text, isNotEmpty);
    expect(cmp.verdict, isNotEmpty);
    expect(cmp.isFiction, isTrue);
    expect(cmp.relatedSgsCharacterId, isNotEmpty);
  });

  test('题库答案可判定：单选 / 多选 / 判断 / 简答', () async {
    final quiz = await repo.loadQuiz();
    QuizQuestion q(String id) => quiz.items.firstWhere((e) => e.id == id);

    final single = q('quiz-001');
    expect(single.type, 'single');
    expect(single.options.length, 4);
    expect(single.answerIndices, <int>[1]);
    expect(single.grade(const <int>[1]), isTrue);
    expect(single.grade(const <int>[0]), isFalse);
    expect(single.grade(const <int>[1, 2]), isFalse);

    final multi = q('quiz-002');
    expect(multi.type, 'multi');
    expect(multi.answerIndices, <int>[0, 1, 2, 3]);
    expect(multi.grade(const <int>[0, 1, 2, 3]), isTrue);
    expect(multi.grade(const <int>[3, 2, 1, 0]), isTrue); // 与顺序无关
    expect(multi.grade(const <int>[0, 1]), isFalse);

    final judge = q('quiz-003');
    expect(judge.type, 'judge');
    // 真实数据 answer = [false]，归一化成「错误」对应选项索引 1
    expect(judge.answerIndices, <int>[1]);
    expect(judge.grade(const <int>[1]), isTrue);
    expect(judge.grade(const <int>[0]), isFalse);

    final short = q('quiz-005');
    expect(short.type, 'short');
    expect(short.grade(const <int>[0]), isNull); // 简答题不自动判分
    expect(short.answerText, isNotEmpty);
    expect(short.referenceAnswer, isNotEmpty);
  });

  test('answer 兼容布尔 / 字符串 / 标量 / 缺省，缺字段模型不抛异常', () {
    QuizQuestion parse(Object? answer) =>
        QuizQuestion.fromJson(<String, dynamic>{
          'id': 'x',
          'type': 'single',
          'answer': answer,
        });

    expect(parse(<dynamic>[1]).answerIndices, <int>[1]);
    expect(parse(<dynamic>[false]).answerIndices, <int>[1]);
    expect(parse(<dynamic>[true]).answerIndices, <int>[0]);
    expect(parse(true).answerIndices, <int>[0]);
    expect(parse(false).answerIndices, <int>[1]);
    expect(parse('B').answerIndices, <int>[1]);
    expect(parse('正确').answerIndices, <int>[0]);
    expect(parse(<dynamic>['2', 'A', '错误']).answerIndices, <int>[0, 1, 2]);
    expect(parse(null).answerIndices, isEmpty);
    expect(parse(<dynamic>[]).answerIndices, isEmpty);

    // 整份对象缺字段时一律降级，绝不抛异常
    expect(() => HistoryIndex.fromJson(<String, dynamic>{}), returnsNormally);
    expect(() => HistoryBook.fromJson(<String, dynamic>{}), returnsNormally);
    expect(() => Chapter.fromJson(<String, dynamic>{}), returnsNormally);
    expect(
      () => ChapterContent.fromJson(<String, dynamic>{}),
      returnsNormally,
    );
    expect(
      () => KnowledgeCard.fromJson(<String, dynamic>{}),
      returnsNormally,
    );
    expect(() => CompareItem.fromJson(<String, dynamic>{}), returnsNormally);
    expect(() => QuizBank.fromJson(<String, dynamic>{}), returnsNormally);
  });

  test('懒加载并缓存：重复调用复用实例，正文按卷独立读取', () async {
    final a = await repo.loadIndex();
    final b = await repo.loadIndex();
    expect(identical(a, b), isTrue);

    final sgz1 = await repo.loadContent('sgz-001');
    final sgz2 = await repo.loadContent('sgz-002');
    expect(sgz1.id, 'sgz-001');
    expect(sgz2.id, 'sgz-002');
    expect(identical(sgz1, sgz2), isFalse); // 不是一次性全量读入
    expect(identical(sgz1, await repo.loadContent('sgz-001')), isTrue);

    repo.clearCache();
    final c = await repo.loadIndex();
    expect(identical(a, c), isFalse); // 清缓存后重新解析
  });
}
