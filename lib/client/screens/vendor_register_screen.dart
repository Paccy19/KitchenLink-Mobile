import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../api/api_client.dart';
import '../../config.dart';
import '../../ui/validation.dart';
import '../../ui/vendor_types.dart';
import '../client_theme.dart';
import '../vendor_type_info.dart';
import '../widgets/form_fields.dart';
import '../widgets/kitchen_location_fields.dart';
import 'vendor_login_screen.dart' show ChefHatIcon;

const _bankAccountMaxLength = 20;
const _maxDocumentMb = 5;

/// "0788123456" from any Rwandan phone format ('' when not valid yet).
String localPhone(String value) {
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('250')) digits = digits.substring(3);
  if (!digits.startsWith('0')) digits = '0$digits';
  return RegExp(r'^07\d{8}$').hasMatch(digits) ? digits : '';
}

/// Mobile network of a Rwandan number: 078/079 MTN, 072/073 Airtel.
String networkOf(String phone) {
  final local = localPhone(phone);
  if (RegExp(r'^07[89]').hasMatch(local)) return 'MTN Mobile Money';
  if (RegExp(r'^07[23]').hasMatch(local)) return 'Airtel Money';
  return '';
}

const _payoutMethods = ['MTN Mobile Money', 'Airtel Money', 'Bank Transfer'];

/// A verification document picked on the phone.
class PickedDocument {
  const PickedDocument(this.name, this.bytes);

  final String name;
  final List<int> bytes;
}

/// Opens the phone's file picker; returns the chosen documents ([] when cancelled).
typedef DocumentPicker = Future<List<PickedDocument>> Function();

Future<List<PickedDocument>> _pickWithFilePicker() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
  );
  return [for (final f in files) PickedDocument(f.name, await f.readAsBytes())];
}

/// The website's /vendor-register page ("Become a Vendor"): business details,
/// operations, then verification & payout, and the "You're all set" summary.
class VendorRegisterScreen extends StatefulWidget {
  const VendorRegisterScreen({
    super.key,
    this.client,
    this.pickDocuments,
    this.onLogin,
  });

  /// Defaults to the app's API address.
  final ApiClient? client;

  /// Defaults to the phone's file picker.
  final DocumentPicker? pickDocuments;

  /// "Log in" / "Go to Vendor Login". Defaults to going back.
  final VoidCallback? onLogin;

  @override
  State<VendorRegisterScreen> createState() => _VendorRegisterScreenState();
}

class _VendorRegisterScreenState extends State<VendorRegisterScreen> {
  late final ApiClient _client =
      widget.client ?? ApiClient(baseUrl: kDefaultApiBaseUrl);
  final _scroll = ScrollController();

  int _step = 1;
  Map<String, String> _errors = {};
  bool _submitting = false;
  Map<String, dynamic>? _created;

  // Step 1.
  final _name = TextEditingController();
  String _type = '';
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _description = TextEditingController();

  // Step 2.
  final _area = TextEditingController();
  final _address = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  List<({String name, List<String> vendorTypes})> _categories = const [];
  final List<String> _foodCategories = [];
  bool _showAllCategories = false;
  String _openTime = '08:00';
  String _closeTime = '20:00';

  // Step 3.
  String _payoutMethod = 'MTN Mobile Money';
  final _payoutNumber = TextEditingController();
  final _payoutPhone = TextEditingController();
  final List<PickedDocument> _documents = [];
  bool _agree = false;

