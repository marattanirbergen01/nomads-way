import 'package:flutter/foundation.dart';

/// Текущий язык интерфейса и контента. Поддерживаем kk / ru (en — когда появятся переводы).
class LocaleController extends ChangeNotifier {
  String _code = 'kk';
  String get code => _code;
  void set(String code) {
    if (code == _code) return;
    _code = code;
    notifyListeners();
  }
}
