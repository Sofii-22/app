import 'package:flutter_test/flutter_test.dart';
import 'package:grabadora_de_voz/main.dart';

void main() {
  test(
    'La aplicación contiene la clase MainApp',
    () {
      const app = MainApp();

      expect(app, isNotNull);
    },
  );
}