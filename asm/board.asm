 
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
 
; Constantes de color
COLOR_WHITE     EQU 0
COLOR_BLACK     EQU 1
NO_COLOR        EQU 2       ; celda vacía
 
; Límites del tablero
BOARD_SIZE      EQU 64
BOARD_ROWS      EQU 8
BOARD_COLS      EQU 8


; ---------------------------------------------------------------------------
; Segmento de datos
; ---------------------------------------------------------------------------
.data
 
; Vector lineal de 64 bytes que representa el tablero
; Índice 0 = esquina a8 (arriba izquierda desde perspectiva de las negras)
; Índice 63 = esquina h1 (abajo derecha)
board   BYTE 64 DUP(EMPTY)
 
; Turno actual: 0 = blancas, 1 = negras
currentTurn     BYTE COLOR_WHITE
 
; Estado del juego
; 0 = en curso, 1 = jaque mate blancas ganaron, 2 = jaque mate negras ganaron
; 3 = tablas
gameStatus      BYTE 0
 
; Contador de movimientos (para historial y FEN)
moveCount       DWORD 0
 
; Bandera de jaque: 0 = sin jaque, 1 = jaque al rey blanco, 2 = jaque al rey negro
checkFlag       BYTE 0
 
; Posición del rey blanco (índice en el vector)
whiteKingPos    BYTE 60     ; e1 = índice 60
 
; Posición del rey negro (índice en el vector)
blackKingPos    BYTE 4      ; e8 = índice 4
 
; Mensaje de error de índice fuera de rango
errOutOfRange   BYTE "Error: índice fuera del tablero (0-63).", 0
 
; ---------------------------------------------------------------------------
; Segmento de código
; ---------------------------------------------------------------------------
.code
 
; ===========================================================================
; Procedimiento: Tablero_Inicializar
; Descripción  : Inicializa el tablero con la posición estándar de ajedrez.
;                Rellena las 64 celdas con las piezas en su lugar inicial.
; Parámetros   : Ninguno
; Retorna      : Ninguno (modifica el arreglo global 'tablero')
; Registros usados: EAX, EBX, ECX, ESI
; Preserva     : EBP
; ===========================================================================
Tablero_Inicializar PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx
    push ecx
    push esi
 
    ; --- Limpiar todo el tablero (rellenar con EMPTY = 0) ---
    mov  ecx, BOARD_SIZE
    lea  esi, board
    xor  al, al                 ; al = 0 = EMPTY
ClearLoop:
    mov  [esi], al
    inc  esi
    loop ClearLoop
 
    ; --- Fila 8 (índices 0–7): piezas negras mayores ---
    ; Orden: Torre Caballo Alfil Reina Rey Alfil Caballo Torre
    lea  esi, board
    mov  BYTE PTR [esi+0],  BLACK_ROOK      ; a8
    mov  BYTE PTR [esi+1],  BLACK_KNIGHT    ; b8
    mov  BYTE PTR [esi+2],  BLACK_BISHOP    ; c8
    mov  BYTE PTR [esi+3],  BLACK_QUEEN     ; d8
    mov  BYTE PTR [esi+4],  BLACK_KING      ; e8
    mov  BYTE PTR [esi+5],  BLACK_BISHOP    ; f8
    mov  BYTE PTR [esi+6],  BLACK_KNIGHT    ; g8
    mov  BYTE PTR [esi+7],  BLACK_ROOK      ; h8
 
    ; --- Fila 7 (índices 8–15): peones negros ---
    mov  ecx, 8
    lea  esi, board
    add  esi, 8                 ; apuntar a índice 8
    mov  al, BLACK_PAWN
FillBlackPawns:
    mov  [esi], al
    inc  esi
    loop FillBlackPawns
 
    ; --- Filas 6 a 3 (índices 16–47): celdas vacías (ya limpiadas) ---
    ; No se necesita acción adicional
 
    ; --- Fila 2 (índices 48–55): peones blancos ---
    mov  ecx, 8
    lea  esi, board
    add  esi, 48                ; apuntar a índice 48
    mov  al, WHITE_PAWN
