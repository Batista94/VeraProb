import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/providers/onboarding_provider.dart';

/// Slim top bar verifying 5 core master data and contract prerequisites.
/// Renders as a 60px card anchored above the main content — no layout displacement.
/// Auto-removes from DOM when all prerequisites are met.
class OnboardingProgressBanner extends ConsumerWidget {
  final ValueChanged<int> onNavigate;

  const OnboardingProgressBanner({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(onboardingProgressProvider);

    if (progress.isComplete) {
      return const SizedBox.shrink(); // All green — remove from DOM
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _SlimBar(
        key: const ValueKey('onboarding_bar'),
        progress: progress,
        onNavigate: onNavigate,
      ),
    );
  }
}

class _SlimBar extends StatelessWidget {
  final OnboardingProgress progress;
  final ValueChanged<int> onNavigate;

  const _SlimBar({super.key, required this.progress, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // Progress indicator
            SizedBox(
              width: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuração  ${progress.completedCount}/${progress.steps.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.completedCount / progress.steps.length,
                      backgroundColor: VeraProbColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        VeraProbColors.primary,
                      ),
                      minHeight: 3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            // Prerequisite dots
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: progress.steps
                      .map(
                        (p) =>
                            _PrerequisiteDot(step: p, onNavigate: onNavigate),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrerequisiteDot extends StatelessWidget {
  final OnboardingStep step;
  final ValueChanged<int> onNavigate;

  const _PrerequisiteDot({required this.step, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final color = step.isFulfilled
        ? VeraProbColors.success
        : VeraProbColors.error;

    return Tooltip(
      message: step.isFulfilled
          ? '${step.label}: configurado'
          : '${step.label}: pendente — clique para configurar',
      child: InkWell(
        // Fulfilled items are NOT interactive
        onTap: step.isFulfilled
            ? null
            : () => onNavigate(step.destination.index),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                step.isFulfilled
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                step.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: step.isFulfilled
                      ? VeraProbColors.textSecondary
                      : color,
                  decoration: step.isFulfilled
                      ? TextDecoration.none
                      : TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
