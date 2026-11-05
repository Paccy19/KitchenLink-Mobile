import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/uploads.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../../core/widgets/pickers.dart';
import '../../auth/application/session.dart';
import '../../auth/models/vendor_account.dart';
import '../../auth/presentation/widgets/operating_hours_editor.dart';
import '../application/settings_providers.dart';

/// Account details: profile text, photos, opening hours, payout details.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final VendorAccount _vendor = ref.read(vendorProvider);
  late final _name = TextEditingController(text: _vendor.name);
  late final _owner = TextEditingController(text: _vendor.ownerName);
  late final _description = TextEditingController(text: _vendor.description);
  late final _phone = TextEditingController(text: _vendor.phone);
  late final _accountName = TextEditingController(text: _vendor.paymentInformation.accountName);
  late final _bankName = TextEditingController(text: _vendor.paymentInformation.bankName);
  late final _accountNumber = TextEditingController(text: _vendor.paymentInformation.accountNumber);
  late bool _bank = _vendor.paymentInformation.isBank;
  late List<OperatingHour> _hours = OperatingHour.completeWeek(_vendor.operatingHours);
  PickedUpload? _banner;
  PickedUpload? _profile;
  bool _saving = false;
  double? _progress;

  @override
  void dispose() {
    for (final c in [_name, _owner, _description, _phone, _accountName, _bankName, _accountNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool banner) async {
    final file = await chooseImage(context, ref.read(mediaPickerProvider));
    if (file == null) return;
    setState(() => banner ? _banner = file : _profile = file);
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_hours.every((hour) => hour.isClosed)) {
      showError(context, 'Your kitchen must be open at least one day.');
      return;
    }
    for (final hour in _hours.where((h) => !h.isClosed)) {
      if (hour.openTime.compareTo(hour.closeTime) >= 0) {
        showError(context, '${humanize(hour.day)}: closing time must be after opening time.');
        return;
      }
    }
    final phone = Validators.toLocalPhone(_phone.text);
    final payment = _bank
        ? PaymentInformation(
            payoutMethod: 'bank_transfer',
            accountName: _accountName.text.trim(),
            bankName: _bankName.text.trim(),
            accountNumber: _accountNumber.text.replaceAll(RegExp(r'[\s-]'), ''),
          )
        : PaymentInformation(payoutMethod: 'mobile_money', accountName: _accountName.text.trim(), mobileMoneyNumber: phone);
    setState(() {
      _saving = true;
      _progress = null;
    });
    final actions = ref.read(settingsActionsProvider);
    final saved = await runAction(context, () async {
      await actions.updateProfile({
        'name': _name.text.trim(),
        'owner_name': _owner.text.trim(),
        'description': _description.text.trim(),
        'phone': phone,
        'operating_hours': [for (final hour in _hours) hour.toJson()],
        'payment_information': payment.toJson(),
      });
      if (_banner != null || _profile != null) {
        await actions.updateImages(
          banner: _banner,
          profile: _profile,
          onProgress: (sent, total) {
            if (mounted && total > 0) setState(() => _progress = sent / total);
          },
        );
      }
      return true;
    }, success: 'Account details saved.');
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved == true) {
        _banner = null;
        _profile = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAct = ref.watch(canActProvider);
    final vendor = ref.watch(vendorProvider);
    final (tone, icon) = switch (vendor.verificationStatus) {
      VerificationStatus.approved => (Tone.success, Icons.verified_rounded),
      VerificationStatus.pending => (Tone.warning, Icons.hourglass_top_rounded),
      _ => (Tone.danger, Icons.block_rounded),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Account details')),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: FormPage(children: [
                AppCard(
                  child: Row(children: [
                    StatusChip(label: vendor.verificationStatus.label, tone: tone, icon: icon),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Joined ${formatDate(vendor.createdAt)}', style: theme.textTheme.bodySmall)),
                  ]),
                ),
                if (!canAct) ...[
                  const SizedBox(height: 12),
                  const NoteBox(message: 'You can change your details once your account is approved.', tone: Tone.warning, icon: Icons.hourglass_top_rounded),
                ],
                const SectionHeader('Photos'),
                ImagePickerBox(
                  height: 130,
                  picked: _banner,
                  label: 'Kitchen banner',
                  existingWidget: vendor.bannerImageUrl == null ? null : AppImage(url: vendor.bannerImageUrl, radius: 0),
                  onTap: canAct ? () => _pick(true) : () {},
                  onRemove: () => setState(() => _banner = null),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  SizedBox(
                    width: 96,
                    child: ImagePickerBox(
                      height: 96,
                      picked: _profile,
                      label: 'Logo',
                      existingWidget: vendor.profileImageUrl == null ? null : AppImage(url: vendor.profileImageUrl, radius: 0),
                      onTap: canAct ? () => _pick(false) : () {},
                      onRemove: () => setState(() => _profile = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Your logo or profile photo, shown next to your kitchen name.', style: theme.textTheme.bodySmall)),
                ]),
                const SectionHeader('About your kitchen'),
                AppTextField(label: 'Kitchen name', controller: _name, enabled: canAct, maxLength: Validators.nameMaxLength, validator: (v) => Validators.name(v, 'Kitchen name')),
                AppTextField(label: 'Owner name', controller: _owner, enabled: canAct, maxLength: Validators.nameMaxLength, textCapitalization: TextCapitalization.words, validator: (v) => Validators.name(v, 'Owner name')),
                AppTextField(label: 'Description', controller: _description, enabled: canAct, maxLength: 1000, maxLines: 4, minLines: 3, textCapitalization: TextCapitalization.sentences),
                const SizedBox(height: 4),
                PhoneField(controller: _phone, label: 'Sign-in phone number', enabled: canAct),
                const SizedBox(height: 4),
                Text('Changing this changes the number you sign in with and receive mobile-money payouts on.', style: theme.textTheme.bodySmall),
                const SectionHeader('Opening hours'),
                OperatingHoursEditor(hours: _hours, enabled: canAct, onChanged: (hours) => setState(() => _hours = hours)),
                const SectionHeader('Payout details'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Mobile money'), icon: Icon(Icons.smartphone_rounded)),
                    ButtonSegment(value: true, label: Text('Bank'), icon: Icon(Icons.account_balance_rounded)),
                  ],
                  selected: {_bank},
                  onSelectionChanged: canAct ? (v) => setState(() => _bank = v.first) : null,
                ),
                const SizedBox(height: 12),
                AppTextField(label: 'Account holder name', controller: _accountName, enabled: canAct, textCapitalization: TextCapitalization.words, validator: (v) => Validators.length(v, 'Account name', min: 2, max: 80)),
                if (_bank) ...[
                  AppTextField(label: 'Bank name', controller: _bankName, enabled: canAct, validator: (v) => Validators.length(v, 'Bank name', min: 2, max: 60)),
                  AppTextField(
                    label: 'Account number',
                    controller: _accountNumber,
                    enabled: canAct,
                    keyboardType: TextInputType.number,
                    validator: (v) => RegExp(r'^\d{4,30}$').hasMatch((v ?? '').replaceAll(RegExp(r'[\s-]'), '')) ? null : 'Enter the account number (4–30 digits).',
                  ),
                ] else
                  const NoteBox(message: 'Mobile-money payouts go to your sign-in phone number.', icon: Icons.smartphone_rounded),
                if (vendor.documents.isNotEmpty) ...[
                  const SectionHeader('Verification documents'),
                  for (final document in vendor.documents)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(document.fileType == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.image_rounded),
                      title: Text(document.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Uploaded ${formatDate(document.uploadedAt)}'),
                    ),
                ],
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: FilledButton(
              onPressed: (!canAct || _saving) ? null : _save,
              child: _saving
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                      const SizedBox(width: 10),
                      Text(_progress == null ? 'Saving…' : 'Uploading ${(_progress! * 100).round()}%'),
                    ])
                  : const Text('Save changes'),
            ),
          ),
        ]),
      ),
    );
  }
}
