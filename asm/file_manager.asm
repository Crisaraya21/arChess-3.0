; ===========================================================================
; file_manager.asm — Módulo de Manejo de Archivos Locales (JSON directo)
;
; Funcionalidad:
;   - Leer y escribir game_state.json (formato JSON estándar)
;   - Escribir movimientos al historial moves.log (append secuencial)
;   - Leer hint.json (archivo de pista generado por el servicio Python IA)
;   - Leer y escribir sync_flag.txt (bandera de sincronización)
;   - Generar cadena FEN a partir del tablero actual
;   - Parser JSON mínimo: busca campos por nombre y extrae valores
;
; Archivos manejados:
;   game_state.json  → JSON con: gameId, version, turn, fen,
;                       lastMove, updatedAt, status
;   hint.json        → JSON con: gameId, basedOnVersion, bestMove,
;                       scoreCp, depth, pv
;   moves.log        → Texto plano secuencial (1. e2e4 / ... e7e5)
;   sync_flag.txt    → Un solo byte: '0' o '1'
;
; Dependencias:
;   - board.asm  (board, Tablero_ObtenerPieza, Tablero_ObtenerTurno, etc.)
;   - Irvine32.inc
;
; Funciones Win32 directas:
;   - CreateFileA   (para append en moves.log)
;   - SetFilePointer
;   - GetLocalTime  (para campo updatedAt)
; ===========================================================================

INCLUDE Irvine32.inc

; ---------------------------------------------------------------------------
; Constantes de piezas (deben coincidir con board.asm)
; ---------------------------------------------------------------------------
EMPTY           EQU 0
WHITE_PAWN      EQU 1
WHITE_ROOK      EQU 2
WHITE_KNIGHT    EQU 3
WHITE_BISHOP    EQU 4
WHITE_QUEEN     EQU 5
WHITE_KING      EQU 6
BLACK_PAWN      EQU 7
BLACK_ROOK      EQU 8
BLACK_KNIGHT    EQU 9
BLACK_BISHOP    EQU 10
BLACK_QUEEN     EQU 11
BLACK_KING      EQU 12

COLOR_WHITE     EQU 0
COLOR_BLACK     EQU 1

BOARD_SIZE      EQU 64

; Constantes Win32
GENERIC_WRITE       EQU 40000000h
GENERIC_READ        EQU 80000000h
FILE_SHARE_READ     EQU 1
CREATE_ALWAYS       EQU 2
OPEN_EXISTING       EQU 3
OPEN_ALWAYS         EQU 4
FILE_ATTR_NORMAL    EQU 80h
INVALID_HANDLE      EQU -1
FILE_END            EQU 2

; Prototipos Win32
CreateFileA     PROTO, lpFileName:PTR BYTE, dwAccess:DWORD,
                dwShareMode:DWORD, lpSecurity:DWORD,
                dwCreation:DWORD, dwFlags:DWORD, hTemplate:DWORD
SetFilePointer  PROTO, hFile:DWORD, lDistLow:SDWORD,
                lpDistHigh:PTR DWORD, dwMoveMethod:DWORD

; Estructura SYSTEMTIME para GetLocalTime
SYSTEMTIME STRUCT
    wYear       WORD ?
    wMonth      WORD ?
    wDayOfWeek  WORD ?
    wDay        WORD ?
    wHour       WORD ?
    wMinute     WORD ?
    wSecond     WORD ?
    wMilliseconds WORD ?
SYSTEMTIME ENDS

GetLocalTime PROTO, lpSystemTime:PTR SYSTEMTIME

; ---------------------------------------------------------------------------
; Referencias externas (board.asm)
; ---------------------------------------------------------------------------
EXTERN board : BYTE
Tablero_ObtenerPieza               PROTO
Tablero_ObtenerTurno               PROTO
Tablero_ObtenerContadorMovimientos PROTO

; ===========================================================================
;                       SEGMENTO DE DATOS
; ===========================================================================
.data

; --- PUBLIC de variables (dentro de .data) ---
PUBLIC archivoGameId
PUBLIC archivoVersion
PUBLIC archivoTurno
PUBLIC archivoFEN
PUBLIC archivoLastMove
PUBLIC archivoStatus
PUBLIC archivoUpdatedAt
PUBLIC archivoPista
PUBLIC archivoPistaScore
PUBLIC archivoPistaDepth

; --- Rutas de archivos ---
rutaEstado      BYTE "data\game_state.json", 0
rutaMovesLog    BYTE "data\moves.log", 0
rutaHint        BYTE "data\hint.json", 0
rutaBandera     BYTE "data\sync_flag.txt", 0

