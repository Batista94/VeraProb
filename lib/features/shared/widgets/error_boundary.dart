import 'package:flutter/material.dart';
import 'package:busflow/core/theme/app_theme.dart';

/// A wrapper widget that catches unhandled Flutter errors during the build phase.
/// Prevents the entire screen from turning into the "Red Screen of Death".
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(FlutterErrorDetails errorDetails)? errorBuilder;

  const ErrorBoundary({Key? key, required this.child, this.errorBuilder})
    : super(key: key);

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  FlutterErrorDetails? _error;

  @override
  void initState() {
    super.initState();
    // Intercept local widget build errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _error = details;
          });
        }
      });
      // Return an empty container temporarily while setState triggers
      return const SizedBox.shrink();
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(_error!);
      }
      return _DefaultErrorWidget(error: _error!);
    }

    return widget.child;
  }
}

class _DefaultErrorWidget extends StatelessWidget {
  final FlutterErrorDetails error;

  const _DefaultErrorWidget({Key? key, required this.error}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BusFlowColors.background,
        border: Border.all(color: BusFlowColors.error.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: BusFlowColors.error,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            'Falha de Renderização de Componente',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: BusFlowColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.exceptionAsString(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: BusFlowColors.textSecondary,
              fontFamily: 'monospace',
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
