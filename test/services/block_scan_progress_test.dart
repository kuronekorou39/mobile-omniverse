import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/services/block_scan_service.dart';

void main() {
  BlockScanProgress progress(String targetHandle) => BlockScanProgress(
        runId: 1,
        targetHandle: targetHandle,
        startedAt: DateTime(2026, 9, 7),
        done: 10,
        total: 100,
      );

  group('BlockScanProgress の対象', () {
    // 調査は 1 本しか走らないので、別の対象を調べている間も画面には
    // 進捗が届く。対象が入っていないと、どの画面でも「自分が調査中」に
    // 見えてしまう
    test('進捗はどの対象の調査かを持つ', () {
      expect(progress('rou39').targetHandle, 'rou39');
    });

    test('対象が一致するときだけ自分の調査とみなせる', () {
      final p = progress('rou39');
      expect(p.targetHandle == 'rou39', isTrue);
      expect(p.targetHandle == 'someone', isFalse);
    });

    test('copyWith しても対象は引き継ぐ', () {
      final p = progress('rou39').copyWith(done: 20, currentHandle: 'alice');
      expect(p.targetHandle, 'rou39');
      expect(p.runId, 1);
      expect(p.done, 20);
      expect(p.currentHandle, 'alice');
    });

    test('copyWith は中断中フラグを立てても対象を失わない', () {
      final p = progress('rou39').copyWith(cancelling: true);
      expect(p.targetHandle, 'rou39');
      expect(p.cancelling, isTrue);
    });
  });
}
