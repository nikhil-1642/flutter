import os
import mysql.connector
from mysql.connector import Error
from flask import Flask, request, jsonify
from flask_cors import CORS
from datetime import datetime, date
import decimal
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
CORS(app)

def convert_product(product):
    for key, value in product.items():
        if isinstance(value, (datetime, date)):
            product[key] = value.isoformat()
        elif isinstance(value, decimal.Decimal):
            product[key] = float(value)
    return product

def get_db_connection():
    try:
        return mysql.connector.connect(
            host=os.getenv("DB_HOST"),
            user=os.getenv("DB_USER"),
            port=os.getenv("DB_PORT"),
            password=os.getenv("DB_PASSWORD"),
            database=os.getenv("DB_NAME"),
            auth_plugin='mysql_native_password'
        )
    except Error as e:
        print("DB connection error:", e)
        return None

@app.errorhandler(Exception)
def handle_exception(e):
    print(f"Unhandled Exception: {e}")
    return jsonify({'status': 'error', 'error': str(e)}), 500

@app.route('/products')
def products():
    conn = get_db_connection()
    if conn is None:
        return jsonify({'status': 'error', 'error': 'Database connection failed'}), 500

    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, name, price, image_url FROM products1")
        products = cursor.fetchall()
        
        products = [convert_product(p) for p in products]
        print("Products fetched:", products)
        
        # ✅ FIX: Return a proper JSON object instead of raw array
        return jsonify({
            'status': 'ok',
            'products': products
        })
        
    except Exception as e:
        return jsonify({'status': 'error', 'error': str(e)}), 500
    finally:
        cursor.close()
        conn.close()

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    conn = get_db_connection()
    if conn is None:
        return jsonify({'status': 'error', 'error': 'Database connection failed'}), 500

    cursor = conn.cursor()

    try:
        cursor.execute("INSERT INTO persons (username, password) VALUES (%s, %s)", (username, password))
        conn.commit()
        return jsonify({'status': 'ok'})
    except Exception as e:
        conn.rollback()
        return jsonify({'status': 'error', 'error': str(e)})
    finally:
        cursor.close()
        conn.close()

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    conn = get_db_connection()
    if conn is None:
        return jsonify({'status': 'error', 'error': 'Database connection failed'}), 500

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
    app.run(host='0.0.0.0', port=5050)
