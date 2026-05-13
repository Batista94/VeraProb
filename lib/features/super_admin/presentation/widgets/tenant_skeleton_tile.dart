import 'dart:io';
import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Shimmer-animated skeleton tile matching [_TenantListTile] structure.
///
/// Uses [VeraProbColors.surface] as base and [VeraProbColors.surfaceElevated]
/// as highlight for the industrial dark palette.
class TenantSkeletonTile extends StatefulWidget {
  final int index;

  const TenantSkeletonTile({super.key, required this.index});

  @override
  State<TenantSkeletonTile> createState() => _TenantSkeletonTileState();
}

class _TenantSkeletonTileState extends State<TenantSkeletonTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Only repeat animation if not in a test environment to ensure deterministic goldens
    if (!RegExp(
      r'(_test.dart|test_config.dart)',
    ).hasMatch(Platform.script.path)) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando organização',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  VeraProbColors.surface,
                  VeraProbColors.surfaceElevated,
                  VeraProbColors.surface,
                ],
                stops: [
                  _controller.value - 0.3,
                  _controller.value,
                  _controller.value + 0.3,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: VeraProbColors.surface,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 13,
                      margin: const EdgeInsets.only(right: 40),
                      decoration: BoxDecoration(
                        color: VeraProbColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 60,
                      height: 11,
                      decoration: BoxDecoration(
                        color: VeraProbColors.surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders 5 skeleton tiles as loading placeholder for tenant list.
class TenantSkeletonList extends StatelessWidget {
  const TenantSkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('tenant-skeleton-loading'),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, index) => TenantSkeletonTile(
        key: ValueKey('tenant-skeleton-$index'),
        index: index,
      ),
    );
  }
}
