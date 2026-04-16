import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spine_fupt_app/features/reviews/presentation/review_list_screen.dart';
import 'package:spine_fupt_app/features/models.dart';
import 'package:spine_fupt_app/providers.dart';

final _sampleExams = [
  ExamModel.fromJson({
    'id': 1, 'patient_id': 1, 'patient_name': '张三',
    'status': 'pending_review', 'spine_class': 'lumbar',
    'cobb_angle': 15.0, 'created_at': '2025-01-01T00:00:00Z',
  }),
  ExamModel.fromJson({
    'id': 2, 'patient_id': 2, 'patient_name': '李四',
    'status': 'reviewed', 'spine_class': 'cervical',
    'cobb_angle': 10.0, 'created_at': '2025-01-02T00:00:00Z',
  }),
];

Widget _buildTestApp({required AsyncValue<List<ExamModel>> reviewState}) {
  return ProviderScope(
    overrides: [
      reviewListProvider.overrideWith((_) => Future.value(
          reviewState is AsyncData<List<ExamModel>> ? reviewState.value : [])),
    ],
    child: const MaterialApp(home: ReviewListScreen()),
  );
}

void main() {
  group('ReviewListScreen', () {
    testWidgets('shows title and filter chips', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          reviewListProvider.overrideWith((_) => Future.value(_sampleExams)),
        ],
        child: const MaterialApp(home: ReviewListScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('复核中心'), findsOneWidget);
      expect(find.text('全部'), findsWidgets);
      expect(find.text('待复核'), findsWidgets);
      expect(find.text('已复核'), findsWidgets);
      expect(find.text('推理失败'), findsOneWidget);
    });

    testWidgets('renders exam list when data loaded', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          reviewListProvider.overrideWith((_) => Future.value(_sampleExams)),
        ],
        child: const MaterialApp(home: ReviewListScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
    });

    testWidgets('filter chips narrow down the list', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          reviewListProvider.overrideWith((_) => Future.value(_sampleExams)),
        ],
        child: const MaterialApp(home: ReviewListScreen()),
      ));
      await tester.pumpAndSettle();

      // Tap the '待复核' FilterChip (second chip)
      final chips = find.byType(FilterChip);
      await tester.tap(chips.at(1)); // index 1 = 待复核
      await tester.pump();

      // Only pending_review items shown
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsNothing);
    });

    testWidgets('shows empty state when filtered list is empty', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          reviewListProvider.overrideWith((_) => Future.value(_sampleExams)),
        ],
        child: const MaterialApp(home: ReviewListScreen()),
      ));
      await tester.pumpAndSettle();

      // Tap the '推理失败' FilterChip (fourth chip, index 3) — no items match
      final chips = find.byType(FilterChip);
      await tester.tap(chips.at(3));
      await tester.pump();

      // Both items should NOT appear
      expect(find.text('张三'), findsNothing);
      expect(find.text('李四'), findsNothing);
    });
  });
}
