import 'package:liblanis/liblanis.dart';
import 'package:test/test.dart';

void main() {
  test(
    'scoped settings preserve types and isolate reads, writes and removal',
    () {
      final values = <String, String?>{};
      final base = TypedSettings(
        read: (key) => values[key],
        write: (key, value) => values[key] = value,
        delete: values.remove,
      );
      const key = 'stundenplan.php/custom-lessons';
      base.setJsonList(key, [
        ['original'],
      ]);
      final first = base.scoped('pupil/1/');
      final second = base.scoped('pupil/2/');
      first.setJsonList(key, [
        [
          {'name': 'First'},
        ],
      ]);
      second.setJsonList(key, [
        [
          {'name': 'Second'},
        ],
      ]);
      first.setBool('visible', true);
      second.setJsonMap('colors', {'subject': 'ff000000'});
      expect(base.getJsonList(key), [
        ['original'],
      ]);
      expect(first.getJsonList(key), [
        [
          {'name': 'First'},
        ],
      ]);
      expect(second.getJsonList(key), [
        [
          {'name': 'Second'},
        ],
      ]);
      expect(first.getBool('visible'), isTrue);
      expect(second.getBool('visible'), isNull);
      expect(second.getJsonMap('colors'), {'subject': 'ff000000'});
      first.remove(key);
      expect(first.getJsonList(key), isNull);
      expect(second.getJsonList(key), isNotNull);
      expect(base.getJsonList(key), isNotNull);
    },
  );
}
