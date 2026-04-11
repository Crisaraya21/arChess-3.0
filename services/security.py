# ===========================================================================
# security.py — Modulo de Seguridad Basica para arChess 3.0
#
# Implementa:
#   1. Cifrado XOR para proteger datos de estado de partida
#   2. Hash SHA-256 para verificar integridad de archivos
#   3. Token de sesion simple para identificar clientes
#
# Uso:
#   from security import cifrar_xor, descifrar_xor, generar_hash, generar_token
#
# El PDF del proyecto indica que se puede usar:
#   "cifrado XOR, hash de contrasenas, tokens de sesion"
# ===========================================================================

import hashlib
import os
import json
import base64
import time

# Clave XOR por defecto (se puede cambiar por partida)
XOR_KEY_DEFAULT = "arChess3_IC3101_2026"


def cifrar_xor(datos, clave=XOR_KEY_DEFAULT):
    """
    Cifra una cadena de texto usando XOR con la clave proporcionada.
    Retorna el resultado codificado en base64 para almacenamiento seguro.
    
    Parametros:
        datos (str): Texto plano a cifrar
        clave (str): Clave de cifrado XOR
    
    Retorna:
        str: Texto cifrado en base64
    """
    if not datos or not clave:
        return datos
    
    datos_bytes = datos.encode('utf-8')
    clave_bytes = clave.encode('utf-8')
    clave_len = len(clave_bytes)
    
    resultado = bytearray(len(datos_bytes))
    for i in range(len(datos_bytes)):
        resultado[i] = datos_bytes[i] ^ clave_bytes[i % clave_len]
    
    return base64.b64encode(resultado).decode('ascii')


def descifrar_xor(datos_cifrados, clave=XOR_KEY_DEFAULT):
    """
    Descifra una cadena cifrada con XOR (en base64).
    
    Parametros:
        datos_cifrados (str): Texto cifrado en base64
        clave (str): Clave de cifrado XOR (misma usada para cifrar)
    
    Retorna:
        str: Texto plano descifrado
    """
    if not datos_cifrados or not clave:
        return datos_cifrados
    
    try:
        datos_bytes = base64.b64decode(datos_cifrados)
    except Exception:
        return datos_cifrados  # si no es base64, retornar tal cual
    
    clave_bytes = clave.encode('utf-8')
    clave_len = len(clave_bytes)
    
    resultado = bytearray(len(datos_bytes))
    for i in range(len(datos_bytes)):
        resultado[i] = datos_bytes[i] ^ clave_bytes[i % clave_len]
    
    return resultado.decode('utf-8')


def generar_hash(datos):
    """
    Genera un hash SHA-256 de los datos para verificar integridad.
    
    Parametros:
        datos (str): Texto para generar hash
    
    Retorna:
        str: Hash SHA-256 en hexadecimal
    """
    if isinstance(datos, str):
        datos = datos.encode('utf-8')
    return hashlib.sha256(datos).hexdigest()


def verificar_integridad(datos, hash_esperado):
    """
    Verifica que los datos no hayan sido alterados comparando hashes.
    
    Parametros:
        datos (str): Texto a verificar
        hash_esperado (str): Hash SHA-256 esperado
    
    Retorna:
        bool: True si la integridad es valida
    """
    return generar_hash(datos) == hash_esperado


def generar_token_sesion(game_id, rol):
    """
    Genera un token de sesion unico basado en:
      - ID de partida
      - Rol del cliente (a/b)
      - Timestamp actual
    
    Parametros:
        game_id (str): Identificador de la partida
        rol (str): 'a' o 'b'
    
    Retorna:
        str: Token de sesion (hash de 16 caracteres)
    """
    semilla = f"{game_id}_{rol}_{time.time()}_{os.getpid()}"
    hash_completo = hashlib.sha256(semilla.encode()).hexdigest()
    return hash_completo[:16]


def cifrar_estado(estado_dict, clave=XOR_KEY_DEFAULT):
    """
    Cifra un diccionario de estado de partida.
    Cifra los campos sensibles (fen, lastMove) y agrega hash de integridad.
    
    Parametros:
        estado_dict (dict): Estado de la partida
        clave (str): Clave XOR
    
    Retorna:
        dict: Estado con campos cifrados + hash de integridad
    """
    estado_seguro = dict(estado_dict)
    
    # Cifrar campos sensibles
    if 'fen' in estado_seguro:
        estado_seguro['fen'] = cifrar_xor(estado_seguro['fen'], clave)
    if 'lastMove' in estado_seguro:
        estado_seguro['lastMove'] = cifrar_xor(estado_seguro['lastMove'], clave)
    
    # Marcar como cifrado
    estado_seguro['encrypted'] = True
    
    # Agregar hash de integridad del estado original
    estado_json = json.dumps(estado_dict, sort_keys=True)
    estado_seguro['integrity'] = generar_hash(estado_json)
    
    return estado_seguro


def descifrar_estado(estado_seguro, clave=XOR_KEY_DEFAULT):
    """
    Descifra un diccionario de estado cifrado.
    
    Parametros:
        estado_seguro (dict): Estado cifrado
        clave (str): Clave XOR
    
    Retorna:
        dict: Estado descifrado (sin campos de seguridad)
    """
    if not estado_seguro.get('encrypted', False):
        return estado_seguro  # no esta cifrado, retornar tal cual
    
    estado = dict(estado_seguro)
    
    # Descifrar campos
    if 'fen' in estado:
        estado['fen'] = descifrar_xor(estado['fen'], clave)
    if 'lastMove' in estado:
        estado['lastMove'] = descifrar_xor(estado['lastMove'], clave)
    
    # Quitar campos de seguridad
    estado.pop('encrypted', None)
    estado.pop('integrity', None)
    
    return estado


# ===========================================================================
# Auto-test
# ===========================================================================
if __name__ == "__main__":
    print("=== Test de Seguridad arChess 3.0 ===\n")
    
    # Test XOR
    texto = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"
    cifrado = cifrar_xor(texto)
    descifrado = descifrar_xor(cifrado)
    print(f"Original:    {texto}")
    print(f"Cifrado:     {cifrado[:50]}...")
    print(f"Descifrado:  {descifrado}")
    print(f"Correcto:    {texto == descifrado}\n")
    
    # Test Hash
    h = generar_hash(texto)
    print(f"Hash SHA-256: {h}")
    print(f"Integridad:   {verificar_integridad(texto, h)}\n")
    
    # Test Token
    token = generar_token_sesion("game123", "a")
    print(f"Token sesion: {token}\n")
    
    # Test Estado Completo
    estado = {
        "gameId": "abc123",
        "version": 5,
        "turn": "w",
        "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR",
        "lastMove": "e2e4",
        "status": "ongoing"
    }
    cifrado_est = cifrar_estado(estado)
    print(f"Estado cifrado FEN: {cifrado_est['fen'][:40]}...")
    print(f"Tiene integrity:    {bool(cifrado_est.get('integrity'))}")
    
    descifrado_est = descifrar_estado(cifrado_est)
    print(f"FEN descifrado:     {descifrado_est['fen']}")
    print(f"Correcto:           {descifrado_est['fen'] == estado['fen']}")
