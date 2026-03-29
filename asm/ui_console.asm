; ===========================================================
;  ui_console.asm  -  arChess 3.0
;  CAMBIO: PUBLIC hintBuf (para engine_connector.asm)
; ===========================================================

INCLUDE Irvine32.inc

COLOR_BLANCO         EQU 0
COLOR_NEGRO          EQU 1
STYLE_LIGHT          EQU 0
STYLE_DARK           EQU 1

; Colores MODO CLASICO
CLR_RESET            EQU 7
CLR_LIGHT_WHITE_SQ   EQU 70h
CLR_LIGHT_BLACK_SQ   EQU 80h
CLR_INFO_LIGHT       EQU 3
CLR_HINT_LIGHT       EQU 2
CLR_CHECK_LIGHT      EQU 4

; Colores MODO OSCURO
CLR_DARK_RESET       EQU 07h
CLR_DARK_BLACK_SQ    EQU 02Fh
CLR_DARK_WHITE_SQ    EQU 0A0h
CLR_DARK_PB_OS       EQU 02Fh
CLR_DARK_PB_CL       EQU 0AFh
CLR_DARK_PN_OS       EQU 02Fh
CLR_DARK_PN_CL       EQU 0A0h
CLR_DARK_INFO        EQU 0Ah
CLR_DARK_HINT        EQU 0Ah
CLR_DARK_CHECK       EQU 0Ch

BOARD_COL            EQU 2
BOARD_ROW            EQU 1
STATUS_COL           EQU 2
STATUS_ROW           EQU 20
HIST_COL             EQU 30
HIST_ROW             EQU 1
CLOCK_COL            EQU 30
CLOCK_ROW            EQU 16
HINT_COL             EQU 30
HINT_ROW             EQU 18
MAX_HIST_VISIBLE     EQU 14

PUBLIC UI_LimpiarPantalla
PUBLIC UI_MostrarTablero
PUBLIC UI_MostrarMenuPrincipal
PUBLIC UI_MostrarTurno
PUBLIC UI_MostrarJaque
PUBLIC UI_MostrarJaqueMate
PUBLIC UI_MostrarTablas
PUBLIC UI_MostrarMovimientoIlegal
PUBLIC UI_MostrarHistorial
PUBLIC UI_MostrarReloj
PUBLIC UI_MostrarPista
PUBLIC UI_MostrarPistasAgotadas
PUBLIC UI_ActualizarReloj

Tablero_ObtenerTurno               PROTO
Tablero_ObtenerContadorMovimientos PROTO
Tablero_ObtenerPieza               PROTO

.DATA

EXTERNDEF currentStyle:BYTE
EXTERNDEF uiMoveHistory:BYTE
EXTERNDEF uiMoveCount:DWORD

piecesLight  BYTE '.','P','T','C','A','Q','R',
                  'p','t','c','a','q','r'
piecesDark   BYTE '.','P','T','C','A','Q','R',
                  'p','t','c','a','q','r'

colLabels        BYTE "  a b c d e f g h",0
rowSep           BYTE "  +-+-+-+-+-+-+-+-+",0
strTurnWhite     BYTE "Turno: BLANCAS  ",0
strTurnBlack     BYTE "Turno: NEGRAS   ",0
strCheckMsg      BYTE "*** JAQUE! ***          ",0
strCheckmateMsg  BYTE "*** JAQUE MATE ***      ",0
strDrawMsg       BYTE "*** TABLAS ***          ",0
strClearStatus   BYTE "                        ",0
strIllegal       BYTE "  [!] Mov ilegal.       ",0
strHintLabel     BYTE "Sugerencia: ",0
strClockLabel    BYTE "Reloj: ",0
strHistLabel     BYTE "--- Historial ---",0
strNoHints       BYTE "  Sin pistas.   ",0

clockSeconds     DWORD 300
clockBuf         BYTE "00:00",0,0

PUBLIC hintBuf
hintBuf          BYTE "----",0

tabFila          DWORD 0
tabCol           DWORD 0
tabConsoleRow    BYTE  0
squareIdx        DWORD 0
paridad          DWORD 0
pieceCode        BYTE  0
turnoLocal       BYTE  0
moveCountLocal   DWORD 0

