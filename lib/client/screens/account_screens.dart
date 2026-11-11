import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../client_theme.dart';
import '../customer_api.dart';
import '../customer_session.dart';
import '../market_models.dart';
import '../market_nav.dart';
import '../market_state.dart';
import '../models.dart';
import '../widgets/cards.dart';
import '../widgets/market_ui.dart';
import 'cart_sheet.dart';
import 'checkout_screen.dart';
import 'kitchen_screen.dart';

/// Saved for later (the website's `/wishlist`): each dish with its kitchen,
/// "Add to cart", details and remove.
class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wishlist = context.watch<Wishlist>();
    final media = context.read<CustomerApi>().media;
    final items = wishlist.items;
    return MarketPage(
      title: 'Your wishlist',
      subtitle: '${items.length} ${items.length == 1 ? 'dish' : 'dishes'} saved',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (wishlist.error != null) ...[Notice(wishlist.error!, icon: Icons.error_outline), const SizedBox(height: 10)],
        if (items.isEmpty)
          EmptyCard(
            icon: Icons.favorite_border,
            title: 'Your wishlist is empty',
            message: 'Save dishes from a kitchen menu and they will be waiting for you here.',
            actionLabel: 'Explore kitchens',
            onAction: () => MarketNav.kitchens(context),
          )
        else
          for (final entry in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => showDishSheet(context, entry.dish, entry.kitchen, showKitchenLink: true),
                    child: SizedBox(width: 84, child: NetImage(url: media(entry.dish.image), aspect: 1, radius: BorderRadius.circular(16))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(
                        onTap: () => showDishSheet(context, entry.dish, entry.kitchen, showKitchenLink: true),
                        child: Text(entry.dish.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: kText(14, weight: w900)),
                      ),
                      GestureDetector(
                        onTap: () => MarketNav.kitchen(context, entry.kitchen.id),
                        child: Text(entry.kitchen.name, style: kText(12, weight: FontWeight.w600, color: K.brown500)),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(child: Text(formatRwf(entry.dish.price), style: kText(14, weight: w900, color: K.brown750))),
                        GradientButton(
                          label: entry.dish.isAvailable ? 'Add to cart' : 'Sold out',
                          icon: Icons.shopping_bag_outlined,
                          expand: false,
                          height: 34,
                          fontSize: 11.5,
                          padding: 12,
                          onTap: entry.dish.isAvailable ? () => addDishToCart(context, entry.dish, entry.kitchen) : null,
                        ),
                      ]),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Remove ${entry.dish.name} from wishlist',
                    onPressed: () {
                      wishlist.remove(entry.dish.id);
                      showMarketSnack(context, '${entry.dish.name} removed from your wishlist');
                    },
                    icon: Icon(Icons.delete_outline, color: K.stone400),
                  ),
                ]),
              ),
            ),
      ]),
    );
  }
}

