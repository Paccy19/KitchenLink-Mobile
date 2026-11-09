import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/forms.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/server_address.dart';
import '../application/deliveries.dart';
import '../application/location.dart';
import '../application/session.dart';
import '../models/driver_account.dart';
import 'auth_screens.dart';
import 'widgets/trip_widgets.dart';

/// Who I am, how I travel, my location, help and signing out.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    // Checked against the upload rules (and the reason shown) before it is sent.
    final photo = await chooseImage(context, ref.read(mediaPickerProvider));
    if (photo == null || !context.mounted) return;
    await runAction(context, () => ref.read(driverActionsProvider).uploadPhoto(photo), success: 'Profile photo updated.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final driver = ref.watch(driverProvider);
    final stats = ref.watch(driverStatsProvider).value;
    final tracking = ref.watch(locationTrackerProvider);
    final fix = ref.watch(lastFixProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 12, 16, bottom + 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('Account', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8)),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(children: [
              Row(children: [
                Stack(children: [
                  AppImage(
                    url: driver.profileImageUrl,
                    width: 72,
                    height: 72,
                    radius: 36,
                    fallbackIcon: Icons.person_rounded,
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: IconButton.filled(
                      tooltip: 'Change profile photo',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => _changePhoto(context, ref),
                      icon: const Icon(Icons.photo_camera_rounded),
                    ),
                  ),
                ]),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driver.name, style: theme.textTheme.titleLarge?.copyWith(letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(vehicleIcon(driver.vehicleType), size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          driver.vehicleLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ]),
                    Text(driver.phone, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Row(children: [
                _Figure(value: '${stats?.completedTotal ?? driver.completedDeliveries}', label: 'Trips'),
                _Figure(value: (stats?.rating ?? driver.rating).toStringAsFixed(1), label: 'Rating'),
                _Figure(value: formatNumber(stats?.earningsTotalRwf ?? driver.totalEarningsRwf), label: 'RWF earned'),
              ]),
            ]),
          ),
          const GroupLabel('Profile'),
          _Group(children: [
            _Row(
              icon: Icons.edit_rounded,
              title: 'Edit profile and vehicle',
              subtitle: driver.email ?? 'Name, email, vehicle and plate',
              onTap: () => context.push('/account/edit'),
            ),
            _Row(
              icon: Icons.verified_rounded,
              title: 'Verification',
              trailing: StatusChip(
                label: humanize(driver.verificationStatus),
                tone: driver.verificationStatus == 'approved' ? Tone.success : Tone.warning,
                dense: true,
              ),
            ),
          ]),
          const GroupLabel('Location'),
          _Group(children: [
            _Row(
              icon: tracking.access == LocationAccess.granted ? Icons.location_on_rounded : Icons.location_off_rounded,
              title: tracking.access == LocationAccess.granted ? 'Location allowed' : 'Location not allowed',
              subtitle: tracking.message ??
                  (fix != null
                      ? 'Last sent ${timeAgo(fix.at)}'
                      : driver.locationUpdatedAt != null
                          ? 'Last sent ${timeAgo(driver.locationUpdatedAt)}'
                          : 'Shared while you are online, so offers are near you'),
              onTap: tracking.access == null || tracking.access == LocationAccess.granted || tracking.access == LocationAccess.denied
                  ? null
                  : () => ref.read(locationServiceProvider).openSettings(tracking.access!),
            ),
            _Row(
              icon: Icons.my_location_rounded,
              title: 'Share my location now',
              onTap: () => runAction(context, () async {
                final shared = await ref.read(locationTrackerProvider.notifier).shareNow();
                if (shared == null) throw 'Your location could not be read. Check that location is allowed.';
              }, success: 'Location shared.'),
            ),
          ]),
          const GroupLabel('Help'),
          _Group(children: [
            _Row(icon: Icons.history_rounded, title: 'Delivery history', onTap: () => context.push('/history')),
            _Row(icon: Icons.support_agent_rounded, title: 'Help & support', subtitle: 'Ask the KitchenLink team', onTap: () => context.push('/support')),
            const _Row(icon: Icons.dns_rounded, title: 'Server address', trailing: ServerAddressButton()),
          ]),
          const GroupLabel('Sign out'),
          _Group(children: [
            _Row(
              icon: Icons.logout_rounded,
              title: 'Sign out',
              destructive: true,
              onTap: () async {
                if (driver.isOnline &&
                    !await confirm(
                      context,
                      title: 'Sign out?',
                      message: 'You stay online until you go offline. Go offline first if you are done for the day.',
                      confirmLabel: 'Sign out',
                    )) {
                  return;
                }
                await ref.read(driverSessionProvider.notifier).logout();
              },
            ),
            _Row(
              icon: Icons.devices_rounded,
              title: 'Sign out on all devices',
              destructive: true,
              onTap: () async {
                if (await confirm(
                  context,
                  title: 'Sign out everywhere?',
                  message: 'Every phone and browser signed in to this account will be signed out.',
                  confirmLabel: 'Sign out everywhere',
                  destructive: true,
                )) {
                  await ref.read(driverSessionProvider.notifier).logout(everywhere: true);
                }
              },
            ),
          ]),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(children: [
        Text(
          value,
          maxLines: 1,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

/// An inset group of rows, separated by hairlines (like iOS Settings).
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divider = Divider(indent: 56, color: Theme.of(context).colorScheme.outlineVariant);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) divider, children[i]],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.destructive = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return ListTile(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      leading: Icon(icon, color: destructive ? scheme.error : scheme.primary),
      title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? (onTap != null && !destructive ? Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant) : null),
    );
  }
}

/// Name, email, vehicle and plate (`PATCH /driver/profile`).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final DriverAccount _initial = ref.read(driverProvider);
  late final _name = TextEditingController(text: _initial.name);
  late final _email = TextEditingController(text: _initial.email ?? '');
  late final _plate = TextEditingController(text: _initial.plateNumber);
  late VehicleType _vehicle = _initial.vehicleType ?? VehicleType.motorcycle;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final saved = await runAction(
      context,
      () => ref.read(driverActionsProvider).updateProfile(
            name: _name.text != _initial.name ? _name.text : null,
            email: _email.text.trim() != (_initial.email ?? '') ? _email.text : null,
            vehicleType: _vehicle != _initial.vehicleType ? _vehicle : null,
            plateNumber: _vehicle.hasPlate
                ? (_plate.text.trim().toUpperCase() != _initial.plateNumber ? _plate.text : null)
                : (_initial.plateNumber.isNotEmpty ? '' : null),
          ),
      success: 'Profile saved.',
    );
    if (saved != null && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _form,
        child: FormPage(children: [
          AppTextField(
            label: 'Full name',
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: Validators.nameMaxLength,
            validator: (value) => Validators.name(value, 'Your name'),
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Email (optional)',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            validator: Validators.optionalEmail,
          ),
          const SizedBox(height: 22),
          Text('Vehicle', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final type in VehicleType.values)
              ChoiceChip(
                label: Text(type.label),
                avatar: Icon(vehicleIcon(type), size: 18),
                selected: _vehicle == type,
                showCheckmark: false,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _vehicle = type);
                },
              ),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _vehicle.hasPlate
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: AppTextField(
                      label: 'Plate number',
                      controller: _plate,
                      maxLength: 20,
                      textCapitalization: TextCapitalization.characters,
                      validator: (value) => Validators.required(value, 'The plate number'),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 8),
          Text(
            'Your phone number is your sign-in. To change it, contact support.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          AsyncButton(label: 'Save', icon: Icons.check_rounded, onPressed: _save),
        ]),
      ),
    );
  }
}
