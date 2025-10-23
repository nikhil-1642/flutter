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
    """Convert database types to JSON serializable types"""
    converted = {}
    for key, value in product.items():
        if isinstance(value, (datetime, date)):
            converted[key] = value.isoformat()
        elif isinstance(value, decimal.Decimal):
            converted[key] = float(value)
        elif isinstance(value, (bytes, bytearray)):
            converted[key] = value.decode('utf-8')
        elif value is None:
            converted[key] = None
        else:
            converted[key] = value
    return converted

def get_db_connection():
    """Create and return database connection"""
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

@app.after_request
def after_request(response):
    """Add CORS headers to all responses"""
    response.headers.add('Access-Control-Allow-Origin', '*')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

@app.errorhandler(Exception)
def handle_exception(e):
    """Global error handler"""
    print(f"Unhandled Exception: {e}")
    return jsonify({'status': 'error', 'error': str(e)}), 500

@app.route('/')
def home():
    """Root endpoint - API info"""
    return jsonify({
        'status': 'ok',
        'message': 'Flask API is running',
        'endpoints': {
            '/products': 'GET - Get all products',
            '/register': 'POST - Register new user',
            '/login': 'POST - User login'
        }
    })

@app.route('/products')
def products():
    """Get all products - returns wrapped JSON object for Flutter"""
    conn = get_db_connection()
    if conn is None:
        return jsonify({'status': 'error', 'error': 'Database connection failed'}), 500

    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT id, name, price, image_url FROM products1")
        products = cursor.fetchall()

        # Convert DB types to JSON-serializable types
        products = [convert_product(p) for p in products]
        print("Products fetched:", products)

        # ✅ Fixed: wrap response inside a dictionary
        return jsonify({'status': 'ok', 'products': products})

    except Exception as e:
        print(f"Error in /products: {e}")
        return jsonify({'status': 'error', 'error': str(e)}), 500
    finally:
        cursor.close()
        conn.close()


@app.route('/register', methods=['POST', 'OPTIONS'])
def register():
    """User registration endpoint"""
    if request.method == 'OPTIONS':
        return jsonify({'status': 'ok'})
        
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'error': 'No JSON data provided'}), 400
        
    username = data.get('username')
    password = data.get('password')

    if not username or not password:
        return jsonify({'status': 'error', 'error': 'Username and password required'}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({'status': 'error', 'error': 'Database connection failed'}), 500

    cursor = conn.cursor()
    try:
        cursor.execute("INSERT INTO persons (username, password) VALUES (%s, %s)", (username, password))
        conn.commit()
        return jsonify({'status': 'ok', 'message': 'User registered successfully'})
    except Exception as e:
        conn.rollback()
        return jsonify({'status': 'error', 'error': str(e)}), 400
    finally:
        cursor.close()
        conn.close()

@app.route('/login', methods=['POST', 'OPTIONS'])
def login():
    """User login endpoint"""
    if request.method == 'OPTIONS':
        return jsonify({'status': 'ok'})
        
    data = request.get_json()
    if not data:
        return jsonify({'status': 'error', 'error': 'No JSON data provided'}), 400
        
    username = data.get('username')
    password = data.get('password')

    if not username or not password:
        return jsonify({'status': 'error', 'error': 'Username and password required'}), 400

    conn = get_db_connection()
    if conn is None:
        return jsonify({'status': 'error', 'error': 'Database connection failed'}), 500

    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute("SELECT * FROM persons WHERE username = %s AND password = %s", (username, password))
        user = cursor.fetchone()
        
        if user:
            return jsonify({
                'status': 'ok', 
                'user': {
                    'id': user['id'], 
                    'username': user['username']
                }
            })
        else:
            return jsonify({'status': 'error', 'error': 'Invalid credentials'}), 401
            
    except Exception as e:
        return jsonify({'status': 'error', 'error': str(e)}), 500
    finally:
        cursor.close()
        conn.close()

@app.route('/test-db')
def test_db():
    """Test database connection"""
    conn = get_db_connection()
    if conn and conn.is_connected():
        conn.close()
        return jsonify({'status': 'ok', 'message': 'Database connected successfully'})
    else:
        return jsonify({'status': 'error', 'message': 'Database connection failed'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)


