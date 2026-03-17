 
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
 