  bool get _isBankPayout => _payoutMethod == 'Bank Transfer';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _owner,
      _phone,
      _email,
      _description,
      _area,
      _address,
      _lat,
      _lng,
      _payoutNumber,
      _payoutPhone,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await _client.request('/home/categories');
      final list = data is Map && data['categories'] is List
          ? data['categories'] as List
          : const [];
      if (!mounted) return;
      setState(
        () => _categories = [
          for (final c in list)
            if (c is Map && (c['name'] ?? '').toString().isNotEmpty)
              (
                name: c['name'].toString(),
                vendorTypes: [
                  for (final t in (c['vendor_types'] as List? ?? const []))
                    t.toString(),
                ],
              ),
        ],
      );
    } catch (_) {
      // Categories are best-effort, as on the website.
    }
  }

  void _clearError(String key) {
    if (_errors.containsKey(key)) {
      setState(() => _errors = {..._errors}..remove(key));
    }
  }

  // ------------------------------------------------------------- validation

  bool _validate(int step) {
    final next = <String, String>{};
    if (step == 1) {
      if (_name.text.trim().isEmpty) {
        next['name'] = 'Business name is required.';
      }
      if (_type.isEmpty) {
        next['type'] = 'Choose the type of food business you run.';
      }
      if (_owner.text.trim().isEmpty) next['owner'] = 'Owner name is required.';
      if (_phone.text.trim().isEmpty) {
        next['phone'] = 'Phone number is required.';
      } else if (!isValidRwandaPhone(_phone.text)) {
        next['phone'] = phoneError;
      }
      if (_email.text.trim().isNotEmpty && !isValidEmail(_email.text)) {
        next['email'] = emailError;
      }
      if (_description.text.trim().length < 10) {
        next['description'] = 'Please write at least 10 characters.';
      }
    }
    if (step == 2) {
      if (_area.text.trim().isEmpty) {
        next['location'] = 'Your area is required.';
      }
      if (parseCoords(_lat.text, _lng.text) == null) next['coords'] = "Enter your kitchen's latitude and longitude, or pick it on the map.";
      if (_foodCategories.isEmpty) {
        next['categories'] = 'Select at least one food category.';
      }
    }
    if (step == 3) {
      final network = networkOf(_phone.text);
      if (_isBankPayout) {
        if (_payoutNumber.text.trim().isEmpty) {
          next['payout'] = 'Bank account number is required.';
        } else if (_payoutNumber.text.length < 6) {
          next['payout'] = 'Enter a valid bank account number.';
        }
      } else if (localPhone(_phone.text).isEmpty) {
        next['payout'] = 'Enter a valid phone number in step 1 first — payouts go to that number.';
      } else if (network.isNotEmpty && network != _payoutMethod) {
        next['payout'] =
            '${localPhone(_phone.text)} is an ${network.split(' ').first} number — choose $network, or Bank Transfer.';
      }
      if (_documents.isEmpty) {
        next['documents'] = 'Upload at least one verification document.';
      }
      if (!_agree) next['agree'] = 'Please accept the vendor agreement.';
    }
    setState(() => _errors = next);
    return next.isEmpty;
  }

  void _goNext() {
    if (!_validate(_step)) {
      _toast('Please fix the highlighted fields.');
      return;
    }
    setState(() => _step = (_step + 1).clamp(1, 3));
    _scrollToTop();
  }

  void _goBack() {
    setState(() {
      _errors = {};
      _step = (_step - 1).clamp(1, 3);
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickDocuments() async {
    try {
      final picked = await (widget.pickDocuments ?? _pickWithFilePicker)();
      if (!mounted || picked.isEmpty) return;
      final tooBig = picked
          .where((d) => d.bytes.length > _maxDocumentMb * 1024 * 1024)
          .map((d) => d.name)
          .toList();
      setState(() {
        _documents.addAll(
          picked.where((d) => d.bytes.length <= _maxDocumentMb * 1024 * 1024),
        );
        _errors = {..._errors}..remove('documents');
      });
      if (tooBig.isNotEmpty) {
        _toast(
          '${tooBig.join(', ')} ${tooBig.length == 1 ? 'is' : 'are'} over $_maxDocumentMb MB.',
        );
      }
    } catch (_) {
      if (mounted) _toast('Could not open your files. Please try again.');
    }
  }

  // ----------------------------------------------------------------- submit

  Future<void> _submit() async {
    if (_submitting || !_validate(3)) return;
    final coords = parseCoords(_lat.text, _lng.text)!;
    setState(() => _submitting = true);
    try {
      final fields = <String, String>{
        'name': _name.text.trim(),
        'owner_name': _owner.text.trim(),
        'vendor_type': _type,
        'phone': _phone.text.trim(),
        if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        'description': _description.text.trim(),
        'location': jsonEncode({
          'neighborhood': _area.text.trim(),
          'address': _address.text.trim().isEmpty
              ? _area.text.trim()
              : _address.text.trim(),
          'latitude': coords.lat,
          'longitude': coords.lng,
        }),
        'food_categories': jsonEncode(_foodCategories),
        'operating_hours': jsonEncode([
          {'day': 'monday', 'open_time': _openTime, 'close_time': _closeTime},
        ]),
        'payment_information': jsonEncode(
          _isBankPayout
              ? {
                  'payout_method': 'bank_transfer',
                  'account_name': _owner.text.trim(),
                  'account_number': _payoutNumber.text,
                }
              // Always the registered phone (the server refuses any other).
              : {
                  'payout_method': 'mobile_money',
                  'account_name': _owner.text.trim(),
                  'mobile_money_number': _phone.text.trim(),
                },
        ),
      };
      final files = [
        for (final d in _documents)
          http.MultipartFile.fromBytes(
            'documents',
            d.bytes,
            filename: d.name,
            contentType: _mediaType(d.name),
          ),
      ];
      final data = await _client.upload(
        '/vendor/auth/register',
        fields: fields,
        files: files,
      );
      final vendor = data is Map && data['vendor'] is Map
          ? Map<String, dynamic>.from(data['vendor'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() => _created = vendor);
      _scrollToTop();
      _toast('Vendor account created successfully!');
    } catch (e) {
      if (mounted) {
        _toast(
          e is ApiException
              ? e.message
              : 'Could not create your vendor account.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static MediaType _mediaType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => MediaType('application', 'pdf'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      _ => MediaType('image', 'jpeg'),
    };
  }

  void _login() => widget.onLogin != null
      ? widget.onLogin!()
      : Navigator.of(context).maybePop();

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final sm = width >= 640;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F4),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.symmetric(
            horizontal: sm ? 24 : 16,
            vertical: _created != null ? 64 : (sm ? 48 : 32),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _created != null ? 672 : 768,
              ),
              child: _created != null ? _success(_created!, sm) : _form(sm),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(bool sm) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(sm),
      const SizedBox(height: 32),
      _stepper(sm),
      const SizedBox(height: 32),
      _card(
        sm,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_step == 1) _businessStep(sm),
            if (_step == 2) _operationsStep(sm),
            if (_step == 3) _verificationStep(sm),
            const SizedBox(height: 24),
            const Divider(height: 1, thickness: 1, color: K.stone100),
            const SizedBox(height: 16),
            _footer(),
          ],
        ),
      ),
    ],
  );

  Widget _card(bool sm, Widget child) => Container(
    padding: EdgeInsets.all(sm ? 32 : 24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: K.stone200.withValues(alpha: 0.8)),
      boxShadow: K.shadowSm,
    ),
    child: child,
  );

  Widget _header(bool sm) => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: K.brown50,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: K.brown200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 14,
              color: K.brown850,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'TURN YOUR COOKING INTO A BUSINESS',
                style: kText(
                  11,
                  weight: FontWeight.w700,
                  color: K.brown850,
                  spacing: 0.55,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Become a Vendor',
        textAlign: TextAlign.center,
        style: kText(
          sm ? 30 : 24,
          weight: w900,
          color: K.gray900,
          spacing: sm ? -0.75 : -0.6,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 512),
        child: Text(
          'Create your digital storefront on KitchenLink in a few steps — no restaurant required.',
          textAlign: TextAlign.center,
          style: kText(14, color: K.stone500, height: 1.43),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Already have a vendor account? ',
            style: kText(12, weight: FontWeight.w700, color: K.stone500),
          ),
          GestureDetector(
            onTap: _login,
            child: Text(
              'Log in',
              style: kText(12, weight: FontWeight.w700, color: K.brown700)
                  .copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: K.brown700,
                  ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _stepper(bool sm) {
    const steps = [
      (1, 'Business', Icons.storefront_outlined),
      (2, 'Operations', Icons.place_outlined),
      (3, 'Verification', Icons.verified_user_outlined),
    ];
    const emerald500 = Color(0xFF10B981);
    const emerald400 = Color(0xFF34D399);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in steps.indexed) ...[
          Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _step > s.$1
                      ? emerald500
                      : (_step == s.$1 ? null : Colors.white),
                  gradient: _step == s.$1
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [K.brown900, K.brown700],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  border: _step < s.$1 ? Border.all(color: K.stone200) : null,
                  boxShadow: _step == s.$1 ? K.shadowMd : null,
                ),
                child: Icon(
                  _step > s.$1 ? Icons.check : s.$3,
                  size: 20,
                  color: _step >= s.$1 ? Colors.white : K.stone400,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 80,
                child: Text(
                  s.$2,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kText(
                    11,
                    weight: FontWeight.w700,
                    color: _step >= s.$1 ? K.brown700 : K.stone400,
                  ),
                ),
              ),
            ],
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: EdgeInsets.fromLTRB(sm ? 16 : 8, 21, sm ? 16 : 8, 0),
                color: _step > s.$1 ? emerald400 : K.stone200,
              ),
            ),
        ],
      ],
    );
  }

  Widget _stepHeader(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: kText(18, weight: w900, color: K.gray900, height: 1.4),
        ),
        Text(subtitle, style: kText(12, color: K.stone400)),
      ],
    ),
  );

  Widget _field(String label, Widget input, {String? errorKey}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      input,
      if (errorKey != null && _errors[errorKey] != null)
        FieldError(_errors[errorKey]!),
    ],
  );

  /// Two fields side by side from 640 px (`sm:grid-cols-2 gap-4`), stacked below.
  Widget _pair(bool side, Widget a, Widget b) => side
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [a, const SizedBox(height: 16), b],
        );

  // ------------------------------------------------------------ step 1

  Widget _businessStep(bool sm) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _stepHeader('Business details', 'Tell customers who you are'),
      _field(
        'Business / vendor name',
        MarketInput(
          controller: _name,
          icon: Icons.storefront_outlined,
          hint: 'e.g. Your Kitchen Name',
          maxLength: nameMaxLength,
          error: _errors['name'] != null,
          onChanged: (_) => _clearError('name'),
        ),
        errorKey: 'name',
      ),
      const SizedBox(height: 16),
      _typePicker(sm),
      const SizedBox(height: 16),
      _pair(
        sm,
        _field(
          'Owner name',
          MarketInput(
            controller: _owner,
            icon: Icons.person_outline,
            hint: 'Full name',
            autofill: const [AutofillHints.name],
            capitalization: TextCapitalization.words,
            formatters: [formatWith(formatNameInput)],
            error: _errors['owner'] != null,
            onChanged: (_) => _clearError('owner'),
          ),
          errorKey: 'owner',
        ),
        _field(
          'Phone number',
          MarketInput(
            controller: _phone,
            icon: Icons.phone_outlined,
            hint: phonePlaceholder,
            keyboard: TextInputType.phone,
            autofill: const [AutofillHints.telephoneNumber],
            formatters: [formatWith(sanitizePhoneInput)],
            error: _errors['phone'] != null,
            onChanged: (phone) {
              // Mobile-money payouts use this number, so match its network.
              final network = networkOf(phone);
              if (network.isNotEmpty && !_isBankPayout) _payoutMethod = network;
              _clearError('phone');
            },
          ),
          errorKey: 'phone',
        ),
      ),
      const SizedBox(height: 16),
      _field(
        'Email (optional)',
        MarketInput(
          controller: _email,
          hint: 'you@example.rw',
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
          formatters: [formatWith(sanitizeEmailInput)],
          error: _errors['email'] != null,
          onChanged: (_) => _clearError('email'),
        ),
        errorKey: 'email',
      ),
      const SizedBox(height: 16),
      _field(
        'Description',
        MarketInput(
          controller: _description,
          icon: Icons.description_outlined,
          hint: 'Describe your food, story and what makes it special…',
          maxLines: 3,
          capitalization: TextCapitalization.sentences,
          error: _errors['description'] != null,
          onChanged: (_) => _clearError('description'),
        ),
        errorKey: 'description',
      ),
    ],
  );

  Widget _typePicker(bool sm) {
    final twoColumns = MediaQuery.sizeOf(context).width >= 420;
    final cards = [for (final t in vendorTypes) _typeCard(t)];
    final selected = _type.isEmpty ? null : vendorTypeOf(_type);
    final info = selected == null ? null : vendorTypeInfo[selected.code]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel('What kind of food business are you?'),
        if (twoColumns)
          for (var i = 0; i < cards.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[i]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < cards.length
                        ? cards[i + 1]
                        : const SizedBox(),
                  ),
                ],
              ),
            ),
          ]
        else
          for (final (i, card) in cards.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            card,
          ],
        if (selected != null && info != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: K.brown50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: K.brown200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  info.title ?? selected.label,
                  style: kText(12, weight: w900, color: K.gray900),
                ),
                const SizedBox(height: 8),
                _typeProfile(info, sm),
              ],
            ),
          ),
        ],
        if (_type == 'other') ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: K.stone50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: K.stone200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Other is for kitchens like:',
                  style: kText(11, weight: FontWeight.w700, color: K.stone600),
                ),
                const SizedBox(height: 4),
                for (final example in vendorTypeInfo['other']!.examples)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      '•  $example',
                      style: kText(11, color: K.stone500),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Same features as every kitchen type — customers can filter by Other to find unique kitchens.',
                  style: kText(11, color: K.stone400),
                ),
              ],
            ),
          ),
        ],
        if (_errors['type'] != null)
          FieldError(_errors['type']!)
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'You can sell any kind of food whatever type you choose.',
              style: kText(11, color: K.stone400),
            ),
          ),
      ],
    );
  }

  Widget _typeCard(VendorType type) {
    final selected = _type == type.code;
    final info = vendorTypeInfo[type.code]!;
    return Material(
      color: selected ? K.brown50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? K.brown700 : K.stone200,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() {
          _type = type.code;
          _errors = {..._errors}..remove('type');
        }),
        child: Semantics(
          inMutuallyExclusiveGroup: true,
          checked: selected,
          label: info.title ?? type.label,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: type.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: type.border),
                  ),
                  child: Center(
                    child: type.code == 'chef'
                        ? ChefHatIcon(size: 16, color: type.foreground)
                        : Icon(
                            _typeIcons[type.code] ?? type.icon,
                            size: 16,
                            color: type.foreground,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title ?? type.label,
                        style: kText(
                          14,
                          weight: FontWeight.w800,
                          color: K.gray900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.description,
                        style: kText(11, color: K.stone500, height: 1.375),
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, size: 16, color: K.brown700),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Closer matches to the website's lucide icons than the admin badges use.
  static const _typeIcons = {
    'restaurant': Icons.restaurant_outlined,
    'meal_prep': Icons.eco_outlined,
    'juice_drinks': Icons.local_cafe_outlined,
  };

  /// The website's VendorTypeProfile.
  Widget _typeProfile(VendorTypeInfo info, bool sm) {
    Widget list(
      String heading,
      Color headingColor,
      List<String> items,
      IconData icon,
      Color iconColor,
      Color textColor,
      String empty,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: kText(11, weight: w900, color: headingColor, spacing: 0.55),
        ),
        const SizedBox(height: 4),
        if (items.isEmpty) Text(empty, style: kText(12, color: K.stone500)),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 14, color: iconColor),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item, style: kText(12, color: textColor)),
                ),
              ],
            ),
          ),
      ],
    );
    final great = list(
      'GREAT FOR',
      const Color(0xFF047857),
      info.strengths,
      Icons.check_circle_outline,
      const Color(0xFF059669),
      K.stone700,
      '',
    );
    final less = list(
      'LESS SUITED FOR',
      const Color(0xFFB45309),
      info.lessSuited,
      Icons.remove_circle_outline,
      const Color(0xFFD97706),
      K.stone600,
      'Nothing — fully open.',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pair(sm, great, less),
        const SizedBox(height: 12),
        Text(
          'HOW YOU TAKE ORDERS',
          style: kText(11, weight: w900, color: K.stone600, spacing: 0.55),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final line in info.rules.lines)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: K.stone200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_available_outlined,
                      size: 12,
                      color: K.stone600,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        line,
                        style: kText(
                          11,
                          weight: FontWeight.w600,
                          color: K.stone600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.info_outline, size: 14, color: K.stone400),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${info.note} You can sell any kind of food. The order rules above apply at checkout; a daily limit and minimum order can be adjusted later in your profile.',
                style: kText(11, color: K.stone500),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ step 2

  Widget _operationsStep(bool sm) {
    final names = [for (final c in _categories) c.name];
    final typeCategories = suggestedCategories(_type, _categories);
    final narrow = typeCategories.isNotEmpty && !_showAllCategories;
    final shown = narrow
        ? names
              .where(
                (n) =>
                    typeCategories.contains(n) || _foodCategories.contains(n),
              )
              .toList()
        : names;
    final hidden = names.length - shown.length;
    final typeLabel = _type.isEmpty ? '' : vendorTypeOf(_type).label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeader('Operations', 'Where you cook and what you serve'),
        Row(
          children: [
            const Icon(Icons.place_outlined, size: 14, color: K.brown500),
            const SizedBox(width: 6),
            Text(
              'Kitchen location',
              style: kText(12, weight: FontWeight.w700, color: K.stone500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Type your area to see it on the map, then your street to place your kitchen. When your store is open, '
          'customers find you on the map here. You can change it later in your profile.',
          style: kText(11, color: K.stone500, height: 1.4),
        ),
        const SizedBox(height: 12),
        KitchenLocationFields(
          client: _client,
          area: _area,
          address: _address,
          lat: _lat,
          lng: _lng,
          areaError: _errors['location'],
          coordsError: _errors['coords'],
          onChanged: () {
            if (_area.text.trim().isNotEmpty) _clearError('location');
            if (parseCoords(_lat.text, _lng.text) != null) {
              _clearError('coords');
            }
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Food categories',
          style: kText(12, weight: FontWeight.w700, color: K.stone500),
        ),
        const SizedBox(height: 4),
        Text(
          typeCategories.isNotEmpty
              ? 'Categories for $typeLabel kitchens. Pick the ones you serve.'
              : 'Pick the categories you serve.',
          style: kText(11, color: K.stone500),
        ),
        const SizedBox(height: 8),
        if (names.isEmpty)
          Text('Loading categories…', style: kText(11, color: K.stone400))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in shown)
                _categoryChip(name, _foodCategories.contains(name)),
            ],
          ),
        if (typeCategories.isNotEmpty && (hidden > 0 || _showAllCategories))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _showAllCategories = !_showAllCategories),
              child: Text(
                _showAllCategories
                    ? 'Show only $typeLabel categories'
                    : 'Show all categories ($hidden more)',
                style: kText(11, weight: FontWeight.w700, color: K.brown700),
              ),
            ),
          ),
        if (_errors['categories'] != null) FieldError(_errors['categories']!),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _field(
                'Opens at',
                _timeField(_openTime, (t) => setState(() => _openTime = t)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _field(
                'Closes at',
                _timeField(_closeTime, (t) => setState(() => _closeTime = t)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _categoryChip(String name, bool active) => Material(
    color: active ? K.brown700 : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: active ? Colors.transparent : K.stone200),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        active ? _foodCategories.remove(name) : _foodCategories.add(name);
        if (_foodCategories.isNotEmpty) {
          _errors = {..._errors}..remove('categories');
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          name,
          style: kText(
            12,
            weight: FontWeight.w700,
            color: active ? Colors.white : K.stone600,
          ),
        ),
      ),
    ),
  );

  Widget _timeField(String value, ValueChanged<String> onPicked) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: () async {
      final parts = value.split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked != null) {
        onPicked(
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
        );
      }
    },
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.stone200),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 16, color: K.stone400),
          const SizedBox(width: 8),
          Text(value, style: kText(14, color: K.gray900, height: 1.43)),
        ],
      ),
    ),
  );

  // ------------------------------------------------------------ step 3

  Widget _verificationStep(bool sm) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _stepHeader('Verification & payout', 'Build trust and get paid'),
      _pair(
        sm,
        _field('Payout method', _payoutDropdown()),
        _field(
          _isBankPayout ? 'Bank account number' : 'Payout number',
          _isBankPayout
              ? MarketInput(
                  controller: _payoutNumber,
                  hint: 'Bank account number',
                  keyboard: TextInputType.number,
                  maxLength: _bankAccountMaxLength,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  error: _errors['payout'] != null,
                  onChanged: (_) => _clearError('payout'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mobile-money payouts always go to the registered phone.
                    MarketInput(
                      controller: _payoutPhone
                        ..text = localPhone(_phone.text).isEmpty
                            ? _phone.text
                            : localPhone(_phone.text),
                      hint: phonePlaceholder,
                      readOnly: true,
                      error: _errors['payout'] != null,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your registered phone number. To use another number, change your phone in step 1.',
                      style: kText(11, color: K.stone500),
                    ),
                  ],
                ),
          errorKey: 'payout',
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Verification documents (ID, food permit…)',
          style: kText(12, weight: FontWeight.w700, color: K.stone500),
        ),
      ),
      CustomPaint(
        painter: _DashedBorder(color: K.stone300, radius: 16),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            hoverColor: K.brown50,
            onTap: _pickDocuments,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  const Icon(
                    Icons.upload_outlined,
                    size: 24,
                    color: K.brown500,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to upload documents',
                    style: kText(
                      12,
                      weight: FontWeight.w700,
                      color: K.stone600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PDF, JPG or PNG (max $_maxDocumentMb MB each)',
                    style: kText(11, color: K.stone400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      for (final (i, doc) in _documents.indexed)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 8 : 4),
          child: Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 14,
                color: K.brown500,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.name,
                  overflow: TextOverflow.ellipsis,
                  style: kText(12, weight: FontWeight.w500, color: K.stone600),
                ),
              ),
              InkWell(
                onTap: () => setState(() => _documents.removeAt(i)),
                child: Tooltip(
                  message: 'Remove ${doc.name}',
                  child: const Icon(Icons.close, size: 14, color: K.stone400),
                ),
              ),
            ],
          ),
        ),
      if (_errors['documents'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: FieldError(_errors['documents']!),
        ),
      const SizedBox(height: 16),
      InkWell(
        onTap: () => setState(() {
          _agree = !_agree;
          if (_agree) _errors = {..._errors}..remove('agree');
        }),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: _agree,
                activeColor: K.brown700,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                side: const BorderSide(color: K.stone400),
                onChanged: (v) => setState(() {
                  _agree = v ?? false;
                  if (_agree) _errors = {..._errors}..remove('agree');
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'I confirm the information is accurate and agree to the KitchenLink vendor terms & commission policy.',
                style: kText(12, weight: FontWeight.w500, color: K.stone600),
              ),
            ),
          ],
        ),
      ),
      if (_errors['agree'] != null) FieldError(_errors['agree']!),
    ],
  );

  Widget _payoutDropdown() => DropdownButtonFormField<String>(
    initialValue: _payoutMethod,
    isExpanded: true,
    icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: K.stone500),
    style: kText(14, color: K.gray900, height: 1.43),
    dropdownColor: Colors.white,
    borderRadius: BorderRadius.circular(12),
    decoration: InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: const Icon(Icons.credit_card, size: 16, color: K.stone400),
      prefixIconConstraints: const BoxConstraints(minWidth: 36),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: K.stone200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: K.brown700, width: 1.5),
      ),
    ),
    items: [
      for (final m in _payoutMethods)
        DropdownMenuItem(value: m, child: Text(m)),
    ],
    onChanged: (m) => setState(() {
      _payoutMethod = m ?? _payoutMethod;
      _payoutNumber.clear();
      _errors = {..._errors}..remove('payout');
    }),
  );

  // ------------------------------------------------------------ footer

  Widget _footer() => Row(
    children: [
      if (_step > 1)
        Material(
          color: K.stone100,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _goBack,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chevron_left, size: 16, color: K.stone700),
                  const SizedBox(width: 6),
                  Text(
                    'Back',
                    style: kText(
                      14,
                      weight: FontWeight.w700,
                      color: K.stone700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        )
      else
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Cancel',
              style: kText(12, weight: FontWeight.w700, color: K.stone500),
            ),
          ),
        ),
      const SizedBox(width: 16),
      _gradientButton(
        onTap: _step < 3 ? _goNext : (_submitting ? null : _submit),
        children: _step < 3
            ? [
                Flexible(
                  child: Text(
                    'Continue',
                    overflow: TextOverflow.ellipsis,
                    style: kText(14, weight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 16, color: Colors.white),
              ]
            : [
                const Icon(
                  Icons.verified_outlined,
                  size: 16,
                  color: K.brown300,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _submitting ? 'Creating account…' : 'Create Vendor Account',
                    overflow: TextOverflow.ellipsis,
                    style: kText(
                      14,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
      ),
    ],
  );

  /// The footer's main button: pushed to the right, and allowed to shrink
  /// (its label then shortens) when the screen is narrow.
  Widget _gradientButton({
    required VoidCallback? onTap,
    required List<Widget> children,
  }) => Expanded(
    child: Align(
      alignment: Alignment.centerRight,
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: K.buttonGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: K.shadowMd,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  // ------------------------------------------------------------ success

  Widget _success(Map<String, dynamic> vendor, bool sm) {
    final name = (vendor['name'] ?? _name.text.trim()).toString();
    final location = vendor['location'] is Map
        ? vendor['location'] as Map
        : const {};
    final place = (location['neighborhood'] ?? location['address'] ?? '')
        .toString();
    final summaries = [
      _summary(
        'VENDOR TYPE',
        vendorTypeOf(vendor['vendor_type'] ?? _type).label,
      ),
      _summary(
        'LOCATION',
        place.isEmpty
            ? (_area.text.trim().isEmpty ? 'Kigali' : _area.text.trim())
            : place,
      ),
      _summary(
        'STATUS',
        (vendor['verification_status'] ?? 'pending').toString(),
      ),
    ];
    final login = Container(
      decoration: BoxDecoration(
        gradient: K.buttonGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: K.shadowMd,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _login,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    'Go to Vendor Login',
                    overflow: TextOverflow.ellipsis,
                    style: kText(14, weight: FontWeight.w700, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
    final back = Material(
      color: K.stone100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
            widthFactor: 1,
            child: Text(
              'Back to marketplace',
              overflow: TextOverflow.ellipsis,
              style: kText(14, weight: FontWeight.w700, color: K.stone700),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: K.stone200.withValues(alpha: 0.8)),
        boxShadow: K.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.verified_outlined,
                size: 36,
                color: Color(0xFF059669),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "You're all set, $name!",
            textAlign: TextAlign.center,
            style: kText(24, weight: w900, color: K.gray900),
          ),
          const SizedBox(height: 4),
          Text(
            'Your account has been created. Your kitchen is listed on the marketplace while its verification is pending. '
            'Sign in to add your menu and manage your store.',
            textAlign: TextAlign.center,
            style: kText(14, color: K.stone500, height: 1.43),
          ),
          const SizedBox(height: 20),
          if (sm)
            Row(
              children: [
                for (final (i, s) in summaries.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: s),
                ],
              ],
            )
          else
            for (final (i, s) in summaries.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              s,
            ],
          const SizedBox(height: 28),
          if (sm)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: login),
                const SizedBox(width: 12),
                Flexible(child: back),
              ],
            )
          else ...[
            login,
            const SizedBox(height: 12),
            back,
          ],
        ],
      ),
    );
  }

  Widget _summary(String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: K.stone50,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: K.stone100),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: kText(
            11,
            weight: FontWeight.w700,
            color: K.stone400,
            spacing: 0.55,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: kText(14, weight: FontWeight.w700, color: K.gray900),
        ),
      ],
    ),
  );
}

/// `border-2 border-dashed rounded-2xl`.
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(1),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
