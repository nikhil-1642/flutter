from flask import Flask, request, jsonify
from flask_cors import CORS
from db import get_connection
from datetime import datetime, date
import decimal
app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})
def convert_product(product):
    for key, value in product.items():
        if isinstance(value, (datetime, date)):
            product[key] = value.isoformat()
        elif isinstance(value, decimal.Decimal):  # ← this line fixes the price issue
            product[key] = float(value)
    return product

@app.route('/products')
def product_page():
    conn = get_connection()  # Use consistent connection function
    cursor = conn.cursor(dictionary=True)
    cursor.execute("SELECT id, name, price, image_url FROM products1")
    products = cursor.fetchall()
    cursor.close()
    conn.close()

    # Convert any datetime fields to string for JSON serialization
    products = [convert_product(p) for p in products]

    return jsonify(products)  # <-- IMPORTANT: Return the data as JSON!
@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    conn = get_connection()
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

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    conn = get_connection()
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
