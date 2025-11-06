import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
const String baseUrl = 'http://localhost:8080';
int? userId;       // will store the logged-in user's id
void main() {
  runApp(const MyApp());
}
class Product {
  final int id;
  final String name;
  final String imageUrl;
  final double price;
  final int? shopId; // nullable now

  Product({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.shopId,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final dynamic rawShopId = json['shop_id'] ?? json['shopId'] ?? json['shop'] ?? 0;
    final dynamic rawId = json['id'] ?? json['item_id'] ?? json['product_id'] ?? 0;
    final dynamic rawPrice = json['price'] ?? json['cost'] ?? json['amount'] ?? 0;

    return Product(
      id: _toInt(rawId),
      name: json['name'] ?? json['item_name'] ?? '',
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      price: _parsePrice(rawPrice),
      shopId: rawShopId != null ? _toInt(rawShopId) : null,
    );
  }

  static double _parsePrice(dynamic value) {
    if (value is int) return value.toDouble();
    if (value is double) return value;
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}


class Shop {
  final int shopId;
  final String name;
  final String imageUrl;
  final String address;
  final String status;

  Shop({
    required this.shopId,
    required this.name,
    required this.imageUrl,
    required this.address,
    required this.status,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      shopId: json['shop_id'] ?? json['id'] ?? 0, // ✅ Correct shop ID
      name: json['shop_name'] ?? json['name'] ?? '',
      imageUrl: json['image_url'] ?? '',
      address: json['address'] ?? '',
      status: json['status'] ?? 'inactive',
    );
  }
}

class ShopsPage extends StatefulWidget {
  const ShopsPage({Key? key}) : super(key: key);

  @override
  State<ShopsPage> createState() => _ShopsPageState();
}

class _ShopsPageState extends State<ShopsPage> {
  bool _loading = true;
  List<Shop> _shops = [];
  List<Shop> _filteredShops = [];
  String _error = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchShops(); // Load all shops initially
  }

  /// Fetch all shops from backend
  Future<void> _fetchShops() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final url = Uri.parse('$baseUrl/shops');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final shops = data.map((item) => Shop.fromJson(item)).toList();

        setState(() {
          _shops = shops;
          _filteredShops = shops;
        });
      } else {
        setState(() {
          _error = '❌ Failed to load shops: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = '⚠️ Request failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }
  /// 🔍 Search shops locally by name starting with query
  void _searchShops() {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredShops = _shops;
      });
      return;
    }

    final filtered = _shops
        .where((shop) => shop.name.toLowerCase().startsWith(query))
        .toList();