.CODE

; ===========================================================
;  Helpers de color
; ===========================================================
UI_ClrReset PROC
    mov  eax, CLR_DARK_RESET
    ret
UI_ClrReset ENDP

UI_ClrInfo PROC
    cmp  currentStyle, STYLE_DARK
    jne  ClrInfo_Light
    mov  eax, CLR_DARK_INFO
    ret
ClrInfo_Light:
    mov  eax, CLR_INFO_LIGHT
    ret
UI_ClrInfo ENDP

UI_ClrCheck PROC
    cmp  currentStyle, STYLE_DARK
    jne  ClrCheck_Light
    mov  eax, CLR_DARK_CHECK
    ret
ClrCheck_Light:
    mov  eax, CLR_CHECK_LIGHT
    ret
UI_ClrCheck ENDP

UI_ClrHint PROC
    cmp  currentStyle, STYLE_DARK
    jne  ClrHint_Light
    mov  eax, CLR_DARK_HINT
    ret
ClrHint_Light:
    mov  eax, CLR_HINT_LIGHT
    ret
UI_ClrHint ENDP

UI_ClrCasilla PROC
    cmp  currentStyle, STYLE_DARK
    jne  ClrCas_Light
    cmp  paridad, 0
    jne  ClrCas_DarkOsc
    mov  eax, CLR_DARK_WHITE_SQ
    ret
ClrCas_DarkOsc:
    mov  eax, CLR_DARK_BLACK_SQ
    ret
ClrCas_Light:
    cmp  paridad, 0
    jne  ClrCas_LightOsc
    mov  eax, CLR_LIGHT_WHITE_SQ
    ret
ClrCas_LightOsc:
    mov  eax, CLR_LIGHT_BLACK_SQ
    ret
UI_ClrCasilla ENDP

UI_ClrPiezaBlanca PROC
    cmp  currentStyle, STYLE_DARK
    jne  ClrPB_Normal
    cmp  paridad, 0
    jne  ClrPB_Oscura
    mov  eax, CLR_DARK_PB_CL
    ret
ClrPB_Oscura:
    mov  eax, CLR_DARK_PB_OS
    ret
ClrPB_Normal:
    call UI_ClrCasilla
    ret
UI_ClrPiezaBlanca ENDP

UI_ClrPiezaNegra PROC
    cmp  currentStyle, STYLE_DARK
    jne  ClrPN_Normal
    cmp  paridad, 0
    jne  ClrPN_Oscura
    mov  eax, CLR_DARK_PN_CL
    ret
ClrPN_Oscura:
    mov  eax, CLR_DARK_PN_OS
    ret
ClrPN_Normal:
    call UI_ClrCasilla
    ret
UI_ClrPiezaNegra ENDP

UI_Goto PROC
    call Gotoxy
    ret
UI_Goto ENDP

UI_LimpiarPantalla PROC USES eax
    mov  eax, CLR_RESET
    call SetTextColor
    call Clrscr
    ret
UI_LimpiarPantalla ENDP

UI_MostrarMenuPrincipal PROC USES eax
    mov  eax, CLR_RESET
    call SetTextColor
    call Clrscr
    ret
UI_MostrarMenuPrincipal ENDP

; ===========================================================
;  UI_MostrarHistorial
; ===========================================================
UI_MostrarHistorial PROC USES eax ecx edx esi
    call UI_ClrHint
    mov  dl, HIST_COL
    mov  dh, HIST_ROW
    call UI_Goto
    call SetTextColor
    mov  edx, OFFSET strHistLabel
    call WriteString

    mov  eax, uiMoveCount
    mov  moveCountLocal, eax
    cmp  eax, MAX_HIST_VISIBLE
    jle  Hist_NoScroll
    sub  eax, MAX_HIST_VISIBLE
Hist_NoScroll:
    mov  esi, eax
    mov  ecx, MAX_HIST_VISIBLE
    mov  dh,  HIST_ROW + 1

Hist_Loop:
    mov  dl, HIST_COL
    call UI_Goto
    mov  eax, CLR_RESET
    call SetTextColor
    cmp  esi, moveCountLocal
    jge  Hist_LimpiaLinea

    mov  eax, esi
    shr  eax, 1
    inc  eax
    call WriteDec
    test esi, 1
    jnz  Hist_PuntoDoble
    mov  al, '.'
    call WriteChar
    jmp  Hist_ImpMov
