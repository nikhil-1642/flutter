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
        title: const Text('Message'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'shopowner':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ShopLogin()),
        );
        break;
      case 'delivery':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DeliveryPage()),
        );
        break;
    }
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
      appBar: AppBar(
        title: const Text('Login'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'shopowner',
                child: Text('Shop Owner'),
              ),
              PopupMenuItem(
                value: 'delivery',
                child: Text('Delivery'),
              ),
            ],
          ),
        ],
      ),
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
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text('Login'),
                  ),
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
class ShopLogin extends StatefulWidget {
  const ShopLogin({super.key});

  @override
  State<ShopLogin> createState() => _ShopLoginState();
}

class _ShopLoginState extends State<ShopLogin> {
  bool isLogin = true;
  bool isLoading = false;

  // Common Controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // Register Controllers
  final TextEditingController shopNameController = TextEditingController();
  final TextEditingController shopTypeController = TextEditingController();
  final TextEditingController ownerController = TextEditingController();
  final TextEditingController contactController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController stateController = TextEditingController();
  final TextEditingController postalController = TextEditingController();
  final TextEditingController countryController = TextEditingController(text: "India");
  final TextEditingController openingController = TextEditingController();
  final TextEditingController closingController = TextEditingController();
  final TextEditingController latitudeController = TextEditingController();
  final TextEditingController longitudeController = TextEditingController();
  final TextEditingController imageController = TextEditingController();

  void toggleView() => setState(() => isLogin = !isLogin);

  // ---------------- LOGIN ----------------
  Future<void> handleLogin() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    setState(() => isLoading = true);

    final loginUrl = "$baseUrl/shop_login";
    final loginBody = {
      "email": emailController.text.trim(),
      "password": passwordController.text.trim(),
    };

