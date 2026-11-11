// 三国史料学习模块 · 数据读取层。
// 统一走 core/sync/data_file_source.dart 的 readDataString，relPath 相对 seed 根。
// 所有分片懒加载并按 key 缓存；正文按卷单独读取，绝不一次性把 313 卷读进内存。
import 'dart:convert';

import 'package:sgs_heroes/core/sync/data_file_source.dart';

import 'history_models.dart';

class HistoryRepository {
  HistoryRepository({this.source = const BundleOnlySource()});

  final DataFileSource source;

  /// 已解析结果缓存（按逻辑 key）。
  final Map<String, Object> _cache = <String, Object>{};

  /// 进行中的加载，避免同一分片被并发重复读取。
  final Map<String, Future<Object>> _inflight = <String, Future<Object>>{};

  /// 通用懒加载：命中缓存直接返回；同一 key 并发时复用同一个 Future；
  /// 失败不写缓存、清掉 inflight，下次调用可重试。
  Future<T> _load<T extends Object>(
    String key,
    Future<T> Function() compute,
  ) async {
    final cached = _cache[key];
    if (cached is T) return cached;

    final running = _inflight[key];
    if (running != null) {
      final Object value = await running;
      return value as T;
    }

    final Future<T> future = compute();
    _inflight[key] = future;
    try {
      final T value = await future;
      _cache[key] = value;
      return value;
    } finally {
      _inflight.remove(key);
    }
  }

  /// 把相对 history/ 目录的路径（如 books/sgz.json）补成相对 seed 根的路径。
  String _historyPath(String rel) {
    final r = rel.replaceAll('\\', '/');
    if (r.isEmpty) return 'history/';
    if (r.startsWith('history/')) return r;
    return 'history/$r';
  }

  Future<T> _decode<T>(
    String relPath,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final text = await readDataString(source, relPath);
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return fromJson(Map<String, dynamic>.from(decoded));
    }
    throw FormatException('史料数据根节点应为对象：$relPath');
  }

  Future<List<T>> _decodeList<T>(
    String relPath,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      _decode<List<T>>(relPath, (Map<String, dynamic> m) {
        final raw = m[key];
        if (raw is! List) return <T>[];
        final out = <T>[];
        for (final e in raw) {
          if (e is Map) out.add(fromJson(Map<String, dynamic>.from(e)));
        }
        return out;
      });

  /// history/index.json：书籍清单、免责声明、学习路线。
  Future<HistoryIndex> loadIndex() => _load<HistoryIndex>(
        'index',
        () => _decode<HistoryIndex>('history/index.json', HistoryIndex.fromJson),
      );

  /// 卷目录：先由 index 找到该书的 catalog 路径，再按路径懒加载 `books/<id>.json`。
  Future<BookCatalog> loadBook(String bookId) => _load<BookCatalog>(
        'book:$bookId',
        () async {
          final idx = await loadIndex();
          final book = idx.books.firstWhere(
            (b) => b.id == bookId,
            orElse: () => HistoryBook(id: bookId),
          );
          final rel = book.catalog.isNotEmpty
              ? _historyPath(book.catalog)
              : _historyPath('books/$bookId.json');
          return _decode<BookCatalog>(rel, BookCatalog.fromJson);
        },
      );

  /// 单卷正文：按需读取 `history/contents/<id>.json`，逐卷缓存。
  Future<ChapterContent> loadContent(String chapterId) =>
      _load<ChapterContent>(
        'content:$chapterId',
        () => _decode<ChapterContent>(
          'history/contents/$chapterId.json',
          ChapterContent.fromJson,
        ),
      );

  /// 知识卡片。
  Future<List<KnowledgeCard>> loadCards() => _load<List<KnowledgeCard>>(
        'cards',
        () => _decodeList<KnowledgeCard>(
          'history/cards.json',
          'items',
          KnowledgeCard.fromJson,
        ),
      );

  /// 正史 vs 演义。
  Future<List<CompareItem>> loadCompares() => _load<List<CompareItem>>(
        'compares',
        () => _decodeList<CompareItem>(
          'history/compare.json',
          'items',
          CompareItem.fromJson,
        ),
      );

  /// 题库（含 scopes 与 items）。
  Future<QuizBank> loadQuiz() => _load<QuizBank>(
        'quiz',
        () => _decode<QuizBank>('history/quiz.json', QuizBank.fromJson),
      );

  /// 清空缓存，便于复用或测试隔离。进行中的加载不主动取消。
  void clearCache() {
    _cache.clear();
    _inflight.clear();
  }
}
