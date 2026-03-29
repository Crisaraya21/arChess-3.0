import os
import json
import urllib.request
import urllib.parse

print("--- AI SERVICE: INICIADO ---")

# Rutas fijas para el TEC
RUTA_ESTADO = r"C:\arChess-3.0\data\game_state.json"
RUTA_HINT   = r"C:\arChess-3.0\data\hint.json"

def main():
    if not os.path.exists(RUTA_ESTADO):
        print(f"ERROR: No existe {RUTA_ESTADO}")
        return

    try:
        with open(RUTA_ESTADO, "r", encoding="utf-8") as f:
            data = json.load(f)
            fen = data.get("fen", "")
            print(f"PROCESANDO FEN: {fen[:30]}...")

        # Consultamos a Lichess (Cloud Eval)
        params = urllib.parse.urlencode({"fen": fen, "multiPv": 1})
        url = f"https://lichess.org/api/cloud-eval?{params}"
        
        req = urllib.request.Request(url, headers={"User-Agent": "arChess-3.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            res_data = json.loads(resp.read().decode("utf-8"))
            best_move = res_data["pvs"][0]["moves"].split()[0]
            
            # Guardamos el resultado para que MASM lo lea
            hint = {
                "gameId": data.get("gameId", "1"),
                "basedOnVersion": data.get("version", 1),
                "bestMove": best_move,
                "scoreCp": res_data["pvs"][0].get("cp", 0),
                "depth": res_data.get("depth", 20),
                "pv": best_move
            }
            
            with open(RUTA_HINT, "w") as f_out: # Quitá el encoding="utf-8"
                 json.dump(hint, f_out)
            
            print(f"--- HINT CREADO: {best_move} ---")

    except Exception as e:
        print(f"ERROR: {e}")

if __name__ == "__main__":
    main()