    try {
      print("🔹 Sending login request to: $loginUrl");
      print("🔹 Request body: $loginBody");

      final loginResponse = await http.post(
        Uri.parse(loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(loginBody),
      );

      print("🔹 Login response: ${loginResponse.body}");
      final loginData = jsonDecode(loginResponse.body);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loginData["message"] ?? "Login result")),
      );

      if (loginData["status"] == "ok") {
        print("✅ Login success, fetching shop info...");

        final shopUrl = "$baseUrl/shop_by_email";
        final shopResponse = await http.post(
          Uri.parse(shopUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({"email": emailController.text.trim()}),
        );

        print("🔹 Shop response: ${shopResponse.body}");
        final shopData = jsonDecode(shopResponse.body);

        if (shopData["status"] == "ok") {
          final shop = shopData["shop"];
          final int shopUserId = shop["shop_id"];
          print("✅ Shop ID fetched: $shopUserId");

          // ✅ Navigate to ShopOwnerInfo
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ShopOwnerInfo(shopUserId: shopUserId),
            ),
          );
        } else {
          print("❌ Shop not found or status not ok");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(shopData["error"] ?? "Shop not found")),
          );
        }
      } else {
        print("❌ Login failed: ${loginData["status"]}");
      }
    } catch (e) {
      print("🔥 Exception during login: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }
  // ---------------- REGISTER ----------------
  Future<void> handleRegister() async {
    if (shopNameController.text.isEmpty ||
        ownerController.text.isEmpty ||
        contactController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all required fields")),
      );
      return;
    }

    setState(() => isLoading = true);

    final url = "$baseUrl/shop_register";
    final body = {
      "shop_name": shopNameController.text,
      "shop_type": shopTypeController.text,
      "owner_name": ownerController.text,
      "contact_number": contactController.text,
      "email": emailController.text,
      "address": addressController.text,
      "city": cityController.text,
      "state": stateController.text,
      "postal_code": postalController.text,
      "country": countryController.text,
      "opening_time": openingController.text,
      "closing_time": closingController.text,
      "image_url": imageController.text,
      "latitude": latitudeController.text,
      "longitude": longitudeController.text,
      "password": passwordController.text,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data["message"] ?? "Registration result")),
      );

      if (data["status"] == "ok") {
        toggleView(); // Go back to login after registration
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isLogin ? "Shop Login" : "Shop Registration"),
        leading: !isLogin
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: toggleView,
        )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (isLogin) ...[
              // LOGIN UI
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: "Password"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : handleLogin,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Login"),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: toggleView,
                child: const Text("Don’t have an account? Register Now"),
              ),
            ] else ...[
              // REGISTER UI
              TextField(controller: shopNameController, decoration: const InputDecoration(labelText: "Shop Name")),
              TextField(controller: shopTypeController, decoration: const InputDecoration(labelText: "Shop Type")),
              TextField(controller: ownerController, decoration: const InputDecoration(labelText: "Owner Name")),
              TextField(controller: contactController, decoration: const InputDecoration(labelText: "Contact Number")),
              TextField(controller: addressController, decoration: const InputDecoration(labelText: "Address")),
              TextField(controller: cityController, decoration: const InputDecoration(labelText: "City")),
              TextField(controller: stateController, decoration: const InputDecoration(labelText: "State")),
              TextField(controller: postalController, decoration: const InputDecoration(labelText: "Postal Code")),
              TextField(controller: countryController, decoration: const InputDecoration(labelText: "Country")),
              TextField(controller: openingController, decoration: const InputDecoration(labelText: "Opening Time (HH:MM:SS)")),
              TextField(controller: closingController, decoration: const InputDecoration(labelText: "Closing Time (HH:MM:SS)")),
              TextField(controller: latitudeController, decoration: const InputDecoration(labelText: "Latitude")),
              TextField(controller: longitudeController, decoration: const InputDecoration(labelText: "Longitude")),
              TextField(controller: imageController, decoration: const InputDecoration(labelText: "Image URL")),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email")),
              TextField(controller: passwordController, decoration: const InputDecoration(labelText: "Password"), obscureText: true),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: isLoading ? null : handleRegister,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Register"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


class ShopOwnerInfo extends StatefulWidget {
  final int shopUserId; // shop_id
  const ShopOwnerInfo({super.key, required this.shopUserId});

  @override
  State<ShopOwnerInfo> createState() => _ShopOwnerInfoState();
}

class _ShopOwnerInfoState extends State<ShopOwnerInfo> {
  List<dynamic> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchShopOrders();
  }

  Future<void> fetchShopOrders() async {
    final url = Uri.parse('$baseUrl/shop_orders');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shop_id": widget.shopUserId}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        setState(() {
          orders = (result is List) ? result : [];
          isLoading = false;
        });
      } else {
        setState(() {
          orders = [];
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        orders = [];
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
          appBar: AppBar(
            title: const Text("Shop Owner Info"),
            actions: [
              IconButton(
                icon: const Icon(Icons.person),
                tooltip: "Profile",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          OwnerDetails(shopUserId: widget.shopUserId),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.store),
                tooltip: "Products",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProductsInfo(shopUserId: widget.shopUserId),
                    ),
                  );
                },
              ),
            ],
          ),


      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
          ? const Center(child: Text("No orders found"))
          : ListView.builder(
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.shopping_bag),
              title: Text(order['ordered_product'] ?? "Unknown Product"),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Quantity: ${order['quantity']}"),
                  Text("Price: \$${order['cost']}"),
                  Text("Final Cost: \$${order['final_cost']}"),
                  Text("Date: ${order['order_date']}"),
                  const SizedBox(height: 4),
                  Text(
                    "Customer: ${order['user_name']}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
class ProductsInfo extends StatefulWidget {
  final int shopUserId;
  const ProductsInfo({super.key, required this.shopUserId});

  @override
  State<ProductsInfo> createState() => _ProductsInfoState();
}

class _ProductsInfoState extends State<ProductsInfo> {
  List<dynamic> products = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    setState(() {
      isLoading = true;
    });

    final url = Uri.parse('$baseUrl/ownerproducts');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"shop_id": widget.shopUserId}),
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        setState(() {
          products = (result is List) ? result : [];
          isLoading = false;
        });
      } else {
        setState(() {
          products = [];
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        products = [];
        isLoading = false;
      });
    }
  }

  Future<void> deleteProduct(int productId) async {
    final url = Uri.parse('$baseUrl/delete_owner_product');

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"product_id": productId}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product deleted successfully")),
        );
        fetchProducts();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to delete product")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Products Info"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: "Add Product",
            onPressed: () async {
              // Navigate to AddProductPage and refresh list after adding
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddProductPage(shopUserId: widget.shopUserId),
                ),
              );
              fetchProducts();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : products.isEmpty
          ? const Center(child: Text("No products found"))
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      product['image_url'] != null
                          ? Image.network(
                        '$baseUrl/proxy_image?url=${Uri.encodeComponent(product['image_url'])}',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.broken_image, size: 80),
                      )
                          : const Icon(Icons.image_not_supported, size: 80),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'] ?? "",
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text("Category: ${product['category'] ?? "-"}"),
                            Text("Price: \$${product['price']}"),
                            Text("Stock: ${product['quantity_in_stock']}"),
                            Text("Date Added: ${product['date_added'] ?? "-"}"),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.edit),
                                  label: const Text("Edit"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                  ),
                                  onPressed: () async {
                                    // Navigate to UpdateProductPage
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UpdateProductPage(
                                          product: product,
                                        ),
                                      ),
                                    );
                                    fetchProducts();
                                  },
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.delete),
                                  label: const Text("Delete"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text("Confirm Delete"),
                                        content: const Text(
                                            "Are you sure you want to delete this product?"),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text("Cancel"),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              deleteProduct(product['id']);
                                            },
                                            child: const Text("Delete"),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class UpdateProductPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const UpdateProductPage({super.key, required this.product});

  @override
  State<UpdateProductPage> createState() => _UpdateProductPageState();
}

