import mysql.connector

def get_connection():
    return mysql.connector.connect(
        host='interchange.proxy.rlwy.net',
        user='root',
        password='HmYEmvNwCcTKXONUKaWXeMjNwyglNTrA',
        database='nikhil1',
        port=36069
    )
