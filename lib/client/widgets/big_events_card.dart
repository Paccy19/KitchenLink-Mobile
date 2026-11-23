import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../client_theme.dart';

/// "KitchenLink Big Events": the website's banner under the benefits strip,
/// as a phone card under the promotions. It opens the existing Big Events
/// listing (every kitchen that takes event orders).
class BigEventsCard extends StatelessWidget {
  const BigEventsCard({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _brown = Color(0xFF2B1206);
  static const _orange = Color(0xFFF28C18);
  static const _orangeLight = Color(0xFFF7A23B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'KitchenLink Big Events. Planning something special? Explore Big Events',
      child: PressScale(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _brown,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [BoxShadow(color: Color(0x332B1206), blurRadius: 24, offset: Offset(0, 12))],
          ),
          child: Stack(children: [
            // Warm glows, as on the website's banner.
            Positioned(
              left: -40,
              top: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _orange.withValues(alpha: 0.18)),
              ),
            ),
            Positioned(
              right: -30,
              bottom: -50,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _orange.withValues(alpha: 0.12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_orangeLight, Color(0xFFE07B0C)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.celebration_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'KitchenLink\n'),
                        TextSpan(text: 'Big Events', style: kText(17, weight: w900, color: _orangeLight, height: 1.15)),
                      ]),
                      style: kText(17, weight: w900, color: Colors.white, height: 1.15),
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.event_available_rounded, color: _orange, size: 24),
                  ),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _orange.withValues(alpha: 0.4)),
                  ),
                  child: Text('SPECIAL EXPERIENCES', style: kText(10, weight: w900, color: const Color(0xFFFFC27A), spacing: 1.2)),
                ),
                const SizedBox(height: 8),
                Text('Planning something special?', style: kText(20, weight: w900, color: Colors.white, height: 1.2, spacing: -0.4)),
                const SizedBox(height: 6),
                Text(
                  'Discover food events, catering experiences and special occasions hosted by local kitchens.',
                  style: kText(13, color: const Color(0xFFEBD7C5), height: 1.45),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [BoxShadow(color: _orange.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(
                        'Explore Big Events',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kText(14, weight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                  ]),
                ),
              ]),
            ),
          ]),
          ),
        ),
      ),
    );
  }
}
