; ===========================================================
;  input_handler.asm  -  arChess 3.0
; ===========================================================

INCLUDE Irvine32.inc

STYLE_LIGHT EQU 0
STYLE_DARK  EQU 1

PROMPT_ROW  EQU 23
PROMPT_COL  EQU 0

CLOCK_COL_IH    EQU 30
CLOCK_ROW_IH    EQU 16

UI_MostrarReloj PROTO
Sleep PROTO, dwMilliseconds:DWORD

.DATA

PUBLIC currentStyle
currentStyle     BYTE STYLE_LIGHT

PUBLIC necesitaRedibujo
necesitaRedibujo BYTE 0

PUBLIC uiMoveHistory
PUBLIC uiMoveCount
uiMoveHistory    BYTE 512 DUP(0)
uiMoveCount      DWORD 0

cursorCol        BYTE 40

promptMov    BYTE "> Mov (e2e4) s=estilo i=pista: ",0
strLightMsg  BYTE "[CLASICO]",0
strDarkMsg   BYTE "[OSCURO] ",0
msgInvalido  BYTE "  Entrada invalida, intente de nuevo.   ",0
msgClearLine BYTE "                                                  ",0

.CODE
UI_MostrarReloj PROTO

PUBLIC Entrada_LeerMovimientoUCI
PUBLIC Entrada_LeerOpcionMenu
PUBLIC Entrada_SolicitoPista

Inp_LimpiarPrompt PROC USES eax edx
    mov  dl, PROMPT_COL
    mov  dh, PROMPT_ROW
    call Gotoxy
    mov  eax, 7
    call SetTextColor
    mov  edx, OFFSET msgClearLine
    call WriteString
    mov  dl, PROMPT_COL
    mov  dh, PROMPT_ROW + 1
    call Gotoxy
    mov  edx, OFFSET msgClearLine
    call WriteString
    ret
Inp_LimpiarPrompt ENDP

Inp_MostrarPrompt PROC USES eax edx
    call UI_MostrarReloj 
    call Inp_LimpiarPrompt
    mov  dl, PROMPT_COL
    mov  dh, PROMPT_ROW
    call Gotoxy
    mov  eax, 3
    call SetTextColor
    mov  edx, OFFSET promptMov
    call WriteString
    mov  eax, 2
    call SetTextColor
    cmp  currentStyle, STYLE_DARK
    jne  MosPrompt_Light
    mov  edx, OFFSET strDarkMsg
    jmp  MosPrompt_Imp
MosPrompt_Light:
    mov  edx, OFFSET strLightMsg
MosPrompt_Imp:
    call WriteString
    mov  eax, 7
    call SetTextColor
    ret
Inp_MostrarPrompt ENDP

Inp_RegistrarMov PROC USES eax ebx esi edx
    mov  eax, uiMoveCount
    imul eax, 5
    lea  ebx, uiMoveHistory
    add  ebx, eax
    mov  al, BYTE PTR [esi+0]
    mov  BYTE PTR [ebx+0], al
    mov  al, BYTE PTR [esi+1]
    mov  BYTE PTR [ebx+1], al
    mov  al, BYTE PTR [esi+2]
    mov  BYTE PTR [ebx+2], al
    mov  al, BYTE PTR [esi+3]
    mov  BYTE PTR [ebx+3], al
    mov  BYTE PTR [ebx+4], 0
    inc  uiMoveCount
    ret
Inp_RegistrarMov ENDP

Entrada_LeerOpcionMenu PROC USES edx
Menu_Loop:
    call ReadChar
    call WriteChar
    push eax
    mov  al, 0Dh
    call WriteChar
    mov  al, 0Ah
    call WriteChar
    pop  eax
    cmp  al, '0'
    jb   Menu_Invalido
    cmp  al, '3'
    ja   Menu_Invalido
    sub  al, '0'
    ret
Menu_Invalido:
    mov  edx, OFFSET msgInvalido
    call WriteString
    jmp  Menu_Loop