class _UpdateProductPageState extends State<UpdateProductPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController nameController;
  late TextEditingController categoryController;
  late TextEditingController priceController;
  late TextEditingController stockController;
  late TextEditingController imageUrlController;
  bool isSubmitting = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.product['name']);
    categoryController =
        TextEditingController(text: widget.product['category']);
    priceController =
        TextEditingController(text: widget.product['price'].toString());
    stockController =
        TextEditingController(text: widget.product['quantity_in_stock'].toString());
    imageUrlController = TextEditingController(text: widget.product['image_url']);
  }

  Future<void> updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isSubmitting = true;
    });

    final url = Uri.parse('$baseUrl/update_product_owner');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "product_id": widget.product['id'],
          "name": nameController.text,
          "category": categoryController.text,
          "price": double.tryParse(priceController.text) ?? 0,
          "quantity_in_stock": int.tryParse(stockController.text) ?? 0,
          "image_url": imageUrlController.text,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product updated successfully")),
        );
        Navigator.pop(context, true); // return true to refresh list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update product")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() {
        isSubmitting = false;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[100],
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Update Product"), backgroundColor: Colors.teal),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField(
                  controller: nameController,
                  label: "Product Name",
                  icon: Icons.shopping_bag,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter product name" : null),
              const SizedBox(height: 16),
              _buildTextField(
                  controller: categoryController,
                  label: "Category",
                  icon: Icons.category,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter category" : null),
              const SizedBox(height: 16),
              _buildTextField(
                  controller: priceController,
                  label: "Price",
                  icon: Icons.attach_money,
                  keyboardType: TextInputType.number,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter price" : null),
              const SizedBox(height: 16),
              _buildTextField(
                  controller: stockController,
                  label: "Stock Quantity",
                  icon: Icons.inventory,
                  keyboardType: TextInputType.number,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter stock quantity" : null),
              const SizedBox(height: 16),
              _buildTextField(
                  controller: imageUrlController,
                  label: "Image URL",
                  icon: Icons.image),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : updateProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Update Product", style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ----------------- Add Product Page -----------------
class AddProductPage extends StatefulWidget {
  final int shopUserId;
  const AddProductPage({super.key, required this.shopUserId});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  final TextEditingController imageUrlController = TextEditingController();

  bool isSubmitting = false;

  Future<void> addProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      isSubmitting = true;
    });

    final url = Uri.parse('$baseUrl/add_owner_product');
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "shop_id": widget.shopUserId,
          "name": nameController.text,
          "category": categoryController.text,
          "price": double.tryParse(priceController.text) ?? 0,
          "quantity_in_stock": int.tryParse(stockController.text) ?? 0,
          "image_url": imageUrlController.text,
        }),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product added successfully")),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to add product")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() {
        isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Product"),
        backgroundColor: Colors.teal,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Enter Product Details",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Name
                _buildTextField(
                  controller: nameController,
                  label: "Product Name",
                  icon: Icons.shopping_bag,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter product name" : null,
                ),
                const SizedBox(height: 16),

                // Category
                _buildTextField(
                  controller: categoryController,
                  label: "Category",
                  icon: Icons.category,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter category" : null,
                ),
                const SizedBox(height: 16),

                // Price
                _buildTextField(
                  controller: priceController,
                  label: "Price",
                  icon: Icons.attach_money,
                  keyboardType: TextInputType.number,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter price" : null,
                ),
                const SizedBox(height: 16),

                // Stock
                _buildTextField(
                  controller: stockController,
                  label: "Quantity in Stock",
                  icon: Icons.inventory,
                  keyboardType: TextInputType.number,
                  validator: (val) =>
                  val!.isEmpty ? "Please enter stock quantity" : null,
                ),
                const SizedBox(height: 16),

                // Image URL
                _buildTextField(
                  controller: imageUrlController,
                  label: "Image URL",
                  icon: Icons.image,
                ),
                const SizedBox(height: 24),

                // Add Button
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSubmitting ? null : addProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: isSubmitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                      "Add Product",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[100],
      ),
      validator: validator,
    );
  }
}


