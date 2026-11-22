import 'package:flutter/material.dart';

/// Shared premium card used across diary, analytics, notes and settings.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Theme.of(context).colorScheme.surface.withValues(alpha: 0.98),
          const Color(0xFF111630),
        ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: const Color(0xFFC5A5F2).withValues(alpha: 0.10),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF050817).withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: child,
  );
}
