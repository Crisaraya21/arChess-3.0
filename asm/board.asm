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


; ===========================================================================
; Procedimiento: Tablero_IndiceACoord
; Descripción  : Convierte un índice lineal a coordenadas (fila, columna).
;
;   fila    = 7 - (índice / 8)
;   columna = índice mod 8
;
; Parámetros   : EAX = índice (0–63)
; Retorna      : AL = fila (0–7), AH = columna (0–7)
;                Si error: AX = 0FFFFh
; Registros usados: EAX, EBX, ECX, EDX
; ===========================================================================
Tablero_IndiceACoord PROC
    push ebx
    push ecx
    push edx
 
    ; Validar rango
    cmp  eax, BOARD_SIZE
    jae  IndiceACoord_Error
 
    mov  ecx, eax               ; guardar índice
    xor  edx, edx
    mov  eax, ecx
    mov  ebx, 8
    div  ebx                    ; EAX = índice / 8 (fila desde arriba)
                                ; EDX = índice mod 8 (columna)
    ; fila desde abajo = 7 - (índice / 8)
    mov  ecx, 7
    sub  ecx, eax               ; ecx = fila (0=fila1, 7=fila8)
 
    mov  al, cl                 ; AL = fila
    mov  ah, dl                 ; AH = columna
 
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
; Descripción  : Retorna el color de la pieza en el índice dado.
; Parámetros   : EAX = índice (0–63)
; Retorna      : AL = 0 (COLOR_WHITE), 1 (COLOR_BLACK), 2 (NO_COLOR/vacía)
; ===========================================================================
Tablero_ObtenerColor PROC
    push esi
    push ebx
 
    ; Validar rango
    cmp  eax, BOARD_SIZE
    jae  ObtenerColor_Vacia
 
    lea  esi, board
    movzx ebx, BYTE PTR [esi + eax]
 
    ; Vacía?
    cmp  bl, EMPTY
    je   ObtenerColor_Vacia
 
    ; Blanca (1–6)?
    cmp  bl, WHITE_KING
    jbe  ObtenerColor_Blanca
 
    ; Negra (7–12)
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
; Descripción  : Mueve una pieza de origen a destino en el vector, capturando
;                la pieza en destino si la hubiera. Actualiza posición de reyes.
;
; Parámetros   : EAX = índice origen (0–63)
;                EBX = índice destino (0–63)
; Retorna      : AL  = pieza capturada (0 si ninguna), 0FFh si error
; Registros usados: EAX, EBX, ECX, ESI
; ===========================================================================
Tablero_MoverPieza PROC
    push esi
    push ecx
    push edx
 
    ; Validar origen y destino
    cmp  eax, BOARD_SIZE
    jae  MoverPieza_Error
    cmp  ebx, BOARD_SIZE
    jae  MoverPieza_Error
 
    lea  esi, board
 
    ; Leer pieza en origen
    movzx ecx, BYTE PTR [esi + eax]    ; ECX = pieza origen
    cmp  ecx, EMPTY
    je   MoverPieza_Error              ; no mover celda vacía
 
    ; Leer pieza capturada en destino (puede ser EMPTY)
    movzx edx, BYTE PTR [esi + ebx]    ; EDX = pieza destino (capturada)
 
    ; Escribir pieza en destino
    mov  BYTE PTR [esi + ebx], cl
 
    ; Dejar origen vacío
    mov  BYTE PTR [esi + eax], EMPTY
 
    ; Actualizar posición de reyes si se movió un rey
    cmp  cl, WHITE_KING
    jne  VerificarReyNegro
    mov  al, bl                        ; whiteKingPos = destino (byte)
    mov  whiteKingPos, al
    jmp  MoverPieza_Retornar
 
VerificarReyNegro:
    cmp  cl, BLACK_KING
    jne  MoverPieza_Retornar
    mov  al, bl
    mov  blackKingPos, al
 
MoverPieza_Retornar:
    mov  al, dl                        ; retornar pieza capturada en AL
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
; Descripción  : Verifica si una celda está vacía.
; Parámetros   : EAX = índice (0–63)
; Retorna      : ZF = 1 si vacía, ZF = 0 si tiene pieza (o error)
; ===========================================================================
Tablero_EstaVacia PROC
    push esi
    push ebx
 
    cmp  eax, BOARD_SIZE
    jae  EstaVacia_NoVacia
 
    lea  esi, board
    movzx ebx, BYTE PTR [esi + eax]
    cmp  ebx, EMPTY                    ; ZF=1 si vacía
    jmp  EstaVacia_Fin
 
