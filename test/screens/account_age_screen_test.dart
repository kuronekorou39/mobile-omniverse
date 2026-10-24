import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_omniverse/models/follow_user.dart';
import 'package:mobile_omniverse/models/sns_service.dart';
import 'package:mobile_omniverse/screens/account_age_screen.dart';
import 'package:mobile_omniverse/services/follow_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 作成日の分布画面。集計そのものは account_age_stats_test で見るので、
/// ここでは DB から読んで棒が並び、押すと一覧に進むことだけ確かめる。
///
/// FFI の DB は別スレッドで動くので、読み書きは runAsync の中で待つ。
/// 待たずに pumpAndSettle すると、読み込み中の棒の光が止まらず帰ってこない
void main() {
  final db = FollowDb.instance;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    db.factoryOverride = databaseFactoryFfi;
    db.pathOverride = inMemoryDatabasePath;
  });

  tearDown(() async {
    await db.close();
    db.factoryOverride = null;
    db.pathOverride = null;
  });

  Future<FollowSnapshot> snapshotWith(List<FollowUser> users) async {
    final id = await db.startSnapshot(
        service: SnsService.x, targetHandle: 'alice', kind: 'followers');
    await db.addBatch(snapshotId: id, users: users, cursor: '0|end');
    await db.finishSnapshot(snapshotId: id, completed: true, reason: 'end');
    return (await db.listSnapshots(targetHandle: 'alice', kind: 'followers'))
        .single;
  }

  /// 画面を組み立てて DB の読み込みを始め、終わるまで実時間で待ってから描き直す
  Future<void> settleDb(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('年ごとの棒が出て、押すとその年の人が並ぶ', (tester) async {
    final s = await tester.runAsync(() => snapshotWith([
          const FollowUser(
              restId: '1',
              screenName: 'old',
              name: 'Old Timer',
              createdAt: 'Thu Apr 06 15:24:15 +0000 2015'),
          const FollowUser(
              restId: '2',
              screenName: 'new1',
              name: 'Newbie One',
              createdAt: 'Thu Apr 06 15:24:15 +0000 2024'),
          const FollowUser(
              restId: '3',
              screenName: 'new2',
              name: 'Newbie Two',
              createdAt: 'Fri May 10 10:00:00 +0000 2024'),
        ]));

    await tester.pumpWidget(MaterialApp(home: AccountAgeScreen(snapshot: s!)));
    await settleDb(tester);

    expect(find.text('年ごと'), findsOneWidget);
    expect(find.text('2015年'), findsOneWidget);
    expect(find.text('2024年'), findsOneWidget);
    // 一番多い年のカード
    expect(find.text('2024'), findsOneWidget);

    await tester.tap(find.text('2024年'));
    await settleDb(tester);

    expect(find.text('2024年に作られた人'), findsOneWidget);
    expect(find.text('Newbie One'), findsOneWidget);
    expect(find.text('Newbie Two'), findsOneWidget);
    expect(find.text('Old Timer'), findsNothing);
  });

  testWidgets('作成日が無い人は不明として数える', (tester) async {
    final s = await tester.runAsync(() => snapshotWith([
          const FollowUser(restId: '1', screenName: 'a', name: 'A'),
        ]));
    await tester.pumpWidget(MaterialApp(home: AccountAgeScreen(snapshot: s!)));
    await settleDb(tester);

    expect(find.text('作成日が分かる人が居ません'), findsOneWidget);
    // 月ごとの棒の下にあるので、そこまで送る
    await tester.scrollUntilVisible(
      find.text('1 人は作成日が分かりません'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 人は作成日が分かりません'), findsOneWidget);
  });
}
