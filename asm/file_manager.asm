; ===========================================================================
; file_manager.asm - Modulo de Manejo de Archivos Locales (JSON directo)
;
; CAMBIO: Rutas corregidas a la ubicacion real del proyecto:
;   C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\
;
; Funcionalidad:
;   - Leer y escribir game_state.json
;   - Escribir movimientos al historial moves.log
;   - Leer hint.json
;   - Leer y escribir sync_flag.txt
;   - Generar cadena FEN a partir del tablero actual
;   - Parser JSON minimo
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

INVALID_HANDLE      EQU -1
FILE_END_CONST      EQU 2

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

; --- Rutas de archivos (CORREGIDAS) ---
rutaEstado      BYTE "C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\data\game_state.json", 0
rutaMovesLog    BYTE "C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\data\moves.log", 0
rutaHint        BYTE "C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\data\hint.json", 0
rutaBandera     BYTE "C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\data\sync_flag.txt", 0

; --- Buffers para estado del juego (game_state.json) ---
archivoGameId   BYTE 32 DUP(0)
archivoVersion  DWORD 0
archivoTurno    BYTE 0
archivoFEN      BYTE 128 DUP(0)
archivoLastMove BYTE 8 DUP(0)
archivoStatus   BYTE 16 DUP(0)
archivoUpdatedAt BYTE 32 DUP(0)

; --- Buffers para pista de IA (hint.json) ---
archivoPista      BYTE 8 DUP(0)
archivoPistaScore SDWORD 0
archivoPistaDepth DWORD 0

; --- Buffer grande de lectura/escritura ---
bufArchivo      BYTE 1024 DUP(0)
bytesLeidos     DWORD 0

; --- Buffer auxiliar de escritura JSON ---
bufJSON         BYTE 1024 DUP(0)

; --- Buffer de numero temporal ---
numBuf          BYTE 16 DUP(0)

; --- Claves JSON para parseo (con comillas) ---
clave_gameId    BYTE '"gameId"', 0
clave_version   BYTE '"version"', 0
clave_turn      BYTE '"turn"', 0
clave_fen       BYTE '"fen"', 0
clave_lastMove  BYTE '"lastMove"', 0
clave_status    BYTE '"status"', 0
clave_updatedAt BYTE '"updatedAt"', 0

clave_bestMove  BYTE '"bestMove"', 0
clave_scoreCp   BYTE '"scoreCp"', 0
clave_depth     BYTE '"depth"', 0

; --- Valores por defecto ---
gameIdDefault   BYTE "partida_default", 0
statusOngoing   BYTE "ongoing", 0
lastMoveNone    BYTE "-", 0

; --- Tabla FEN ---
fenPiezas       BYTE 0
                BYTE 'P'
                BYTE 'R'
                BYTE 'N'
                BYTE 'B'
                BYTE 'Q'
                BYTE 'K'
                BYTE 'p'
                BYTE 'r'
                BYTE 'n'
                BYTE 'b'
                BYTE 'q'
                BYTE 'k'

tiempoActual    SYSTEMTIME <>

; ===========================================================================
;                       SEGMENTO DE CODIGO
; ===========================================================================
.code

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
; Archivo_InicializarEstado
; ===========================================================================
Archivo_InicializarEstado PROC
    push eax
    push ecx
    push esi
    push edi

    lea  esi, gameIdDefault
    lea  edi, archivoGameId
    call Aux_CopiarStr

    mov  archivoVersion, 1
    mov  archivoTurno, 'w'

    call Archivo_GenerarFEN

    lea  esi, lastMoveNone
    lea  edi, archivoLastMove
    call Aux_CopiarStr

    lea  esi, statusOngoing
    lea  edi, archivoStatus
    call Aux_CopiarStr

    call Aux_GenerarTimestamp

    pop  edi
    pop  esi
    pop  ecx
    pop  eax
    ret
Archivo_InicializarEstado ENDP


; ===========================================================================
; Archivo_GenerarFEN
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
    xor  ecx, ecx
    mov  edx, 0

FEN_FilaLoop:
    cmp  edx, 8
    je   FEN_Terminar

    xor  ebx, ebx
    push edx

    mov  eax, 8
FEN_ColLoop:
    cmp  eax, 0
    je   FEN_FinFila

    movzx edx, BYTE PTR [esi + ecx]

    cmp  edx, EMPTY
    jne  FEN_EsPieza
    inc  ebx
    jmp  FEN_SigCol

