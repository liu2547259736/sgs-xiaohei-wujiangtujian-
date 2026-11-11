// 2v2 龙虎斗 · 对战页面（导出供外部 import 使用）。
//
// 数据只走随包 seed（readDataString + BundleOnlySource），不接后端、不发网络请求。
// 选将 -> 2v2 牌桌 -> 出牌 / 敌方 AI -> 中文日志 -> 结算弹窗。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sgs_heroes/core/sync/data_file_source.dart';
import 'package:sgs_heroes/data/models.dart'
    show kKingdomArgb, kKingdomLabel;
import 'package:sgs_heroes/ui/widgets/hero_avatar.dart';

import 'battle_engine.dart';
import 'battle_models.dart' as bm;

/// 2v2 龙虎斗对战页。
///
/// 外部接入：`import 'package:sgs_heroes/features/battle/battle_page.dart';`
/// 然后 `Navigator.push(context, MaterialPageRoute(builder: (_) => const BattlePage()));`
/// 若App 已接入数据更新覆盖层，可传 `BattlePage(source: mySource)`。
class BattlePage extends StatefulWidget {
  const BattlePage({super.key, this.source = const BundleOnlySource()});

  /// 数据读取源，默认纯随包（rootBundle）。
  final DataFileSource source;

  @override
  State<BattlePage> createState() => _BattlePageState();
}

class _BattlePageState extends State<BattlePage> {
  List<bm.BattleHero>? _heroes;
  String? _error;
  bm.BattleHero? _picked;
  String _query = '';

  BattleEngine? _engine;
  bm.Card? _selectedCard;
  List<bm.Player> _targets = <bm.Player>[];
  bool _overShown = false;

  @override
  void initState() {
    super.initState();
    _loadHeroes();
  }

