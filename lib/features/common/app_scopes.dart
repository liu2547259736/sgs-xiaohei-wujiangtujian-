// 全局服务的 widget 树注入点。
// InheritedNotifier 会在服务 notifyListeners() 时自动重建依赖它的页面。
import 'package:flutter/widgets.dart';

import '../account/local_auth.dart';
import '../assets/asset_roots.dart';

class AuthScope extends InheritedNotifier<LocalAuthService> {
  const AuthScope({
    super.key,
    required LocalAuthService auth,
    required super.child,
  }) : super(notifier: auth);

  static LocalAuthService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()!.notifier!;
}

class AssetRootsScope extends InheritedNotifier<AssetRoots> {
  const AssetRootsScope({
    super.key,
    required AssetRoots roots,
    required super.child,
  }) : super(notifier: roots);

  static AssetRoots of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssetRootsScope>()!.notifier!;
}
