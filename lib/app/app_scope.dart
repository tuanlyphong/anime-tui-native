import 'package:flutter/widgets.dart';

import '../state/app_controller.dart';

/// Makes the [AppController] available to the widget tree without a package.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final AppController controller;

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found above this widget.');
    return scope!.controller;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      oldWidget.controller != controller;
}