; --- Buffers para estado del juego (game_state.json) ---
archivoGameId   BYTE 32 DUP(0)
archivoVersion  DWORD 0
archivoTurno    BYTE 0               ; 'w' o 'b'
archivoFEN      BYTE 128 DUP(0)
archivoLastMove BYTE 8 DUP(0)
archivoStatus   BYTE 16 DUP(0)
archivoUpdatedAt BYTE 32 DUP(0)      ; "2026-03-23T10:15:00Z"

; --- Buffers para pista de IA (hint.json) ---
archivoPista      BYTE 8 DUP(0)      ; bestMove (ej: "g1f3")
archivoPistaScore SDWORD 0           ; scoreCp (centipawns, con signo)
archivoPistaDepth DWORD 0            ; depth

; --- Buffer grande de lectura/escritura ---
bufArchivo      BYTE 1024 DUP(0)
bytesLeidos     DWORD 0

; --- Buffer auxiliar de escritura JSON ---
bufJSON         BYTE 1024 DUP(0)

; --- Buffer de número temporal ---
numBuf          BYTE 16 DUP(0)

; --- Claves JSON para parseo (con comillas) ---
; game_state.json
clave_gameId    BYTE '"gameId"', 0
clave_version   BYTE '"version"', 0
clave_turn      BYTE '"turn"', 0
clave_fen       BYTE '"fen"', 0
clave_lastMove  BYTE '"lastMove"', 0
clave_status    BYTE '"status"', 0
clave_updatedAt BYTE '"updatedAt"', 0

; hint.json
clave_bestMove  BYTE '"bestMove"', 0
clave_scoreCp   BYTE '"scoreCp"', 0
clave_depth     BYTE '"depth"', 0

; --- Valores por defecto ---
gameIdDefault   BYTE "partida_default", 0
statusOngoing   BYTE "ongoing", 0
lastMoveNone    BYTE "-", 0

; --- Tabla FEN: código de pieza → carácter FEN ---
fenPiezas       BYTE 0               ; 0 = EMPTY
                BYTE 'P'             ; 1 = WHITE_PAWN
                BYTE 'R'             ; 2 = WHITE_ROOK
                BYTE 'N'             ; 3 = WHITE_KNIGHT
                BYTE 'B'             ; 4 = WHITE_BISHOP
                BYTE 'Q'             ; 5 = WHITE_QUEEN
                BYTE 'K'             ; 6 = WHITE_KING
                BYTE 'p'             ; 7 = BLACK_PAWN
                BYTE 'r'             ; 8 = BLACK_ROOK
                BYTE 'n'             ; 9 = BLACK_KNIGHT
                BYTE 'b'             ; 10 = BLACK_BISHOP
                BYTE 'q'             ; 11 = BLACK_QUEEN
                BYTE 'k'             ; 12 = BLACK_KING

; --- SYSTEMTIME para timestamp ---
tiempoActual    SYSTEMTIME <>

; ===========================================================================
;                       SEGMENTO DE CÓDIGO
; ===========================================================================
.code

; --- PUBLIC de procedimientos (dentro de .code) ---
PUBLIC Archivo_InicializarEstado
PUBLIC Archivo_EscribirEstado
PUBLIC Archivo_LeerEstado
PUBLIC Archivo_ActualizarLastMove
PUBLIC Archivo_RegistrarMovimiento
PUBLIC Archivo_LeerBandera
PUBLIC Archivo_EscribirBandera
PUBLIC Archivo_LeerPista
PUBLIC Archivo_GenerarFEN
PUBLIC Archivo_IncrementarVersion


; ===========================================================================
; Procedimiento: Archivo_InicializarEstado
; Descripción : Inicializa los campos del estado con valores por defecto
;               al iniciar una nueva partida.
; ===========================================================================
Archivo_InicializarEstado PROC
    push eax
    push ecx
    push esi
    push edi

    ; gameId = "partida_default"
    lea  esi, gameIdDefault
    lea  edi, archivoGameId
    call Aux_CopiarStr

    ; version = 1
    mov  archivoVersion, 1

    ; turno = 'w'
    mov  archivoTurno, 'w'

    ; FEN del tablero actual
    call Archivo_GenerarFEN

    ; lastMove = "-"
    lea  esi, lastMoveNone
    lea  edi, archivoLastMove
    call Aux_CopiarStr

    ; status = "ongoing"
    lea  esi, statusOngoing
    lea  edi, archivoStatus
    call Aux_CopiarStr

    ; updatedAt (generar timestamp actual)
    call Aux_GenerarTimestamp

    pop  edi
    pop  esi
    pop  ecx
    pop  eax
    ret
Archivo_InicializarEstado ENDP


