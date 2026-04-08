import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

/// A single shimmer line placeholder (rectangle).
class _Box extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const _Box({required this.width, required this.height, this.radius = 4});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Wraps children in a shimmer effect that respects the current theme.
class _ThemedShimmer extends StatelessWidget {
  final Widget child;
  const _ThemedShimmer({required this.child});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? AppColors.darkBgCard : const Color(0xFFE0E0E0),
      highlightColor: isDark ? const Color(0xFF424242) : AppColors.bgSecondary,
      child: child,
    );
  }
}

// ─── List-tile style shimmer (reusable) ───

class ShimmerListItem extends StatelessWidget {
  final bool circleLeading;
  final double leadingSize;
  final bool hasTrailing;
  final bool isThreeLine;
  const ShimmerListItem({
    super.key,
    this.circleLeading = true,
    this.leadingSize = 40,
    this.hasTrailing = false,
    this.isThreeLine = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _Box(
            width: leadingSize,
            height: leadingSize,
            radius: circleLeading ? leadingSize / 2 : 6,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Box(width: 140, height: 14),
                const SizedBox(height: 8),
                const _Box(width: 200, height: 11),
                if (isThreeLine) ...[
                  const SizedBox(height: 6),
                  const _Box(width: 80, height: 10),
                ],
              ],
            ),
          ),
          if (hasTrailing) const _Box(width: 48, height: 18, radius: 10),
        ],
      ),
    );
  }
}

// ─── Concrete shimmer screens ───

/// Patient list shimmer: 8 card tiles with circle avatar + badge trailing.
class ShimmerPatientList extends StatelessWidget {
  const ShimmerPatientList({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ShimmerListItem(hasTrailing: true),
        ),
      ),
    );
  }
}

/// Review list shimmer: square thumbnail + badge.
class ShimmerReviewList extends StatelessWidget {
  const ShimmerReviewList({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ShimmerListItem(circleLeading: false, leadingSize: 48, hasTrailing: true),
        ),
      ),
    );
  }
}

/// Chat conversation list shimmer.
class ShimmerChatList extends StatelessWidget {
  const ShimmerChatList({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 10,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, __) => const ShimmerListItem(hasTrailing: true),
      ),
    );
  }
}

/// Questionnaire list shimmer.
class ShimmerQuestionnaireList extends StatelessWidget {
  const ShimmerQuestionnaireList({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ShimmerListItem(hasTrailing: true),
        ),
      ),
    );
  }
}

/// Notification list shimmer.
class ShimmerNotificationList extends StatelessWidget {
  const ShimmerNotificationList({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 10,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
        itemBuilder: (_, __) => const ShimmerListItem(isThreeLine: true),
      ),
    );
  }
}

/// Overview dashboard shimmer: stat cards + feed items.
class ShimmerOverview extends StatelessWidget {
  const ShimmerOverview({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2×2 stat cards
            Row(children: [
              Expanded(child: _statCard()),
              const SizedBox(width: 12),
              Expanded(child: _statCard()),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _statCard()),
              const SizedBox(width: 12),
              Expanded(child: _statCard()),
            ]),
            const SizedBox(height: 24),
            // Section title
            const _Box(width: 100, height: 16),
            const SizedBox(height: 12),
            // Feed items
            for (int i = 0; i < 4; i++) ...[
              const ShimmerListItem(isThreeLine: true),
              if (i < 3) const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _statCard() => const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Box(width: 32, height: 32, radius: 16),
            SizedBox(height: 12),
            _Box(width: 60, height: 24),
            SizedBox(height: 6),
            _Box(width: 80, height: 12),
          ],
        ),
      );
}

/// Patient detail shimmer.
class ShimmerPatientDetail extends StatelessWidget {
  const ShimmerPatientDetail({super.key});
  @override
  Widget build(BuildContext context) {
    return _ThemedShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: const [
                  _Box(width: 56, height: 56, radius: 28),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Box(width: 100, height: 18),
                      SizedBox(height: 8),
                      _Box(width: 160, height: 12),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Action buttons
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Box(width: 64, height: 32, radius: 16),
                _Box(width: 64, height: 32, radius: 16),
                _Box(width: 64, height: 32, radius: 16),
              ],
            ),
            const SizedBox(height: 24),
            // Chart placeholder
            const _Box(width: double.infinity, height: 180, radius: 12),
            const SizedBox(height: 24),
            // Timeline items
            for (int i = 0; i < 3; i++) ...[
              const ShimmerListItem(circleLeading: false, leadingSize: 48),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