Hist_PuntoDoble:
    mov  al, '.'
    call WriteChar
    mov  al, '.'
    call WriteChar
Hist_ImpMov:
    mov  al, ' '
    call WriteChar
    mov  eax, esi
    imul eax, 5
    lea  edx, uiMoveHistory
    add  edx, eax
    call WriteString
    jmp  Hist_SigLinea

Hist_LimpiaLinea:
    push ecx
    mov  ecx, 12
Hist_Blancos:
    mov  al, ' '
    call WriteChar
    loop Hist_Blancos
    pop  ecx

Hist_SigLinea:
    inc  esi
    inc  dh
    loop Hist_Loop
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarHistorial ENDP

; ===========================================================
;  UI_MostrarTablero
; ===========================================================
UI_MostrarTablero PROC USES eax edx esi

    call UI_ClrInfo
    mov  dl, BOARD_COL
    mov  dh, BOARD_ROW
    call UI_Goto
    call SetTextColor
    mov  edx, OFFSET colLabels
    call WriteString

    mov  tabFila, 8
    mov  tabConsoleRow, BOARD_ROW + 1

Tab_FilaLoop:
    cmp  tabFila, 0
    je   Tab_FinFilas

    mov  dl, BOARD_COL
    mov  dh, tabConsoleRow
    call UI_Goto
    mov  eax, CLR_RESET
    call SetTextColor
    mov  edx, OFFSET rowSep
    call WriteString
    inc  tabConsoleRow

    mov  dl, BOARD_COL
    mov  dh, tabConsoleRow
    call UI_Goto
    call UI_ClrInfo
    call SetTextColor
    mov  eax, tabFila
    add  al, '0'
    call WriteChar
    mov  al, ' '
    call WriteChar

    mov  eax, 8
    sub  eax, tabFila
    imul eax, 8
    mov  squareIdx, eax
    mov  tabCol, 0

Tab_ColLoop:
    cmp  tabCol, 8
    je   Tab_FinCols

    mov  eax, squareIdx
    mov  edx, eax
    shr  edx, 3
    add  edx, tabCol
    and  edx, 1
    mov  paridad, edx

    call UI_ClrCasilla
    call SetTextColor

    mov  eax, squareIdx
    call Tablero_ObtenerPieza
    mov  pieceCode, al

    cmp  pieceCode, 0
    je   Tab_Punto

    cmp  currentStyle, STYLE_DARK
    jne  Tab_Punto

    cmp  pieceCode, 6
    jbe  Tab_EsBlanca
    call UI_ClrPiezaNegra
    jmp  Tab_ColorPiezaSet
Tab_EsBlanca:
    call UI_ClrPiezaBlanca
Tab_ColorPiezaSet:
    call SetTextColor

Tab_Punto:
    cmp  currentStyle, STYLE_DARK
    jne  Tab_UsaLight
    lea  edx, piecesDark
    jmp  Tab_ImpPieza
Tab_UsaLight:
    lea  edx, piecesLight
Tab_ImpPieza:
    movzx eax, pieceCode
    add  edx, eax
    mov  al, BYTE PTR [edx]
    call WriteChar

    call UI_ClrCasilla
    call SetTextColor
    mov  al, ' '
    call WriteChar

    inc  squareIdx
    inc  tabCol
    jmp  Tab_ColLoop

Tab_FinCols:
    mov  eax, CLR_RESET
    call SetTextColor
    mov  al, '|'
    call WriteChar
    inc  tabConsoleRow
    dec  tabFila
    jmp  Tab_FilaLoop

Tab_FinFilas:
    mov  dl, BOARD_COL
    mov  dh, tabConsoleRow
    call UI_Goto
    mov  eax, CLR_RESET
    call SetTextColor
    mov  edx, OFFSET rowSep
    call WriteString

    inc  tabConsoleRow
    mov  dl, BOARD_COL
    mov  dh, tabConsoleRow
    call UI_Goto
    call UI_ClrInfo
    call SetTextColor
    mov  edx, OFFSET colLabels
    call WriteString

    mov  eax, CLR_RESET
    call SetTextColor
    call UI_MostrarHistorial
    ret