// ✅profile  OwnerDetails page (receives shopUserId)
class OwnerDetails extends StatefulWidget {
  final int shopUserId;

  const OwnerDetails({super.key, required this.shopUserId});

  @override
  State<OwnerDetails> createState() => _OwnerDetailsState();
}

class _OwnerDetailsState extends State<OwnerDetails> {
  Map<String, dynamic> shop = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOwnerDetails();
  }

  Future<void> fetchOwnerDetails() async {
    final url = Uri.parse('$baseUrl/owner-details/${widget.shopUserId}');
    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          setState(() {
            shop = data['shop'];
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
          });
        }
      } else {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      print("❌ Error fetching shop details: $e");
    }
  }

  Widget buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(value.isNotEmpty ? value : "-"),
          ),
        ],
      ),
    );
  }

  // ===== Edit Form =====
  void showEditForm() {
    final _formKey = GlobalKey<FormState>();

    // Controllers initialized with current values
    final nameCtrl = TextEditingController(text: shop['shop_name']);
    final typeCtrl = TextEditingController(text: shop['shop_type']);
    final ownerCtrl = TextEditingController(text: shop['owner_name']);
    final contactCtrl = TextEditingController(text: shop['contact_number']);
    final emailCtrl = TextEditingController(text: shop['email']);
    final addressCtrl = TextEditingController(text: shop['address']);
    final cityCtrl = TextEditingController(text: shop['city']);
    final stateCtrl = TextEditingController(text: shop['state']);
    final statusCtrl = TextEditingController(text: shop['status']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Owner Details"),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Shop Name")),
                TextFormField(controller: typeCtrl, decoration: const InputDecoration(labelText: "Shop Type")),
                TextFormField(controller: ownerCtrl, decoration: const InputDecoration(labelText: "Owner Name")),
                TextFormField(controller: contactCtrl, decoration: const InputDecoration(labelText: "Contact Number")),
                TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: "Email")),
                TextFormField(controller: addressCtrl, decoration: const InputDecoration(labelText: "Address")),
                TextFormField(controller: cityCtrl, decoration: const InputDecoration(labelText: "City")),
                TextFormField(controller: stateCtrl, decoration: const InputDecoration(labelText: "State")),
                TextFormField(controller: statusCtrl, decoration: const InputDecoration(labelText: "Status")),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              // Send update request
              final url = Uri.parse('$baseUrl/update-owner-details/${widget.shopUserId}');
              final body = {
                "shop_name": nameCtrl.text,
                "shop_type": typeCtrl.text,
                "owner_name": ownerCtrl.text,
                "contact_number": contactCtrl.text,
                "email": emailCtrl.text,
                "address": addressCtrl.text,
                "city": cityCtrl.text,
                "state": stateCtrl.text,
                "status": statusCtrl.text,
              };
              try {
                final res = await http.put(
                  url,
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode(body),
                );
                final result = jsonDecode(res.body);
                if (res.statusCode == 200 && result['status'] == 'ok') {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Details updated successfully ✅")));
                  Navigator.pop(context);
                  fetchOwnerDetails(); // Refresh data
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Update failed: ${result['message']}")));
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Update failed: $e")));
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Owner Details"),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: "Edit Details",
            onPressed: () {
              if (!isLoading) showEditForm();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              shop['image_url'] != null && shop['image_url'] != ""
                  ? Center(
                child: Image.network(
                  shop['image_url'],
                  height: 120,
                ),
              )
                  : const SizedBox.shrink(),
              const SizedBox(height: 20),
              buildRow("Shop Name", shop['shop_name'] ?? ""),
              buildRow("Shop Type", shop['shop_type'] ?? ""),
              buildRow("Owner Name", shop['owner_name'] ?? ""),
              buildRow("Contact Number", shop['contact_number'] ?? ""),
              buildRow("Email", shop['email'] ?? ""),
              buildRow("Address", shop['address'] ?? ""),
              buildRow("City", shop['city'] ?? ""),
              buildRow("State", shop['state'] ?? ""),
              buildRow("Postal Code", shop['postal_code'] ?? ""),
              buildRow("Country", shop['country'] ?? ""),
              buildRow("Opening Time", shop['opening_time'] ?? ""),
              buildRow("Closing Time", shop['closing_time'] ?? ""),
              buildRow("Status", shop['status'] ?? ""),
              buildRow("Latitude", shop['latitude']?.toString() ?? ""),
              buildRow("Longitude", shop['longitude']?.toString() ?? ""),
              buildRow("Created At", shop['created_at'] ?? ""),
              buildRow("Updated At", shop['updated_at'] ?? ""),
            ],
          ),
        ),
      ),
    );
  }
}