Entrada_LeerOpcionMenu ENDP

; ===========================================================
;  Entrada_LeerMovimientoUCI
;  EDX = puntero al buffer 5 bytes (bufferMovUCI en main)
; ===========================================================
Entrada_LeerMovimientoUCI PROC USES ebx ecx esi edx
    mov  esi, edx
    mov  necesitaRedibujo, 0

UCI_Inicio:
    call Inp_MostrarPrompt
    mov  cursorCol, 40

UCI_PollLoop:
    call ReadKey
    jnz  UCI_GotKey

    push edx
    push eax
    mov  dl, CLOCK_COL_IH
    mov  dh, CLOCK_ROW_IH
    call Gotoxy
    call UI_MostrarReloj
    mov  eax, 7
    call SetTextColor
    mov  dl, cursorCol
    mov  dh, PROMPT_ROW
    call Gotoxy
    pop  eax
    pop  edx
    INVOKE Sleep, 200
    jmp  UCI_PollLoop

UCI_GotKey:
    cmp  al, 's'
    jne  UCI_NoToggle
    cmp  currentStyle, STYLE_LIGHT
    jne  UCI_PonerLight
    mov  currentStyle, STYLE_DARK
    jmp  UCI_ToggleDone
UCI_PonerLight:
    mov  currentStyle, STYLE_LIGHT
UCI_ToggleDone:
    mov  necesitaRedibujo, 1
    mov  al, 0
    ret

UCI_NoToggle:
    cmp  al, 'i'
    jne  UCI_LeerResto
    call WriteChar
    mov  BYTE PTR [esi], 'i'
    mov  BYTE PTR [esi+1], 0
    mov  al, 0
    ret

UCI_LeerResto:
    call WriteChar
    mov  BYTE PTR [esi], al
    inc  cursorCol
    mov  ebx, 1

UCI_Loop:
    cmp  ebx, 4
    je   UCI_Validar
    call ReadChar

    cmp  al, 08h
    jne  UCI_NoBackspace
    cmp  ebx, 0
    je   UCI_Loop
    dec  ebx
    dec  cursorCol
    mov  al, 08h
    call WriteChar
    mov  al, ' '
    call WriteChar
    mov  al, 08h
    call WriteChar
    jmp  UCI_Loop

UCI_NoBackspace:
    call WriteChar
    mov  BYTE PTR [esi + ebx], al
    inc  ebx
    inc  cursorCol
    jmp  UCI_Loop

UCI_Validar:
    mov  BYTE PTR [esi + 4], 0
    call ReadChar

    mov  al, BYTE PTR [esi+0]
    cmp  al, 'a'
    jb   UCI_Invalido
    cmp  al, 'h'
    ja   UCI_Invalido
    mov  al, BYTE PTR [esi+1]
    cmp  al, '1'
    jb   UCI_Invalido
    cmp  al, '8'
    ja   UCI_Invalido
    mov  al, BYTE PTR [esi+2]
    cmp  al, 'a'
    jb   UCI_Invalido
    cmp  al, 'h'
    ja   UCI_Invalido
    mov  al, BYTE PTR [esi+3]
    cmp  al, '1'
    jb   UCI_Invalido
    cmp  al, '8'
    ja   UCI_Invalido

    ; movimiento valido: registrar en historial
    call Inp_RegistrarMov

    mov  al, 1
    ret

UCI_Invalido:
    mov  dl, PROMPT_COL
    mov  dh, PROMPT_ROW + 1
    call Gotoxy
    mov  eax, 4
    call SetTextColor
    mov  edx, OFFSET msgInvalido
    call WriteString
    mov  eax, 7
    call SetTextColor
    jmp  UCI_Inicio
Entrada_LeerMovimientoUCI ENDP

Entrada_SolicitoPista PROC
    mov  al, 0
    ret
Entrada_SolicitoPista ENDP

END