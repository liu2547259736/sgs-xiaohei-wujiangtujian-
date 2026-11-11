// 把「当前生效的数据源」沿 widget 树传下去。
//
// 包在 MaterialApp 外层，这样连 showModalBottomSheet 建在 Navigator overlay
// 里的详情弹层也能拿到，不需要给每张卡片 / 每个页面层层透传参数。
import 'package:flutter/widgets.dart';

import 'data_file_source.dart';

class DataFileScope extends InheritedWidget {
  const DataFileScope({
    super.key,
    required this.source,
    required super.child,
  });

  final DataFileSource source;

  static DataFileSource? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DataFileScope>()?.source;

  @override
  bool updateShouldNotify(DataFileScope oldWidget) =>
      oldWidget.source != source;
}
