# ===========================================================================
# sync_service.py — Servicio de Sincronización con Firebase
#
# Responsabilidades:
#   - Subir game_state.json a Firebase Realtime Database (upload)
#   - Descargar estado remoto y actualizar game_state.json local (download)
#   - Subir moves.log a Firebase (upload)
#   - Modo escucha: polling continuo que detecta cambios remotos y
#     escribe sync_flag.txt = "1" para que MASM lo detecte (listen)
#
# Uso (lanzado por sync_manager.asm como proceso hijo):
#   python services\sync_service.py upload
#   python services\sync_service.py download
#   python services\sync_service.py listen [intervalo_segundos]
#
# Seguridad:
#   - Las credenciales de Firebase (service account) se leen desde un
#     archivo externo: services\firebase_API.json
#   - NUNCA se almacenan credenciales en texto plano en este código.
#   - La URL de la base de datos se lee de services\firebase_config.json
#   - El archivo firebase_API.json debe tener permisos restringidos
#     y NO debe subirse a repositorios públicos (.gitignore).
#
# Archivos de configuración requeridos:
#   services\firebase_API.json  → Service account key de Firebase
#   services\firebase_config.json       → {"databaseURL": "https://xxx.firebaseio.com"}
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

# Firebase Admin SDK
import firebase_admin
from firebase_admin import credentials, db

# ---------------------------------------------------------------------------
# Rutas de archivos
# ---------------------------------------------------------------------------
# Directorio base: donde está este script (services/)
DIR_SERVICES = os.path.dirname(os.path.abspath(__file__))
DIR_RAIZ     = os.path.dirname(DIR_SERVICES)
DIR_DATA     = os.path.join(DIR_RAIZ, "data")

RUTA_ESTADO      = os.path.join(DIR_DATA, "game_state.json")
RUTA_MOVES_LOG   = os.path.join(DIR_DATA, "moves.log")
RUTA_BANDERA     = os.path.join(DIR_DATA, "sync_flag.txt")

RUTA_CREDENCIALES = os.path.join(DIR_SERVICES, "firebase_API.json")
RUTA_CONFIG       = os.path.join(DIR_SERVICES, "firebase_config.json")


# ---------------------------------------------------------------------------
# Cargar configuración de Firebase desde archivos externos
# ---------------------------------------------------------------------------
def cargar_configuracion():
    """
    Lee firebase_API.json y firebase_config.json.
    Retorna (cred_path, db_url) o lanza excepción si no existen.
    """
    if not os.path.exists(RUTA_CREDENCIALES):
        raise FileNotFoundError(
            f"[SYNC] No se encontró el archivo de credenciales: "
            f"{RUTA_CREDENCIALES}\n"
            f"       Descargue la service account key desde la consola de "
            f"Firebase y guárdela como firebase_API.json en la "
            f"carpeta services/."
        )

    if not os.path.exists(RUTA_CONFIG):
        raise FileNotFoundError(
            f"[SYNC] No se encontró el archivo de configuración: "
            f"{RUTA_CONFIG}\n"
            f'       Cree el archivo con: {{"databaseURL": "https://su-proyecto.firebaseio.com"}}'
        )

    with open(RUTA_CONFIG, "r", encoding="utf-8") as f:
        config = json.load(f)

    db_url = config.get("databaseURL", "")
    if not db_url:
        raise ValueError(
            "[SYNC] El archivo firebase_config.json no contiene 'databaseURL'."
        )

    return RUTA_CREDENCIALES, db_url


# ---------------------------------------------------------------------------
# Inicializar Firebase Admin SDK (solo una vez por proceso)
# ---------------------------------------------------------------------------
def inicializar_firebase():
    """Inicializa Firebase Admin SDK si no está inicializado."""
    if not firebase_admin._apps:
        cred_path, db_url = cargar_configuracion()
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred, {"databaseURL": db_url})
        print(f"[SYNC] Firebase inicializado. DB: {db_url}")


# ===========================================================================
# Funciones de utilidad
# ===========================================================================

def asegurar_directorio_data():
    """Crea el directorio data/ si no existe."""
    os.makedirs(DIR_DATA, exist_ok=True)


def obtener_game_id():
    """Lee el gameId del game_state.json local."""
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            estado = json.load(f)
            return estado.get("gameId", "partida_default")
    except (FileNotFoundError, json.JSONDecodeError):
        return "partida_default"


def obtener_version_local():
    """Lee la versión del game_state.json local."""
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            estado = json.load(f)
            return estado.get("version", 0)
    except (FileNotFoundError, json.JSONDecodeError):
        return 0


def escribir_bandera(valor):
    """Escribe un valor ('0' o '1') en sync_flag.txt."""
    asegurar_directorio_data()
    with open(RUTA_BANDERA, "w", encoding="utf-8") as f:
        f.write(str(valor))


