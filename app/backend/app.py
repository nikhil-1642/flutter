from flask import Flask, request, jsonify,Response
from flask_cors import CORS
from db import get_db_connection
from datetime import datetime, date, time, timedelta
import decimal
from decimal import Decimal, ROUND_HALF_UP
from math import radians, sin, cos, sqrt, atan2
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})
import bcrypt
import requests

@app.route('/proxy_image')
def proxy_image():
    url = request.args.get("url")
    if not url:
        return jsonify({"error": "Missing URL"}), 400

    try:
        # Add a real browser user-agent to avoid being blocked by websites
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                          "AppleWebKit/537.36 (KHTML, like Gecko) "
                          "Chrome/120.0 Safari/537.36"
        }

        # Get the image from the remote site
        resp = requests.get(url, headers=headers, timeout=10)

        # If the image URL is invalid or blocked
        if resp.status_code != 200:
            return jsonify({
                "error": f"Failed to fetch image (status {resp.status_code})"
            }), 400

        # Detect and forward the content type properly
        content_type = resp.headers.get("Content-Type", "image/jpeg")

        # Return the binary image data
        return Response(resp.content, mimetype=content_type)

    except Exception as e:
        return jsonify({"error": str(e)}), 500



def convert_product(product):
    return {
        "id": product["id"],
        "name": product["name"],
        "image_url": product["image_url"],
        "price": float(product["price"])  # Convert string to float
    }
