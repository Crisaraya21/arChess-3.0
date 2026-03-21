; ===========================================================================
; board.asm — Módulo de Representación del Tablero de Ajedrez
;
;
;   - Definir el vector lineal de 64 posiciones (tablero de ajedrez)
;   - Codificar piezas mediante bytes
;   - Inicializar el tablero en posición estándar
;   - Exponer procedimientos para leer/escribir celdas del tablero
;   - Exponer procedimientos para convertir coordenadas (fila, col) <-> índice
;
;
;
; Codificación de piezas (1 byte por celda):
;   0  = vacío
;   --- Piezas blancas (mayúsculas) ---
;   1  = Peón   blanco  (P)
;   2  = Torre  blanca  (R)
;   3  = Caballo blanco (N)
;   4  = Alfil  blanco  (B)
;   5  = Reina  blanca  (Q)
;   6  = Rey    blanco  (K)
;   --- Piezas negras (minúsculas) ---
;   7  = Peón   negro   (p)
;   8  = Torre  negra   (r)
;   9  = Caballo negro  (n)
;   10 = Alfil  negro   (b)
;   11 = Reina  negra   (q)
;   12 = Rey    negro   (k)
;
; Distribución del vector (índice 0 = a8, índice 63 = h1):
;   índice = (7 - fila) * 8 + columna
;   donde fila   : 0=fila1 … 7=fila8 (en ajedrez)
;         columna: 0=a … 7=h
;
;   Índices 0–7   → Fila 8 (piezas negras mayores)
;   Índices 8–15  → Fila 7 (peones negros)
;   Índices 16–47 → Filas 6–3 (vacías al inicio)
;   Índices 48–55 → Fila 2 (peones blancos)
;   Índices 56–63 → Fila 1 (piezas blancas mayores)
; =========================================================================== 

INCLUDE Irvine32.inc
 
; ---------------------------------------------------------------------------
; Constantes de piezas
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
NO_COLOR        EQU 2
 
BOARD_SIZE      EQU 64
BOARD_ROWS      EQU 8
BOARD_COLS      EQU 8
 
; ---------------------------------------------------------------------------
; Segmento de datos
; FIX: PUBLIC board debe estar DENTRO del segmento .data, no antes.
; ---------------------------------------------------------------------------
.data
 
PUBLIC board                                ; ← DENTRO de .data
board   BYTE 64 DUP(EMPTY)
 
currentTurn     BYTE COLOR_WHITE
gameStatus      BYTE 0
moveCount       DWORD 0
checkFlag       BYTE 0
whiteKingPos    BYTE 60
blackKingPos    BYTE 4
errOutOfRange   BYTE "Error: indice fuera del tablero (0-63).", 0
 
; ---------------------------------------------------------------------------
; Segmento de código
; FIX: todos los PUBLIC de procedimientos deben estar DENTRO de .code.
; ---------------------------------------------------------------------------
.code
 
PUBLIC Tablero_Inicializar
PUBLIC Tablero_ObtenerPieza
PUBLIC Tablero_EstablecerPieza
PUBLIC Tablero_CoordAIndice
PUBLIC Tablero_IndiceACoord
PUBLIC Tablero_ObtenerColor
PUBLIC Tablero_MoverPieza
PUBLIC Tablero_EstaVacia
PUBLIC Tablero_ObtenerTurno
PUBLIC Tablero_CambiarTurno
PUBLIC Tablero_ObtenerPosRey
PUBLIC Tablero_EstablecerJaque
PUBLIC Tablero_ObtenerJaque
PUBLIC Tablero_EstablecerEstado
PUBLIC Tablero_ObtenerEstado
PUBLIC Tablero_ObtenerContadorMovimientos
PUBLIC Tablero_UCIAIndice
 
; ===========================================================================
; Procedimiento: Tablero_Inicializar
; ===========================================================================
Tablero_Inicializar PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx
    push ecx
    push esi
 
    mov  ecx, BOARD_SIZE
    lea  esi, board
    xor  al, al
ClearLoop:
    mov  [esi], al
    inc  esi
    loop ClearLoop
 
    lea  esi, board
    mov  BYTE PTR [esi+0],  BLACK_ROOK
    mov  BYTE PTR [esi+1],  BLACK_KNIGHT
    mov  BYTE PTR [esi+2],  BLACK_BISHOP
    mov  BYTE PTR [esi+3],  BLACK_QUEEN
    mov  BYTE PTR [esi+4],  BLACK_KING
    mov  BYTE PTR [esi+5],  BLACK_BISHOP
    mov  BYTE PTR [esi+6],  BLACK_KNIGHT
    mov  BYTE PTR [esi+7],  BLACK_ROOK
 
    mov  ecx, 8
    lea  esi, board
    add  esi, 8
    mov  al, BLACK_PAWN
FillBlackPawns:
    mov  [esi], al
    inc  esi
    loop FillBlackPawns
 
    mov  ecx, 8
    lea  esi, board
    add  esi, 48
    mov  al, WHITE_PAWN
