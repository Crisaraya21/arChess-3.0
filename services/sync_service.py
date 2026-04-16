# ===========================================================================
# sync_service.py — Servicio de Sincronización con Firebase (Subespacios)
#
# Sistema de subespacios para evitar colisiones:
#   Cada cliente tiene su propio nodo en Firebase:
#     /partidas/{gameId}/cliente_a/estado  ← Cliente A escribe, Cliente B lee
#     /partidas/{gameId}/cliente_b/estado  ← Cliente B escribe, Cliente A lee
#     /partidas/{gameId}/historial         ← Compartido (solo append)
#
#   Cliente A: escribe en cliente_a/, lee de cliente_b/
#   Cliente B: escribe en cliente_b/, lee de cliente_a/
#
# Uso (lanzado por sync_manager.asm como proceso hijo):
#   python services\sync_service.py upload a
#   python services\sync_service.py upload b
#   python services\sync_service.py download a
#   python services\sync_service.py download b
#   python services\sync_service.py listen a [intervalo]
#   python services\sync_service.py listen b [intervalo]
#
#   El segundo argumento siempre es el rol: "a" o "b"
#
# Seguridad:
#   - Credenciales en archivo externo: services\firebase_API.json
#   - URL de la base de datos en: services\firebase_config.json
#
# Archivos de datos (leídos/escritos):
#   data\game_state.json   → Estado de la partida (JSON)
#   data\moves.log         → Historial de movimientos (texto plano)
#   data\sync_flag.txt     → Bandera de sincronización ("0" o "1")
# ===========================================================================

import sys
import os
import json
import time
import traceback
from security import cifrar_estado, descifrar_estado
import firebase_admin
from firebase_admin import credentials, db

# ---------------------------------------------------------------------------
# Rutas de archivos
# ---------------------------------------------------------------------------
DIR_SERVICES = os.path.dirname(os.path.abspath(__file__))
DIR_RAIZ     = os.path.dirname(DIR_SERVICES)
DIR_DATA     = os.path.join(DIR_RAIZ, "data")

RUTA_ESTADO      = os.path.join(DIR_DATA, "game_state.json")
RUTA_MOVES_LOG   = os.path.join(DIR_DATA, "moves.log")
RUTA_BANDERA     = os.path.join(DIR_DATA, "sync_flag.txt")

RUTA_CREDENCIALES = os.path.join(DIR_SERVICES, "firebase_API.json")
RUTA_CONFIG       = os.path.join(DIR_SERVICES, "firebase_config.json")

# ---------------------------------------------------------------------------
# Roles válidos
# ---------------------------------------------------------------------------
ROLES_VALIDOS = ("a", "b")


# ---------------------------------------------------------------------------
# Determinar subespacios según rol
# ---------------------------------------------------------------------------
def obtener_rutas_firebase(game_id, rol):
    """
    Retorna (ruta_escritura, ruta_lectura) en Firebase según el rol.
    
    Cliente A: escribe en cliente_a/, lee de cliente_b/
    Cliente B: escribe en cliente_b/, lee de cliente_a/
    """
    if rol == "a":
        mi_nodo    = "cliente_a"
        rival_nodo = "cliente_b"
    else:
        mi_nodo    = "cliente_b"
        rival_nodo = "cliente_a"

    ruta_escritura = f"/partidas/{game_id}/{mi_nodo}/estado"
    ruta_lectura   = f"/partidas/{game_id}/{rival_nodo}/estado"
    ruta_historial = f"/partidas/{game_id}/historial"

    return ruta_escritura, ruta_lectura, ruta_historial


# ---------------------------------------------------------------------------
# Configuración y Firebase
# ---------------------------------------------------------------------------
def cargar_configuracion():
    if not os.path.exists(RUTA_CREDENCIALES):
        raise FileNotFoundError(
            f"[SYNC] No se encontro: {RUTA_CREDENCIALES}\n"
            f"       Descargue la service account key de Firebase."
        )
    if not os.path.exists(RUTA_CONFIG):
        raise FileNotFoundError(
            f"[SYNC] No se encontro: {RUTA_CONFIG}\n"
            f'       Cree el archivo con: {{"databaseURL": "https://...firebaseio.com"}}'
        )
    with open(RUTA_CONFIG, "r", encoding="utf-8") as f:
        config = json.load(f)
    db_url = config.get("databaseURL", "")
    if not db_url:
        raise ValueError("[SYNC] firebase_config.json no contiene 'databaseURL'.")
    return RUTA_CREDENCIALES, db_url