; ===========================================================================
; Procedimiento: Archivo_GenerarFEN
; Descripción : Genera la cadena FEN del tablero actual y la almacena
;               en archivoFEN. Recorre board[] de índice 0 a 63.
;
; Formato: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"
; ===========================================================================
Archivo_GenerarFEN PROC
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    lea  esi, board
    lea  edi, archivoFEN
    xor  ecx, ecx              ; ECX = índice tablero (0–63)
    mov  edx, 0                ; EDX = fila (0–7)

FEN_FilaLoop:
    cmp  edx, 8
    je   FEN_Terminar

    xor  ebx, ebx              ; EBX = vacíos consecutivos
    push edx

    mov  eax, 8                ; 8 columnas
FEN_ColLoop:
    cmp  eax, 0
    je   FEN_FinFila

    movzx edx, BYTE PTR [esi + ecx]

    cmp  edx, EMPTY
    jne  FEN_EsPieza
    inc  ebx
    jmp  FEN_SigCol

FEN_EsPieza:
    ; Escribir vacíos acumulados
    cmp  ebx, 0
    je   FEN_EscribirPieza
    push eax
    mov  al, bl
    add  al, '0'
    mov  [edi], al
    inc  edi
    xor  ebx, ebx
    pop  eax

FEN_EscribirPieza:
    push eax
    lea  eax, fenPiezas
    add  eax, edx
    mov  al, [eax]
    mov  [edi], al
    inc  edi
    pop  eax

FEN_SigCol:
    inc  ecx
    dec  eax
    jmp  FEN_ColLoop

FEN_FinFila:
    ; Vacíos pendientes al final de fila
    cmp  ebx, 0
    je   FEN_SepFila
    mov  al, bl
    add  al, '0'
    mov  [edi], al
    inc  edi

FEN_SepFila:
    pop  edx
    inc  edx
    cmp  edx, 8
    je   FEN_Terminar
    mov  BYTE PTR [edi], '/'
    inc  edi
    jmp  FEN_FilaLoop

FEN_Terminar:
    mov  BYTE PTR [edi], 0

    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
Archivo_GenerarFEN ENDP


; ===========================================================================
; Procedimiento: Archivo_EscribirEstado
; Descripción : Escribe game_state.json con formato JSON válido.
;
; Genera:
;   {
;     "gameId": "partida_default",
;     "version": 1,
;     "turn": "w",
;     "fen": "rnbqkbnr/pppppppp/8/8/...",
;     "lastMove": "e2e4",
;     "updatedAt": "2026-03-23T10:15:00Z",
;     "status": "ongoing"
;   }
;
; Retorna: AL = 1 si éxito, 0 si error
; ===========================================================================
Archivo_EscribirEstado PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Actualizar FEN y turno antes de escribir
    call Archivo_GenerarFEN
    call Tablero_ObtenerTurno
    cmp  al, COLOR_WHITE
    jne  EscEst_Negro
    mov  archivoTurno, 'w'
    jmp  EscEst_Timestamp
EscEst_Negro:
    mov  archivoTurno, 'b'

EscEst_Timestamp:
    call Aux_GenerarTimestamp

    ; --- Construir JSON en bufJSON ---
    lea  edi, bufJSON

    ; "{\r\n"
    mov  BYTE PTR [edi], '{'
    inc  edi
    call Aux_CRLF

    ; campo "gameId" (string con coma)
    lea  esi, clave_gameId
    lea  edx, archivoGameId
    mov  cl, 1                 ; 1 = con coma
    call Aux_JSON_EscribirCampoStr

    ; campo "version" (número con coma)
    lea  esi, clave_version
    mov  eax, archivoVersion
    mov  cl, 1
    call Aux_JSON_EscribirCampoNum

    ; campo "turn" (string con coma)
    lea  esi, clave_turn
    mov  numBuf, 0
    push eax
    mov  al, archivoTurno
    mov  numBuf, al
    mov  numBuf+1, 0
    pop  eax
    lea  edx, numBuf
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    ; campo "fen" (string con coma)
    lea  esi, clave_fen
    lea  edx, archivoFEN
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    ; campo "lastMove" (string con coma)
    lea  esi, clave_lastMove
    lea  edx, archivoLastMove
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    ; campo "updatedAt" (string con coma)
    lea  esi, clave_updatedAt
    lea  edx, archivoUpdatedAt
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    ; campo "status" (string SIN coma — último campo)
    lea  esi, clave_status
    lea  edx, archivoStatus
    mov  cl, 0                 ; 0 = sin coma
    call Aux_JSON_EscribirCampoStr

    ; "}\r\n"
    mov  BYTE PTR [edi], '}'
    inc  edi
    call Aux_CRLF
    mov  BYTE PTR [edi], 0     ; null terminator

    ; --- Escribir bufJSON al archivo ---
    mov  edx, OFFSET rutaEstado
    call CreateOutputFile
    cmp  eax, INVALID_HANDLE
    je   EscEst_Error
    mov  ebx, eax

    ; Calcular longitud del JSON
    lea  edx, bufJSON
    call Aux_StrLen
    mov  ecx, eax

    lea  edx, bufJSON
    mov  eax, ebx
    call WriteToFile

    mov  eax, ebx
    call CloseFile

    mov  al, 1
    jmp  EscEst_Fin