FillWhitePawns:
    mov  [esi], al
    inc  esi
    loop FillWhitePawns
 
    lea  esi, board
    mov  BYTE PTR [esi+56], WHITE_ROOK
    mov  BYTE PTR [esi+57], WHITE_KNIGHT
    mov  BYTE PTR [esi+58], WHITE_BISHOP
    mov  BYTE PTR [esi+59], WHITE_QUEEN
    mov  BYTE PTR [esi+60], WHITE_KING
    mov  BYTE PTR [esi+61], WHITE_BISHOP
    mov  BYTE PTR [esi+62], WHITE_KNIGHT
    mov  BYTE PTR [esi+63], WHITE_ROOK
 
    mov  currentTurn,   COLOR_WHITE
    mov  gameStatus,    0
    mov  moveCount,     0
    mov  checkFlag,     0
    mov  whiteKingPos,  60
    mov  blackKingPos,  4
 
    pop  esi
    pop  ecx
    pop  ebx
    pop  eax
    pop  ebp
    ret
Tablero_Inicializar ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerPieza
; Parámetros   : EAX = índice (0–63)
; Retorna      : AL = código de pieza, 0FFh si error
; ===========================================================================
Tablero_ObtenerPieza PROC
    push esi
    push ebx
 
    cmp  eax, BOARD_SIZE
    jae  ObtenerPieza_Error
 
    lea  esi, board
    mov  bl, [esi + eax]
    mov  al, bl
    jmp  ObtenerPieza_Fin
 
ObtenerPieza_Error:
    mov  al, 0FFh
 
ObtenerPieza_Fin:
    pop  ebx
    pop  esi
    ret
Tablero_ObtenerPieza ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_EstablecerPieza
; Parámetros   : EAX = índice (0–63), BL = código de pieza
; Retorna      : CF = 0 si OK, CF = 1 si error
; ===========================================================================
Tablero_EstablecerPieza PROC
    push esi
 
    cmp  eax, BOARD_SIZE
    jae  EstablecerPieza_Error
 
    lea  esi, board
    mov  [esi + eax], bl
    clc
    jmp  EstablecerPieza_Fin
 
EstablecerPieza_Error:
    stc
 
EstablecerPieza_Fin:
    pop  esi
    ret
Tablero_EstablecerPieza ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_CoordAIndice
; Parámetros   : AL = fila (0–7), AH = columna (0–7)
; Retorna      : EAX = índice (0–63), 0FFFFFFFFh si inválido
; ===========================================================================
Tablero_CoordAIndice PROC
    push ebx
    push ecx
 
    movzx ecx, al
    movzx ebx, ah
 
    cmp  ecx, 8
    jae  CoordAIndice_Error
    cmp  ebx, 8
    jae  CoordAIndice_Error
 
    mov  eax, 7
    sub  eax, ecx
    imul eax, 8
    add  eax, ebx
    jmp  CoordAIndice_Fin
 
CoordAIndice_Error:
    mov  eax, 0FFFFFFFFh
 
CoordAIndice_Fin:
    pop  ecx
    pop  ebx
    ret
Tablero_CoordAIndice ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_IndiceACoord
; Parámetros   : EAX = índice (0–63)
; Retorna      : AL = fila (0–7), AH = columna (0–7), 0FFFFh si error
; ===========================================================================
Tablero_IndiceACoord PROC
    push ebx
    push ecx
    push edx
 
    cmp  eax, BOARD_SIZE
    jae  IndiceACoord_Error
 
    mov  ecx, eax
    xor  edx, edx
    mov  eax, ecx
    mov  ebx, 8
    div  ebx
    mov  ecx, 7
    sub  ecx, eax
 
    mov  al, cl
    mov  ah, dl
    jmp  IndiceACoord_Fin
 
IndiceACoord_Error:
    mov  ax, 0FFFFh
 
IndiceACoord_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    ret
Tablero_IndiceACoord ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerColor
; Parámetros   : EAX = índice (0–63)
; Retorna      : AL = 0 (blanca), 1 (negra), 2 (vacía/error)
; ===========================================================================
Tablero_ObtenerColor PROC
    push esi
    push ebx
 
    cmp  eax, BOARD_SIZE
    jae  ObtenerColor_Vacia
 
    lea  esi, board
    movzx ebx, BYTE PTR [esi + eax]
 
    cmp  bl, EMPTY
    je   ObtenerColor_Vacia
 
    cmp  bl, WHITE_KING
    jbe  ObtenerColor_Blanca
 
    mov  al, COLOR_BLACK
    jmp  ObtenerColor_Fin
 
ObtenerColor_Blanca:
    mov  al, COLOR_WHITE
    jmp  ObtenerColor_Fin
 
ObtenerColor_Vacia:
    mov  al, NO_COLOR
 
ObtenerColor_Fin:
    pop  ebx
    pop  esi
    ret