EstaVacia_NoVacia:
    or   ebx, 1                        ; ZF = 0
    cmp  ebx, 0
 
EstaVacia_Fin:
    pop  ebx
    pop  esi
    ret
Tablero_EstaVacia ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerTurno
; Descripción  : Retorna el turno actual.
; Parámetros   : Ninguno
; Retorna      : AL = 0 (COLOR_WHITE) o 1 (COLOR_BLACK)
; ===========================================================================
Tablero_ObtenerTurno PROC
    mov  al, currentTurn
    ret
Tablero_ObtenerTurno ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_CambiarTurno
; Descripción  : Alterna el turno entre blancas y negras.
;                Incrementa el contador de movimientos.
; Parámetros   : Ninguno
; Retorna      : Ninguno
; ===========================================================================
Tablero_CambiarTurno PROC
    ; Alternar turno
    xor  currentTurn, 1
    ; Incrementar contador global
    inc  moveCount
    ret
Tablero_CambiarTurno ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerPosRey
; Descripción  : Retorna la posición del rey del color dado.
; Parámetros   : AL = 0 (blancas) o 1 (negras)
; Retorna      : AL = índice del rey en el vector (0–63)
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
; Descripción  : Establece la bandera de jaque.
; Parámetros   : AL = 0 (sin jaque), 1 (jaque blancas), 2 (jaque negras)
; Retorna      : Ninguno
; ===========================================================================
Tablero_EstablecerJaque PROC
    mov  checkFlag, al
    ret
Tablero_EstablecerJaque ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerJaque
; Descripción  : Retorna la bandera de jaque actual.
; Parámetros   : Ninguno
; Retorna      : AL = 0 (sin jaque), 1 (jaque blancas), 2 (jaque negras)
; ===========================================================================
Tablero_ObtenerJaque PROC
    mov  al, checkFlag
    ret
Tablero_ObtenerJaque ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_EstablecerEstado
; Descripción  : Establece el estado del juego.
; Parámetros   : AL = 0 (en curso), 1 (jaque mate blancas), 2 (jaque mate negras), 3 (tablas)
; Retorna      : Ninguno
; ===========================================================================
Tablero_EstablecerEstado PROC
    mov  gameStatus, al
    ret
Tablero_EstablecerEstado ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerEstado
; Descripción  : Retorna el estado actual del juego.
; Parámetros   : Ninguno
; Retorna      : AL = gameStatus
; ===========================================================================
Tablero_ObtenerEstado PROC
    mov  al, gameStatus
    ret
Tablero_ObtenerEstado ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_ObtenerContadorMovimientos
; Descripción  : Retorna el número total de movimientos realizados.
; Parámetros   : Ninguno
; Retorna      : EAX = moveCount
; ===========================================================================
Tablero_ObtenerContadorMovimientos PROC
    mov  eax, moveCount
    ret
Tablero_ObtenerContadorMovimientos ENDP
 
 
; ===========================================================================
; Procedimiento: Tablero_UCIAIndice
; Descripción  : Convierte notación UCI de una casilla (ej. "e2") a índice.
;                'e' = columna 4 (a=0, b=1, ... h=7)
;                '2' = fila 1 (fila 0 en base 0)
; Parámetros   : AL = carácter columna ('a'–'h')
;                AH = carácter fila    ('1'–'8')
; Retorna      : EAX = índice (0–63), o EAX = 0FFFFFFFFh si inválido
; Registros usados: EAX, EBX, ECX
; ===========================================================================
Tablero_UCIAIndice PROC
    push ebx
    push ecx
 
    ; Extraer columna: 'a'=0, 'b'=1, ..., 'h'=7
    movzx ebx, al
    sub   ebx, 'a'              ; ebx = columna (0–7)
 
    ; Extraer fila: '1'=0, '2'=1, ..., '8'=7
    movzx ecx, ah
    sub   ecx, '1'              ; ecx = fila base-0 (0=fila1 ... 7=fila8)
 
    ; Validar rangos
    cmp  ebx, 8
    jae  UCIAIndice_Error
    cmp  ecx, 8
    jae  UCIAIndice_Error
 
    ; índice = (7 - fila) * 8 + columna
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