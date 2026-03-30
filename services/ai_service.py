# ===========================================================================
# ai_service.py - Servicio de IA para arChess 3.0
#
# APIs (en orden de prioridad):
#   1. Lichess Cloud Eval - gratis, sin key, solo posiciones cacheadas
#   2. chess-api.com - Stockfish 18 NNUE gratis, CUALQUIER posicion
#
# FIX CRITICO: Archivo_GenerarFEN en MASM solo genera la parte del
# tablero (ej: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR").
# Este script COMPLETA el FEN con turno, enroque, etc. antes de
# consultar las APIs. Sin esto, las APIs rechazan la consulta.
# ===========================================================================

import sys
import os
import json
import urllib.request
import urllib.parse
import urllib.error
import time

DIR_SERVICES = os.path.dirname(os.path.abspath(__file__))
_parent = os.path.dirname(DIR_SERVICES)
DIR_RAIZ = _parent if os.path.basename(DIR_SERVICES).lower() == "services" else DIR_SERVICES
DIR_DATA = os.path.join(DIR_RAIZ, "data")

RUTA_ESTADO = os.path.join(DIR_DATA, "game_state.json")
RUTA_HINT   = os.path.join(DIR_DATA, "hint.json")

HEADERS = {
    "Accept": "application/json",
    "User-Agent": "arChess-3.0/1.0 (IC3101 MASM chess project)"
}

TIMEOUT = 12


# ===========================================================================
# Completar FEN incompleto
# ===========================================================================
def completar_fen(fen_parcial, turno="w"):
    """
    Si el FEN solo tiene la parte del tablero, le agrega:
      turno, enroque, en-passant, halfmove, fullmove
    Ejemplo:
      "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR"
      -> "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"
    """
    partes = fen_parcial.strip().split()
    if len(partes) >= 4:
        return fen_parcial  # ya esta completo
    if len(partes) == 1:
        return f"{partes[0]} {turno} KQkq - 0 1"
    if len(partes) == 2:
        return f"{partes[0]} {partes[1]} KQkq - 0 1"
    if len(partes) == 3:
        return f"{partes[0]} {partes[1]} {partes[2]} - 0 1"
    return fen_parcial


# ===========================================================================
# Leer estado local
# ===========================================================================
def leer_estado():
    if not os.path.exists(RUTA_ESTADO):
        print(f"[AI] Error: no encontre {RUTA_ESTADO}")
        return None
    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            estado = json.load(f)
    except Exception as e:
        print(f"[AI] Error leyendo game_state.json: {e}")
        return None

    fen_raw = estado.get("fen", "")
    turno   = estado.get("turn", "w")
    game_id = estado.get("gameId", "partida_default")
    version = estado.get("version", 0)

    if not fen_raw:
        print("[AI] Error: FEN vacio")
        return None

    fen_completo = completar_fen(fen_raw, turno)
    print(f"PROCESANDO FEN: {fen_completo[:60]}...")

    return {"fen": fen_completo, "gameId": game_id, "version": version}


# ===========================================================================
# API 1: Lichess Cloud Eval (solo posiciones cacheadas)
# ===========================================================================
def consultar_lichess(fen):
    params = urllib.parse.urlencode({"fen": fen, "multiPv": 1})
    url = f"https://lichess.org/api/cloud-eval?{params}"
    print("[AI] Intentando Lichess cloud-eval...")

    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            if resp.status != 200:
                print(f"[AI] Lichess HTTP {resp.status}")
                return None
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"[AI] Lichess HTTP {e.code}: {e.reason}")
        return None
    except Exception as e:
        print(f"[AI] Lichess error: {e}")
        return None

    pvs = data.get("pvs", [])
    if not pvs:
        print("[AI] Lichess: posicion no cacheada")
        return None

    pv = pvs[0]
    moves = pv.get("moves", "").strip().split()
    if not moves:
        return None

    best = moves[0][:4]
    print(f"[AI] Lichess OK: {best}")
    return {
        "bestMove": best,
        "scoreCp":  pv.get("cp", 0),
        "depth":    data.get("depth", 0),
        "pv":       pv.get("moves", "")
    }


# ===========================================================================
# API 2: chess-api.com (Stockfish 18 NNUE - cualquier posicion)
# ===========================================================================
def consultar_stockfish_online(fen):
    print("[AI] Intentando chess-api.com (Stockfish 18)...")

    try:
        payload = json.dumps({
            "fen": fen,
            "depth": 12,
            "maxThinkingTime": 50,
            "variants": 1
        }).encode("utf-8")

        req = urllib.request.Request(
            "https://chess-api.com/v1",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "arChess-3.0/1.0"
            }
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"[AI] chess-api.com error: {e}")
        return None

    # chess-api.com retorna: {"move":"e2e4","eval":0.3,"depth":12,...}
    move = data.get("move", "") or data.get("lan", "")
    if not move or len(move) < 4:
        # A veces retorna error en un campo "text"
        txt = data.get("text", "")
        print(f"[AI] chess-api.com sin movimiento. Respuesta: {txt[:80]}")
        return None

    # Convertir eval a centipawns
    raw_eval = data.get("eval", 0)
    try:
        score_cp = int(float(raw_eval) * 100)
    except (ValueError, TypeError):
        score_cp = 0

    depth = data.get("depth", 12)
    best  = move[:4]

    print(f"[AI] Stockfish OK: {best} (cp={score_cp}, depth={depth})")
    return {
        "bestMove": best,
        "scoreCp":  score_cp,
        "depth":    depth,
        "pv":       move
    }


# ===========================================================================
# Escribir hint.json
# ===========================================================================
def escribir_hint(game_id, version, best_move, score_cp, depth, pv):
    os.makedirs(DIR_DATA, exist_ok=True)
    hint = {
        "gameId":         game_id,
        "basedOnVersion": version,
        "bestMove":       best_move,
        "scoreCp":        score_cp,
        "depth":          depth,
        "pv":             pv
    }
    with open(RUTA_HINT, "w", encoding="utf-8") as f:
        json.dump(hint, f, ensure_ascii=False, indent=2)
    print(f"--- HINT CREADO: {best_move} ---")


# ===========================================================================
# Punto de entrada
# ===========================================================================
def main():
    print("--- AI SERVICE: INICIADO ---")

    estado = leer_estado()
    if not estado:
        escribir_hint("error", 0, "0000", 0, 0, "")
        sys.exit(1)

    fen     = estado["fen"]
    game_id = estado["gameId"]
    version = estado["version"]

    # --- Intentar Lichess primero (rapido, posiciones comunes) ---
    resultado = consultar_lichess(fen)

    # --- Si Lichess falla, usar Stockfish 18 online (cualquier posicion) ---
    if not resultado:
        resultado = consultar_stockfish_online(fen)

    # --- Si ambos fallan ---
    if not resultado:
        print("[AI] TODAS las APIs fallaron.")
        escribir_hint(game_id, version, "0000", 0, 0, "")
        sys.exit(1)

    # --- Exito: escribir hint ---
    escribir_hint(
        game_id, version,
        resultado["bestMove"],
        resultado["scoreCp"],
        resultado["depth"],
        resultado["pv"]
    )
    sys.exit(0)


if __name__ == "__main__":
    main()