import 'package:flutter/material.dart';

/// Skeleton loader displayed while routes are being fetched.
class RouteSkeleton extends StatelessWidget {
  const RouteSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}