def inicializar_firebase():
    if not firebase_admin._apps:
        cred_path, db_url = cargar_configuracion()
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred, {"databaseURL": db_url})
        print(f"[SYNC] Firebase inicializado. DB: {db_url}")


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def asegurar_directorio_data():
    os.makedirs(DIR_DATA, exist_ok=True)


def obtener_game_id():
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            return json.load(f).get("gameId", "partida_default")
    except (FileNotFoundError, json.JSONDecodeError):
        return "partida_default"


def obtener_version_local():
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            return json.load(f).get("version", 0)
    except (FileNotFoundError, json.JSONDecodeError):
        return 0


def escribir_bandera(valor):
    asegurar_directorio_data()
    with open(RUTA_BANDERA, "w", encoding="utf-8") as f:
        f.write(str(valor))


def leer_bandera():
    try:
        with open(RUTA_BANDERA, "r", encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return "0"


# ===========================================================================
# Funciones de sincronización con subespacios
# ===========================================================================

def subir_estado(rol):
    """
    Sube game_state.json al subespacio propio del cliente.
    Cliente A sube a /partidas/{id}/cliente_a/estado
    Cliente B sube a /partidas/{id}/cliente_b/estado
    """
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            estado = json.load(f)
    except FileNotFoundError:
        print("[SYNC] Error: game_state.json no encontrado.")
        return False
    except json.JSONDecodeError as e:
        print(f"[SYNC] Error parseando game_state.json: {e}")
        return False

    game_id = estado.get("gameId", "partida_default")
    version = estado.get("version", "?")

    ruta_escritura, _, _ = obtener_rutas_firebase(game_id, rol)

    try:
        ref = db.reference(ruta_escritura)
        estado = cifrar_estado(estado)
        ref.set(estado)
        print(f"[SYNC] [{rol.upper()}] Estado subido a {ruta_escritura}. "
              f"version={version}")
        return True
    except Exception as e:
        print(f"[SYNC] Error subiendo estado: {e}")
        return False


def subir_historial(rol):
    """Sube moves.log al nodo compartido de historial."""
    game_id = obtener_game_id()
    _, _, ruta_historial = obtener_rutas_firebase(game_id, rol)

    try:
        with open(RUTA_MOVES_LOG, "r", encoding="utf-8") as f:
            historial = f.read()
    except FileNotFoundError:
        historial = ""

    try:
        ref = db.reference(ruta_historial)
        ref.set(historial)
        return True
    except Exception as e:
        print(f"[SYNC] Error subiendo historial: {e}")
        return False


def descargar_estado(rol):
    game_id = obtener_game_id()
    _, ruta_lectura, _ = obtener_rutas_firebase(game_id, rol)

    try:
        ref = db.reference(ruta_lectura)
        estado_remoto = ref.get()
    except Exception as e:
        print(f"[SYNC] Error descargando de {ruta_lectura}: {e}")
        raise

    if not estado_remoto or not isinstance(estado_remoto, dict):
        return False

    # Descifrar si viene cifrado
    if estado_remoto.get('encrypted', False):
        estado_remoto = descifrar_estado(estado_remoto)

    version_remota = estado_remoto.get("version", 0)
    version_local = obtener_version_local()

    if version_remota > version_local:
        asegurar_directorio_data()
        with open(RUTA_ESTADO, "w", encoding="utf-8") as f:
            json.dump(estado_remoto, f, ensure_ascii=False, indent=2)

        escribir_bandera("1")
        print(f"[SYNC] [{rol.upper()}] Estado rival descargado de {ruta_lectura}. "
              f"version={version_remota} (local era {version_local})")
        return True

    return False

def descargar_historial(rol):
    """Descarga el historial compartido."""
    game_id = obtener_game_id()
    _, _, ruta_historial = obtener_rutas_firebase(game_id, rol)

    try:
        ref = db.reference(ruta_historial)
        historial = ref.get()
    except Exception as e:
        print(f"[SYNC] Error descargando historial: {e}")
        return False

    if historial and isinstance(historial, str):
        asegurar_directorio_data()
        with open(RUTA_MOVES_LOG, "w", encoding="utf-8") as f:
            f.write(historial)
        return True
    return False
# ===========================================================================
# Modo escucha con subespacios
# ===========================================================================

def modo_escucha(rol, intervalo=1):
    """
    Polling continuo: lee del subespacio del RIVAL.
    
    Cliente A escucha cambios en cliente_b/estado.
    Cliente B escucha cambios en cliente_a/estado.
    
    Esto GARANTIZA que nunca se descargue el propio movimiento.
    """
    rival = "B" if rol == "a" else "A"
    print(f"[SYNC] [{rol.upper()}] Escuchando cambios de cliente {rival}. "
          f"Polling cada {intervalo}s...")

    errores_consecutivos = 0
    MAX_ERRORES = 10

    while True:
        try:
            bandera_actual = leer_bandera()
            if bandera_actual == "1":
                time.sleep(intervalo)
                continue

            nuevo = descargar_estado(rol)
            if nuevo:
                descargar_historial(rol)
                errores_consecutivos = 0
            else:
                errores_consecutivos = 0

        except Exception as e:
            errores_consecutivos += 1
            print(f"[SYNC] Error en polling ({errores_consecutivos}): {e}")

            if errores_consecutivos >= MAX_ERRORES:
                print(f"[SYNC] Demasiados errores. Deteniendo listener.")
                break

            time.sleep(min(intervalo * errores_consecutivos, 30))
            continue

        time.sleep(intervalo)


# ===========================================================================
# Comandos combinados
# ===========================================================================

def comando_upload(rol):
    ok_estado = subir_estado(rol)
    subir_historial(rol)
    return ok_estado


def comando_download(rol):
    ok_estado = descargar_estado(rol)
    descargar_historial(rol)
    return ok_estado


# ===========================================================================
# Punto de entrada
# ===========================================================================

def main():
    if len(sys.argv) < 3:
        print("Uso: python sync_service.py <comando> <rol>")
        print("")
        print("Comandos:")
        print("  upload a     - Sube estado al subespacio de cliente A")
        print("  upload b     - Sube estado al subespacio de cliente B")
        print("  download a   - Descarga estado del rival de A (lee de B)")
        print("  download b   - Descarga estado del rival de B (lee de A)")
        print("  listen a [s] - Escucha cambios del rival de A")
        print("  listen b [s] - Escucha cambios del rival de B")
        print("")
        print("  <rol> = 'a' o 'b' (identifica al cliente)")
        sys.exit(1)

    comando = sys.argv[1].lower()
    rol     = sys.argv[2].lower()

    if rol not in ROLES_VALIDOS:
        print(f"[SYNC] Rol invalido: '{rol}'. Use 'a' o 'b'.")
        sys.exit(1)

    try:
        inicializar_firebase()
    except (FileNotFoundError, ValueError) as e:
        print(str(e))
        sys.exit(1)
    except Exception as e:
        print(f"[SYNC] Error inicializando Firebase: {e}")
        traceback.print_exc()
        sys.exit(1)

    if comando == "upload":
        exito = comando_upload(rol)
        sys.exit(0 if exito else 1)

    elif comando == "download":
        exito = comando_download(rol)
        sys.exit(0 if exito else 1)

    elif comando == "listen":
        intervalo = 1
        if len(sys.argv) > 3:
            try:
                intervalo = max(1, int(sys.argv[3]))
            except ValueError:
                intervalo = 1
        modo_escucha(rol, intervalo)

    else:
        print(f"[SYNC] Comando desconocido: '{comando}'")
        sys.exit(1)


if __name__ == "__main__":
    main()