def leer_bandera():
    """Lee el valor actual de sync_flag.txt."""
    try:
        with open(RUTA_BANDERA, "r", encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return "0"


# ===========================================================================
# Funciones principales de sincronización
# ===========================================================================

def subir_estado():
    """
    Lee game_state.json local y lo sube a Firebase Realtime Database.
    Ruta en Firebase: /partidas/{gameId}/estado
    
    Retorna True si éxito, False si error.
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

    try:
        ref = db.reference(f"/partidas/{game_id}/estado")
        ref.set(estado)
        print(f"[SYNC] Estado subido. gameId={game_id}, version={version}")
        return True
    except Exception as e:
        print(f"[SYNC] Error subiendo estado a Firebase: {e}")
        return False


def subir_historial():
    """
    Lee moves.log local y lo sube a Firebase como texto.
    Ruta en Firebase: /partidas/{gameId}/historial
    """
    game_id = obtener_game_id()

    try:
        with open(RUTA_MOVES_LOG, "r", encoding="utf-8") as f:
            historial = f.read()
    except FileNotFoundError:
        historial = ""

    try:
        ref = db.reference(f"/partidas/{game_id}/historial")
        ref.set(historial)
        return True
    except Exception as e:
        print(f"[SYNC] Error subiendo historial: {e}")
        return False


def descargar_estado():
    """
    Descarga el estado desde Firebase y lo compara con el local.
    Si la versión remota es mayor, actualiza game_state.json local
    y escribe sync_flag.txt = "1" para notificar a MASM.
    
    Retorna True si se descargó un estado nuevo, False si no.
    """
    game_id = obtener_game_id()

    try:
        ref = db.reference(f"/partidas/{game_id}/estado")
        estado_remoto = ref.get()
    except Exception as e:
        print(f"[SYNC] Error descargando de Firebase: {e}")
        return False

    if not estado_remoto or not isinstance(estado_remoto, dict):
        print("[SYNC] No hay estado remoto disponible.")
        return False

    version_remota = estado_remoto.get("version", 0)
    version_local = obtener_version_local()

    if version_remota > version_local:
        asegurar_directorio_data()
        with open(RUTA_ESTADO, "w", encoding="utf-8") as f:
            json.dump(estado_remoto, f, ensure_ascii=False, indent=2)

        escribir_bandera("1")
        print(f"[SYNC] Estado nuevo descargado. "
              f"Version remota={version_remota}, local={version_local}")
        return True
    else:
        return False


def descargar_historial():
    """Descarga el historial desde Firebase y lo guarda en moves.log."""
    game_id = obtener_game_id()

    try:
        ref = db.reference(f"/partidas/{game_id}/historial")
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
# Modo escucha (listener) — corre en background
# ===========================================================================

def modo_escucha(intervalo=1):
    """
    Polling continuo a Firebase.
    Cada 'intervalo' segundos verifica si hay un estado nuevo.
    Si lo hay, descarga y escribe la bandera para MASM.
    
    Este proceso se lanza por sync_manager.asm con CreateProcessA
    y corre indefinidamente hasta que el proceso padre lo termine.
    
    Args:
        intervalo: segundos entre cada verificación (default: 1)
    """
    print(f"[SYNC] Modo escucha iniciado. Polling cada {intervalo}s...")

    errores_consecutivos = 0
    MAX_ERRORES = 10

    while True:
        try:
            # Solo verificar si MASM ya procesó la actualización anterior
            bandera_actual = leer_bandera()
            if bandera_actual == "1":
                # MASM aún no procesó el cambio anterior, esperar
                time.sleep(intervalo)
                continue

            nuevo = descargar_estado()
            if nuevo:
                descargar_historial()
                errores_consecutivos = 0
            else:
                errores_consecutivos = 0  # no hay error, solo no hay cambios

        except Exception as e:
            errores_consecutivos += 1
            print(f"[SYNC] Error en polling ({errores_consecutivos}): {e}")

            if errores_consecutivos >= MAX_ERRORES:
                print(f"[SYNC] Demasiados errores consecutivos "
                      f"({MAX_ERRORES}). Deteniendo listener.")
                break

            # Backoff exponencial ante errores repetidos
            time.sleep(min(intervalo * errores_consecutivos, 30))
            continue

        time.sleep(intervalo)


# ===========================================================================
# Comando combinado: upload (estado + historial)
# ===========================================================================

def comando_upload():
    """Sube tanto el estado como el historial a Firebase."""
    ok_estado = subir_estado()
    ok_historial = subir_historial()
    return ok_estado


def comando_download():
    """Descarga estado e historial desde Firebase."""
    ok_estado = descargar_estado()
    ok_historial = descargar_historial()
    return ok_estado


# ===========================================================================
# Punto de entrada
# ===========================================================================

def main():
    if len(sys.argv) < 2:
        print("Uso: python sync_service.py [upload|download|listen]")
        print("")
        print("Comandos:")
        print("  upload    - Sube game_state.json y moves.log a Firebase")
        print("  download  - Descarga estado remoto de Firebase")
        print("  listen [s]- Polling continuo (s = intervalo en segundos)")
        sys.exit(1)

    comando = sys.argv[1].lower()

    try:
        # Inicializar Firebase (carga credenciales desde archivo externo)
        inicializar_firebase()
    except (FileNotFoundError, ValueError) as e:
        print(str(e))
        sys.exit(1)
    except Exception as e:
        print(f"[SYNC] Error inicializando Firebase: {e}")
        traceback.print_exc()
        sys.exit(1)

    if comando == "upload":
        exito = comando_upload()
        sys.exit(0 if exito else 1)

    elif comando == "download":
        exito = comando_download()
        sys.exit(0 if exito else 1)

    elif comando == "listen":
        intervalo = 1
        if len(sys.argv) > 2:
            try:
                intervalo = int(sys.argv[2])
                if intervalo < 1:
                    intervalo = 1
            except ValueError:
                intervalo = 1
        modo_escucha(intervalo)

    else:
        print(f"[SYNC] Comando desconocido: '{comando}'")
        print("  Comandos válidos: upload, download, listen")
        sys.exit(1)


if __name__ == "__main__":
    main()