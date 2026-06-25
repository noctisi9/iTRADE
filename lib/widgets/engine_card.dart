import 'package:flutter/material.dart';
import '../theme.dart';

/// White rounded-xl card used for Engine 1 (AO) / Engine 2 (AC).
class EngineCard extends StatelessWidget {
  final String label; // e.g. "ENGINE 1"
  final Widget child;
  final Widget? footer;
  final bool highlighted;

  const EngineCard({
    super.key,
    required this.label,
    required this.child,
    this.footer,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: highlighted ? AppColors.borderBright : AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: AppColors.red,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          child,
          if (footer != null) ...[
            const SizedBox(height: 8),
            footer!,
          ],
        ],
      ),
    );
  }
}