EscEst_Error:
    mov  al, 0

EscEst_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Archivo_EscribirEstado ENDP


; ===========================================================================
; Aux_JSON_EscribirCampoStr — Escribe un campo JSON tipo string a EDI.
; Formato: '  "clave": "valor",\r\n'  o sin coma si CL=0
;
; Parámetros: ESI = clave (ej: '"gameId"'), EDX = valor, CL = 1 coma / 0 sin
;             EDI = posición actual en bufJSON (se avanza)
; ===========================================================================
Aux_JSON_EscribirCampoStr PROC
    push eax
    push esi

    ; Indentación "  "
    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi

    ; Clave (ya incluye comillas)
    call Aux_CopiarAEdi

    ; ": "
    mov  BYTE PTR [edi], ':'
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], '"'
    inc  edi

    ; Valor
    mov  esi, edx
    call Aux_CopiarAEdi

    ; Comilla de cierre
    mov  BYTE PTR [edi], '"'
    inc  edi

    ; Coma si corresponde
    cmp  cl, 0
    je   EscCampoStr_SinComa
    mov  BYTE PTR [edi], ','
    inc  edi
EscCampoStr_SinComa:

    ; CR+LF
    call Aux_CRLF

    pop  esi
    pop  eax
    ret
Aux_JSON_EscribirCampoStr ENDP


; ===========================================================================
; Aux_JSON_EscribirCampoNum — Escribe un campo JSON numérico a EDI.
; Formato: '  "clave": 123,\r\n'
;
; Parámetros: ESI = clave, EAX = valor numérico, CL = 1 coma / 0 sin
;             EDI = posición actual
; ===========================================================================
Aux_JSON_EscribirCampoNum PROC
    push eax
    push esi
    push edx

    ; Indentación
    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi

    ; Clave
    call Aux_CopiarAEdi

    ; ": "
    mov  BYTE PTR [edi], ':'
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi

    ; Convertir número a string
    pop  edx
    push edx
    push edi
    lea  edi, numBuf
    call Aux_DwordToStr
    pop  edi

    ; Copiar numBuf a bufJSON
    push esi
    lea  esi, numBuf
    call Aux_CopiarAEdi
    pop  esi

    ; Coma si corresponde
    cmp  cl, 0
    je   EscCampoNum_SinComa
    mov  BYTE PTR [edi], ','
    inc  edi
EscCampoNum_SinComa:

    call Aux_CRLF

    pop  edx
    pop  esi
    pop  eax
    ret
Aux_JSON_EscribirCampoNum ENDP


; ===========================================================================
; Procedimiento: Archivo_LeerEstado
; Descripción : Lee game_state.json y extrae cada campo con el parser JSON.
;
; Retorna     : AL = 1 si éxito, 0 si error
; ===========================================================================
Archivo_LeerEstado PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  edx, OFFSET rutaEstado
    call OpenInputFile
    cmp  eax, INVALID_HANDLE
    je   LeerEst_Error
    mov  ebx, eax

    mov  eax, ebx
    lea  edx, bufArchivo
    mov  ecx, 1020
    call ReadFromFile
    mov  bytesLeidos, eax

    mov  eax, ebx
    call CloseFile

    ; Null terminator
    lea  esi, bufArchivo
    mov  eax, bytesLeidos
    mov  BYTE PTR [esi + eax], 0

    ; --- Extraer campos ---

    ; gameId
    lea  edx, clave_gameId
    lea  edi, archivoGameId
    mov  ecx, 30
    call Aux_JSON_ExtraerStr

    ; version
    lea  edx, clave_version
    call Aux_JSON_ExtraerNum
    mov  archivoVersion, eax

    ; turn
    lea  edx, clave_turn
    lea  edi, numBuf
    mov  ecx, 4
    call Aux_JSON_ExtraerStr
    mov  al, numBuf
    mov  archivoTurno, al

    ; fen
    lea  edx, clave_fen
    lea  edi, archivoFEN
    mov  ecx, 120
    call Aux_JSON_ExtraerStr

    ; lastMove
    lea  edx, clave_lastMove
    lea  edi, archivoLastMove
    mov  ecx, 6
    call Aux_JSON_ExtraerStr

    ; updatedAt
    lea  edx, clave_updatedAt
    lea  edi, archivoUpdatedAt
    mov  ecx, 28
    call Aux_JSON_ExtraerStr

    ; status
    lea  edx, clave_status
    lea  edi, archivoStatus
    mov  ecx, 14
    call Aux_JSON_ExtraerStr

    mov  al, 1
    jmp  LeerEst_Fin

