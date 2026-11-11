// 三国史料学习模块 · 页面。
// 形态对齐主程序 history.js：书库(默认) → 卷目录 → 阅读器；
// 知识卡片 / 正史vs演义 / 自测题库 为并列板块。
// 底部 NavigationBar 切板块，书库内部用视图栈逐层深入，页面内返回条回上一级。
// 仅依赖 Flutter SDK，数据全部经 HistoryRepository 读随包 seed。
import 'package:flutter/material.dart';

import 'history_models.dart';
import 'history_repository.dart';

enum _Status { loading, ready, error }

enum _ShelfView { shelf, catalog, reader }

/// 三国史料学习页，自带 Scaffold / AppBar。
/// [repository] 不传时使用默认的 BundleOnlySource（纯随包 seed）。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.repository});

  final HistoryRepository? repository;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryRepository _repo;

  _Status _status = _Status.loading;
  String? _bootError;

  // index / cards / compare / quiz 与主程序 init() 一样一次性并行加载。
  HistoryIndex? _index;
  List<KnowledgeCard>? _cards;
  List<CompareItem>? _compares;
  QuizBank? _quiz;

  int _tab = 0; // 0 书库 / 1 知识卡片 / 2 正史vs演义 / 3 自测题库
  String _difficulty = 'all';

  // 书库内部视图栈
  _ShelfView _view = _ShelfView.shelf;
  String _openBookId = '';
  BookCatalog? _catalog;
  List<Chapter> _readyChapters = const <Chapter>[];
  int _readerIndex = 0;
  ChapterContent? _content;
  bool _busy = false;
  String? _subError;
  int _catalogReq = 0;
  int _contentReq = 0;

  // 题库作答状态
  String _scope = 'all';
  bool _quizStarted = false;
  final Map<String, List<int>> _picked = <String, List<int>>{};
  final Map<String, bool?> _graded = <String, bool?>{};
  final Set<String> _submitted = <String>{};
  final Map<String, TextEditingController> _shortControllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? HistoryRepository();
    _boot();
  }

  @override
  void dispose() {
    _disposeShortControllers();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _status = _Status.loading;
      _bootError = null;
    });
    try {
      final futures = <Future<Object>>[
        _repo.loadIndex(),
        _repo.loadCards(),
        _repo.loadCompares(),
        _repo.loadQuiz(),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _index = results[0] as HistoryIndex;
        _cards = results[1] as List<KnowledgeCard>;
        _compares = results[2] as List<CompareItem>;
        _quiz = results[3] as QuizBank;
        _status = _Status.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = '$e';
        _status = _Status.error;
      });
    }
  }

  // ---------------- 顶层骨架 ----------------

  String _title() {
    if (_tab == 1) return '知识卡片';
    if (_tab == 2) return '正史 vs 演义';
    if (_tab == 3) return '自测题库';
    if (_view == _ShelfView.catalog) {
      final t = _catalog?.title ?? '';
      return t.isNotEmpty ? t : '卷目录';
    }
    if (_view == _ShelfView.reader &&
        _readyChapters.isNotEmpty &&
        _readerIndex < _readyChapters.length) {
      return chapterVolLabel(_readyChapters[_readerIndex], withPart: true);
    }
    return '三国史料学习';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        centerTitle: false,
      ),
      body: _buildBody(),
      bottomNavigationBar: _status == _Status.ready ? _navBar() : null,
    );
  }

  Widget _buildBody() => switch (_status) {
        _Status.loading => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('正在加载随包史料数据…'),
              ],
            ),
          ),
        _Status.error => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 12),
                  Text('史料数据加载失败：${_bootError ?? ''}'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _boot, child: const Text('重试')),
                ],
              ),
            ),
          ),
        _Status.ready => IndexedStack(
            index: _tab,
            children: <Widget>[
              _buildShelfSection(),
              _buildCards(),
              _buildCompare(),
              _buildQuiz(),
            ],
          ),
      };

  Widget _navBar() => NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (int i) => setState(() => _tab = i),
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书库',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: '知识卡片',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows_outlined),
            selectedIcon: Icon(Icons.compare_arrows),
            label: '正史vs演义',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '自测题库',
          ),
        ],
      );

  // ---------------- 通用小组件 ----------------

  Widget _backRow(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: Text(label),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      );

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: fg)),
      );

  bool _matchDiff(String d) => _difficulty == 'all' || d == _difficulty;

  Widget _difficultyBar() {
    const diffs = <String, String>{
      'all': '全部',
      'beginner': '入门',
      'intermediate': '进阶',
      'advanced': '深度',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 8,
        children: diffs.entries
            .map((e) => ChoiceChip(
                  label: Text(e.value),
                  selected: _difficulty == e.key,
                  onSelected: (_) => setState(() => _difficulty = e.key),
                  visualDensity: VisualDensity.compact,
                ))
            .toList(growable: false),
      ),
    );
  }

  Widget _disclaimer() {
    final d = _index?.disclaim ?? '';
    if (d.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        d,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ---------------- ⓪ 书库 → 卷目录 → 阅读器 ----------------

  Widget _buildShelfSection() => switch (_view) {
        _ShelfView.shelf => _buildShelf(),
        _ShelfView.catalog => _buildCatalog(),
        _ShelfView.reader => _buildReader(),
      };

  Widget _buildShelf() {
    final idx = _index;
    if (idx == null) return const Center(child: CircularProgressIndicator());
    const groups = <Map<String, String>>[
      <String, String>{
        'key': 'core',
        'label': '三国直接史料',
        'hint': '记载三国本身，可逐卷通读',
      },
      <String, String>{
        'key': 'related',
        'label': '汉末 / 西晋背景',
        'hint': '三国人物的前后时代，含汉末群雄与司马氏',
      },
    ];
    final children = <Widget>[];
    for (final g in groups) {
      final items = idx.books
          .where((b) => b.relKey == g['key'])
          .toList(growable: false);
      if (items.isEmpty) continue;
      children.add(_shelfGroupHeader(g['label'] ?? '', g['hint'] ?? ''));
      for (final b in items) {
        children.add(_bookCard(b));
      }
    }
    children.add(_disclaimer());
    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  Widget _shelfGroupHeader(String label, String hint) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookCard(HistoryBook b) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: b.catalog.isEmpty ? null : () => _openBook(b.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      b.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${b.author} · ${kindLabel(b.kind)}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      b.coverage,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _tag(
                      b.isCore ? '核心必读' : '辅助史料',
                      b.isCore ? cs.primaryContainer : cs.surfaceContainerHighest,
                      b.isCore ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              if (b.catalog.isNotEmpty)
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBook(String id) async {
    final req = ++_catalogReq;
    setState(() {
      _view = _ShelfView.catalog;
      _openBookId = id;
      _catalog = null;
      _readyChapters = const <Chapter>[];
      _subError = null;
      _busy = true;
    });
    try {
      final cat = await _repo.loadBook(id);
      if (!mounted || req != _catalogReq) return;
      setState(() {
        _catalog = cat;
        _readyChapters =
            cat.chapters.where((c) => c.isReady).toList(growable: false);
        _busy = false;
      });
    } catch (e) {
      if (!mounted || req != _catalogReq) return;
      setState(() {
        _subError = '目录加载失败：$e';
        _busy = false;
      });
    }
  }

  void _showShelf() {
    setState(() {
      _view = _ShelfView.shelf;
      _busy = false;
      _subError = null;
    });
  }

  void _showCatalog() {
    setState(() {
      _view = _ShelfView.catalog;
      _content = null;
      _busy = false;
      _subError = null;
    });
  }

  Widget _buildCatalog() {
    final children = <Widget>[_backRow('返回书库', _showShelf)];
    if (_busy) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
      return ListView(children: children);
    }
    if (_subError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text(_subError!)),
        ),
      );
      return ListView(children: children);
    }
    final cat = _catalog;
    if (cat == null) {
      children.add(const Center(child: Text('目录暂无数据')));
      return ListView(children: children);
    }

    children.add(_catalogHeader(cat));
    final groups = <String>[];
    for (final c in cat.chapters) {
      if (!groups.contains(c.part)) groups.add(c.part);
    }
    if (groups.length <= 1) {
      children.addAll(cat.chapters.map(_chapterRow));
    } else {
      for (final g in groups) {
        final items = cat.chapters
            .where((c) => c.part == g)
            .toList(growable: false);
        children.add(_catalogGroupHeader(g, items.length));
        children.addAll(items.map(_chapterRow));
      }
    }
    children.add(_disclaimer());
    return ListView(padding: const EdgeInsets.all(12), children: children);
  }

  Widget _catalogHeader(BookCatalog cat) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              cat.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(cat.author, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              cat.intro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '共 ${cat.chapters.length} 篇 · 已录入 ${cat.readyCount} 篇',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogGroupHeader(String part, int count) {
    final label = part.isEmpty
        ? '目录'
        : (part.endsWith('书') ? '$part · $count卷' : part);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _chapterRow(Chapter c) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        enabled: c.isReady,
        onTap: c.isReady ? () => _openChapter(c.id) : null,
        leading: SizedBox(
          width: 76,
          child: Text(
            chapterVolLabel(c),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
        ),
        title: Text(c.title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          '${c.chars} 字',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
        trailing: c.isReady
            ? _tag('已录入', cs.primaryContainer, cs.onPrimaryContainer)
            : _tag('待录入', cs.surfaceContainerHighest, cs.onSurfaceVariant),
      ),
    );
  }

  void _openChapter(String id) {
    final idx = _readyChapters.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    setState(() {
      _view = _ShelfView.reader;
      _readerIndex = idx;
      _content = null;
      _subError = null;
      _busy = true;
    });
    _loadReaderContent();
  }

  void _gotoChapter(int delta) {
    final next = _readerIndex + delta;
    if (next < 0 || next >= _readyChapters.length) return;
    setState(() {
      _readerIndex = next;
      _content = null;
      _subError = null;
      _busy = true;
    });
    _loadReaderContent();
  }

  Future<void> _loadReaderContent() async {
    final req = ++_contentReq;
    final id = _readyChapters[_readerIndex].id;
    try {
      final content = await _repo.loadContent(id);
      if (!mounted || req != _contentReq) return;
      setState(() {
        _content = content;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || req != _contentReq) return;
      setState(() {
        _subError = '本卷内容加载失败：$e';
        _busy = false;
      });
    }
  }

  Widget _buildReader() {
    final children = <Widget>[_backRow('返回目录', _showCatalog)];
    if (_readyChapters.isEmpty || _readerIndex >= _readyChapters.length) {
      children.add(
        const Expanded(child: Center(child: Text('暂无可阅读的卷'))),
      );
      return Column(children: children);
    }
    children.add(Expanded(child: _readerBody(_readyChapters[_readerIndex])));
    return Column(children: children);
  }

  Widget _readerBody(Chapter ch) {
    if (_busy) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正文加载中…'),
          ],
        ),
      );
    }
    if (_subError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_subError!, textAlign: TextAlign.center),
        ),
      );
    }
    final content = _content;
    if (content == null) return const Center(child: Text('暂无正文'));

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(child: _readerHeader(ch, content)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext ctx, int i) => _originalParagraph(content.original[i]),
            childCount: content.original.length,
          ),
        ),
        if (content.peizhu.isNotEmpty)
          SliverToBoxAdapter(child: _peizhuBlock(content.peizhu)),
        SliverToBoxAdapter(child: _readerNav()),
      ],
    );
  }

  Widget _readerHeader(Chapter ch, ChapterContent content) {
    final cs = Theme.of(context).colorScheme;
    final bookTitle = _catalog?.title ?? _openBookId;
    final vol = chapterVolLabel(ch, withPart: true);
    final disclaim = _index?.disclaim ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            content.title.isNotEmpty ? content.title : ch.title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            '$bookTitle · $vol · ${srcLabel(ch.sourceType)}',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
          if (ch.sourceNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              ch.sourceNote,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
          if (disclaim.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '免责声明：$disclaim',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            '原文',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _originalParagraph(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: SelectableText(
          text,
          style: TextStyle(
            fontSize: 17,
            height: 1.9,
            letterSpacing: 0.2,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

  Widget _peizhuBlock(List<PeizhuNote> notes) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          title: Text('裴松之注 / 异说（${notes.length} 条）'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: notes
              .map((n) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SelectableText(
                          n.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.7,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        if (n.source.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          Text(
                            '—— ${n.source}',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _readerNav() {
    final cs = Theme.of(context).colorScheme;
    final total = _readyChapters.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _readerIndex > 0 ? () => _gotoChapter(-1) : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一卷'),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_readerIndex + 1} / $total',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  _readerIndex < total - 1 ? () => _gotoChapter(1) : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一卷'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- ① 知识卡片 ----------------

  Widget _buildCards() {
    final list = (_cards ?? const <KnowledgeCard>[])
        .where((c) => _matchDiff(c.difficulty))
        .toList(growable: false);
    return Column(
      children: <Widget>[
        _backRow('返回书库', () => setState(() => _tab = 0)),
        _difficultyBar(),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('当前难度暂无卡片'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (BuildContext ctx, int i) => _cardTile(list[i]),
                ),
        ),
      ],
    );
  }

  Widget _cardBadges(KnowledgeCard c) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: <Widget>[
        if (c.difficulty.isNotEmpty)
          _tag(diffLabel(c.difficulty), cs.primaryContainer, cs.onPrimaryContainer),
        if (c.sourceType.isNotEmpty)
          _tag(srcLabel(c.sourceType), cs.surfaceContainerHighest, cs.onSurfaceVariant),
        if (c.reliabilityLevel.isNotEmpty)
          _tag('可信度 ${c.reliabilityLevel}', cs.tertiaryContainer, cs.onTertiaryContainer),
        if (c.isFiction)
          _tag('《三国演义》文学虚构，正史无记载', cs.errorContainer, cs.onErrorContainer),
        if (c.relatedSgsCharacterId.isNotEmpty)
          _tag(
            '关联武将：${c.relatedSgsCharacterId.join('、')}',
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _cardTile(KnowledgeCard c) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showCardDetail(c),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _cardBadges(c),
                const SizedBox(height: 8),
                Text(c.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  c.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );

  void _showCardDetail(KnowledgeCard c) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (BuildContext ctx, ScrollController scrollController) =>
              ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: <Widget>[
              _cardBadges(c),
              const SizedBox(height: 12),
              Text(c.title, style: Theme.of(ctx).textTheme.headlineSmall),
              if (c.summary.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  c.summary,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SelectableText(
                c.contentText,
                style: TextStyle(fontSize: 15, height: 1.7, color: cs.onSurface),
              ),
              if (c.quote.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SelectableText(
                        '「${c.quote}」',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (c.quoteSource.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '—— ${c.quoteSource}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (c.pitfall.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '易错点：${c.pitfall}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: cs.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '出处：${c.reference.isEmpty ? '—' : c.reference} · 可信度 ${c.reliabilityLevel.isEmpty ? '—' : c.reliabilityLevel}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- ② 正史 vs 演义 ----------------

  Widget _buildCompare() {
    final cs = Theme.of(context).colorScheme;
    final list = (_compares ?? const <CompareItem>[])
        .where((c) => _matchDiff(c.difficulty))
        .toList(growable: false)
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return Column(
      children: <Widget>[
        _backRow('返回书库', () => setState(() => _tab = 0)),
        _difficultyBar(),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('当前难度暂无对照内容'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (BuildContext ctx, int i) =>
                      _compareCard(list[i], cs),
                ),
        ),
      ],
    );
  }

  Widget _compareBadges(CompareItem c) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: <Widget>[
        if (c.difficulty.isNotEmpty)
          _tag(diffLabel(c.difficulty), cs.primaryContainer, cs.onPrimaryContainer),
        if (c.isFiction)
          _tag('《三国演义》文学虚构，正史无记载', cs.errorContainer, cs.onErrorContainer),
        if (c.relatedSgsCharacterId.isNotEmpty)
          _tag(
            '关联武将：${c.relatedSgsCharacterId.join('、')}',
            cs.surfaceContainerHighest,
            cs.onSurfaceVariant,
          ),
      ],
    );
  }

  Widget _compareSide(
    String label,
    CompareSide side,
    Color bg,
    Color fg,
    Color subtle,
  ) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              side.sourceType.isEmpty ? label : '$label · ${srcLabel(side.sourceType)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: fg),
            ),
            const SizedBox(height: 6),
            SelectableText(
              side.text,
              style: TextStyle(fontSize: 14, height: 1.6, color: fg),
            ),
            if (side.reference.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(side.reference, style: TextStyle(fontSize: 11, color: subtle)),
            ],
          ],
        ),
      );

  Widget _compareCard(CompareItem c, ColorScheme cs) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _compareBadges(c),
              const SizedBox(height: 8),
              Text(c.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              _compareSide(
                '正史',
                c.historySide,
                cs.primaryContainer,
                cs.onPrimaryContainer,
                cs.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              _compareSide(
                '演义',
                c.fictionSide,
                cs.tertiaryContainer,
                cs.onTertiaryContainer,
                cs.onSurfaceVariant,
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '结论：${c.verdict}',
                  style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurface),
                ),
              ),
            ],
          ),
        ),
      );

  // ---------------- ③ 自测题库 ----------------

  TextEditingController _shortController(String id) =>
      _shortControllers.putIfAbsent(id, () => TextEditingController());

  void _disposeShortControllers() {
    for (final c in _shortControllers.values) {
      c.dispose();
    }
    _shortControllers.clear();
  }

  void _resetQuiz() {
    _picked.clear();
    _graded.clear();
    _submitted.clear();
    _disposeShortControllers();
  }

  void _setScope(String id) {
    setState(() {
      _scope = id;
      _quizStarted = false;
      _resetQuiz();
    });
  }

  void _startQuiz() {
    setState(() {
      _resetQuiz();
      _quizStarted = true;
    });
  }

  Widget _buildQuiz() {
    final cs = Theme.of(context).colorScheme;
    final quiz = _quiz;
    if (quiz == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final qs = quiz.items
        .where((q) => _scope == 'all' || q.scopeId == _scope)
        .toList(growable: false);
    final scopeChips = <Widget>[
      ChoiceChip(
        label: const Text('全部单元'),
        selected: _scope == 'all',
        onSelected: (_) => _setScope('all'),
        visualDensity: VisualDensity.compact,
      ),
      ...quiz.scopes.map((s) => ChoiceChip(
            label: Text(s.label),
            selected: _scope == s.id,
            onSelected: (_) => _setScope(s.id),
            visualDensity: VisualDensity.compact,
          )),
    ];
    return Column(
      children: <Widget>[
        _backRow('返回书库', () => setState(() => _tab = 0)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(spacing: 8, children: scopeChips),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: <Widget>[
              FilledButton(
                onPressed: _startQuiz,
                child: const Text('开始答题'),
              ),
              const SizedBox(width: 12),
              Text(
                '共 ${qs.length} 题',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: !_quizStarted
              ? const Center(child: Text('选择单元后点击「开始答题」'))
              : qs.isEmpty
                  ? const Center(child: Text('该单元暂无题目'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: qs.length + 1,
                      itemBuilder: (BuildContext ctx, int i) => i == qs.length
                          ? _quizScore(cs, qs.length)
                          : _quizCard(qs[i], i, cs),
                    ),
        ),
      ],
    );
  }

  void _toggleOption(QuizQuestion q, int oi) {
    setState(() {
      if (q.isMulti) {
        final cur = List<int>.from(_picked[q.id] ?? const <int>[]);
        if (cur.contains(oi)) {
          cur.remove(oi);
        } else {
          cur.add(oi);
        }
        _picked[q.id] = cur;
      } else {
        _picked[q.id] = <int>[oi];
      }
    });
  }

  void _submit(QuizQuestion q) {
    if (q.isShort) {
      setState(() {
        _submitted.add(q.id);
        _graded[q.id] = null;
      });
      return;
    }
    final picked = _picked[q.id] ?? const <int>[];
    if (picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先作答')),
      );
      return;
    }
    setState(() {
      _submitted.add(q.id);
      _graded[q.id] = q.grade(picked);
    });
  }

  Widget _optionTile(
    QuizQuestion q,
    int oi,
    String label,
    List<int> picked,
    bool done,
    ColorScheme cs,
  ) {
    final selected = picked.contains(oi);
    Color bg = cs.surfaceContainerHighest;
    Color fg = cs.onSurface;
    if (done) {
      if (q.answerIndices.contains(oi)) {
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      } else if (selected) {
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
      }
    } else if (selected) {
      bg = cs.secondaryContainer;
      fg = cs.onSecondaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: done ? null : () => _toggleOption(q, oi),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? (q.isMulti
                        ? Icons.check_box
                        : Icons.radio_button_checked)
                    : (q.isMulti
                        ? Icons.check_box_outline_blank
                        : Icons.radio_button_unchecked),
                size: 18,
                color: fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 14, color: fg)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortInput(QuizQuestion q) => TextField(
        controller: _shortController(q.id),
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: '输入你的答案…',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );

  Widget _resultBlock(QuizQuestion q, bool? graded, ColorScheme cs) {
    final String head;
    final Color bg;
    final Color fg;
    if (q.isShort) {
      head = '参考答案（简答题请对照自评，不自动判分）';
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurface;
    } else if (graded == true) {
      head = '回答正确 ✓';
      bg = cs.primaryContainer;
      fg = cs.onPrimaryContainer;
    } else {
      head = '回答错误 ✗';
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
    }
    final body = q.isShort ? q.referenceAnswer : q.explanation;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(head, style: TextStyle(fontWeight: FontWeight.bold, color: fg)),
          const SizedBox(height: 6),
          SelectableText(
            body,
            style: TextStyle(fontSize: 13, height: 1.6, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _quizCard(QuizQuestion q, int index, ColorScheme cs) {
    final theme = Theme.of(context);
    final picked = _picked[q.id] ?? const <int>[];
    final done = _submitted.contains(q.id);
    final options =
        q.isJudge ? const <String>['正确', '错误'] : q.options;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${qTypeLabel(q.type)} · ${diffLabel(q.difficulty)} · 考点：${q.examSource}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text('${index + 1}. ${q.stem}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (q.isShort)
              _shortInput(q)
            else
              ...options.asMap().entries.map(
                    (e) => _optionTile(
                      q,
                      e.key,
                      q.isJudge
                          ? e.value
                          : '${String.fromCharCode(65 + e.key)}. ${e.value}',
                      picked,
                      done,
                      cs,
                    ),
                  ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: done ? null : () => _submit(q),
                child: Text(
                  done ? '已提交' : (q.isShort ? '查看参考答案' : '提交本题'),
                ),
              ),
            ),
            if (done) ...<Widget>[
              const SizedBox(height: 12),
              _resultBlock(q, _graded[q.id], cs),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quizScore(ColorScheme cs, int total) {
    if (total <= 0 || _submitted.length < total) {
      return const SizedBox.shrink();
    }
    final correct = _graded.values.where((v) => v == true).length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        '本次完成 $total 题，客观题答对 $correct 题（简答题请对照参考答案自评）',
        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
      ),
    );
  }
}
