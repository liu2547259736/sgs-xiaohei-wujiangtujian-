import 'package:flutter/material.dart';

import '../../data/atlas_controller.dart';
import '../../data/models.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.controller,
    required this.searchController,
  });

  final AtlasController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: searchController,
              onChanged: controller.setSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜武将 / 拼音缩写 / 技能',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: controller.search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          searchController.clear();
                          controller.setSearch('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          _chipRow(
            controller.versions
                .map((v) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(v.short),
                        selected: controller.selectedVersion == v.id,
                        onSelected: (_) => controller.selectVersion(v.id),
                        visualDensity: VisualDensity.compact,
                      ),
                    ))
                .toList(),
          ),
          _chipRow(<Widget>[
            ...kKingdomOrder.map((k) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(kKingdomLabel[k] ?? k),
                    selected: controller.kingdom == k,
                    onSelected: (_) => controller.setKingdom(k),
                    visualDensity: VisualDensity.compact,
                  ),
                )),
            const SizedBox(width: 4),
            _genderChip('male', '男'),
            const SizedBox(width: 6),
            _genderChip('female', '女'),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _dropdown(
                    context,
                    value: controller.pack,
                    hint: '全部扩展包',
                    items: <(String, String)>[
                      ('all', '全部扩展包'),
                      ...controller.currentPacks
                          .map((p) => (p.id, '${p.label} (${p.count})')),
                    ],
                    onChanged: controller.setPack,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dropdown(
                    context,
                    value: controller.level,
                    hint: '全部品质',
                    items: <(String, String)>[
                      ('all', '全部品质'),
                      ...controller.currentLevels.map((l) => (l, l)),
                    ],
                    onChanged: controller.setLevel,
                  ),
                ),
                IconButton(
                  tooltip: '清除筛选',
                  icon: Icon(
                    Icons.filter_alt_off_outlined,
                    size: 20,
                    color: controller.hasFilters
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    searchController.clear();
                    controller.clearFilters();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipRow(List<Widget> children) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Row(children: children),
      );

  Widget _genderChip(String value, String label) => ChoiceChip(
        label: Text(label),
        selected: controller.gender == value,
        onSelected: (_) =>
            controller.setGender(controller.gender == value ? 'all' : value),
        visualDensity: VisualDensity.compact,
      );

  Widget _dropdown(
    BuildContext context, {
    required String value,
    required String hint,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    final valid = items.any((e) => e.$1 == value) ? value : 'all';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButton<String>(
        value: valid,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: items
            .map((e) => DropdownMenuItem<String>(
                  value: e.$1,
                  child: Text(e.$2,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