LeerEst_Error:
    mov  al, 0

LeerEst_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Archivo_LeerEstado ENDP


; ===========================================================================
; Procedimiento: Archivo_LeerPista
; Descripción : Lee hint.json y extrae bestMove, scoreCp y depth.
;
; Retorna     : AL = 1 si éxito, 0 si error
; ===========================================================================
Archivo_LeerPista PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  edx, OFFSET rutaHint
    call OpenInputFile
    cmp  eax, INVALID_HANDLE
    je   LeerPista_Error

    mov  ebx, eax
    lea  edx, bufArchivo
    mov  ecx, 512
    mov  eax, ebx
    call ReadFromFile
    mov  bytesLeidos, eax

    mov  eax, ebx
    call CloseFile

    lea  esi, bufArchivo
    mov  eax, bytesLeidos
    mov  BYTE PTR [esi + eax], 0

    ; bestMove
    lea  edx, clave_bestMove
    lea  edi, archivoPista
    mov  ecx, 6
    call Aux_JSON_ExtraerStr

    ; scoreCp (puede ser negativo)
    lea  edx, clave_scoreCp
    call Aux_JSON_ExtraerNum
    mov  archivoPistaScore, eax

    ; depth
    lea  edx, clave_depth
    call Aux_JSON_ExtraerNum
    mov  archivoPistaDepth, eax

    mov  al, 1
    jmp  LeerPista_Fin

LeerPista_Error:
    mov  al, 0

LeerPista_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Archivo_LeerPista ENDP


; ===========================================================================
; Procedimiento: Archivo_RegistrarMovimiento
; Descripción : Agrega un movimiento a moves.log (append).
;               "N. e2e4\r\n" (blancas) o "... e7e5\r\n" (negras)
;
; Parámetros  : EDX = puntero al string UCI (4 chars + null)
; ===========================================================================
Archivo_RegistrarMovimiento PROC
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  esi, edx              ; ESI = movimiento UCI

    ; Abrir en modo append
    INVOKE CreateFileA,
        ADDR rutaMovesLog,
        GENERIC_WRITE,
        FILE_SHARE_READ,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTR_NORMAL,
        NULL
    cmp  eax, INVALID_HANDLE
    je   RegMov_Fin
    mov  ebx, eax

    INVOKE SetFilePointer, ebx, 0, NULL, FILE_END

    ; Construir línea en bufJSON (reutilizado como temporal)
    lea  edi, bufJSON

    ; Formato según turno
    call Tablero_ObtenerTurno
    cmp  al, COLOR_WHITE
    jne  RegMov_Negras

    ; --- Blancas: "N. xxxx\r\n" ---
    call Tablero_ObtenerContadorMovimientos
    shr  eax, 1
    inc  eax

    push edi
    lea  edi, numBuf
    call Aux_DwordToStr
    pop  edi

    push esi
    lea  esi, numBuf
    call Aux_CopiarAEdi
    pop  esi

    mov  BYTE PTR [edi], '.'
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi
    jmp  RegMov_CopiarUCI

RegMov_Negras:
    ; --- Negras: "... xxxx\r\n" ---
    mov  BYTE PTR [edi+0], '.'
    mov  BYTE PTR [edi+1], '.'
    mov  BYTE PTR [edi+2], '.'
    mov  BYTE PTR [edi+3], ' '
    add  edi, 4

RegMov_CopiarUCI:
    mov  al, [esi+0]
    mov  [edi], al
    inc  edi
    mov  al, [esi+1]
    mov  [edi], al
    inc  edi
    mov  al, [esi+2]
    mov  [edi], al
    inc  edi
    mov  al, [esi+3]
    mov  [edi], al
    inc  edi

    ; CR+LF
    mov  BYTE PTR [edi], 0Dh
    inc  edi
    mov  BYTE PTR [edi], 0Ah
    inc  edi

    ; Escribir
    lea  edx, bufJSON
    mov  ecx, edi
    sub  ecx, edx
    mov  eax, ebx
    call WriteToFile

    mov  eax, ebx
    call CloseFile

RegMov_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
Archivo_RegistrarMovimiento ENDP


; ===========================================================================
; Procedimiento: Archivo_ActualizarLastMove
; Parámetros  : EDX = puntero al string UCI (4 chars + null)
; ===========================================================================
Archivo_ActualizarLastMove PROC
    push eax
    push edi
    push esi

    mov  esi, edx
    lea  edi, archivoLastMove
    mov  al, [esi+0]
    mov  [edi+0], al
    mov  al, [esi+1]
    mov  [edi+1], al
    mov  al, [esi+2]
    mov  [edi+2], al
    mov  al, [esi+3]
    mov  [edi+3], al
    mov  BYTE PTR [edi+4], 0

    pop  esi
    pop  edi
    pop  eax
    ret
