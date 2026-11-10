import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'customer_api.dart';
import 'customer_session.dart';
import 'screens/account_screens.dart';
import 'screens/cart_sheet.dart';
import 'screens/chat_screens.dart';
import 'screens/checkout_screen.dart';
import 'screens/event_order_screen.dart';
import 'screens/kitchen_screen.dart';
import 'screens/kitchens_map_screen.dart';
import 'screens/kitchens_screen.dart';
import 'screens/order_screen.dart';
import 'screens/support_screens.dart';
import 'widgets/customer_auth_sheet.dart';
import 'widgets/market_ui.dart';

/// Every page a customer can open, like the website's routes (`/vendor/:id`,
/// `/checkout`, `/track/:id`, `/orders`, `/wishlist`, `/profile`,
/// `/messages`, `/support`, `/vendors`, `/vendors/map`, `/event-order/:id`).
class MarketNav {
  MarketNav._();

  static Future<T?> _push<T>(BuildContext context, Widget page) =>
      Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));

  /// True when signed in, asking the customer to sign in first otherwise.
  static Future<bool> requireSignIn(BuildContext context) async {
    if (context.read<CustomerSession>().isSignedIn) return true;
    return showCustomerSignIn(context);
  }

  static Future<void> kitchen(BuildContext context, String vendorId, {String? dishId}) =>
      _push(context, KitchenScreen(vendorId: vendorId, openDishId: dishId));

  static Future<void> cart(BuildContext context) => showCartSheet(context);

  static Future<void> checkout(BuildContext context) => _push(context, const CheckoutScreen());

  /// Replaces the current page (after placing an order, back goes home).
  static Future<void> orderAfterCheckout(BuildContext context, String orderId) =>
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => OrderScreen(orderId: orderId)));

  static Future<void> order(BuildContext context, String orderId) => _push(context, OrderScreen(orderId: orderId));

  /// "Track order": the latest order, or the history when there is none.
  static Future<void> track(BuildContext context) => _push(context, const OrderScreen());

  static Future<void> orders(BuildContext context) => _push(context, const OrdersScreen());

  static Future<void> wishlist(BuildContext context) => _push(context, const WishlistScreen());

  static Future<void> profile(BuildContext context) => _push(context, const ProfileScreen());

  static Future<void> kitchens(BuildContext context, {String? categoryId, String? categoryName, List<String> vendorTypes = const []}) =>
      _push(context, KitchensScreen(categoryId: categoryId, categoryName: categoryName, vendorTypes: vendorTypes));

  static Future<void> specials(BuildContext context) => _push(context, const KitchensScreen(mode: KitchensMode.specials));

  static Future<void> bigEvent(BuildContext context) => _push(context, const KitchensScreen(mode: KitchensMode.events));

  static Future<void> map(BuildContext context) => _push(context, const KitchensMapScreen());

  static Future<void> eventOrder(BuildContext context, {required String vendorId, String? packageId, int? guests, bool pickup = false}) =>
      _push(context, EventOrderScreen(vendorId: vendorId, packageId: packageId, guests: guests, pickup: pickup));

  static Future<void> messages(BuildContext context) => _push(context, const MessagesScreen());

  static Future<void> chat(BuildContext context, String conversationId) => _push(context, ChatScreen(conversationId: conversationId));

  static Future<void> support(BuildContext context, {String? orderId}) => _push(context, SupportScreen(orderId: orderId));

  /// "Message kitchen": opens (or starts) the chat with this kitchen.
  static Future<void> messageKitchen(BuildContext context, String vendorId) async {
    if (!await requireSignIn(context) || !context.mounted) return;
    try {
      final id = await context.read<CustomerApi>().openChatWith(vendorId);
      if (context.mounted && id.isNotEmpty) await chat(context, id);
    } catch (error) {
      if (context.mounted) showMarketSnack(context, error.toString());
    }
  }
}
