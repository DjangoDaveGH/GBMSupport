import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/notifications/domain/app_notification.dart';
import 'package:hyport/features/notifications/presentation/announcement_popup_listener.dart';

AppNotification _note({bool edited = false}) => AppNotification(
  id: 'n1',
  userId: 'u1',
  type: NotificationType.maintenance,
  title: 'Planned Maintenance',
  message: 'GBMS will be offline on Saturday.',
  read: false,
  createdAt: DateTime(2026, 11, 23, 9),
  announcementId: 'abc',
  edited: edited,
);

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => dialog,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the announcement and closes', (tester) async {
    await _open(tester, AnnouncementDialog(notification: _note(edited: true)));
    expect(find.text('Planned Maintenance'), findsOneWidget);
    expect(find.text('GBMS will be offline on Saturday.'), findsOneWidget);
    expect(find.textContaining('Edited'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Planned Maintenance'), findsNothing);
  });

  testWidgets('says how many more follow', (tester) async {
    await _open(tester, AnnouncementDialog(notification: _note(), remaining: 2));
    expect(find.text('Next (2 more)'), findsOneWidget);
    await tester.tap(find.text('Next (2 more)'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementDialog), findsNothing);
  });
}