UI_MostrarTablero ENDP

UI_MostrarTurno PROC USES eax edx
    mov  dl, STATUS_COL
    mov  dh, STATUS_ROW
    call UI_Goto
    mov  eax, CLR_RESET
    call SetTextColor
    mov  edx, OFFSET strClearStatus
    call WriteString
    mov  dl, STATUS_COL
    mov  dh, STATUS_ROW
    call UI_Goto
    call UI_ClrInfo
    call SetTextColor
    call Tablero_ObtenerTurno
    mov  turnoLocal, al
    cmp  turnoLocal, COLOR_BLANCO
    jne  MosTurno_Negro
    mov  edx, OFFSET strTurnWhite
    jmp  MosTurno_Imp
MosTurno_Negro:
    mov  edx, OFFSET strTurnBlack
MosTurno_Imp:
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarTurno ENDP

UI_MostrarJaque PROC USES eax edx
    mov  dl, STATUS_COL
    mov  dh, STATUS_ROW + 1
    call UI_Goto
    call UI_ClrCheck
    call SetTextColor
    mov  edx, OFFSET strCheckMsg
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarJaque ENDP

UI_MostrarJaqueMate PROC USES eax edx
    mov  dl, STATUS_COL
    mov  dh, STATUS_ROW + 1
    call UI_Goto
    call UI_ClrCheck
    call SetTextColor
    mov  edx, OFFSET strCheckmateMsg
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarJaqueMate ENDP

UI_MostrarTablas PROC USES eax edx
    mov  dl, STATUS_COL
    mov  dh, STATUS_ROW + 1
    call UI_Goto
    call UI_ClrInfo
    call SetTextColor
    mov  edx, OFFSET strDrawMsg
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarTablas ENDP

UI_MostrarMovimientoIlegal PROC USES eax edx
    mov  dl, STATUS_COL
    mov  dh, STATUS_ROW + 1
    call UI_Goto
    call UI_ClrCheck
    call SetTextColor
    mov  edx, OFFSET strIllegal
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarMovimientoIlegal ENDP

UI_MostrarReloj PROC USES eax ebx ecx edx
    mov  dl, CLOCK_COL
    mov  dh, CLOCK_ROW
    call UI_Goto
    call UI_ClrInfo
    call SetTextColor
    mov  edx, OFFSET strClockLabel
    call WriteString
    mov  eax, clockSeconds
    xor  edx, edx
    mov  ebx, 60
    div  ebx
    push edx
    xor  edx, edx
    mov  ecx, 10
    div  ecx
    add  al, '0'
    mov  clockBuf[0], al
    add  dl, '0'
    mov  clockBuf[1], dl
    mov  clockBuf[2], ':'
    pop  eax
    xor  edx, edx
    div  ecx
    add  al, '0'
    mov  clockBuf[3], al
    add  dl, '0'
    mov  clockBuf[4], dl
    mov  clockBuf[5], 0
    mov  edx, OFFSET clockBuf
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarReloj ENDP

UI_ActualizarReloj PROC USES eax
    cmp  clockSeconds, 0
    jne  ActReloj_Dec
    mov  clockSeconds, 300
    jmp  ActReloj_Dibujar
ActReloj_Dec:
    dec  clockSeconds
ActReloj_Dibujar:
    call UI_MostrarReloj
    ret
UI_ActualizarReloj ENDP

UI_MostrarPista PROC USES eax edx
    mov  dl, HINT_COL
    mov  dh, HINT_ROW
    call UI_Goto
    call UI_ClrHint
    call SetTextColor
    mov  edx, OFFSET strHintLabel
    call WriteString
    mov  edx, OFFSET hintBuf
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarPista ENDP

UI_MostrarPistasAgotadas PROC USES eax edx
    mov  dl, HINT_COL
    mov  dh, HINT_ROW
    call UI_Goto
    call UI_ClrCheck
    call SetTextColor
    mov  edx, OFFSET strNoHints
    call WriteString
    mov  eax, CLR_RESET
    call SetTextColor
    ret
UI_MostrarPistasAgotadas ENDP

END