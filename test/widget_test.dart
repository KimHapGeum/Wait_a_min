import 'package:flutter_test/flutter_test.dart';
import 'package:monday/main.dart';

void main() {
  testWidgets('shows the active waiting ticket', (tester) async {
    await tester.pumpWidget(const PassNowApp());

    expect(find.text('맛있는 녀석들 삼겹살 본점'), findsOneWidget);
    expect(find.text('내 번호표'), findsOneWidget);
  });

  testWidgets('advances the active waiting ticket', (tester) async {
    await tester.pumpWidget(const PassNowApp());

    await tester.tap(find.text('1팀 줄이기'));
    await tester.pumpAndSettle();

    expect(find.text('No.33'), findsOneWidget);
  });

  testWidgets('cancels a waiting ticket after confirmation', (tester) async {
    await tester.pumpWidget(const PassNowApp());

    await tester.tap(find.text('대기 취소'));
    await tester.pumpAndSettle();
    expect(find.text('대기 취소 확인'), findsOneWidget);

    await tester.tap(find.text('취소하기'));
    await tester.pumpAndSettle();
    expect(find.text('현재 대기 중인 매장이 없습니다'), findsOneWidget);
  });

  testWidgets('starts a countdown when the ticket is called', (tester) async {
    await tester.pumpWidget(const PassNowApp());

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('1팀 줄이기'));
      await tester.pump();
    }

    expect(find.text('응답 대기 카운트다운'), findsOneWidget);
    expect(find.text('직원 확인 후 입장 완료'), findsOneWidget);
  });

  testWidgets('notifies when three teams remain', (tester) async {
    await tester.pumpWidget(const PassNowApp());

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('1팀 줄이기'));
      await tester.pump();
    }

    expect(find.text('입장 임박'), findsOneWidget);
  });
}