/// The customer's profile (the website's `/profile`): photo, name, phone and
/// email, order history, and the saved delivery addresses.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  bool _uploading = false;
  String? _error;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startEditing(CustomerSession session) {
    _name.text = session.name;
    _phone.text = localPhone(session.phone);
    _email.text = session.email;
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    final session = context.read<CustomerSession>();
    if (_name.text.trim().length < 2) return setState(() => _error = 'Enter your full name.');
    if (!isRwandaPhone(_phone.text)) return setState(() => _error = 'Enter a valid Rwandan phone number (e.g. 0788123456).');
    final email = _email.text.trim();
    if (email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) return setState(() => _error = 'Enter a valid email address.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Keep the form open if the server refuses (e.g. the phone is used by another customer).
      await session.updateProfile(newName: _name.text.trim(), newPhone: localPhone(_phone.text), newEmail: email);
      if (mounted) setState(() => _editing = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// A new photo, shrunk first (phone photos are far bigger than the 1 MB upload limit).
  Future<void> _pickPhoto() async {
    final session = context.read<CustomerSession>();
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
      if (file == null) return;
      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      final type = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      await session.updateProfile(avatarBase64: 'data:image/$type;base64,${base64Encode(bytes)}');
    } catch (e) {
      if (mounted) showMarketSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<CustomerSession>();
    if (!session.isSignedIn) {
      return MarketPage(
        title: 'My profile',
        body: SignInPrompt(icon: Icons.person_outline, title: 'Sign in to see your profile', message: 'Your details and saved addresses show up here.', onSignIn: () => MarketNav.requireSignIn(context)),
      );
    }
    final media = context.read<CustomerApi>().media;
    final avatar = media(session.avatarUrl);
    final initials = session.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    return MarketPage(
      title: 'My profile',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Panel(
          child: Column(children: [
            Stack(children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: K.brown100,
                backgroundImage: avatar == null ? null : NetworkImage(avatar),
                child: avatar == null ? Text(initials.isEmpty ? '?' : initials, style: kText(26, weight: w900, color: K.brown700)) : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: K.fillBrown700,
                  shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _uploading ? null : _pickPhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: _uploading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.photo_camera_outlined, size: 15, color: Colors.white, semanticLabel: 'Upload profile picture'),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(session.name, style: kDisplay(26)),
            Text([session.phone, session.email].where((s) => s.isNotEmpty).join(' · '), style: kText(12, color: K.stone500)),
            const SizedBox(height: 6),
            StatusPill('Verified Customer Account', background: K.tone(const Color(0xFFD1FAE5)), foreground: K.tone(const Color(0xFF065F46))),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              OutlineAction(label: 'Order History', icon: Icons.receipt_long_outlined, onTap: () => MarketNav.orders(context)),
              OutlineAction(label: _editing ? 'Cancel' : 'Edit Profile', icon: Icons.edit_outlined, color: K.brown700, onTap: () => _editing ? setState(() => _editing = false) : _startEditing(session)),
            ]),
          ]),
        ),
        if (_editing) ...[
          const SizedBox(height: 14),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Edit Personal Details', style: kText(15, weight: w900)),
              const SizedBox(height: 12),
              const FieldLabel('Full name'),
              TextField(controller: _name, maxLength: 60, textCapitalization: TextCapitalization.words, decoration: marketInput('Your name').copyWith(counterText: '')),
              const SizedBox(height: 10),
              const FieldLabel('Phone number'),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: marketInput('0788123456')),
              const SizedBox(height: 10),
              const FieldLabel('Email'),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: marketInput('name@example.com')),
              if (_error != null) ...[const SizedBox(height: 10), Notice(_error!)],
              const SizedBox(height: 14),
              GradientButton(label: _saving ? 'Saving…' : 'Save Changes', onTap: _saving ? null : _save),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Saved Addresses (${session.addresses.length})', style: kText(15, weight: w900))),
              TextButton.icon(onPressed: () => showAddressForm(context), icon: const Icon(Icons.add, size: 16), label: Text('Add Address', style: kText(12, weight: FontWeight.w700, color: K.brown700))),
            ]),
            if (session.addresses.isEmpty)
              Text('No saved addresses yet. Add one to check out faster.', style: kText(12, color: K.stone500))
            else
              for (final address in session.addresses)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: address.isDefault ? K.brown50 : K.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: address.isDefault ? K.brown200 : K.stone200)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.location_on_outlined, size: 18, color: K.brown500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(address.title, style: kText(13.5, weight: w900)),
                          if (address.isDefault) ...[const SizedBox(width: 6), StatusPill('Default', background: K.brown100, foreground: K.brown850)],
                        ]),
                        Text(address.street, style: kText(12.5, color: K.stone700)),
                        Text('${address.district}, Kigali', style: kText(12, color: K.stone500)),
                        if (address.instructions.isNotEmpty) Text('Note: ${address.instructions}', style: kText(11.5, color: K.stone500)),
                        const SizedBox(height: 6),
                        address.isDefault
                            ? Text('Primary location', style: kText(11, weight: FontWeight.w700, color: K.forest700))
                            : GestureDetector(onTap: () => session.setDefaultAddress(address.id), child: Text('Set as Default', style: kText(11.5, weight: FontWeight.w700, color: K.brown700))),
                      ]),
                    ),
                    IconButton(tooltip: 'Delete ${address.title}', onPressed: () => session.deleteAddress(address.id), icon: Icon(Icons.delete_outline, color: K.stone400)),
                  ]),
                ),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          // Its own Material, so the rows' tap ripple shows on the card.
          child: Material(
            type: MaterialType.transparency,
            child: Column(children: [
            for (final (icon, label, onTap) in [
              (Icons.favorite_border, 'Saved dishes', () => MarketNav.wishlist(context)),
              (Icons.chat_bubble_outline, 'Messages', () => MarketNav.messages(context)),
              (Icons.support_agent, 'Help & Support', () => MarketNav.support(context)),
            ])
              ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon, color: K.brown700), title: Text(label, style: kText(13.5, weight: FontWeight.w700)), trailing: const Icon(Icons.chevron_right), onTap: onTap),
            ]),
          ),
        ),
      ]),
    );
  }
}

