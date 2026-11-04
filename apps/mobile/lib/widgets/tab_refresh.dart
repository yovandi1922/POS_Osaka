// apps/mobile/lib/widgets/tab_refresh.dart
// Mixin: panggil refresh() setiap kali tab milik screen ini dibuka (IndexedStack menjaga state).
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/tab_nav.dart';

mixin TabRefresh<T extends StatefulWidget> on State<T> {
  AppTab get tab;
  Future<void> refresh();

  TabNav? _nav;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nav = context.read<TabNav>();
    if (!identical(nav, _nav)) {
      _nav?.removeListener(_onNav);
      _nav = nav;
      nav.addListener(_onNav);
    }
  }

  void _onNav() {
    if (_nav?.current == tab && mounted) refresh();
  }

  @override
  void dispose() {
    _nav?.removeListener(_onNav);
    super.dispose();
  }
}