FEN_EsPieza:
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
; Archivo_EscribirEstado
; Retorna: AL = 1 si exito, 0 si error
; ===========================================================================
Archivo_EscribirEstado PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

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

    lea  edi, bufJSON

    mov  BYTE PTR [edi], '{'
    inc  edi
    call Aux_CRLF

    lea  esi, clave_gameId
    lea  edx, archivoGameId
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    lea  esi, clave_version
    mov  eax, archivoVersion
    mov  cl, 1
    call Aux_JSON_EscribirCampoNum

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

    lea  esi, clave_fen
    lea  edx, archivoFEN
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    lea  esi, clave_lastMove
    lea  edx, archivoLastMove
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    lea  esi, clave_updatedAt
    lea  edx, archivoUpdatedAt
    mov  cl, 1
    call Aux_JSON_EscribirCampoStr

    lea  esi, clave_status
    lea  edx, archivoStatus
    mov  cl, 0
    call Aux_JSON_EscribirCampoStr

    mov  BYTE PTR [edi], '}'
    inc  edi
    call Aux_CRLF
    mov  BYTE PTR [edi], 0

    mov  edx, OFFSET rutaEstado
    call CreateOutputFile
    cmp  eax, INVALID_HANDLE
    je   EscEst_Error
    mov  ebx, eax

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
; Aux_JSON_EscribirCampoStr
; ESI = clave, EDX = valor, CL = 1 coma / 0 sin, EDI = posicion en bufJSON
; ===========================================================================
Aux_JSON_EscribirCampoStr PROC
    push eax
    push esi

    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi

    call Aux_CopiarAEdi

    mov  BYTE PTR [edi], ':'
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], '"'
    inc  edi

    mov  esi, edx
    call Aux_CopiarAEdi

    mov  BYTE PTR [edi], '"'
    inc  edi

    cmp  cl, 0
    je   EscCampoStr_SinComa
    mov  BYTE PTR [edi], ','
    inc  edi
EscCampoStr_SinComa:

    call Aux_CRLF

    pop  esi
    pop  eax
    ret
Aux_JSON_EscribirCampoStr ENDP


; ===========================================================================
; Aux_JSON_EscribirCampoNum
; ESI = clave, EAX = valor, CL = 1 coma / 0 sin, EDI = posicion
; ===========================================================================
Aux_JSON_EscribirCampoNum PROC
    push eax
    push esi
    push edx

    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi

    call Aux_CopiarAEdi

    mov  BYTE PTR [edi], ':'
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi

    pop  edx
    push edx
    push edi
    lea  edi, numBuf
    call Aux_DwordToStr
    pop  edi

    push esi
    lea  esi, numBuf
    call Aux_CopiarAEdi
    pop  esi

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
; Archivo_LeerEstado
; Retorna: AL = 1 si exito, 0 si error
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

    ; Limpiar buffer antes de leer
    mov  eax, ebx
    lea  edi, bufArchivo
    mov  ecx, 1024
    push eax
    xor  al, al
    rep  stosb
    pop  eax

    lea  edx, bufArchivo
    mov  ecx, 1020
    call ReadFromFile
    mov  bytesLeidos, eax

    mov  eax, ebx
    call CloseFile

    lea  esi, bufArchivo
    mov  eax, bytesLeidos
    mov  BYTE PTR [esi + eax], 0

    ; --- Extraer campos ---
    lea  edx, clave_gameId
    lea  edi, archivoGameId
    mov  ecx, 30
    call Aux_JSON_ExtraerStr

    lea  edx, clave_version
    call Aux_JSON_ExtraerNum
    mov  archivoVersion, eax

    lea  edx, clave_turn
    lea  edi, numBuf
    mov  ecx, 4
    call Aux_JSON_ExtraerStr
    mov  al, numBuf
    mov  archivoTurno, al

    lea  edx, clave_fen
    lea  edi, archivoFEN
    mov  ecx, 120
    call Aux_JSON_ExtraerStr

    lea  edx, clave_lastMove
    lea  edi, archivoLastMove
    mov  ecx, 6
    call Aux_JSON_ExtraerStr

    lea  edx, clave_updatedAt
    lea  edi, archivoUpdatedAt
    mov  ecx, 28
    call Aux_JSON_ExtraerStr

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
; Archivo_LeerPista
; Retorna: AL = 1 si exito, 0 si error
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

    lea  edx, clave_bestMove
    lea  edi, archivoPista
    mov  ecx, 6
    call Aux_JSON_ExtraerStr

    lea  edx, clave_scoreCp
    call Aux_JSON_ExtraerNum
    mov  archivoPistaScore, eax

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
; Archivo_RegistrarMovimiento
; EDX = puntero al string UCI
; ===========================================================================
Archivo_RegistrarMovimiento PROC
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  esi, edx

    INVOKE CreateFileA,
        ADDR rutaMovesLog,
        GENERIC_WRITE,
        FILE_SHARE_READ,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    cmp  eax, INVALID_HANDLE_VALUE
    je   RegMov_Fin
    mov  ebx, eax

    INVOKE SetFilePointer, ebx, 0, NULL, FILE_END_CONST

    lea  edi, bufJSON

    call Tablero_ObtenerTurno
    cmp  al, COLOR_WHITE
    jne  RegMov_Negras

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

    mov  BYTE PTR [edi], 0Dh
    inc  edi
    mov  BYTE PTR [edi], 0Ah
    inc  edi

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
; Archivo_ActualizarLastMove
; EDX = puntero al string UCI
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
; Archivo_IncrementarVersion
; ===========================================================================
Archivo_IncrementarVersion PROC
    inc  archivoVersion
    ret