    setState(() {
      _filteredShops = filtered;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search shops...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.black),
                ),
                style: const TextStyle(color: Colors.black),
                cursorColor: Colors.white,
                onChanged: (_) => _searchShops(), // Live search
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _searchShops,
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : _filteredShops.isEmpty
          ? const Center(child: Text('No shops found'))
          : ListView.builder(
        itemCount: _filteredShops.length,
        itemBuilder: (context, index) {
          final shop = _filteredShops[index];
          return Card(
            margin: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: ListTile(
              leading: shop.imageUrl.isNotEmpty
                  ? Image.network(
                '$baseUrl/proxy_image?url=${Uri.encodeComponent(shop.imageUrl)}',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder:
                    (context, error, stackTrace) =>
                const Icon(Icons.store,
                    size: 50,
                    color: Colors.grey),
              )
                  : const Icon(Icons.store,
                  size: 50, color: Colors.grey),
              title: Text(shop.name),
              subtitle: Text(shop.address),
              trailing: Text(
                shop.status.toUpperCase(),
                style: TextStyle(
                  color: shop.status == 'active'
                      ? Colors.green
                      : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () {
                // Navigate to shop details page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShopDetailsPage(shop: shop),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// 🧾 Shop Details Page - Displays shop info and items

class ShopDetailsPage extends StatelessWidget {
  final Shop shop;

  const ShopDetailsPage({Key? key, required this.shop}) : super(key: key);

  /// 🧾 Fetch products for this shop
  Future<List<Product>> fetchShopItems() async {
    final response = await http.get(
      Uri.parse('$baseUrl/items/${shop.shopId}'), // ✅ Using shopId now
    );

    if (response.statusCode == 200) {
      final List jsonData = json.decode(response.body);
      return jsonData.map((data) => Product.fromJson(data)).toList();
    } else {
      throw Exception('Failed to load items for ${shop.name}');
    }
  }


  Future<void> addToCart(BuildContext context, Product product) async {
    print('Adding to cart - shopId: ${shop.shopId}'); // ✅ Debug

    try {
      final url = Uri.parse('$baseUrl/add_to_cart');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "user_id": userId,
          "items": [
            {
              "pickle_name": product.name,
              "quantity": 1,
              "cost": product.price,
              "shop_id": shop.shopId, // ✅ Send correct shopId
            }
          ]
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🛒 Added ${product.name} to cart')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed: ${data['message'] ?? 'Unknown error'}'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Error: $e')),
      );
    }
  }


  /// 🟢 Navigate to Order Detail Page
  void _buyNow(BuildContext context, Product product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailPage(product: product,
            shopId: shop.shopId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${shop.name} Items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 🏪 Shop header
          Container(
            margin: const EdgeInsets.all(16),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    '$baseUrl/proxy_image?url=${Uri.encodeComponent(shop.imageUrl)}',
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: double.infinity,
                        height: 180,
                        color: Colors.grey[200],
                        child: const Icon(Icons.store, size: 80, color: Colors.grey),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  shop.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  shop.address,
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 5),
                Text(
                  shop.status.toUpperCase(),
                  style: TextStyle(
                    color: shop.status == 'active' ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // 🛍️ Items Table Section
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: fetchShopItems(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('No items available for ${shop.name}'));
                }

                final products = snapshot.data!;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
                    columns: const [
                      DataColumn(label: Text('Image')),
                      DataColumn(label: Text('Item Name')),
                      DataColumn(label: Text('Price')),
                      DataColumn(label: Text('Actions')),
                    ],
                    rows: products.map((product) {
                      return DataRow(cells: [
                        DataCell(
                          Image.network(
                            '$baseUrl/proxy_image?url=${Uri.encodeComponent(product.imageUrl)}',
                            width: 60,
                            height: 60,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.image_not_supported, color: Colors.grey);
                            },
                          ),
                        ),
                        DataCell(Text(product.name)),
                        DataCell(Text('₹${product.price.toStringAsFixed(2)}')),
                        DataCell(
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: () => addToCart(context, product),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                ),
                                child: const Text('Add to Cart'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _buyNow(context, product),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text('Buy Now'),
                              ),
                            ],
                          ),
                        ),
                      ]);
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ CartPage
class CartPage extends StatefulWidget {
  const CartPage({Key? key}) : super(key: key);

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  List<dynamic> cartItems = [];
  bool isLoading = false;
  double totalCost = 0.0;

  @override
  void initState() {
    super.initState();
    fetchCart();
  }

  Future<void> fetchCart() async {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User ID not found. Please log in.')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final url = Uri.parse('$baseUrl/your_cart?user_id=$userId');
      final response = await http.get(url, headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          final List<dynamic> items = data['cart_items'];

          double computedTotal = 0.0;
          for (var item in items) {
            final cost = double.tryParse(item['cost'].toString()) ?? 0.0;
            final quantity = double.tryParse(item['quantity'].toString()) ?? 1.0;
            computedTotal += cost * quantity;
          }

          setState(() {
            cartItems = items;
            totalCost = computedTotal;
          });
        } else {
          print("Error: ${data['error']}");
        }
      } else {
        print("HTTP error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching cart: $e");
    }

    setState(() => isLoading = false);
  }

  Future<void> removeItem(int cartItemId) async {
    final url = Uri.parse('$baseUrl/remove_from_cart');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "user_id": userId,
        "cart_item_id": cartItemId,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item removed from cart')),
        );
        fetchCart();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove item')),
      );
    }
  }

  // ✅ BUY SINGLE ITEM → Navigate to OrderDetailPage
  // In _CartPageState class - Update buyItem method
  void buyItem(dynamic item) {
    final int itemShopId = item['shop_id'] ?? 0;

    if (itemShopId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Cannot order: Shop information missing')),
      );
      return;
    }

    final product = Product(
      id: item['id'] ?? 0,
      name: item['pickle_name'] ?? 'Unknown Pickle',
      imageUrl: item['image_url'] ?? '',
      price: double.tryParse(item['cost'].toString()) ?? 0.0,
      shopId: itemShopId, // ✅ Use actual shopId
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          shopId: product.shopId,
          product: product,
        ),
      ),
    );
  }

  // ✅ BUY ALL ITEMS (if same shop) → Navigate to OrderDetailPage
  // In _CartPageState class - Update buyAll method
  void buyAll() {
    if (cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your cart is empty')),
      );
      return;
    }

    // ✅ Validate all items have valid shop_id
    final validItems = cartItems.where((item) =>
    (item['shop_id'] ?? 0) > 0).toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Invalid shop information in cart items')),
      );
      return;
    }

    final shopIds = validItems.map((item) => item['shop_id']).toSet();

    if (shopIds.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ You can only buy items from the same shop together.'),
        ),
      );
      return;
    }

    final int shopId = validItems.first['shop_id'] ?? 0;

    if (shopId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Invalid shop information')),
      );
      return;
    }

    final productNames = validItems
        .map((item) => item['pickle_name'] ?? 'Unnamed')
        .join(', ');

    final firstItem = validItems.first;

    final product = Product(
      id: 0,
      name: productNames,
      imageUrl: firstItem['image_url'] ?? '',
      price: totalCost,
      shopId: shopId, // ✅ Valid shopId
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailPage(
          shopId: shopId,
          product: product,
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        backgroundColor: Colors.green,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : cartItems.isEmpty
          ? const Center(child: Text('Your cart is empty'))
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: cartItems.length,
              itemBuilder: (context, index) {
                final item = cartItems[index];
                final name = item['pickle_name'] ?? 'Unknown';
                final quantity =
                    int.tryParse(item['quantity'].toString()) ?? 1;
                final cost =
                    double.tryParse(item['cost'].toString()) ?? 0.0;
                final total = quantity * cost;

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text(
                        'Qty: $quantity | ₹$cost each | Total: ₹$total'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete,
                              color: Colors.red),
                          onPressed: () => removeItem(item['id']),
                        ),
                        IconButton(
                          icon: const Icon(Icons.shopping_cart_checkout,
                              color: Colors.green),
                          onPressed: () => buyItem(item),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  offset: const Offset(0, -1),
                  blurRadius: 5,
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ₹${totalCost.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.payment),
                  onPressed: buyAll,
                  label: const Text('Buy All'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
// ORDERS PAGE

class OrdersPage extends StatefulWidget {
  const OrdersPage({Key? key}) : super(key: key);

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  // ==================================================
  // 🔹 Fetch Orders from Flask
  // ==================================================
  Future<void> _fetchOrders() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final url = Uri.parse('$baseUrl/orders_info?user_id=$userId');
      final response = await http.get(url, headers: {'Content-Type': 'application/json'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'ok' && data['orders'] != null) {
          setState(() {
            _orders = List<Map<String, dynamic>>.from(data['orders']);
            _error = '';
          });
        } else {
          setState(() {
            _error = 'API error: ${data['error'] ?? 'Unknown error'}';
          });
        }
      } else {
        setState(() {
          _error = 'Failed to load orders: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Request failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // ==================================================
  // 🔹 Show Confirmation Dialog
  // ==================================================
  Future<bool> _showCancelConfirmationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    return result ?? false; // Default to false if dialog dismissed
  }

  // ==================================================
  // 🔹 Cancel (Delete) Order Function
  // ==================================================
  Future<void> _cancelOrder(int orderId) async {
    try {
      final confirmed = await _showCancelConfirmationDialog(context);
      if (!confirmed) return; // User canceled

      final url = Uri.parse('$baseUrl/remove_item');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'order_id': orderId,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully')),
        );
        await _fetchOrders(); // Refresh list after deletion
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel: ${data['message'] ?? 'Unknown error'}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request failed: $e')),
      );
    }
  }

  // ==================================================
  // 🔹 Build Orders Table
  // ==================================================
  Widget _buildOrdersTable() {
    if (_orders.isEmpty) {
      return const Center(child: Text('No orders found'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('user ID')),
          DataColumn(label: Text('Pickles')),
          DataColumn(label: Text('Quantity')),
          DataColumn(label: Text('Cost')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Created At')),
          DataColumn(label: Text('Action')),
        ],
        rows: _orders.map((order) {
          final status = order['status'] ?? '';
          final isCancellable = status == 'Ordered'; // only active orders can be cancelled

          return DataRow(cells: [
            DataCell(Text(order['id'].toString())),
            DataCell(Text(order['user_id'].toString())),
            DataCell(Text(order['pickles'] ?? '')),
            DataCell(Text(order['quantity'].toString())),
            DataCell(Text('₹${order['cost'].toString()}')),
            DataCell(Text(status)),
            DataCell(Text(order['created_at'] ?? '')),
            DataCell(
              isCancellable
                  ? ElevatedButton(
                onPressed: () => _cancelOrder(order['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cancel'),
              )
                  : const Text('—'),
            ),
          ]);
        }).toList(),
      ),
    );
  }

  // ==================================================
  // 🔹 Main Build
  // ==================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Orders')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : Padding(
        padding: const EdgeInsets.all(8.0),
        child: _buildOrdersTable(),
      ),
    );
  }
}




class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login & Shop Demo',
      home: const LoginPage(),
    );
  }
}

