import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/uploads.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/components.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/forms.dart';
import '../../../core/widgets/pickers.dart';
import '../../menu/application/menu_providers.dart';
import '../../settings/presentation/widgets/place_search_field.dart';
import '../../settings/application/settings_providers.dart';
import '../../wallet/application/wallet_providers.dart';
import '../application/registration.dart';
import '../models/registration.dart';
import '../models/vendor_account.dart';
import 'widgets/operating_hours_editor.dart';

/// Registers a new kitchen in six short steps, then uploads everything in a
/// single multipart request.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _titles = ['Your kitchen', 'Owner & contact', 'Location', 'Food & hours', 'Payouts', 'Documents'];

  final _forms = List.generate(6, (_) => GlobalKey<FormState>());
  int _step = 0;
  bool _submitting = false;
  double? _progress;

  // Step 1
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _vendorType;
  PickedUpload? _banner;

  // Step 2
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  // Step 3
  final _address = TextEditingController();
  final _neighborhood = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  // Step 4
  final Set<String> _categoryIds = {};
  List<OperatingHour> _hours = OperatingHour.defaultWeek();

  // Step 5
  bool _bankPayout = false;
  final _accountName = TextEditingController();
  final _bankName = TextEditingController();
  final _accountNumber = TextEditingController();

  // Step 6
  final List<PickedUpload> _documents = [];

  @override
  void dispose() {
    for (final controller in [
      _name, _description, _owner, _phone, _email, _address, _neighborhood,
      _latitude, _longitude, _accountName, _bankName, _accountNumber,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _isLast => _step == _titles.length - 1;

  /// Returns the problem with the current step, or null when it can continue.
  String? _stepProblem() {
    if (!(_forms[_step].currentState?.validate() ?? false)) return 'Please fix the highlighted fields.';
    switch (_step) {
      case 0:
        if (_vendorType == null) return 'Choose your kitchen type.';
      case 3:
        if (_categoryIds.isEmpty) return 'Choose at least one food category.';
        if (_hours.every((hour) => hour.isClosed)) return 'Your kitchen must be open at least one day.';
        for (final hour in _hours.where((hour) => !hour.isClosed)) {
          if (hour.openTime.compareTo(hour.closeTime) >= 0) {
            return '${humanize(hour.day)}: closing time must be after opening time.';
          }
        }
      case 5:
        if (_documents.isEmpty) return 'Add at least one verification document.';
    }
    return null;
  }

  void _next() {
    final problem = _stepProblem();
    if (problem != null) {
      showError(context, problem);
      return;
    }
    if (_isLast) {
      _submit();
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _step++);
    }
  }

  RegistrationData _data() => RegistrationData(
        name: _name.text,
        ownerName: _owner.text,
        vendorType: _vendorType!,
        phone: _phone.text,
        email: _email.text,
        description: _description.text,
        address: _address.text,
        neighborhood: _neighborhood.text,
        latitude: double.parse(_latitude.text.trim()),
        longitude: double.parse(_longitude.text.trim()),
        foodCategoryIds: _categoryIds.toList(),
        operatingHours: _hours,
        payment: PaymentInformation(
          payoutMethod: _bankPayout ? 'bank_transfer' : 'mobile_money',
          accountName: _accountName.text.trim(),
          bankName: _bankPayout ? _bankName.text.trim() : '',
          accountNumber: _bankPayout ? _accountNumber.text.replaceAll(RegExp(r'[\s-]'), '') : '',
        ),
        banner: _banner,
        documents: _documents,
      );

  Future<void> _submit() async {
    if (_submitting) return;
    final data = _data();
    final fileProblem = data.validateFiles();
    if (fileProblem != null) {
      showError(context, fileProblem);
      return;
    }
    setState(() {
      _submitting = true;
      _progress = 0;
    });
    try {
      await ref.read(registrationActionsProvider).submit(
            data,
            onProgress: (sent, total) {
              if (mounted && total > 0) setState(() => _progress = sent / total);
            },
          );
      if (mounted) context.go('/register/done');
    } on ApiException catch (error) {
      if (!mounted) return;
      showError(context, error);
      // Send the vendor back to the step with the problem, when we can tell.
      final fields = error.fieldErrors.keys.join(' ');
      setState(() => _step = _stepForFields(fields, error.code));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progress = null;
        });
      }
    }
  }

  int _stepForFields(String fields, String code) {
    if (code == 'PHONE_ALREADY_REGISTERED' || code == 'EMAIL_ALREADY_REGISTERED' || fields.contains('phone')) return 1;
    if (fields.contains('name') || fields.contains('description') || fields.contains('vendor_type')) return 0;
    if (fields.contains('address') || fields.contains('latitude') || fields.contains('longitude')) return 2;
    if (fields.contains('food_categories') || fields.contains('operating_hours')) return 3;
    if (fields.contains('payment')) return 4;
    if (fields.contains('document') || fields.contains('file')) return 5;
    return _step;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _step == 0 && !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_submitting) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_step]),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _submitting ? null : () => _step == 0 ? context.go('/login') : setState(() => _step--),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _submitting && _progress != null ? _progress : (_step + 1) / _titles.length,
              minHeight: 4,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: FormPage(children: [
                Text(
                  'Step ${_step + 1} of ${_titles.length}',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.secondary),
                ),
                const SizedBox(height: 12),
                Form(key: _forms[_step], child: _stepBody()),
              ]),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              child: Row(children: [
                if (_step > 0)
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: _submitting ? null : () => setState(() => _step--),
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: FilledButton(
                    onPressed: _submitting ? null : _next,
                    child: _submitting
                        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            Text(_progress == null ? 'Submitting…' : 'Uploading ${(_progress! * 100).round()}%'),
                          ])
                        : Text(_isLast ? 'Submit application' : 'Continue'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _stepBody() => switch (_step) {
        0 => _kitchenStep(),
        1 => _ownerStep(),
        2 => _locationStep(),
        3 => _foodStep(),
        4 => _payoutStep(),
        _ => _documentsStep(),
      };

  // ----------------------------------------------------------------- step 1

  Widget _kitchenStep() {
    final types = ref.watch(vendorTypesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppTextField(
        label: 'Kitchen name',
        controller: _name,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        maxLength: Validators.nameMaxLength,
        validator: (value) => Validators.name(value, 'Kitchen name'),
      ),
      const SizedBox(height: 16),
      types.when(
        loading: () => const SkeletonBox(height: 56, radius: 14),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(vendorTypesProvider)),
        data: (list) => DropdownButtonFormField<String>(
          initialValue: _vendorType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kitchen type'),
          items: [
            for (final type in list) DropdownMenuItem(value: type.code, child: Text(type.label)),
          ],
          onChanged: (value) => setState(() => _vendorType = value),
          validator: (value) => value == null ? 'Choose your kitchen type.' : null,
        ),
      ),
      if (_vendorType != null)
        types.maybeWhen(
          data: (list) {
            final type = list.firstWhere((entry) => entry.code == _vendorType, orElse: () => list.first);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(type.description, style: Theme.of(context).textTheme.bodySmall),
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
      const SizedBox(height: 16),
      AppTextField(
        label: 'What do you cook?',
        helper: 'A short description customers will read (at least 10 characters).',
        controller: _description,
        maxLines: 4,
        minLines: 3,
        maxLength: 1000,
        textCapitalization: TextCapitalization.sentences,
        validator: (value) => Validators.length(value, 'Description', min: 10, max: 1000),
      ),
      const SizedBox(height: 16),
      Text('Kitchen banner (optional)', style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      ImagePickerBox(
        picked: _banner,
        label: 'Add a banner photo',
        onTap: () async {
          final file = await chooseImage(context, ref.read(mediaPickerProvider), rules: UploadRules.registrationBanner);
          if (file != null) setState(() => _banner = file);
        },
        onRemove: () => setState(() => _banner = null),
      ),
    ]);
  }

  // ----------------------------------------------------------------- step 2

  Widget _ownerStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppTextField(
          label: 'Owner full name',
          controller: _owner,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: Validators.nameMaxLength,
          validator: (value) => Validators.name(value, 'Owner name'),
        ),
        const SizedBox(height: 16),
        PhoneField(controller: _phone, label: 'Kitchen phone number'),
        const SizedBox(height: 6),
        Text(
          'You will sign in with this number. Mobile-money payouts go to it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Email (optional)',
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          prefix: const Icon(Icons.mail_outline_rounded),
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
          validator: Validators.optionalEmail,
        ),
      ]);

  // ----------------------------------------------------------------- step 3

  Widget _locationStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const NoteBox(
          message: 'Customers find you at this location. Search for your area or street to fill in the '
              'coordinates, then check them.',
        ),
        const SizedBox(height: 16),
        PlaceSearchField(
          onPicked: (place) => setState(() {
            _latitude.text = place.lat.toStringAsFixed(6);
            _longitude.text = place.lng.toStringAsFixed(6);
            if (_neighborhood.text.isEmpty && place.kind == 'area') _neighborhood.text = place.name;
            if (_address.text.isEmpty) {
              _address.text = [place.name, place.secondary].where((part) => part.isNotEmpty).join(', ');
            }
          }),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Street address',
          controller: _address,
          textCapitalization: TextCapitalization.words,
          maxLength: 200,
          validator: (value) => Validators.length(value, 'Address', min: 3, max: 200),
        ),
        const SizedBox(height: 4),
        AppTextField(
          label: 'Neighbourhood',
          controller: _neighborhood,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
        ),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AppTextField(
              label: 'Latitude',
              controller: _latitude,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: Validators.latitude,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppTextField(
              label: 'Longitude',
              controller: _longitude,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: Validators.longitude,
            ),
          ),
        ]),
      ]);

  // ----------------------------------------------------------------- step 4

  Widget _foodStep() {
    final categories = ref.watch(foodCategoriesProvider);
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Food categories', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text('Pick everything you sell.', style: theme.textTheme.bodySmall),
      const SizedBox(height: 10),
      categories.when(
        loading: () => const SkeletonBox(height: 90, radius: 14),
        error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(foodCategoriesProvider)),
        data: (list) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final category in list)
            FilterChip(
              label: Text(category.name),
              selected: _categoryIds.contains(category.id),
              onSelected: (selected) => setState(
                () => selected ? _categoryIds.add(category.id) : _categoryIds.remove(category.id),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 24),
      Text('Opening hours', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      OperatingHoursEditor(hours: _hours, onChanged: (hours) => setState(() => _hours = hours)),
    ]);
  }

  // ----------------------------------------------------------------- step 5

  Widget _payoutStep() {
    final theme = Theme.of(context);
    final localPhone = Validators.isValidPhone(_phone.text) ? Validators.toLocalPhone(_phone.text) : null;
    final banks = ref.watch(bankListProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('How should we pay you?', style: theme.textTheme.titleMedium),
      const SizedBox(height: 10),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Mobile money'), icon: Icon(Icons.smartphone_rounded)),
          ButtonSegment(value: true, label: Text('Bank transfer'), icon: Icon(Icons.account_balance_rounded)),
        ],
        selected: {_bankPayout},
        onSelectionChanged: (value) => setState(() => _bankPayout = value.first),
      ),
      const SizedBox(height: 16),
      AppTextField(
        label: 'Account holder name',
        controller: _accountName,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        validator: (value) => Validators.length(value, 'Account name', min: 2, max: 80),
      ),
      if (!_bankPayout)
        NoteBox(
          message: localPhone == null
              ? 'Mobile-money payouts go to the phone number you registered with.'
              : 'Mobile-money payouts go to your registered phone: $localPhone.',
          icon: Icons.smartphone_rounded,
        )
      else ...[
        const SizedBox(height: 4),
        banks.maybeWhen(
          data: (list) => Autocomplete<String>(
            optionsBuilder: (value) => list.banks
                .map((bank) => bank.name)
                .where((name) => name.toLowerCase().contains(value.text.toLowerCase())),
            onSelected: (name) => _bankName.text = name,
            fieldViewBuilder: (context, controller, focus, onSubmit) {
              if (controller.text.isEmpty && _bankName.text.isNotEmpty) controller.text = _bankName.text;
              return AppTextField(
                label: 'Bank name',
                controller: controller,
                onChanged: (value) => _bankName.text = value,
                validator: (value) => Validators.length(value, 'Bank name', min: 2, max: 60),
              );
            },
          ),
          orElse: () => AppTextField(
            label: 'Bank name',
            controller: _bankName,
            validator: (value) => Validators.length(value, 'Bank name', min: 2, max: 60),
          ),
        ),
        const SizedBox(height: 4),
        AppTextField(
          label: 'Account number',
          controller: _accountNumber,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]'))],
          validator: (value) {
            final digits = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
            if (!RegExp(r'^\d{4,30}$').hasMatch(digits)) return 'Enter the account number (4–30 digits).';
            final bank = banks.value?.banks.where((b) => b.name.toLowerCase() == _bankName.text.trim().toLowerCase());
            return (bank != null && bank.isNotEmpty) ? bank.first.validateAccountNumber(digits) : null;
          },
        ),
      ],
    ]);
  }

  // ----------------------------------------------------------------- step 6

  Future<void> _addDocuments() async {
    try {
      final files = await ref.read(mediaPickerProvider).pickDocuments();
      if (files.isEmpty || !mounted) return;
      final accepted = <PickedUpload>[];
      for (final file in files) {
        final problem = file.validate(UploadRules.document);
        if (problem != null) {
          showError(context, problem);
        } else if (_documents.any((existing) => existing.path == file.path)) {
          continue;
        } else {
          accepted.add(file);
        }
      }
      setState(() {
        _documents.addAll(accepted);
        if (_documents.length > UploadRules.maxDocuments) {
          _documents.removeRange(UploadRules.maxDocuments, _documents.length);
          showError(context, 'You can upload at most ${UploadRules.maxDocuments} documents.');
        }
      });
    } catch (error) {
      if (mounted) showError(context, 'Could not open your files.');
    }
  }

  Widget _documentsStep() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const NoteBox(
        title: 'Verification documents',
        message: 'Upload your ID and any business licence or permit (JPG, PNG, WebP or PDF, up to 10 MB each). '
            'An admin reviews them privately before your kitchen goes live.',
        icon: Icons.verified_user_outlined,
      ),
      const SizedBox(height: 16),
      for (final document in _documents)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(document.isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(document.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  Text('${(document.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB', style: theme.textTheme.bodySmall),
                ]),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: _submitting ? null : () => setState(() => _documents.remove(document)),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _submitting || _documents.length >= UploadRules.maxDocuments ? null : _addDocuments,
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(_documents.isEmpty ? 'Add documents' : 'Add more'),
      ),
    ]);
  }
}

/// Shown after the backend accepted the application.
class RegistrationDoneScreen extends StatelessWidget {
  const RegistrationDoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = toneColors(context, Tone.success);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(padding: const EdgeInsets.all(28), shrinkWrap: true, children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: success.background, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 44, color: success.foreground),
                ),
              ),
              const SizedBox(height: 24),
              Text('Application submitted', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text(
                'Your kitchen was registered and its documents are now under review. '
                'You can sign in right away to build your menu; the rest of the app unlocks once your account is approved.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
            ]),
          ),
        ),
      ),
    );
  }
}