Archivo_ActualizarLastMove ENDP


; ===========================================================================
; Procedimiento: Archivo_IncrementarVersion
; ===========================================================================
Archivo_IncrementarVersion PROC
    inc  archivoVersion
    ret
Archivo_IncrementarVersion ENDP


; ===========================================================================
; Procedimiento: Archivo_LeerBandera
; Retorna     : AL = '1' si hay actualización, '0' si no
; ===========================================================================
Archivo_LeerBandera PROC
    push ebx
    push ecx
    push edx

    mov  edx, OFFSET rutaBandera
    call OpenInputFile
    cmp  eax, INVALID_HANDLE
    je   LeerBand_NoExiste

    mov  ebx, eax
    lea  edx, bufArchivo
    mov  ecx, 4
    mov  eax, ebx
    call ReadFromFile

    mov  eax, ebx
    call CloseFile

    mov  al, bufArchivo
    jmp  LeerBand_Fin

LeerBand_NoExiste:
    mov  al, '0'

LeerBand_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    ret
Archivo_LeerBandera ENDP


; ===========================================================================
; Procedimiento: Archivo_EscribirBandera
; Parámetros  : AL = '0' o '1'
; ===========================================================================
Archivo_EscribirBandera PROC
    push eax
    push ebx
    push ecx
    push edx

    mov  bufArchivo, al

    mov  edx, OFFSET rutaBandera
    call CreateOutputFile
    cmp  eax, INVALID_HANDLE
    je   EscrBand_Fin

    mov  ebx, eax
    lea  edx, bufArchivo
    mov  ecx, 1
    mov  eax, ebx
    call WriteToFile

    mov  eax, ebx
    call CloseFile

EscrBand_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
Archivo_EscribirBandera ENDP


; ===========================================================================
;          PARSER JSON MÍNIMO — PROCEDIMIENTOS DE EXTRACCIÓN
; ===========================================================================

; ===========================================================================
; Aux_JSON_ExtraerStr — Busca clave JSON en bufArchivo y extrae valor string.
;
; Parámetros: EDX = clave (ej: '"gameId"')
;             EDI = buffer destino
;             ECX = máximo de caracteres
; Retorna   : EDI = valor null-terminated, AL = 1 encontrado / 0 no
; ===========================================================================
Aux_JSON_ExtraerStr PROC
    push ebx
    push ecx
    push esi

    lea  esi, bufArchivo
    call Aux_BuscarSubstr
    cmp  esi, 0
    je   ExtrStr_No

    ; Buscar ':' después de la clave
ExtrStr_Dp:
    cmp  BYTE PTR [esi], 0
    je   ExtrStr_No
    cmp  BYTE PTR [esi], ':'
    je   ExtrStr_DpOk
    inc  esi
    jmp  ExtrStr_Dp

ExtrStr_DpOk:
    inc  esi
    ; Buscar '"' de apertura del valor
ExtrStr_Comilla:
    cmp  BYTE PTR [esi], 0
    je   ExtrStr_No
    cmp  BYTE PTR [esi], '"'
    je   ExtrStr_Inicio
    inc  esi
    jmp  ExtrStr_Comilla

ExtrStr_Inicio:
    inc  esi                   ; saltar comilla de apertura
ExtrStr_Copiar:
    cmp  ecx, 0
    je   ExtrStr_FinCopia
    cmp  BYTE PTR [esi], 0
    je   ExtrStr_FinCopia
    cmp  BYTE PTR [esi], '"'
    je   ExtrStr_FinCopia
    mov  al, [esi]
    mov  [edi], al
    inc  esi
    inc  edi
    dec  ecx
    jmp  ExtrStr_Copiar

ExtrStr_FinCopia:
    mov  BYTE PTR [edi], 0
    mov  al, 1
    jmp  ExtrStr_Fin

ExtrStr_No:
    mov  BYTE PTR [edi], 0
    mov  al, 0

ExtrStr_Fin:
    pop  esi
    pop  ecx
    pop  ebx
    ret
Aux_JSON_ExtraerStr ENDP


; ===========================================================================
; Aux_JSON_ExtraerNum — Busca clave JSON y extrae valor numérico.
;
; Parámetros: EDX = clave (ej: '"version"')
; Retorna   : EAX = valor (0 si no encontrado). Soporta signo negativo.
; ===========================================================================
Aux_JSON_ExtraerNum PROC
    push ebx
    push ecx
    push esi
    push edi

    lea  esi, bufArchivo
    call Aux_BuscarSubstr
    cmp  esi, 0
    je   ExtrNum_No

    ; Buscar ':'