Tablero_ObtenerColor ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_MoverPieza
; Parámetros   : EAX = índice origen, EBX = índice destino
; Retorna      : AL = pieza capturada (0 si ninguna), 0FFh si error
; ===========================================================================
Tablero_MoverPieza PROC
    push esi
    push ecx
    push edx
 
    cmp  eax, BOARD_SIZE
    jae  MoverPieza_Error
    cmp  ebx, BOARD_SIZE
    jae  MoverPieza_Error
 
    lea  esi, board
 
    movzx ecx, BYTE PTR [esi + eax]
    cmp  ecx, EMPTY
    je   MoverPieza_Error
 
    movzx edx, BYTE PTR [esi + ebx]
 
    mov  BYTE PTR [esi + ebx], cl
    mov  BYTE PTR [esi + eax], EMPTY
 
    cmp  cl, WHITE_KING
    jne  VerificarReyNegro
    mov  al, bl
    mov  whiteKingPos, al
    jmp  MoverPieza_Retornar
 
VerificarReyNegro:
    cmp  cl, BLACK_KING
    jne  MoverPieza_Retornar
    mov  al, bl
    mov  blackKingPos, al
 
MoverPieza_Retornar:
    mov  al, dl
    jmp  MoverPieza_Fin
 
MoverPieza_Error:
    mov  al, 0FFh
 
MoverPieza_Fin:
    pop  edx
    pop  ecx
    pop  esi
    ret
Tablero_MoverPieza ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_EstaVacia
; Parámetros   : EAX = índice (0–63)
; Retorna      : ZF = 1 si vacía, ZF = 0 si tiene pieza o error
; ===========================================================================
Tablero_EstaVacia PROC
    push esi
    push ebx
 
    cmp  eax, BOARD_SIZE
    jae  EstaVacia_NoVacia
 
    lea  esi, board
    movzx ebx, BYTE PTR [esi + eax]
    cmp  ebx, EMPTY
    jmp  EstaVacia_Fin
 
EstaVacia_NoVacia:
    or   ebx, 1
    cmp  ebx, 0
 
EstaVacia_Fin:
    pop  ebx
    pop  esi
    ret
Tablero_EstaVacia ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerTurno
; Retorna      : AL = 0 (blancas) o 1 (negras)
; ===========================================================================
Tablero_ObtenerTurno PROC
    mov  al, currentTurn
    ret
Tablero_ObtenerTurno ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_CambiarTurno
; Alterna el turno e incrementa el contador de movimientos.
; ===========================================================================
Tablero_CambiarTurno PROC
    xor  currentTurn, 1
    inc  moveCount
    ret
Tablero_CambiarTurno ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerPosRey
; Parámetros   : AL = 0 (blancas) o 1 (negras)
; Retorna      : AL = índice del rey (0–63)
; ===========================================================================
Tablero_ObtenerPosRey PROC
    cmp  al, COLOR_WHITE
    je   ObtenerPosRey_Blanco
    mov  al, blackKingPos
    ret
ObtenerPosRey_Blanco:
    mov  al, whiteKingPos
    ret
Tablero_ObtenerPosRey ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_EstablecerJaque
; Parámetros   : AL = 0 (sin jaque), 1 (jaque blancas), 2 (jaque negras)
; ===========================================================================
Tablero_EstablecerJaque PROC
    mov  checkFlag, al
    ret
Tablero_EstablecerJaque ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerJaque
; Retorna      : AL = checkFlag
; ===========================================================================
Tablero_ObtenerJaque PROC
    mov  al, checkFlag
    ret
Tablero_ObtenerJaque ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_EstablecerEstado
; Parámetros   : AL = 0..3
; ===========================================================================
Tablero_EstablecerEstado PROC
    mov  gameStatus, al
    ret
Tablero_EstablecerEstado ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerEstado
; Retorna      : AL = gameStatus
; ===========================================================================
Tablero_ObtenerEstado PROC
    mov  al, gameStatus
    ret
Tablero_ObtenerEstado ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerContadorMovimientos
; Retorna      : EAX = moveCount
; ===========================================================================
Tablero_ObtenerContadorMovimientos PROC
    mov  eax, moveCount
    ret
Tablero_ObtenerContadorMovimientos ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_UCIAIndice
; Parámetros   : AL = columna ('a'–'h'), AH = fila ('1'–'8')
; Retorna      : EAX = índice (0–63), 0FFFFFFFFh si inválido
; ===========================================================================
Tablero_UCIAIndice PROC
    push ebx
    push ecx
 
    movzx ebx, al
    sub   ebx, 'a'
 
    movzx ecx, ah
    sub   ecx, '1'
 
    cmp  ebx, 8
    jae  UCIAIndice_Error
    cmp  ecx, 8
    jae  UCIAIndice_Error
 
    mov  eax, 7
    sub  eax, ecx
    imul eax, 8
    add  eax, ebx
    jmp  UCIAIndice_Fin
 
UCIAIndice_Error:
    mov  eax, 0FFFFFFFFh
 
UCIAIndice_Fin:
    pop  ecx
    pop  ebx
    ret
Tablero_UCIAIndice ENDP
 
END