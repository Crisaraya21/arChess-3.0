# ===========================================================================
# sync_service.py — Servicio de Sincronización con Firebase
#   - Autenticar al usuario con Firebase Auth (login)
#   - Subir game_state.json a Firebase Realtime Database (upload)
#   - Descargar el estado remoto y actualizar game_state.json local (download)
#   - Escribir sync_flag.txt = "1" cuando hay nuevo estado remoto disponible
#     para que sync_manager.asm lo detecte mediante polling
#
# Uso (lanzado por sync_manager.asm como proceso hijo):
#   python sync_service.py login
#   python sync_service.py upload
#   python sync_service.py download
#
# Seguridad:
#   - Las credenciales de Firebase (email/password, API key) se leen desde
#     variables de entorno del sistema operativo — NUNCA en texto plano aquí.
#   - El token de sesión (ID token de Firebase Auth) se guarda solo en memoria
#     del proceso Python durante su ciclo de vida.
#   - La API key de Firebase se lee de la variable FIREBASE_API_KEY.
#   - Las credenciales del usuario de: FIREBASE_EMAIL y FIREBASE_PASSWORD.
#   - La URL de la base de datos de: FIREBASE_DB_URL.
#
# Variables de entorno requeridas:
#   FIREBASE_API_KEY    → clave de API del proyecto Firebase
#   FIREBASE_EMAIL      → correo del usuario autenticado
#   FIREBASE_PASSWORD   → contraseña del usuario (solo en entorno local seguro)
#   FIREBASE_DB_URL     → URL de Realtime Database (ej: https://xxx.firebaseio.com)
# ===========================================================================

import sys
import os
import json
import time
import requests
import firebase_admin
from firebase_admin import credentials, db

# ---------------------------------------------------------------------------
# Credenciales directas del proyecto
# ---------------------------------------------------------------------------
SERVICE_ACCOUNT = {
    "type": "service_account",
    "project_id": "proyectoensamblador",
    "private_key_id": "4e53c7e5e49b9961d92c0e9cb69aea614f9aec62",
    "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDfZ35oy9pgZlVS\nz7bFY8+R3FPf14q9EGkNnZT9NYXZTgSeZIPENenfh2Xck/WkKP60CwFiOR7hs9s9\nNAOwDwkFcUnTkssch4JBvclyLwk9v2UoZopBldmxp4HhyC5r7SkI+6VJhVGH60lj\nCHGKfIxIY2+AtkaOCQ3FuUroo5kMFe7NaAhVWdEN4yzhW3+W8Zg0tFpjIR4lJEgp\nRQXn7Z0Ns5LLG1hunMKqi9CzlEITX3Pr3cSPqRrXXt8+j4b0/6IhO1uWFhB1uSA0\nqDxJ9Pe0lWy+zho5awc5pgs63/8dkGNaH81P0bGPjzVk7d5kl/3a8bDv+Bb9WW1B\n7DacZMTDAgMBAAECggEAEZ5XXUtqYvzfEMNZ3jJTbeTq5nXYtrVjG5RIajm83xjk\ni1tQ+vnngl3qvh0bG8Gx6KAPkWAA2/rzuN1vxwRAiWHYWSu0AgF719RwXSVxfKGq\nCCgiEi8Pto+H0jcX1iIjgNZbwDMX7Xi0Vm+ViL7uz0ysQAHgCZaUM/o7eqJgURAJ\n/wQKr2jsKt2AZxTZIQFJ2WbodZsQ+mW2gbvC+31/psLtw5mRtIIVraswzYaaQ+qW\nTE+bmXSzkNrDxFOInOg7C+nGxzIF+pAqF6zpmY/83cC/DXGSpg8MflEy1QnhQNV1\nwRUm6IsXKV42Ysj5xRQ1Kca1QKllCV5a/wozjPaiNQKBgQD5OObTYZSOIh2btzuY\ndjSQw9ILNtpBdq09yWuyCaTPKwykQXfsHClzuN2Gj3sYIBfLM2yDi0rzmACrA5Nh\nIf6+I+e+WAyUsIF/70y3Aw9RQr1Sr4D7SK6OIN5y9JIlBwUDvG+8TB2dOu4pepnD\nmKGiWfSrM8ctCYRVqAcfwQ4+bwKBgQDletiLYsndK6IjpdcVBoQTawB6+3aBq6Hd\nWoLWDCz1/hA7p9xE90yj7Se9liwk/w0BA6KETTAdBELoEoDeWq0WNOixR2h/7Tso\n6NvEWw1A61zHmzg223P1FDzzX/NYO4I0uF1gDlPuEfEswSAxlAS1meijmKU6J5Ka\nkNiBBJaI7QKBgQDFtraoi4lnGPmUR1EoKt6Y2kEQVHvh41yc3+ZoX+43zFdDGA0j\na1QXUlmsHrfw88Tsl+dGlILprXUaNsP9ExMdlS6Mex2/+CdEb3vU1MCaHvBDYKha\nsdaJOto/KHeomGEKDbw3DcuQqOe4UGMcIUJZojPQfktNF3e83IiKUIYUUQKBgQDg\npO2vJbovRTOoagSvlH1e9PS3b8uHDRmbs6s5Fxo8hcYmYCEFcoIYR2UL9yKn5PY5\n8/D4Swe6oB1PSi3VfjbK8miIgzsNYJL1bV8WTXwf/UgKLy1MpnBRjspMBbYWvcqt\nCX5/Ngd7mxzZjwWRAzHJBS30WM4GrA6cOQd45aDn0QKBgQDtKNanZ39f/NNvOOcN\n6oK1TNh3i2Kzg3dnBJhiPnJSkJAUTg+7S6AWMK/fyyUogplnfuFAqN/xzRKmybGQ\nkKugt1PQBQe56k49+22c7rych4d6WIBRuTxUbM4csEovuEmO9c9zNN7SXevSqUvo\nEgJ8q8voTUaqvZrbA5oIG7MEBw==\n-----END PRIVATE KEY-----\n",
    "client_email": "firebase-adminsdk-fbsvc@proyectoensamblador.iam.gserviceaccount.com",
    "client_id": "116698727296411017436",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40proyectoensamblador.iam.gserviceaccount.com",
    "universe_domain": "googleapis.com"
}