ExtrNum_Dp:
    cmp  BYTE PTR [esi], 0
    je   ExtrNum_No
    cmp  BYTE PTR [esi], ':'
    je   ExtrNum_DpOk
    inc  esi
    jmp  ExtrNum_Dp

ExtrNum_DpOk:
    inc  esi
    ; Saltar espacios/tabs
ExtrNum_Esp:
    cmp  BYTE PTR [esi], ' '
    je   ExtrNum_SaltarEsp
    cmp  BYTE PTR [esi], 09h
    je   ExtrNum_SaltarEsp
    jmp  ExtrNum_Leer
ExtrNum_SaltarEsp:
    inc  esi
    jmp  ExtrNum_Esp

ExtrNum_Leer:
    ; Verificar signo negativo
    xor  ebx, ebx
    cmp  BYTE PTR [esi], '-'
    jne  ExtrNum_Pos
    mov  ebx, 1
    inc  esi
ExtrNum_Pos:
    mov  edx, esi
    call Aux_StrToDword

    cmp  ebx, 0
    je   ExtrNum_Fin
    neg  eax
    jmp  ExtrNum_Fin

ExtrNum_No:
    xor  eax, eax

ExtrNum_Fin:
    pop  edi
    pop  esi
    pop  ecx
    pop  ebx
    ret
Aux_JSON_ExtraerNum ENDP


; ===========================================================================
; Aux_BuscarSubstr — Busca subcadena EDX en buffer ESI.
;
; Parámetros: ESI = buffer, EDX = subcadena (null-terminated)
; Retorna   : ESI = posición DESPUÉS de la subcadena, o 0 si no encontrada
; ===========================================================================
Aux_BuscarSubstr PROC
    push eax
    push ebx
    push ecx
    push edi

    ; Longitud de subcadena
    mov  edi, edx
    xor  ecx, ecx
BuscSub_Len:
    cmp  BYTE PTR [edi + ecx], 0
    je   BuscSub_LenOk
    inc  ecx
    jmp  BuscSub_Len
BuscSub_LenOk:
    ; ECX = longitud

BuscSub_Loop:
    cmp  BYTE PTR [esi], 0
    je   BuscSub_No

    ; Comparar ECX bytes
    push esi
    push ecx
    mov  edi, edx
    mov  ebx, ecx
BuscSub_Cmp:
    cmp  ebx, 0
    je   BuscSub_Match
    mov  al, [esi]
    cmp  al, [edi]
    jne  BuscSub_NoMatch
    inc  esi
    inc  edi
    dec  ebx
    jmp  BuscSub_Cmp

BuscSub_Match:
    pop  ecx
    add  esp, 4                ; descartar ESI viejo de la pila
    jmp  BuscSub_Fin           ; ESI apunta después de subcadena

BuscSub_NoMatch:
    pop  ecx
    pop  esi
    inc  esi
    jmp  BuscSub_Loop

BuscSub_No:
    mov  esi, 0

BuscSub_Fin:
    pop  edi
    pop  ecx
    pop  ebx
    pop  eax
    ret
Aux_BuscarSubstr ENDP


; ===========================================================================
;               PROCEDIMIENTOS AUXILIARES GENERALES
; ===========================================================================

; Aux_CopiarStr — Copia cadena ESI→EDI incluyendo null. EDI termina en null.
Aux_CopiarStr PROC
    push eax
CopStr_Loop:
    mov  al, [esi]
    mov  [edi], al
    cmp  al, 0
    je   CopStr_Fin
    inc  esi
    inc  edi
    jmp  CopStr_Loop
CopStr_Fin:
    pop  eax
    ret
Aux_CopiarStr ENDP


; Aux_CopiarAEdi — Copia cadena ESI→EDI SIN copiar null. EDI queda avanzado.
Aux_CopiarAEdi PROC
    push eax
CopAEdi_Loop:
    mov  al, [esi]
    cmp  al, 0
    je   CopAEdi_Fin
    mov  [edi], al
    inc  esi
    inc  edi
    jmp  CopAEdi_Loop
CopAEdi_Fin:
    pop  eax
    ret
Aux_CopiarAEdi ENDP


; Aux_StrLen — Longitud de cadena. EDX = puntero, Retorna EAX = longitud.
Aux_StrLen PROC
    push esi
    mov  esi, edx
    xor  eax, eax
StrLen_Loop:
    cmp  BYTE PTR [esi], 0
    je   StrLen_Fin
    inc  eax
    inc  esi
    jmp  StrLen_Loop
StrLen_Fin:
    pop  esi
    ret
