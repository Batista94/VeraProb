import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class SkeletonListLoader extends StatelessWidget {
  final int itemCount;

  const SkeletonListLoader({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: VeraProbColors.surfaceElevated,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: VeraProbColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: VeraProbColors.border.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: VeraProbColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: VeraProbColors.border.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
