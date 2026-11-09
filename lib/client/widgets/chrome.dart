import 'package:flutter/material.dart';

import '../client_theme.dart';
import '../location.dart';

/// The website's Footer, stacked in one column as on a phone.
class MarketFooter extends StatelessWidget {
  const MarketFooter({super.key, required this.onLink});

  final ValueChanged<String> onLink;

  @override
  Widget build(BuildContext context) {
    final heading = kText(14, weight: w900, color: Colors.white, spacing: 0.6);
    final body = kText(12, weight: FontWeight.w400, color: K.stone400, height: 1.6);
    Widget link(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => onLink(label),
        child: Text(label, style: kText(12, color: K.stone400)),
      ),
    );
    Widget pay(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: kText(12, weight: FontWeight.w700, color: Color.lerp(color, Colors.white, 0.25)!),
      ),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 64, 16, 48 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: K.footer,
        border: Border(top: BorderSide(color: K.brown850.withValues(alpha: 0.6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand.
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [K.brown850, K.brown600]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.restaurant, size: 20, color: K.brown100),
              ),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Kitchen'),
                    TextSpan(
                      text: 'Link',
                      style: kText(20, weight: w900, color: K.brown500),
                    ),
                  ],
                ),
                style: kText(20, weight: w900, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text("Rwanda's multi-vendor marketplace connecting home cooks, culinary chefs, bakeries and restaurants directly with food lovers.", style: body),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 16, color: K.brown500),
              const SizedBox(width: 8),
              Text(
                'Kigali, Rwanda',
                style: kText(12, weight: FontWeight.w400, color: K.stone400),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // For customers.
          Text('FOR FOOD LOVERS', style: heading),
          const SizedBox(height: 16),
          link('Browse Home Kitchens'),
          link("Tomorrow's Specials (Pre-Order)"),
          link('Order Tracking & History'),
          link('Saved Addresses & Preferences'),
          const SizedBox(height: 22),
          // Coverage.
          Text('WE DELIVER ACROSS KIGALI', style: heading),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final district in kigaliDistricts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: K.stone900.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: K.stone800),
                  ),
                  child: Text(
                    district,
                    style: kText(11, weight: FontWeight.w400, color: K.stone300),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Every neighbourhood in all three districts. Order from home kitchens near you, wherever you are in the city.', style: body),
          const SizedBox(height: 32),
          // Payments.
          Text('SUPPORTED PAYMENTS', style: heading),
          const SizedBox(height: 16),
          Text(
            'Pay with Mobile Money, cards, eKash, or your wallet:',
            style: kText(12, weight: FontWeight.w400, color: K.stone400),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pay('Mobile Money', const Color(0xFFFACC15)),
              pay('Cards', const Color(0xFF60A5FA)),
              pay('eKash', const Color(0xFFC084FC)),
              pay('Wallet', const Color(0xFF34D399)),
            ],
          ),
          const SizedBox(height: 48),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 32),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: K.brown850.withValues(alpha: 0.6))),
            ),
            child: Column(
              children: [
                Text(
                  '© ${DateTime.now().year} KitchenLink. All rights reserved.',
                  style: kText(12, weight: FontWeight.w400, color: K.stone500),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Made with ',
                      style: kText(12, weight: FontWeight.w400, color: K.stone500),
                    ),
                    const Icon(Icons.favorite, size: 14, color: K.red500),
                    Text(
                      ' for Kigali Food Culture',
                      style: kText(12, weight: FontWeight.w400, color: K.stone500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