@app.route('/update-owner-details/<int:shop_id>', methods=['PUT'])
def update_owner_details(shop_id):
    try:
        data = request.get_json()
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # ✅ Allowed fields to update
        fields = [
            'shop_name', 'shop_type', 'owner_name', 'contact_number', 'email',
            'address', 'city', 'state', 'postal_code', 'country',
            'opening_time', 'closing_time', 'status', 'image_url',
            'latitude', 'longitude'
        ]

        update_data = {k: v for k, v in data.items() if k in fields}

        if not update_data:
            return jsonify({"status": "error", "message": "No valid fields to update"}), 400

        # Build query dynamically
        set_clause = ', '.join([f"{key} = %s" for key in update_data.keys()])
        values = list(update_data.values())
        values.append(shop_id)

        query = f"UPDATE shops SET {set_clause}, updated_at = NOW() WHERE shop_id = %s"
        cursor.execute(query, values)
        conn.commit()

        return jsonify({"status": "ok", "message": "Shop details updated successfully"}), 200

    except Exception as e:
        print(f"❌ Error updating shop details: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# ----------------- Add Product -----------------
@app.route('/add_owner_product', methods=['POST'])
def add_owner_product():
    try:
        data = request.get_json()
        shop_id = data.get('shop_id')
        name = data.get('name')
        category = data.get('category')
        price = data.get('price')
        quantity_in_stock = data.get('quantity_in_stock')
        image_url = data.get('image_url')

        if not all([shop_id, name, category, price is not None, quantity_in_stock is not None]):
            return jsonify({"error": "Missing required fields"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        query = """
        INSERT INTO products (shop_id, name, category, price, quantity_in_stock, image_url, date_added)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """
        cursor.execute(query, (
            shop_id,
            name,
            category,
            price,
            quantity_in_stock,
            image_url,
            datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        ))
        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({"message": "Product added successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
@app.route('/delete_owner_product', methods=['POST'])
def delete_owner_product():
    try:
        data = request.get_json()
        product_id = data.get('product_id')

        if product_id is None:
            return jsonify({"error": "product_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()

        query = "DELETE FROM products WHERE id = %s"
        cursor.execute(query, (product_id,))
        conn.commit()

        cursor.close()
        conn.close()

        return jsonify({"message": "Product deleted successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
# ------------------ UPDATE PRODUCT ------------------
@app.route('/update_product_owner', methods=['POST'])
def update_product_owner():
    try:
        data = request.get_json()
        product_id = data.get("product_id")
        name = data.get("name")
        category = data.get("category")
        price = data.get("price")
        quantity_in_stock = data.get("quantity_in_stock")
        image_url = data.get("image_url")

        if not product_id:
            return jsonify({"error": "product_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE products
            SET name=%s, category=%s, price=%s, quantity_in_stock=%s, image_url=%s
            WHERE id=%s
        """, (name, category, price, quantity_in_stock, image_url, product_id))
        conn.commit()
        cursor.close()
        conn.close()
        return jsonify({"message": "Product updated successfully"}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
# ==================================================
# 1️⃣ Fetch Products
@app.route('/products')
def product_page():
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # ✅ Include shop_id in your query
        cursor.execute("SELECT id, shop_id, name, category, image_url, price, quantity_in_stock, date_added FROM products")
        products = cursor.fetchall()
        cursor.close()
        conn.close()

        products = [
            {
                "id": p["id"],
                "shop_id": p["shop_id"],  # ✅ include
                "name": p["name"],
                "category": p["category"],
                "image_url": p["image_url"],
                "price": float(p["price"]),
                "quantity_in_stock": p["quantity_in_stock"],
                "date_added": p["date_added"]
            }
            for p in products
        ]

        return jsonify({
            'status': 'ok',
            'products': products
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'error': str(e)
        }), 500
@app.route('/ownerproducts', methods=['POST'])
def ownerproduct_page():
    try:
        data = request.get_json()
        shop_id = data.get('shop_id')

        if shop_id is None:
            return jsonify({"error": "shop_id is required"}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        query = """
        SELECT id, shop_id, name, category, image_url, price, quantity_in_stock, date_added
        FROM products
        WHERE shop_id = %s
        """
        cursor.execute(query, (shop_id,))
        products = cursor.fetchall()

        cursor.close()
        conn.close()

        return jsonify(products), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
@app.route('/owner-details/<int:shop_id>', methods=['GET'])
def get_owner_details(shop_id):
    try:
        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM shops WHERE shop_id = %s", (shop_id,))
        shop = cursor.fetchone()

        if not shop:
            return jsonify({"status": "error", "message": "Shop not found"}), 404

        # ✅ Remove sensitive fields
        if 'password' in shop:
            del shop['password']

        # ✅ Convert MySQL objects (time, Decimal, datetime, etc.) to strings
        for key, value in shop.items():
            if isinstance(value, (datetime, date, time, timedelta)):
                shop[key] = str(value)
            elif isinstance(value, Decimal):
                shop[key] = float(value)

        return jsonify({"status": "ok", "shop": shop}), 200

    except Exception as e:
        print(f"❌ Error fetching shop details: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()
# =========================================
# 🧾 Full Shop Registration Route
# =========================================
@app.route('/shop_register', methods=['POST'])
def shop_register():
    data = request.json
    try:
        required_fields = ['shop_name', 'email', 'password']
        if not all(field in data and data[field] for field in required_fields):
            return jsonify({'status': 'error', 'message': 'Missing required fields'}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        # Check if email already exists
        cursor.execute("SELECT * FROM shops WHERE email = %s", (data['email'],))
        if cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({'status': 'error', 'message': 'Email already registered'}), 400

        # Hash password
        hashed_pw = bcrypt.hashpw(data['password'].encode('utf-8'), bcrypt.gensalt())

        # Insert shop record
        cursor.execute("""
            INSERT INTO shops (
                shop_name, shop_type, owner_name, contact_number, email, address, city, state,
                postal_code, country, opening_time, closing_time, status, image_url,
                latitude, longitude, password, created_at
            ) VALUES (
                %s, %s, %s, %s, %s, %s, %s, %s,
                %s, %s, %s, %s, 'active', %s,
                %s, %s, %s, NOW()
            )
        """, (
            data.get('shop_name'),
            data.get('shop_type'),
            data.get('owner_name'),
            data.get('contact_number'),
            data.get('email'),
            data.get('address'),
            data.get('city'),
            data.get('state'),
            data.get('postal_code'),
            data.get('country', 'India'),
            data.get('opening_time'),
            data.get('closing_time'),
            data.get('image_url'),
            data.get('latitude'),
            data.get('longitude'),
            hashed_pw
        ))

        conn.commit()
        cursor.close()
        conn.close()

        return jsonify({'status': 'ok', 'message': 'Shop registered successfully'})

    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500


# =========================================
# 🔑 Shop Login (same as before)
# =========================================
@app.route('/shop_login', methods=['POST'])
def shop_login():
    data = request.json
    try:
        email = data.get('email')
        password = data.get('password')

        if not email or not password:
            return jsonify({'status': 'error', 'message': 'Missing email or password'}), 400

        conn = get_db_connection()
        cursor = conn.cursor(dictionary=True)

        cursor.execute("SELECT * FROM shops WHERE email = %s", (email,))
        shop = cursor.fetchone()
        cursor.close()
        conn.close()

        if not shop:
            return jsonify({'status': 'error', 'message': 'Invalid email or password'}), 400

        if bcrypt.checkpw(password.encode('utf-8'), shop['password'].encode('utf-8')):
            return jsonify({
                'status': 'ok',
                'message': 'Login successful',
                'shop': {
                    'shop_id': shop['shop_id'],
                    'shop_name': shop['shop_name'],
                    'email': shop['email'],
                    'shop_type': shop['shop_type']
                }
            })
        else:
            return jsonify({'status': 'error', 'message': 'Invalid password'}), 400
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# 2️⃣ Add to Cart
# ==================================================
@app.route('/add_to_cart', methods=['POST'])
def add_to_cart():
    data = request.get_json()
    user_id = data.get("user_id")
    items = data.get("items", [])

    if not user_id:
        return jsonify({"success": False, "message": "user_id missing"}), 400

    if not items:
        return jsonify({"success": False, "message": "No items received"}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        for item in items:
            pickle_name = item.get("pickle_name")
            quantity = item.get("quantity")
            cost = item.get("cost")
            shop_id = item.get("shop_id")  # 👈 NEW FIELD

            if not pickle_name or not quantity or not cost or shop_id is None:
                continue  # skip invalid items

            cursor.execute("""
                INSERT INTO cart (user_id, pickle_name, quantity, cost, shop_id)
                VALUES (%s, %s, %s, %s, %s)
            """, (user_id, pickle_name, quantity, cost, shop_id))

        conn.commit()
        return jsonify({"success": True})
    except Exception as e:
        print("Error adding to cart:", e)
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()

# ==================================================
# 3️⃣ Buy Now
# ==================================================
def calc_distance(lat1, lon1, lat2, lon2):
    R = 6371.0  # km
    dlat = radians(float(lat2) - float(lat1))
    dlon = radians(float(lon2) - float(lon1))
    a = sin(dlat / 2)**2 + cos(radians(float(lat1))) * cos(radians(float(lat2))) * sin(dlon / 2)**2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c
@app.route('/buy_now', methods=['POST'])
def buy_now():
    data = request.get_json()
    user_id = data.get("user_id")
    latitude = data.get("latitude")
    longitude = data.get("longitude")
    items = data.get("items", [])
    requested_shop_id = int(data.get("shop_id", 0))  # Get shop_id from client

    if not user_id:
        return jsonify({'success': False, 'message': 'user_id missing'}), 400
    if not items:
        return jsonify({'success': False, 'message': 'No items received'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # Fetch all active shops
        cursor.execute("""
            SELECT shop_id, latitude, longitude 
            FROM shops 
            WHERE status = 'active' AND latitude IS NOT NULL AND longitude IS NOT NULL
        """)
        shops = cursor.fetchall()
        if not shops:
            return jsonify({'success': False, 'message': 'No active shops found'}), 404

        # Determine which shop to use
        if requested_shop_id == 0:
            # Choose nearest shop
            nearest_shop = min(
                shops,
                key=lambda shop: calc_distance(latitude, longitude, shop[1], shop[2])
            )
            shop_id, shop_lat, shop_lon = nearest_shop
        else:
            # Try to find requested shop
            shop_found = next((s for s in shops if s[0] == requested_shop_id), None)
            if shop_found:
                shop_id, shop_lat, shop_lon = shop_found
            else:
                # If requested shop_id not found, fallback to nearest
                nearest_shop = min(
                    shops,
                    key=lambda shop: calc_distance(latitude, longitude, shop[1], shop[2])
                )
                shop_id, shop_lat, shop_lon = nearest_shop

        # Calculate distance and delivery charge
        distance_km = Decimal(str(calc_distance(latitude, longitude, shop_lat, shop_lon))).quantize(Decimal('0.00000001'))
        DELIVERY_PER_KM = Decimal('10')
        MIN_CHARGE = Decimal('20')
        delivery_charge = max(MIN_CHARGE, (distance_km * DELIVERY_PER_KM).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))

        order_details = []

        # Insert each item into orders
        for item in items:
            name = item.get("pickle_name")
            if not name:
                return jsonify({'success': False, 'message': 'pickle_name missing for an item'}), 400

            qty = int(item.get("quantity", 1))
            unit_price = Decimal(str(item.get("cost", 0)))
            cost = (unit_price * qty).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)
            final_cost = (cost + delivery_charge).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

            cursor.execute("""
                INSERT INTO orders (
                    user_id, pickles, quantity, cost, status, created_at,
                    latitude, longitude, distance, delivery_charge, final_cost, shop_id
                ) VALUES (
                    %s, %s, %s, %s, 'Ordered', NOW(),
                    %s, %s, %s, %s, %s, %s
                )
            """, (
                user_id, name, qty, cost,
                Decimal(str(latitude)).quantize(Decimal('0.00000001')),
                Decimal(str(longitude)).quantize(Decimal('0.00000001')),
                distance_km, delivery_charge, final_cost, shop_id
            ))

            order_details.append({
                "pickle_name": name,
                "quantity": qty,
                "cost": float(cost),
                "delivery_charge": float(delivery_charge),
                "final_cost": float(final_cost),
                "shop_id": shop_id
            })

        conn.commit()

        return jsonify({
            "success": True,
            "message": "Order placed successfully",
            "shop_id": shop_id,
            "distance_km": float(distance_km),
            "delivery_charge": float(delivery_charge),
            "orders": order_details
        })

    except Exception as e:
        conn.rollback()
        print("Error in /buy_now:", e)
        return jsonify({"success": False, "message": str(e)}), 500

    finally:
        cursor.close()
        conn.close()

@app.route('/distance_finder', methods=['POST'])
def distance_finder():
    data = request.get_json()
    latitude = data.get("latitude")
    longitude = data.get("longitude")
    items = data.get("items", [])
    requested_shop_id = int(data.get("shop_id", 0))  # Get shop_id from client

    if not latitude or not longitude:
        return jsonify({'success': False, 'message': 'Missing coordinates'}), 400
    if not items:
        return jsonify({'success': False, 'message': 'No items received'}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # Fetch active shops
        cursor.execute("""
            SELECT shop_id, latitude, longitude 
            FROM shops 
            WHERE status = 'active' AND latitude IS NOT NULL AND longitude IS NOT NULL
        """)
        shops = cursor.fetchall()
        if not shops:
            return jsonify({'success': False, 'message': 'No active shops found'}), 404

        # Determine which shop to use
        if requested_shop_id == 0:
            nearest_shop = min(
                shops,
                key=lambda shop: calc_distance(latitude, longitude, shop[1], shop[2])
            )
            shop_id, shop_lat, shop_lon = nearest_shop
        else:
            shop_found = next((s for s in shops if s[0] == requested_shop_id), None)
            if shop_found:
                shop_id, shop_lat, shop_lon = shop_found
            else:
                nearest_shop = min(
                    shops,
                    key=lambda shop: calc_distance(latitude, longitude, shop[1], shop[2])
                )
                shop_id, shop_lat, shop_lon = nearest_shop

        # Calculate distance and delivery charge
        distance_km = Decimal(str(calc_distance(latitude, longitude, shop_lat, shop_lon))).quantize(Decimal('0.00000001'))
        DELIVERY_PER_KM = Decimal('10')
        MIN_CHARGE = Decimal('20')
        delivery_charge = max(MIN_CHARGE, (distance_km * DELIVERY_PER_KM).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))

        # Calculate total item cost
        total_cost = sum(Decimal(str(i.get("cost", 0))) * int(i.get("quantity", 1)) for i in items)
        final_cost = (total_cost + delivery_charge).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

        return jsonify({
            "success": True,
            "shop_id": shop_id,
            "distance_km": float(distance_km),
            "delivery_charge": float(delivery_charge),
            "final_cost": float(final_cost)
        })

    except Exception as e:
        print("Error in /distance_finder:", e)
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


# ==================================================
# 4️⃣ Remove from Cart
# ==================================================
@app.route('/remove_from_cart', methods=['POST'])
def remove_from_cart():
    """Remove an item from user's cart by ID or pickle_name"""
    data = request.get_json()
    user_id = data.get("user_id")
    cart_item_id = data.get("cart_item_id")
    pickle_name = data.get("pickle_name")

    if not user_id:
        return jsonify({"success": False, "message": "user_id missing"}), 400

    if not cart_item_id and not pickle_name:
        return jsonify({"success": False, "message": "cart_item_id or pickle_name required"}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        if cart_item_id:
            cursor.execute("DELETE FROM cart WHERE id = %s AND user_id = %s", (cart_item_id, user_id))
        else:
            cursor.execute("DELETE FROM cart WHERE pickle_name = %s AND user_id = %s", (pickle_name, user_id))

        if cursor.rowcount == 0:
            conn.rollback()
            return jsonify({"success": False, "message": "Item not found"}), 404

        conn.commit()
        return jsonify({"success": True, "message": "Item removed from cart"})
    except Exception as e:
        print("Error removing from cart:", e)
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


# ==================================================
# 5️⃣ Fetch Cart
# ==================================================
@app.route('/your_cart', methods=['GET'])
def your_cart():
    user_id = request.args.get("user_id")

    if not user_id:
        return jsonify({"status": "error", "error": "user_id missing"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    try:
        cursor.execute("""
    SELECT id, user_id, pickle_name, quantity, cost, added_at, shop_id
    FROM cart
    WHERE user_id = %s
""", (user_id,))
        rows = cursor.fetchall()
        return jsonify({"status": "ok", "cart_items": rows})
    except Exception as e:
        print("Error fetching cart:", e)
        return jsonify({"status": "error", "error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()
# ==================================================
# 9️⃣ Cancel Order (Delete from Orders)
# ==================================================
@app.route('/remove_item', methods=['POST'])
def remove_item():
    """Completely delete an order from the orders table."""
    data = request.get_json()
    user_id = data.get("user_id")
    order_id = data.get("order_id")

    if not user_id:
        return jsonify({"success": False, "message": "user_id missing"}), 400
    if not order_id:
        return jsonify({"success": False, "message": "order_id missing"}), 400

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("DELETE FROM orders WHERE id = %s AND user_id = %s", (order_id, user_id))

        if cursor.rowcount == 0:
            conn.rollback()
            return jsonify({"success": False, "message": "Order not found"}), 404

        conn.commit()
        return jsonify({"success": True, "message": "Order deleted successfully"})
    except Exception as e:
        print("Error deleting order:", e)
        return jsonify({"success": False, "message": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


# ==================================================
# 6️⃣ Fetch Orders
# ==================================================
@app.route('/orders_info', methods=['GET'])
def orders_info():
    user_id = request.args.get("user_id")

    if not user_id:
        return jsonify({"status": "error", "error": "user_id missing"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    try:
        cursor.execute("""
            SELECT id, user_id, pickles, quantity, cost, status, created_at
            FROM orders
            WHERE user_id = %s
            ORDER BY created_at DESC
        """, (user_id,))
        rows = cursor.fetchall()
        return jsonify({"status": "ok", "orders": rows})
    except Exception as e:
        print("Error fetching orders:", e)
        return jsonify({"status": "error", "error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()
@app.route('/shop_by_email', methods=['POST'])
def get_shop_by_email():
    try:
        data = request.get_json()
        email = data.get("email")

        if not email:
            return jsonify({"error": "Email is required"}), 400

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        cursor.execute("""
            SELECT shop_id, shop_name, image_url, address, status 
            FROM shops 
            WHERE email = %s
        """, (email,))

        shop = cursor.fetchone()

        if not shop:
            return jsonify({"error": "Shop not found"}), 404

        return jsonify({"status": "ok", "shop": shop})

    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/shops', methods=['GET'])
def get_shops():
    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)
        cursor.execute("""
            SELECT shop_id, shop_name, image_url, address, status 
            FROM shops
        """)
        shops = cursor.fetchall()
        return jsonify(shops)
    except Error as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

# /items/<shop_name> route
@app.route('/items/<int:shop_id>', methods=['GET'])
def get_items_for_shop(shop_id):
    try:
        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        query = """
            SELECT id, shop_id, name, category, image_url, price, quantity_in_stock, date_added
            FROM products
            WHERE shop_id = %s
        """
        cursor.execute(query, (shop_id,))
        items = cursor.fetchall()

        return jsonify(items)

    except Exception as e:
        print("Error fetching items:", e)
        return jsonify({"error": str(e)}), 500

    finally:
        if connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/shop_orders', methods=['POST'])
def get_shop_orders():
    try:
        data = request.get_json()
        shop_id = data.get("shop_id")

        if not shop_id:
            return jsonify({"error": "shop_id is required"}), 400

        connection = get_db_connection()
        cursor = connection.cursor(dictionary=True)

        # ✅ Join orders and users tables to get all details
        query = """
            SELECT 
                o.id AS order_id,
                o.pickles AS ordered_product,
                o.quantity,
                o.cost,
                o.final_cost,
                o.created_at AS order_date,
                u.name AS user_name,
                u.email AS user_email
            FROM orders o
            JOIN users u ON o.user_id = u.id
            WHERE o.shop_id = %s
        """

        cursor.execute(query, (shop_id,))
        orders = cursor.fetchall()

        if not orders:
            return jsonify({"message": "No orders found for this shop_id"}), 404

        return jsonify(orders), 200

    except Error as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if 'connection' in locals() and connection.is_connected():
            cursor.close()
            connection.close()

@app.route('/search_items', methods=['GET'])
def search_items():
    query = request.args.get("query", "").strip().lower()
    if not query:
        return jsonify({"status": "error", "error": "Missing search query"}), 400

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    try:
        cursor.execute("""
            SELECT id, name, price, image_url
            FROM products
            WHERE LOWER(TRIM(name)) LIKE %s
            ORDER BY name ASC
        """, (f"%{query}%",))  # lowercase & trimmed
        rows = cursor.fetchall()
        return jsonify({"status": "ok", "products": rows, "count": len(rows)})
    except Exception as e:
        print("❌ Error while searching products:", e)
        return jsonify({"status": "error", "error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


# ==================================================
# 7️⃣ Register
# ==================================================
@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("INSERT INTO persons (username, password) VALUES (%s, %s)", (username, password))
        conn.commit()
        return jsonify({'status': 'ok'})
    except Exception as e:
        return jsonify({'status': 'error', 'error': str(e)})
    finally:
        cursor.close()
        conn.close()


# ==================================================
# 8️⃣ Login
# ==================================================
@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    conn = get_db_connection()
    cursor = conn.cursor(dictionary=True)

    cursor.execute("SELECT * FROM persons WHERE username = %s AND password = %s", (username, password))
    user = cursor.fetchone()

    cursor.close()
    conn.close()

    if user:
        return jsonify({'status': 'ok', 'user': {'id': user['id'], 'username': user['username']}})
    else:
        return jsonify({'status': 'error', 'error': 'Invalid credentials'})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