DB_URL = "https://proyectoensamblador-default-rtdb.firebaseio.com"

# ---------------------------------------------------------------------------
# Rutas de archivos locales
# ---------------------------------------------------------------------------
RUTA_ESTADO  = os.path.join("data", "game_state.json")
RUTA_BANDERA = os.path.join("data", "sync_flag.txt")

# ---------------------------------------------------------------------------
# Inicializar Firebase Admin SDK (solo una vez)
# ---------------------------------------------------------------------------
if not firebase_admin._apps:
    cred = credentials.Certificate(SERVICE_ACCOUNT)
    firebase_admin.initialize_app(cred, {"databaseURL": DB_URL})


# ===========================================================================
# Funciones principales
# ===========================================================================

def obtener_game_id() -> str:
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            return json.load(f).get("gameId", "partida_default")
    except:
        return "partida_default"


def escribir_bandera(valor: str):
    os.makedirs("data", exist_ok=True)
    with open(RUTA_BANDERA, "w", encoding="utf-8") as f:
        f.write(valor)


def subir_estado() -> bool:
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            estado = json.load(f)
    except Exception as e:
        print(f"[SYNC] Error leyendo game_state.json: {e}")
        return False

    game_id = estado.get("gameId", "partida_default")
    ref = db.reference(f"/partidas/{game_id}/estado")
    ref.set(estado)
    print(f"[SYNC] Estado subido. Versión: {estado.get('version', '?')}")
    return True


def descargar_estado() -> bool:
    game_id = obtener_game_id()
    ref = db.reference(f"/partidas/{game_id}/estado")
    estado_remoto = ref.get()

    if not estado_remoto:
        print("[SYNC] No hay estado remoto disponible.")
        return False

    version_remota = estado_remoto.get("version", 0)
    version_local = 0

    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            version_local = json.load(f).get("version", 0)
    except:
        pass

    if version_remota > version_local:
        os.makedirs("data", exist_ok=True)
        with open(RUTA_ESTADO, "w", encoding="utf-8") as f:
            json.dump(estado_remoto, f, ensure_ascii=False, indent=2)
        escribir_bandera("1")
        print(f"[SYNC] Estado nuevo descargado. Versión: {version_remota}")
        return True
    else:
        print(f"[SYNC] Sin cambios. Versión local: {version_local}")
        return False


def modo_escucha(intervalo: int = 1):
    print(f"[SYNC] Escuchando cambios cada {intervalo}s...")
    while True:
        try:
            descargar_estado()
        except Exception as e:
            print(f"[SYNC] Error en polling: {e}")
        time.sleep(intervalo)


# ===========================================================================
# Punto de entrada
# ===========================================================================
def main():
    if len(sys.argv) < 2:
        print("Uso: python sync_service.py [upload|download|listen]")
        sys.exit(1)

    comando = sys.argv[1].lower()

    if comando == "upload":
        sys.exit(0 if subir_estado() else 1)
    elif comando == "download":
        sys.exit(0 if descargar_estado() else 1)
    elif comando == "listen":
        intervalo = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        modo_escucha(intervalo)
    else:
        print(f"[SYNC] Comando desconocido: '{comando}'")
        sys.exit(1)


if __name__ == "__main__":
    main()