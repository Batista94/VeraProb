import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/super_admin/proxy_resilience_notifier.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Animated banner that slides in when the proxy enters degraded/unavailable.
///
/// - Amber glassmorphism for [ResilienceStatus.degraded]
/// - Red glassmorphism for [ResilienceStatus.unavailable]
/// - Slides out when [ResilienceStatus.healthy]
///
/// INV-10: No silent failures — degraded state is always visible.
class ContingencyBanner extends ConsumerWidget {
  const ContingencyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(proxyResilienceProvider.select((s) => s.status));
    final isVisible = status != ResilienceStatus.healthy;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      offset: isVisible ? Offset.zero : const Offset(0, -1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isVisible ? 1.0 : 0.0,
        child: isVisible
            ? _BannerContent(status: status)
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _BannerContent extends StatelessWidget {
  final ResilienceStatus status;
  const _BannerContent({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDegraded = status == ResilienceStatus.degraded;
    final accentColor = isDegraded
        ? VeraProbColors.warning
        : VeraProbColors.error;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            border: Border(
              bottom: BorderSide(color: accentColor.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isDegraded ? Icons.warning_amber_rounded : Icons.cloud_off,
                color: accentColor,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDegraded
                      ? 'Modo degradado — exibindo dados em cache. Escritas bloqueadas.'
                      : 'Serviço indisponível — circuit breaker ativo. Aguardando cooldown.',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isDegraded ? 'DEGRADED' : 'UNAVAILABLE',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
