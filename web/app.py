import os
import time

import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

SERVER_NAME = os.environ.get("SERVER_NAME", "Serveur Web")
DB_HOST = os.environ.get("DB_HOST", "db-primary")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("POSTGRES_DB", "appdb")
DB_USER = os.environ.get("POSTGRES_USER", "app")
DB_PASSWORD = os.environ.get("POSTGRES_PASSWORD", "secretpassword")


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


@app.route("/")
def index():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, contenu, serveur, created_at FROM messages ORDER BY id")
        rows = cur.fetchall()
        cur.close()
        conn.close()
        db_status = "connecté"
        messages_html = "".join(
            f"<li><strong>#{r[0]}</strong> {r[1]} <em>({r[2]})</em> — {r[3]}</li>"
            for r in rows
        )
    except Exception as exc:
        db_status = f"erreur : {exc}"
        messages_html = "<li>Impossible de lire la base de données</li>"

    return f"""<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>{SERVER_NAME}</title>
  <style>
    body {{ font-family: sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; }}
    h1 {{ color: #1a5276; }}
    .status {{ padding: 0.5rem 1rem; background: #eaf2f8; border-radius: 4px; }}
  </style>
</head>
<body>
  <h1>{SERVER_NAME}</h1>
  <p class="status">Base de données : <strong>{db_status}</strong></p>
  <h2>Messages en base</h2>
  <ul>{messages_html}</ul>
</body>
</html>"""


@app.route("/health")
def health():
    return jsonify({"status": "ok", "server": SERVER_NAME, "timestamp": time.time()})


@app.route("/api/messages", methods=["POST"])
def add_message():
    from flask import request

    contenu = request.json.get("contenu", "message sans contenu") if request.is_json else "message test"
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute(
            "INSERT INTO messages (contenu, serveur) VALUES (%s, %s) RETURNING id",
            (contenu, SERVER_NAME),
        )
        new_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({"id": new_id, "serveur": SERVER_NAME}), 201
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