Archivo_IncrementarVersion ENDP


; ===========================================================================
; Archivo_LeerBandera
; Retorna: AL = '1' si hay actualizacion, '0' si no
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
; Archivo_EscribirBandera
; AL = '0' o '1'
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
;          PARSER JSON MINIMO
; ===========================================================================

Aux_JSON_ExtraerStr PROC
    push ebx
    push ecx
    push esi

    lea  esi, bufArchivo
    call Aux_BuscarSubstr
    cmp  esi, 0
    je   ExtrStr_No

ExtrStr_Limpiar:
    cmp  BYTE PTR [esi], 0
    je   ExtrStr_No
    cmp  BYTE PTR [esi], '"'
    je   ExtrStr_Inicio
    inc  esi
    jmp  ExtrStr_Limpiar

ExtrStr_Inicio:
    inc  esi
ExtrStr_Copiar:
    cmp  ecx, 1
    jbe  ExtrStr_FinCopia
    mov  al, [esi]
    cmp  al, 0
    je   ExtrStr_FinCopia
    cmp  al, '"'
    je   ExtrStr_FinCopia

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


Aux_JSON_ExtraerNum PROC
    push ebx
    push ecx
    push esi
    push edi

    lea  esi, bufArchivo
    call Aux_BuscarSubstr
    cmp  esi, 0
    je   ExtrNum_No

ExtrNum_Dp:
    cmp  BYTE PTR [esi], 0
    je   ExtrNum_No
    cmp  BYTE PTR [esi], ':'
    je   ExtrNum_DpOk
    inc  esi
    jmp  ExtrNum_Dp

ExtrNum_DpOk:
    inc  esi
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


Aux_BuscarSubstr PROC
    push eax
    push ebx
    push ecx
    push edi

    mov  edi, edx
    xor  ecx, ecx
BuscSub_Len:
    cmp  BYTE PTR [edi + ecx], 0
    je   BuscSub_LenOk
    inc  ecx
    jmp  BuscSub_Len
BuscSub_LenOk:

BuscSub_Loop:
    cmp  BYTE PTR [esi], 0
    je   BuscSub_No

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
    add  esp, 4
    jmp  BuscSub_Fin

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


Aux_CRLF PROC
    mov  BYTE PTR [edi], 0Dh
    inc  edi
    mov  BYTE PTR [edi], 0Ah
    inc  edi
    ret
Aux_CRLF ENDP


; ===========================================================================
; Aux_GenerarTimestamp
; ===========================================================================
Aux_GenerarTimestamp PROC
    push eax
    push ebx
    push ecx
    push edx
    push edi

    INVOKE GetLocalTime, ADDR tiempoActual

    lea  edi, archivoUpdatedAt

    movzx eax, tiempoActual.wYear
    call Aux_Escribir4Digitos
    mov  BYTE PTR [edi], '-'
    inc  edi

    movzx eax, tiempoActual.wMonth
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], '-'
    inc  edi

    movzx eax, tiempoActual.wDay
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], 'T'
    inc  edi

    movzx eax, tiempoActual.wHour
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], ':'
    inc  edi

    movzx eax, tiempoActual.wMinute
    call Aux_Escribir2Digitos
    mov  BYTE PTR [edi], ':'
    inc  edi

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