// ==========================
// LOGIN PAGE
// ==========================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      _showMessage('Please enter username and password');
      return;
    }

    setState(() => _loading = true);

    try {
      final url = Uri.parse('$baseUrl/login');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'ok') {
        userId = responseData['user']['id'];
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChoicePage()),
        );
      } else {
        _showMessage('❌ Login failed: ${responseData['error']}');
      }
    } catch (e) {
      _showMessage('⚠️ Request failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Login Result'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _login, child: const Text('Login')),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                );
              },
              child: const Text("Don't have an account? Register"),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ChoicePage()),
                );
              },
              child: const Text('Skip'),
            ),
          ],
        ),
      ),
    );
  }
}


class ChoicePage extends StatelessWidget {
  const ChoicePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose View'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersPage()),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShopPage()),
                );
              },
              child: const Text('Items View'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShopsPage()),
                );
              },
              child: const Text('Shops View'),
            ),
          ],
        ),
      ),
    );
  }
}// ==========================
// REGISTER PAGE
// ==========================
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Please fill all fields');
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Passwords do not match');
      return;
    }

    setState(() => _loading = true);

    try {
      final url = Uri.parse('$baseUrl/register');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == 'ok') {
        _showMessage('✅ Registered successfully!');
        Navigator.pop(context);
      } else {
        _showMessage('❌ Registration failed: ${responseData['error']}');
      }
    } catch (e) {
      _showMessage('⚠️ Request failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showMessage(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Register Result'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            TextField(
              controller: _confirmPasswordController,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(onPressed: _register, child: const Text('Register')),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Already have an account? Login"),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================
// SHOP PAGE (Product Grid)
// ==========================

class ShopPage extends StatefulWidget {
  const ShopPage({Key? key}) : super(key: key);

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  bool _loading = true;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  String _error = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProducts(); // Load all products initially
  }

  /// Fetch all products from backend
  Future<void> _fetchProducts() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final url = Uri.parse('$baseUrl/products');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        if (data['status'] == 'ok' && data['products'] != null) {
          final List<dynamic> productsData = data['products'];
          final products =
          productsData.map((item) => Product.fromJson(item)).toList();

          setState(() {
            _products = products;
            _filteredProducts = products;
          });
        } else {
          setState(() {
            _error = '❌ API error: ${data['error']}';
          });
        }
      } else {
        setState(() {
          _error = '❌ Failed to load products: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _error = '⚠️ Request failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  /// 🔍 Search products locally by name starting with query
  void _searchProducts() {
    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredProducts = _products;
      });
      return;
    }

    final filtered = _products
        .where((product) => product.name.toLowerCase().startsWith(query))
        .toList();

    setState(() {
      _filteredProducts = filtered;
    });
  }

  /// 🛒 Add to Cart function
  void _addToCart(Product product) async {
    try {
      final url = Uri.parse('$baseUrl/add_to_cart');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "user_id": userId,
          "items": [
            {
              "pickle_name": product.name,
              "quantity": 1,
              "cost": product.price,
              "shop_id": product.shopId, // 👈 Added this
            }
          ]
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🛒 Added ${product.name} to cart')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed: ${data['message'] ?? 'Unknown'}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Error adding to cart: $e')),
      );
    }
  }

  // In _ShopPageState class - Replace the _buyNow method
  void _buyNow(Product product) {
    if (product.shopId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Cannot order: Shop information missing')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderDetailPage(
          product: product,
          shopId: product.shopId, // ✅ Use actual shopId from product
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search products...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.black),
                ),
                style: const TextStyle(color: Colors.black),
                cursorColor: Colors.black,
                onChanged: (_) => _searchProducts(), // Live search
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _searchProducts,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.store), // Store icon
            tooltip: 'View Shops',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopsPage()),
              );
            },
          ),

          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CartPage()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const OrdersPage()));
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(child: Text(_error))
          : _filteredProducts.isEmpty
          ? const Center(child: Text('No products found'))
          : Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.builder(
          itemCount: _filteredProducts.length,
          gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.7,
          ),
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            return Card(
              elevation: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: product.imageUrl.isNotEmpty
                        ? Image.network(
                      '$baseUrl/proxy_image?url=${Uri.encodeComponent(product.imageUrl)}',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image,
                          size: 50, color: Colors.grey),
                    )
                        : const Icon(Icons.broken_image,
                        size: 50, color: Colors.grey),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Text(
                      product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '₹${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _addToCart(product),
                        child: const Text('Add to Cart'),
                      ),
                      ElevatedButton(
                        onPressed: () => _buyNow(product),
                        child: const Text('Buy'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
class OrderDetailPage extends StatefulWidget {
  final Product product;
  final int? shopId; // ✅ nullable now

  const OrderDetailPage({Key? key, required this.product, this.shopId})
      : super(key: key);

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  LatLng? _selectedLocation;

  bool _loadingLocation = true;
  bool _loadingCalc = false;
  bool _loadingBuy = false;

  double? _distanceKm;
  double? _deliveryCharge;
  double? _finalCost;
  int? _shopId; // ✅ nullable, no default 0

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return setState(() => _loadingLocation = false);

    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _loadingLocation = false);
      return;
    }

    Position pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      _loadingLocation = false;
    });
  }

  /// 🔢 Calculate distance and delivery charge
  Future<void> _calculateDistance() async {
    if (_selectedLocation == null) return;

    setState(() => _loadingCalc = true);

    final url = Uri.parse('$baseUrl/distance_finder');
    final body = {
      "latitude": _selectedLocation!.latitude,
      "longitude": _selectedLocation!.longitude,
      if (widget.shopId != null) "shop_id": widget.shopId, // ✅ only if available
      "items": [
        {
          "pickle_name": widget.product.name,
          "quantity": 1,
          "cost": widget.product.price
        }
      ]
    };

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(res.body);

      if (data['success'] == true) {
        setState(() {
          _distanceKm = (data['distance_km'] as num?)?.toDouble() ?? 0.0;
          _deliveryCharge = (data['delivery_charge'] as num?)?.toDouble() ?? 0.0;
          _finalCost = (data['final_cost'] as num?)?.toDouble() ?? 0.0;
          _shopId = (data['shop_id'] as int?) ?? widget.shopId; // ✅ use backend or existing
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${data['message']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ $e')),
      );
    } finally {
      setState(() => _loadingCalc = false);
    }
  }

  /// 🛒 Confirm & Place Order
  Future<void> _confirmAndBuy() async {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 Please select a location')),
      );
      return;
    }

    if (_shopId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Shop information is missing.')),
      );
      return;
    }

    setState(() => _loadingBuy = true);

    final url = Uri.parse('$baseUrl/buy_now');
    final body = {
      "user_id": userId,
      "latitude": _selectedLocation!.latitude,
      "longitude": _selectedLocation!.longitude,
      "shop_id": _shopId, // ✅ correct shop id
      "distance_km": _distanceKm ?? 0.0,
      "delivery_charge": _deliveryCharge ?? 0.0,
      "final_cost": _finalCost ?? 0.0,
      "items": [
        {
          "pickle_name": widget.product.name,
          "quantity": 1,
          "cost": widget.product.price
        }
      ]
    };

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = jsonDecode(res.body);

      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Order placed successfully for ${widget.product.name}!')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${data['message']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Error: $e')),
      );
    } finally {
      setState(() => _loadingBuy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: _loadingLocation
          ? const Center(child: CircularProgressIndicator())
          : _currentLocation == null
          ? const Center(child: Text("Unable to fetch location"))
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: product.imageUrl.isNotEmpty
                    ? Image.network(
                  '$baseUrl/proxy_image?url=${Uri.encodeComponent(product.imageUrl)}',
                  height: 180,
                  fit: BoxFit.cover,
                )
                    : const Icon(Icons.broken_image,
                    size: 100, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Text(product.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Price: ₹${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 18, color: Colors.green)),
              const Divider(height: 32),
              const Text('Select Delivery Location (2 km radius)',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 300,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLocation!,
                    initialZoom: 15.0,
                    onTap: (tapPos, point) {
                      setState(() {
                        _selectedLocation = point;
                        _distanceKm = null;
                        _deliveryCharge = null;
                        _finalCost = null;
                        _shopId = null;
                      });
                      _calculateDistance();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: 'com.example.app',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                          point: _currentLocation!,
                          width: 60,
                          height: 60,
                          child: const Icon(Icons.my_location,
                              color: Colors.blue, size: 35))
                    ]),
                    if (_selectedLocation != null)
                      MarkerLayer(markers: [
                        Marker(
                            point: _selectedLocation!,
                            width: 60,
                            height: 60,
                            child: const Icon(Icons.location_pin,
                                color: Colors.red, size: 45))
                      ]),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _selectedLocation == null
                      ? "📍 Tap on map to select location"
                      : "Selected: ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(height: 20),
              if (_loadingCalc)
                const Center(child: CircularProgressIndicator()),
              if (_distanceKm != null) ...[
                Text('Distance: ${_distanceKm!.toStringAsFixed(2)} km'),
                Text('Delivery Charge: ₹${_deliveryCharge!.toStringAsFixed(2)}'),
                Text('Final Cost: ₹${_finalCost!.toStringAsFixed(2)}'),
                const SizedBox(height: 20),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: _loadingBuy
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : const Text('Confirm & Buy'),
                  onPressed: (_selectedLocation == null ||
                      _distanceKm == null ||
                      _loadingBuy)
                      ? null
                      : _confirmAndBuy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
