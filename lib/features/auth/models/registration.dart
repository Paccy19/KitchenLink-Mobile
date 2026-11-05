import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/utils/uploads.dart';
import '../../../core/utils/validators.dart';
import 'vendor_account.dart';

/// Everything the registration form collects (`POST /vendor/auth/register`).
class RegistrationData {
  const RegistrationData({
    required this.name,
    required this.ownerName,
    required this.vendorType,
    required this.phone,
    required this.description,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.foodCategoryIds,
    required this.operatingHours,
    required this.payment,
    required this.documents,
    this.neighborhood = '',
    this.email = '',
    this.banner,
  });

  final String name;
  final String ownerName;
  final String vendorType;
  final String phone;
  final String email;
  final String description;
  final String address;
  final String neighborhood;
  final double latitude;
  final double longitude;
  final List<String> foodCategoryIds;
  final List<OperatingHour> operatingHours;
  final PaymentInformation payment;
  final PickedUpload? banner;
  final List<PickedUpload> documents;

  /// The text parts of the multipart request. JSON values are sent as JSON
  /// strings, the way the backend's `parseJsonField` reads them.
  Map<String, String> toFields() {
    final localPhone = Validators.toLocalPhone(phone);
    final payout = payment.isBank
        ? payment
        : PaymentInformation(
            payoutMethod: 'mobile_money',
            accountName: payment.accountName,
            // Mobile-money payouts must use the registered phone.
            mobileMoneyNumber: localPhone,
          );
    return {
      'name': name.trim(),
      'owner_name': ownerName.trim(),
      'vendor_type': vendorType,
      'phone': localPhone,
      if (email.trim().isNotEmpty) 'email': email.trim().toLowerCase(),
      'description': description.trim(),
      'location': jsonEncode({
        'latitude': latitude,
        'longitude': longitude,
        'address': address.trim(),
        'neighborhood': neighborhood.trim(),
      }),
      'food_categories': jsonEncode(foodCategoryIds),
      'operating_hours': jsonEncode([for (final hour in operatingHours) hour.toJson()]),
      'payment_information': jsonEncode(payout.toJson()),
    };
  }

  /// The first problem with the chosen files, or null.
  String? validateFiles() {
    if (documents.isEmpty) return 'Add at least one verification document.';
    if (documents.length > UploadRules.maxDocuments) {
      return 'You can upload at most ${UploadRules.maxDocuments} documents.';
    }
    for (final document in documents) {
      final error = document.validate(UploadRules.document);
      if (error != null) return error;
    }
    return banner?.validate(UploadRules.registrationBanner);
  }

  /// Builds the multipart body with the files as real parts.
  Future<FormData> toFormData() async {
    final form = FormData();
    toFields().forEach((key, value) => form.fields.add(MapEntry(key, value)));
    final bannerFile = banner;
    if (bannerFile != null) {
      form.files.add(MapEntry('banner_image', await bannerFile.toMultipart()));
    }
    for (final document in documents) {
      form.files.add(MapEntry('documents', await document.toMultipart()));
    }
    return form;
  }
}