class DeliveryPage extends StatelessWidget {
  const DeliveryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Page')),
      body: const Center(
        child: Text(
          'Welcome, Delivery Person! 🚚',
          style: TextStyle(fontSize: 22),
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
  final int? shopId;

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
  int? _shopId;

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

  Future<void> _calculateDistance() async {
    if (_selectedLocation == null) return;

    setState(() => _loadingCalc = true);

    final url = Uri.parse('$baseUrl/distance_finder');
    final body = {
      "latitude": _selectedLocation!.latitude,
      "longitude": _selectedLocation!.longitude,
      if (widget.shopId != null) "shop_id": widget.shopId,
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
          _shopId = (data['shop_id'] as int?) ?? widget.shopId;
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
      "shop_id": _shopId,
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Details'),
        centerTitle: true,
        elevation: 2,
        backgroundColor: theme.colorScheme.primaryContainer,
        foregroundColor: theme.colorScheme.onPrimaryContainer,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _loadingLocation
            ? const Center(child: CircularProgressIndicator())
            : _currentLocation == null
            ? const Center(child: Text("Unable to fetch location"))
            : Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🖼️ Product Card
                Card(
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Hero(
                          tag: product.name,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: product.imageUrl.isNotEmpty
                                ? Image.network(
                              '$baseUrl/proxy_image?url=${Uri.encodeComponent(product.imageUrl)}',
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                                : const Icon(Icons.broken_image,
                                size: 100, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(product.name,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('₹${product.price.toStringAsFixed(2)}',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: Colors.green)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // 📍 Map Section
                Text('Select Delivery Location (2 km radius)',
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
                const SizedBox(height: 8),

                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
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
                ),

                const SizedBox(height: 12),

                // 🗺️ Map Info Text
                Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _selectedLocation == null
                          ? "📍 Tap on map to select location"
                          : "Selected: ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}",
                      key: ValueKey(_selectedLocation),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                if (_loadingCalc)
                  const Center(child: CircularProgressIndicator()),

                // 💰 Delivery Details
                if (_distanceKm != null) ...[
                  Card(
                    color: theme.colorScheme.surfaceContainerHighest,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow('Distance:',
                              '${_distanceKm!.toStringAsFixed(2)} km'),
                          _infoRow('Delivery Charge:',
                              '₹${_deliveryCharge!.toStringAsFixed(2)}'),
                          _infoRow('Final Cost:',
                              '₹${_finalCost!.toStringAsFixed(2)}',
                              bold: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 🛒 Buy Button
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: _loadingBuy
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : const Icon(Icons.shopping_bag_outlined),
                      label: Text(_loadingBuy
                          ? "Processing..."
                          : "Confirm & Buy"),
                      onPressed: (_selectedLocation == null ||
                          _distanceKm == null ||
                          _loadingBuy)
                          ? null
                          : _confirmAndBuy,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Helper method for cleaner display of price/distance info
  Widget _infoRow(String label, String value, {bool bold = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[700], fontWeight: FontWeight.w500)),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: bold ? theme.colorScheme.primary : Colors.black87,
              )),
        ],
      ),
    );
  }
}