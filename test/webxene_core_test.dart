import 'package:flutter_test/flutter_test.dart';
import 'package:webxene_core/motes/mote.dart';

void main() {
  test('Mote creation', () {
    final newMote = Mote();
    expect(newMote.id, 0);
    expect(newMote.payload.length, 0);
    expect(newMote.comments.length, 0);
  });
}