Aux_StrLen ENDP


; Aux_DwordToStr — DWORD EAX → string en EDI. Retorna ECX = longitud.
Aux_DwordToStr PROC
    push ebx
    push edx
    push esi

    mov  esi, edi
    add  edi, 10
    mov  BYTE PTR [edi], 0
    dec  edi
    mov  ebx, 10
    xor  ecx, ecx

    cmp  eax, 0
    jne  DtoS_Loop
    mov  BYTE PTR [edi], '0'
    mov  ecx, 1
    jmp  DtoS_Ajustar

DtoS_Loop:
    cmp  eax, 0
    je   DtoS_Ajustar
    xor  edx, edx
    div  ebx
    add  dl, '0'
    mov  [edi], dl
    dec  edi
    inc  ecx
    jmp  DtoS_Loop

DtoS_Ajustar:
    inc  edi
    cmp  edi, esi
    je   DtoS_Fin
    push ecx
    push edi
    mov  edx, esi
DtoS_Copiar:
    mov  al, [edi]
    mov  [edx], al
    inc  edi
    inc  edx
    cmp  BYTE PTR [edi-1], 0
    jne  DtoS_Copiar
    mov  BYTE PTR [edx], 0
    pop  edi
    pop  ecx
    mov  edi, esi

DtoS_Fin:
    pop  esi
    pop  edx
    pop  ebx
    ret
Aux_DwordToStr ENDP


; Aux_StrToDword — String decimal EDX → DWORD en EAX.
Aux_StrToDword PROC
    push ebx
    push ecx
    push esi

    mov  esi, edx
    xor  eax, eax
    mov  ecx, 10

StrToD_Loop:
    movzx ebx, BYTE PTR [esi]
    cmp  bl, '0'
    jb   StrToD_Fin
    cmp  bl, '9'
    ja   StrToD_Fin
    imul eax, ecx
    sub  bl, '0'
    add  eax, ebx
    inc  esi
    jmp  StrToD_Loop

StrToD_Fin:
    pop  esi
    pop  ecx
    pop  ebx
    ret
Aux_StrToDword ENDP


; Aux_CRLF — Escribe CR+LF a EDI y avanza EDI.
Aux_CRLF PROC
    mov  BYTE PTR [edi], 0Dh
    inc  edi
    mov  BYTE PTR [edi], 0Ah
    inc  edi
    ret
Aux_CRLF ENDP


; ===========================================================================
; Aux_GenerarTimestamp — Genera "YYYY-MM-DDTHH:MM:SSZ" en archivoUpdatedAt
; ===========================================================================
Aux_GenerarTimestamp PROC
    push eax
    push ebx
    push ecx
    push edx
    push edi

    INVOKE GetLocalTime, ADDR tiempoActual

    lea  edi, archivoUpdatedAt

    ; Año
    movzx eax, tiempoActual.wYear
    call Aux_Escribir4Digitos
    mov  BYTE PTR [edi], '-'
    inc  edi

    ; Mes
    movzx eax, tiempoActual.wMonth
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], '-'
    inc  edi

    ; Día
    movzx eax, tiempoActual.wDay
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], 'T'
    inc  edi

    ; Hora
    movzx eax, tiempoActual.wHour
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], ':'
    inc  edi

    ; Minuto
    movzx eax, tiempoActual.wMinute
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], ':'
    inc  edi

    ; Segundo
    movzx eax, tiempoActual.wSecond
    call Aux_Escribir2Digitos

    mov  BYTE PTR [edi], 'Z'
    inc  edi
    mov  BYTE PTR [edi], 0

    pop  edi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
Aux_GenerarTimestamp ENDP


; Aux_Escribir2Digitos — EAX como 2 dígitos (zero-padded) a EDI.
Aux_Escribir2Digitos PROC
    push edx
    push ebx
    mov  ebx, 10
    xor  edx, edx
    div  ebx
    add  al, '0'
    mov  [edi], al
    inc  edi
    add  dl, '0'
    mov  [edi], dl
    inc  edi
    pop  ebx
    pop  edx
    ret
Aux_Escribir2Digitos ENDP


; Aux_Escribir4Digitos — EAX como 4 dígitos a EDI.
Aux_Escribir4Digitos PROC
    push edx
    push ebx

    mov  ebx, 1000
    xor  edx, edx
    div  ebx
    add  al, '0'
    mov  [edi], al
    inc  edi
    mov  eax, edx

    mov  ebx, 100
    xor  edx, edx
    div  ebx
    add  al, '0'
    mov  [edi], al
    inc  edi
    mov  eax, edx

    call Aux_Escribir2Digitos

    pop  ebx
    pop  edx
    ret
Aux_Escribir4Digitos ENDP

END