FillWhitePawns:
    mov  [esi], al
    inc  esi
    loop FillWhitePawns
 
    ; --- Fila 1 (índices 56–63): piezas blancas mayores ---
    ; Orden: Torre Caballo Alfil Reina Rey Alfil Caballo Torre
    lea  esi, board
    mov  BYTE PTR [esi+56], WHITE_ROOK      ; a1
    mov  BYTE PTR [esi+57], WHITE_KNIGHT    ; b1
    mov  BYTE PTR [esi+58], WHITE_BISHOP    ; c1
    mov  BYTE PTR [esi+59], WHITE_QUEEN     ; d1
    mov  BYTE PTR [esi+60], WHITE_KING      ; e1
    mov  BYTE PTR [esi+61], WHITE_BISHOP    ; f1
    mov  BYTE PTR [esi+62], WHITE_KNIGHT    ; g1
    mov  BYTE PTR [esi+63], WHITE_ROOK      ; h1
 
    ; --- Restablecer estado del juego ---
    mov  currentTurn,   COLOR_WHITE
    mov  gameStatus,    0
    mov  moveCount,     0
    mov  checkFlag,     0
    mov  whiteKingPos,  60      ; e1
    mov  blackKingPos,  4       ; e8
 
    pop  esi
    pop  ecx
    pop  ebx
    pop  eax
    pop  ebp
    ret
Tablero_Inicializar ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerPieza
; Descripción  : Retorna el byte (pieza) en la posición dada del vector.
; Parámetros   : EAX = índice (0–63)
; Retorna      : AL = código de pieza en esa celda
;                Si el índice es inválido, AL = 0FFh (código de error)
; Registros usados: EAX, ESI
; ===========================================================================
Tablero_ObtenerPieza PROC
    push esi
    push ebx
 
    ; Validar rango
    cmp  eax, BOARD_SIZE
    jae  ObtenerPieza_Error     ; si índice >= 64, error
 
    lea  esi, board
    mov  bl, [esi + eax]        ; leer byte en esa posición
    mov  al, bl                 ; retornar en AL
 
    jmp  ObtenerPieza_Fin
 
ObtenerPieza_Error:
    mov  al, 0FFh               ; código de error
 
ObtenerPieza_Fin:
    pop  ebx
    pop  esi
    ret
Tablero_ObtenerPieza ENDP
 
 
 


; ===========================================================================
; Procedimiento: Tablero_EstablecerPieza
; Descripción  : Escribe una pieza en la posición dada del vector.
; Parámetros   : EAX = índice (0–63)
;                BL  = código de pieza a escribir
; Retorna      : CF = 0 si OK, CF = 1 si índice inválido
; Registros usados: EAX, ESI
; ===========================================================================
Tablero_EstablecerPieza PROC
    push esi
 
    ; Validar rango
    cmp  eax, BOARD_SIZE
    jae  EstablecerPieza_Error
 
    lea  esi, board
    mov  [esi + eax], bl        ; escribir pieza
 
    clc                         ; CF = 0: éxito
    jmp  EstablecerPieza_Fin
 
EstablecerPieza_Error:
    stc                         ; CF = 1: error
 
EstablecerPieza_Fin:
    pop  esi
    ret
Tablero_EstablecerPieza ENDP

; ===========================================================================
; Procedimiento: Tablero_CoordAIndice
; Descripción  : Convierte coordenadas (fila, columna) a índice lineal.
;
;   Fórmula: índice = (7 - fila) * 8 + columna
;   donde fila    : 0=fila1 … 7=fila8  (0 es la fila más baja del tablero)
;         columna : 0=a … 7=h
;
; Parámetros   : AL = fila (0–7), AH = columna (0–7)
; Retorna      : EAX = índice (0–63), o EAX = 0FFFFFFFFh si inválido
; Registros usados: EAX, EBX, ECX
; ===========================================================================
Tablero_CoordAIndice PROC
    push ebx
    push ecx
 
    ; Validar fila (AL) y columna (AH)
    movzx ecx, al               ; fila en ECX
    movzx ebx, ah               ; columna en EBX
 
    cmp  ecx, 8
    jae  CoordAIndice_Error
    cmp  ebx, 8
    jae  CoordAIndice_Error
 
    ; índice = (7 - fila) * 8 + columna
    mov  eax, 7
    sub  eax, ecx               ; eax = 7 - fila
    imul eax, 8                 ; eax = (7 - fila) * 8
    add  eax, ebx               ; eax = (7 - fila) * 8 + columna
 
    jmp  CoordAIndice_Fin
 
CoordAIndice_Error:
    mov  eax, 0FFFFFFFFh        ; valor centinela de error
 
CoordAIndice_Fin:
    pop  ecx
    pop  ebx
    ret
Tablero_CoordAIndice ENDP