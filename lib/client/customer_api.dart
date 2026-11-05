import '../api/api_client.dart';
import 'location.dart';
import 'models.dart';

/// The public marketplace endpoints the home page reads (no sign-in needed),
/// as the website's api/endpoints.js.
class CustomerApi {
  CustomerApi(this.client);

  final ApiClient client;

  /// The image URL as this device can load it: relative upload paths are
  /// resolved against the API server, and a `localhost` URL is pointed at the
  /// API's host (a phone can't reach the development computer as localhost).
  String? media(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return null;
    if (raw.startsWith('data:')) return null;
    final api = Uri.tryParse(client.baseUrl);
    final parsed = Uri.tryParse(raw);
    if (api == null || parsed == null) return null;
    final origin = api.replace(path: '', query: null, fragment: null);
    if (!parsed.hasScheme) {
      if (raw.startsWith('//')) return '${api.scheme}:$raw';
      return origin.resolve(raw.startsWith('/') ? raw : '/$raw').toString();
    }
    const loopback = {'localhost', '127.0.0.1', '0.0.0.0', '::1'};
    if (loopback.contains(parsed.host) && !loopback.contains(api.host)) {
      return parsed.replace(host: api.host, port: api.hasPort ? api.port : null).toString();
    }
    return raw;
  }

  Map<String, Object?> _where(ClientLocation location, {bool withLabel = false}) =>
      location.isLocated ? {'lat': location.lat, 'lng': location.lng, if (withLabel) 'label': location.label} : {};

  String? _types(List<String> types) => types.isEmpty ? null : types.join(',');

  /// GET /home/feed — categories, featured kitchens and popular dishes.
  Future<HomeFeed> feed(ClientLocation location, List<String> vendorTypes) async {
    final data = await client.request('/home/feed${ApiClient.qs({..._where(location, withLabel: true), 'vendor_type': _types(vendorTypes)})}');
    return HomeFeed.fromJson(data);
  }

  /// GET /home/categories.
  Future<List<Category>> categories() async {
    final data = await client.request('/home/categories');
    return pickList(data, ['categories']).map(Category.fromJson).toList();
  }

  /// GET /home/vendors — every kitchen, nearest first when the location is known.
  Future<VendorPage> allVendors(ClientLocation location, List<String> vendorTypes, {int limit = 6}) async {
    final data = await client.request(
      '/home/vendors${ApiClient.qs({..._where(location), 'vendor_type': _types(vendorTypes), 'sort': 'distance', 'page': 1, 'limit': limit})}',
    );
    return VendorPage.fromJson(data);
  }

  /// GET /vendors/specials — "Tomorrow's Special" announcements.
  Future<List<SpecialEntry>> specials(ClientLocation location) async {
    final data = await client.request('/vendors/specials${ApiClient.qs(_where(location))}');
    final entries = <SpecialEntry>[];
    for (final raw in pickList(data, ['specials'])) {
      final special = Special.fromJson(raw['special']);
      if (special != null) entries.add(SpecialEntry(Vendor.fromJson(raw), special));
    }
    return entries;
  }

  /// GET /vendors/offers — upcoming Offer Days.
  Future<List<OfferDay>> offers(ClientLocation location) async {
    final data = await client.request('/vendors/offers${ApiClient.qs(_where(location))}');
    return pickList(data, ['offers']).map(OfferDay.fromJson).where((o) => o.vendor.id.isNotEmpty).toList();
  }

  /// GET /home/search — dishes and kitchens matching the query.
  Future<SearchResult> search(String query, ClientLocation location, List<String> vendorTypes) async {
    final data = await client.request(
      '/home/search${ApiClient.qs({'q': query, 'lat': location.lat, 'lng': location.lng, 'vendor_type': _types(vendorTypes)})}',
    );
    return SearchResult.fromJson(data);
  }
}