  // -------------------------------------------------------------------------
  // 选将数据：懒加载两个分片，过滤神/魔，同名去重（优先 std），白名单靠前。
  // -------------------------------------------------------------------------
  Future<void> _loadHeroes() async {
    try {
      final byName = <String, List<bm.BattleHero>>{};
      for (final path in const <String>[
        'heroes/sgsol-001.json',
        'heroes/sgsol-002.json',
      ]) {
        final raw = await readDataString(widget.source, path);
        final data = (jsonDecode(raw) as Map<String, dynamic>)['data'] as Map;
        final generals = data['generals'] as List? ?? const <dynamic>[];
        for (final item in generals) {
          final j = Map<String, dynamic>.from(item as Map);
          final pack = (j['p'] ?? '').toString();
          if (pack == 'shen' || pack == 'mo') continue;
          final skills = j['s'];
          if (skills is! List || skills.isEmpty) continue;
          final h = bm.BattleHero.fromJson(j);
          if (h.name.isEmpty) continue;
          byName.putIfAbsent(h.name, () => <bm.BattleHero>[]).add(h);
        }
      }

      final list = <bm.BattleHero>[];
      for (final group in byName.values) {
        group.sort((a, b) {
          final av = a.pack == 'std' ? 0 : 1;
          final bv = b.pack == 'std' ? 0 : 1;
          return av - bv;
        });
        list.add(group.first);
      }
      final order = kAllyNames;
      list.sort((a, b) {
        final ai = order.indexOf(a.name);
        final bi = order.indexOf(b.name);
        if (ai >= 0 && bi >= 0) return ai - bi;
        if (ai >= 0) return -1;
        if (bi >= 0) return 1;
        return a.name.compareTo(b.name);
      });
      if (!mounted) return;
      setState(() {
        _heroes = list;
        _error = null;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = '武将数据加载失败：$err');
    }
  }

  List<bm.BattleHero> get _visibleHeroes {
    final all = _heroes ?? const <bm.BattleHero>[];
    if (_query.isEmpty) return all;
    return all.where((h) => h.name.contains(_query)).toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // 顶层布局
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('2v2 龙虎斗'),
        actions: <Widget>[
          if (_engine != null)
            IconButton(
              tooltip: '放弃本局 / 重新选将',
              icon: const Icon(Icons.refresh),
              onPressed: _backToPick,
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) return _errorView();
    if (_heroes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在加载随包武将数据…'),
          ],
        ),
      );
    }
    if (_engine == null) return _buildPick();
    return _buildGame();
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_error ?? '加载失败', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _heroes = null;
                  });
                  _loadHeroes();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );

  // -------------------------------------------------------------------------
  // 选将页
  // -------------------------------------------------------------------------
  Widget _buildPick() {
    final theme = Theme.of(context);
    final list = _visibleHeroes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            '从随包真实武将中选一位出战（已过滤神 / 魔）。27 位经典武将排在前面，'
            '技能逐一标注「已实装 / 未实装」，未实装技能在对局里不生效。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索武将名',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('没找到这个武将'))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.55,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _heroPickCard(list[i]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: _picked == null ? null : _startGame,
            child: Text(_picked == null
                ? '请先选择一位武将'
                : '以【${_picked!.name}】开始对战'),
          ),
        ),
      ],
    );
  }

  Widget _heroPickCard(bm.BattleHero h) {
    final theme = Theme.of(context);
    final selected = _picked == h;
    final whitelisted = isWhitelistedHero(h.name);
    final kingdomColor = Color(kKingdomArgb[h.kingdom] ?? 0xFF88857E);
    final kLabel = kKingdomLabel[h.kingdom] ?? '—';
    final tag = whitelisted ? ' · 经典' : '';
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _picked = h),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 46,
                height: 62,
                child: HeroAvatar(
                  relPath: h.avatar,
                  name: h.name,
                  kingdom: h.kingdom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            h.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text('${h.maxHp}体力',
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$kLabel$tag',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: kingdomColor),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: _skillChips(h),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _skillChips(bm.BattleHero h) {
    final white = whitelistSkillsOf(h.name);
    final chips = <Widget>[];
    for (final s in h.skills.take(4)) {
      final on = isSkillImplemented(s) && white.contains(s);
      final flag = on ? '已实装' : '未实装';
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: on
              ? Colors.green.withValues(alpha: 0.14)
              : Colors.grey.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$s·$flag',
          style: TextStyle(
            fontSize: 9,
            color: on ? Colors.green.shade800 : Colors.grey.shade700,
          ),
        ),
      ));
    }
    return chips;
  }

  // -------------------------------------------------------------------------
  // 开局 / 回合推进
  // -------------------------------------------------------------------------
  void _startGame() {
    final chosen = _picked;
    final all = _heroes;
    if (chosen == null || all == null) return;
    final others = all.where((h) => h.name != chosen.name).toList();
    final impl = others.where((h) => isWhitelistedHero(h.name)).toList()
      ..shuffle();
    final rest = others.where((h) => !isWhitelistedHero(h.name)).toList()
      ..shuffle();
    final pool = <bm.BattleHero>[...impl, ...rest];
    final ai = pool.take(3).toList();
    while (ai.length < 3) {
      ai.add(chosen);
    }
    final four = <bm.BattleHero>[chosen, ai[0], ai[1], ai[2]];
    final engine = BattleEngine(seed: DateTime.now().millisecondsSinceEpoch);
    engine.newGame(four);
    setState(() {
      _engine = engine;
      _selectedCard = null;
      _targets = <bm.Player>[];
      _overShown = false;
    });
    _advance();
  }

  /// 推进到下一个人类出牌阶段；中间的 AI 回合用可解释规则一次跑完。
  void _advance() {
    final e = _engine;
    if (e == null) return;
    var guard = 0;
    while (!e.state.over && guard < 400) {
      guard++;
      final cur = e.state.currentPlayer;
      if (!cur.alive || cur.flipped) {
        e.passTurn();
        continue;
      }
      if (cur.isHuman) {
        final canPlay = e.beginTurn();
        if (!canPlay) {
          e.endTurn();
          continue;
        }
        break;
      }
      e.runAiTurn();
    }
    if (!mounted) return;
    setState(() {});
    if (e.state.over && !_overShown) _showOver();
  }

  // -------------------------------------------------------------------------
  // 对局页
  // -------------------------------------------------------------------------
  Widget _buildGame() {
    final e = _engine!;
    final s = e.state;
    final theme = Theme.of(context);
    final me = s.me;
    final myPlay = !s.over &&
        s.currentPlayer == me &&
        me.alive &&
        s.phase == bm.BattlePhase.play;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _statusBar(e, theme),
          const SizedBox(height: 8),
          _seatRow(<bm.Player>[s.players[1], s.players[3]]),
          const SizedBox(height: 8),
          _logPanel(e, theme),
          const SizedBox(height: 8),
          _seatRow(<bm.Player>[s.players[0], s.players[2]]),
          const SizedBox(height: 8),
          _handArea(e, myPlay, theme),
          const SizedBox(height: 8),
          _actionBar(e, myPlay, theme),
        ],
      ),
    );
  }

  Widget _statusBar(BattleEngine e, ThemeData theme) {
    final s = e.state;
    final cur = s.currentPlayer;
    final turnText = s.over
        ? '对局结束'
        : (cur == s.me ? '你的回合' : '${cur.name} 的回合');
    final phaseText = _phaseLabel(s.phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Text('第 ${s.round} 轮', style: theme.textTheme.labelLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Text('$turnText · $phaseText',
                style: theme.textTheme.labelLarge),
          ),
          Text('🂠 ${s.deck.length} / 弃 ${s.pile.length}',
              style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _seatRow(List<bm.Player> seats) => Row(
        children: seats
            .map((p) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _seatCard(p),
                  ),
                ))
            .toList(),
      );

  Widget _seatCard(bm.Player p) {
    final e = _engine!;
    final theme = Theme.of(context);
    final isTurn = !e.state.over && e.state.currentPlayer == p && p.alive;
    final isTarget = _targets.contains(p);
    final opt = _currentOption();
    final canTarget = opt != null && opt.need > 0 && opt.candidates.contains(p);
    final kingdomColor = Color(kKingdomArgb[p.kingdom] ?? 0xFF88857E);
    final borderColor = isTarget
        ? theme.colorScheme.primary
        : (isTurn
            ? theme.colorScheme.tertiary
            : (canTarget
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant));
    final relation = p == e.state.me
        ? '我'
        : (p.team == e.state.me.team ? '友' : '敌');
    final eq = p.equipLabels.isEmpty ? '' : ' · ${p.equipLabels.join('/')}';
    return SizedBox(
      height: 108,
      child: Card(
        elevation: isTurn ? 3 : 0,
        color: p.alive ? null : Colors.grey.withValues(alpha: 0.18),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: borderColor, width: (isTurn || isTarget) ? 2 : 1),
        ),
        child: InkWell(
          onTap: () => _onSeatTap(p),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 40,
                  height: 56,
                  child: HeroAvatar(
                    relPath: p.hero.avatar,
                    name: p.name,
                    kingdom: p.kingdom,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(isTarget ? '◎目标' : relation,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: isTarget
                                      ? theme.colorScheme.primary
                                      : null)),
                        ],
                      ),
                      Text(
                        '${_teamLabel(p.team)}·${_roleLabel(p.role)} · ${p.hp}/${p.maxHp} ${_hpDots(p)}',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: kingdomColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '🃏${p.hand.length}$eq',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _skillsText(p),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                      if (!p.alive)
                        Text('阵亡',
                            style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logPanel(BattleEngine e, ThemeData theme) {
    final all = e.logs;
    final recent = (all.length > 8
            ? all.sublist(all.length - 8)
            : all)
        .reversed
        .toList();
    return Container(
      height: 116,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: recent.isEmpty
          ? Center(
              child: Text('暂无日志', style: theme.textTheme.bodySmall),
            )
          : ListView.builder(
              itemCount: recent.length,
              itemBuilder: (_, i) {
                final l = recent[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    l.text,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.25,
                      color: _logColor(l.kind, theme),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _handArea(BattleEngine e, bool myPlay, ThemeData theme) {
    final me = e.state.me;
    final hand = me.hand;
    final opts = myPlay ? e.playOptions(me) : <bm.PlayOption>[];
    return SizedBox(
      height: 92,
      child: hand.isEmpty
          ? Center(
              child: Text('手牌为空', style: theme.textTheme.bodySmall),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hand.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final c = hand[i];
                final selected = _selectedCard == c;
                final usable = opts.any((o) => o.card == c);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (_selectedCard == c) {
                      _selectedCard = null;
                      _targets = <bm.Player>[];
                    } else {
                      _selectedCard = c;
                      _targets = <bm.Player>[];
                    }
                  }),
                  child: Container(
                    width: 62,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.primary
                            : (usable
                                ? theme.colorScheme.outline
                                : theme.colorScheme.outlineVariant),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          c.corner,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: c.isRed
                                ? theme.colorScheme.error
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          c.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (usable)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Icon(Icons.check_circle,
                                size: 12, color: theme.colorScheme.primary),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _actionBar(BattleEngine e, bool myPlay, ThemeData theme) {
    final opt = myPlay ? _currentOption() : null;
    final canUse = opt != null && _targets.length >= opt.need;
    final skills = myPlay ? e.activeSkills(e.state.me) : <String>[];
    final label = opt == null
        ? '选择一张手牌'
        : (opt.need > 0
            ? '${_actionLabel(opt)} → 选 ${opt.need} 个目标'
            : _actionLabel(opt));
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: canUse ? _useSelected : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: myPlay ? _endPlayerTurn : null,
          child: const Text('结束出牌'),
        ),
        if (skills.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: OutlinedButton(
              onPressed: () => _useSkill(skills.first),
              child: Text(skills.first),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 交互
  // -------------------------------------------------------------------------
  bm.PlayOption? _currentOption() {
    final e = _engine;
    final c = _selectedCard;
    if (e == null || c == null) return null;
    final me = e.state.me;
    if (e.state.over ||
        e.state.currentPlayer != me ||
        !me.alive ||
        e.state.phase != bm.BattlePhase.play) {
      return null;
    }
    for (final o in e.playOptions(me)) {
      if (o.card == c) return o;
    }
    return null;
  }

  void _onSeatTap(bm.Player p) {
    final opt = _currentOption();
    if (opt == null || opt.need == 0) {
      _showHeroInfo(p);
      return;
    }
    if (!opt.candidates.contains(p)) {
      _toast('这张牌打不了他');
      return;
    }
    setState(() {
      if (_targets.contains(p)) {
        _targets.remove(p);
      } else {
        if (_targets.length >= opt.need) _targets.removeAt(0);
        _targets.add(p);
      }
    });
  }

  void _showHeroInfo(bm.Player p) {
    final desc = <String>[];
    final white = whitelistSkillsOf(p.hero.name);
    for (final s in p.hero.skills) {
      final on = isSkillImplemented(s) && white.contains(s);
      final state = on ? '已实装' : '未实装';
      final own = p.hero.skillDescs[s];
      final base = (own != null && own.isNotEmpty)
          ? own
          : skillDescription(s);
      desc.add('$s（$state）：$base');
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${p.name} · ${_teamLabel(p.team)}${_roleLabel(p.role)}'),
        content: SingleChildScrollView(
          child: Text(desc.isEmpty ? '无技能' : desc.join('\n\n')),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _useSelected() {
    final e = _engine;
    final opt = _currentOption();
    if (e == null || opt == null) return;
    if (_targets.length < opt.need) {
      _toast('请先点选目标座位');
      return;
    }
    e.play(opt, List<bm.Player>.from(_targets));
    setState(() {
      _selectedCard = null;
      _targets = <bm.Player>[];
    });
    if (e.state.over && !_overShown) _showOver();
  }

  void _endPlayerTurn() {
    final e = _engine;
    if (e == null) return;
    e.endTurn();
    setState(() {
      _selectedCard = null;
      _targets = <bm.Player>[];
    });
    _advance();
  }

  void _useSkill(String skill) {
    final e = _engine;
    if (e == null) return;
    final ok = e.useSkill(e.state.me, skill);
    if (!ok) _toast('现在不能发动【$skill】');
    setState(() {});
  }

  void _backToPick() {
    setState(() {
      _engine = null;
      _picked = null;
      _selectedCard = null;
      _targets = <bm.Player>[];
      _overShown = false;
    });
  }

  void _showOver() {
    final e = _engine;
    if (e == null || !e.state.over) return;
    _overShown = true;
    final winner = e.state.winner;
    final meWin = winner == e.state.me.team;
    final title = winner == bm.BattleTeam.dragon ? '🏆 龙方胜' : '🏆 虎方胜';
    final content = meWin
        ? '你带队赢下第 ${e.state.round} 轮！'
        : '第 ${e.state.round} 轮惜败，换个武将再来！';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _backToPick();
            },
            child: const Text('再来一局'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  // -------------------------------------------------------------------------
  // 小工具（不依赖 battle_models 的 extension，避免前缀导入下不可见）
  // -------------------------------------------------------------------------
  String _teamLabel(bm.BattleTeam t) =>
      t == bm.BattleTeam.dragon ? '龙' : '虎';

  String _roleLabel(bm.SeatRole r) =>
      r == bm.SeatRole.lord ? '主将' : '先锋';

  String _phaseLabel(bm.BattlePhase p) {
    switch (p) {
      case bm.BattlePhase.judge:
        return '判定';
      case bm.BattlePhase.draw:
        return '摸牌';
      case bm.BattlePhase.play:
        return '出牌';
      case bm.BattlePhase.discard:
        return '弃牌';
      case bm.BattlePhase.end:
        return '结束';
      case bm.BattlePhase.wait:
        return '等待';
      case bm.BattlePhase.over:
        return '对局结束';
    }
  }

  String _hpDots(bm.Player p) {
    final hp = p.hp < 0 ? 0 : (p.hp > p.maxHp ? p.maxHp : p.hp);
    final lost = p.maxHp - hp;
    return List.filled(hp, '♥').join() + List.filled(lost, '♡').join();
  }

  String _skillsText(bm.Player p) {
    if (p.hero.skills.isEmpty) return '无技能';
    final white = whitelistSkillsOf(p.hero.name);
    return p.hero.skills.map((s) {
      final on = isSkillImplemented(s) && white.contains(s);
      final flag = on ? '✓' : '(未实装)';
      return '$s$flag';
    }).join(' ');
  }

  Color _logColor(bm.LogKind k, ThemeData theme) {
    switch (k) {
      case bm.LogKind.damage:
      case bm.LogKind.death:
        return theme.colorScheme.error;
      case bm.LogKind.heal:
        return Colors.green.shade700;
      case bm.LogKind.skill:
        return Colors.purple.shade700;
      case bm.LogKind.quote:
        return theme.colorScheme.onSurfaceVariant;
      case bm.LogKind.win:
        return Colors.orange.shade800;
      case bm.LogKind.system:
        return theme.colorScheme.primary;
      default:
        return theme.colorScheme.onSurface;
    }
  }

  String _actionLabel(bm.PlayOption o) {
    switch (o.view.name) {
      case 'sha':
        return '出【杀】';
      case 'tao':
        return '吃【桃】';
      case 'jiu':
        return '喝【酒】';
      case 'wuzhong':
        return '无中生有';
      case 'taoyuan':
        return '桃园结义';
      case 'wugu':
        return '五谷丰登';
      case 'wanjian':
        return '万箭齐发';
      case 'nanzheng':
        return '南蛮入侵';
      case 'juedou':
        return '决斗';
      case 'guohe':
        return '过河拆桥';
      case 'shunshou':
        return '顺手牵羊';
      case 'lebu':
        return '乐不思蜀';
      case 'bingliang':
        return '兵粮寸断';
      case 'shandian':
        return '闪电';
      case 'tieso':
        return '铁索连环';
      case 'huogong':
        return '火攻';
      case 'jiedao':
        return '借刀杀人';
      default:
        final eq = o.view.real.isEquip ? '装备' : '使用';
        return '$eq【${o.view.label}】';
    }
  }
}
