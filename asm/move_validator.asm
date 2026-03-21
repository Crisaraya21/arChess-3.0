; ===========================================================================
; move_validator.asm — Módulo de Validación de Movimientos
;   - Validar si un movimiento (origen → destino) es legal para cada pieza
;   - Verificar que el movimiento no deje al rey propio en jaque
;   - Detectar jaque: ¿está el rey de cierto color bajo ataque?
;   - Detectar jaque mate: no hay movimientos legales y hay jaque
;   - Detectar tablas: no hay movimientos legales pero no hay jaque
;
; Dependencias:
;   - board.asm  (variables: board, y procedimientos Tablero_*)
;
; Convención de parámetros:
;   Los procedimientos reciben índices del vector (0–63).
;   EAX = índice origen, EBX = índice destino (salvo indicación contraria).
;
; Retorno estándar de validación:
;   AL = 1 → movimiento legal
;   AL = 0 → movimiento ilegal
; ===========================================================================

INCLUDE Irvine32.inc
 
; ---------------------------------------------------------------------------
; Constantes (deben coincidir con board.asm)
; ---------------------------------------------------------------------------
EMPTY           EQU 0
PEON_BLANCO     EQU 1
TORRE_BLANCA    EQU 2
CABALLO_BLANCO  EQU 3
ALFIL_BLANCO    EQU 4
REINA_BLANCA    EQU 5
REY_BLANCO      EQU 6
PEON_NEGRO      EQU 7
TORRE_NEGRA     EQU 8
CABALLO_NEGRO   EQU 9
ALFIL_NEGRO     EQU 10
REINA_NEGRA     EQU 11
REY_NEGRO       EQU 12
 
COLOR_BLANCO    EQU 0
COLOR_NEGRO     EQU 1
SIN_COLOR       EQU 2
 
BOARD_SIZE      EQU 64
BOARD_COLS      EQU 8
 
; ---------------------------------------------------------------------------
; Referencias externas (definidas en board.asm)
; ---------------------------------------------------------------------------
EXTERN board                    : BYTE
EXTERN Tablero_ObtenerPieza     : PROC
EXTERN Tablero_ObtenerColor     : PROC
EXTERN Tablero_EstaVacia        : PROC
EXTERN Tablero_IndiceACoord     : PROC
EXTERN Tablero_MoverPieza       : PROC
EXTERN Tablero_EstablecerPieza  : PROC
EXTERN Tablero_ObtenerPosRey    : PROC
EXTERN Tablero_ObtenerTurno     : PROC
 
; ---------------------------------------------------------------------------
; Segmento de datos local
; ---------------------------------------------------------------------------
.data
 
piezaCapturadaTemp  BYTE 0
indiceOrigenTemp    BYTE 0
indiceDestinoTemp   BYTE 0
 
; ---------------------------------------------------------------------------
; Segmento de código
; FIX: PUBLIC declarations INSIDE .code — this is what the linker needs.
; ---------------------------------------------------------------------------
.code
 
PUBLIC Validar_Movimiento
PUBLIC Verificar_ReyEnJaque
PUBLIC Verificar_JaqueMate
PUBLIC Verificar_Tablas
PUBLIC Validar_Ataque           ; FIX: was missing, needed by Verificar_ReyEnJaque
 
; ===========================================================================
; Validar_Movimiento
; EAX = origen, EBX = destino → AL = 1 legal / 0 ilegal
; ===========================================================================
Validar_Movimiento PROC
    push ebp
    mov  ebp, esp
    push ebx
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    ; Origen no vacío
    call Tablero_EstaVacia
    je   Validar_Ilegal
 
    ; Obtener pieza
    mov  eax, esi
    call Tablero_ObtenerPieza
    movzx ecx, al
 
    ; Color de la pieza = turno actual
    mov  eax, esi
    call Tablero_ObtenerColor
    movzx edx, al
 
    call Tablero_ObtenerTurno
    movzx eax, al
    cmp  eax, edx
    jne  Validar_Ilegal
 
    ; Destino no ocupado por pieza propia
    mov  eax, edi
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, edx
    je   Validar_Ilegal
 
    mov  eax, esi
    mov  ebx, edi
 
    cmp  ecx, PEON_BLANCO
    je   Caso_PeonBlanco
    cmp  ecx, PEON_NEGRO
    je   Caso_PeonNegro
    cmp  ecx, TORRE_BLANCA
    je   Caso_Torre
    cmp  ecx, TORRE_NEGRA
    je   Caso_Torre
    cmp  ecx, CABALLO_BLANCO
    je   Caso_Caballo
    cmp  ecx, CABALLO_NEGRO
    je   Caso_Caballo
    cmp  ecx, ALFIL_BLANCO
    je   Caso_Alfil
    cmp  ecx, ALFIL_NEGRO
    je   Caso_Alfil
    cmp  ecx, REINA_BLANCA
    je   Caso_Reina
    cmp  ecx, REINA_NEGRA
    je   Caso_Reina
    cmp  ecx, REY_BLANCO
    je   Caso_Rey
    cmp  ecx, REY_NEGRO
    je   Caso_Rey
    jmp  Validar_Ilegal
 
Caso_PeonBlanco:
    call Validar_PeonBlanco
    jmp  Verificar_JaquePropio
Caso_PeonNegro:
    call Validar_PeonNegro
    jmp  Verificar_JaquePropio
Caso_Torre:
    call Validar_Torre
    jmp  Verificar_JaquePropio
Caso_Caballo:
    call Validar_Caballo
    jmp  Verificar_JaquePropio
Caso_Alfil:
    ; Guardar índices para Alfil_Completo
    ; EAX = ESI (origen) and EBX = EDI (destino) were set above at lines 123-124
    mov  byte ptr indiceOrigenTemp,  al    ; AL = low byte of EAX (loaded from ESI) = origen
    mov  byte ptr indiceDestinoTemp, bl    ; BL = low byte of EBX (loaded from EDI) = destino
    call Validar_Alfil_Completo
    jmp  Verificar_JaquePropio
Caso_Reina:
    ; EAX = ESI (origen) and EBX = EDI (destino) were set above at lines 123-124
    mov  byte ptr indiceOrigenTemp,  al    ; AL = low byte of EAX (loaded from ESI) = origen
    mov  byte ptr indiceDestinoTemp, bl    ; BL = low byte of EBX (loaded from EDI) = destino
    call Validar_Reina
    jmp  Verificar_JaquePropio
Caso_Rey:
    call Validar_Rey
 
Verificar_JaquePropio:
    cmp  al, 0
    je   Validar_Ilegal
 
    push eax
    mov  eax, esi
    mov  ebx, edi
    call Simular_Y_VerificarJaque
    mov  ecx, eax
    pop  eax
    cmp  ecx, 1
    jne  Validar_Ilegal
 
    mov  al, 1
    jmp  Validar_Fin
 
Validar_Ilegal:
    mov  al, 0
 
Validar_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  ebp
    ret
Validar_Movimiento ENDP
 
 
; ===========================================================================
; Validar_PeonBlanco — EAX=origen, EBX=destino → AL=1/0
; ===========================================================================
Validar_PeonBlanco PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
 
    ; Avance simple
    mov  eax, esi
    sub  eax, 8
    cmp  eax, edi
    jne  PeonB_AvanceDoble
    mov  eax, edi
    call Tablero_EstaVacia
    jne  PeonB_Ilegal
    mov  al, 1
    jmp  PeonB_Fin
 
PeonB_AvanceDoble:
    cmp  esi, 48
    jb   PeonB_Captura
    cmp  esi, 55
    ja   PeonB_Captura
    mov  eax, esi
    sub  eax, 16
    cmp  eax, edi
    jne  PeonB_Captura
    mov  eax, esi
    sub  eax, 8
    call Tablero_EstaVacia
    jne  PeonB_Ilegal
    mov  eax, edi
    call Tablero_EstaVacia
    jne  PeonB_Ilegal
    mov  al, 1
    jmp  PeonB_Fin
 
PeonB_Captura:
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx eax, ah
 
    mov  ecx, edx
    dec  ecx
    cmp  eax, ecx
    jne  PeonB_CapturaDerecha
    mov  eax, esi
    sub  eax, 9
    cmp  eax, edi
    jne  PeonB_Ilegal
    mov  eax, edi
    call Tablero_ObtenerColor
    cmp  al, COLOR_NEGRO
    jne  PeonB_Ilegal
    mov  al, 1
    jmp  PeonB_Fin
 
PeonB_CapturaDerecha:
    mov  ecx, edx
    inc  ecx
    cmp  eax, ecx
    jne  PeonB_Ilegal
    mov  eax, esi
    sub  eax, 7
    cmp  eax, edi
    jne  PeonB_Ilegal
    mov  eax, edi
    call Tablero_ObtenerColor
    cmp  al, COLOR_NEGRO
    jne  PeonB_Ilegal
    mov  al, 1
    jmp  PeonB_Fin
 
PeonB_Ilegal:
    mov  al, 0
PeonB_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_PeonBlanco ENDP
 
 
; ===========================================================================
; Validar_PeonNegro — EAX=origen, EBX=destino → AL=1/0
; ===========================================================================
Validar_PeonNegro PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
 
    ; Avance simple
    mov  eax, esi
    add  eax, 8
    cmp  eax, edi
    jne  PeonN_AvanceDoble
    mov  eax, edi
    call Tablero_EstaVacia
    jne  PeonN_Ilegal
    mov  al, 1
    jmp  PeonN_Fin
 
PeonN_AvanceDoble:
    cmp  esi, 8
    jb   PeonN_Captura
    cmp  esi, 15
    ja   PeonN_Captura
    mov  eax, esi
    add  eax, 16
    cmp  eax, edi
    jne  PeonN_Captura
    mov  eax, esi
    add  eax, 8
    call Tablero_EstaVacia
    jne  PeonN_Ilegal
    mov  eax, edi
    call Tablero_EstaVacia
    jne  PeonN_Ilegal
    mov  al, 1
    jmp  PeonN_Fin
 
PeonN_Captura:
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx eax, ah
 
    mov  ecx, edx
    dec  ecx
    cmp  eax, ecx
    jne  PeonN_CapturaDerecha
    mov  eax, esi
    add  eax, 7
    cmp  eax, edi
    jne  PeonN_Ilegal
    mov  eax, edi
    call Tablero_ObtenerColor
    cmp  al, COLOR_BLANCO
    jne  PeonN_Ilegal
    mov  al, 1
    jmp  PeonN_Fin
 
PeonN_CapturaDerecha:
    mov  ecx, edx
    inc  ecx
    cmp  eax, ecx
    jne  PeonN_Ilegal
    mov  eax, esi
    add  eax, 9
    cmp  eax, edi
    jne  PeonN_Ilegal
    mov  eax, edi
    call Tablero_ObtenerColor
    cmp  al, COLOR_BLANCO
    jne  PeonN_Ilegal
    mov  al, 1
    jmp  PeonN_Fin
 
PeonN_Ilegal:
    mov  al, 0
PeonN_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_PeonNegro ENDP
 
 
; ===========================================================================
; Validar_Torre — EAX=origen, EBX=destino → AL=1/0
; ===========================================================================
Validar_Torre PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
 
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  eax, ecx
    mov  ebx, edx
    pop  edx
    pop  ecx
 
    cmp  ecx, eax
    je   Torre_MismaFila
    cmp  edx, ebx
    je   Torre_MismaColumna
    jmp  Torre_Ilegal
 
Torre_MismaFila:
    cmp  edx, ebx
    jb   Torre_DerechaLoop
    mov  ecx, edi
    mov  edx, esi
Torre_IzquierdaLoop:
    add  ecx, 1
    cmp  ecx, edx
    jge  Torre_Legal
    mov  eax, ecx
    call Tablero_EstaVacia
    jne  Torre_Ilegal
    jmp  Torre_IzquierdaLoop
 
Torre_DerechaLoop:
    mov  ecx, esi
    mov  edx, edi
Torre_DerechaIter:
    add  ecx, 1
    cmp  ecx, edx
    jge  Torre_Legal
    mov  eax, ecx
    call Tablero_EstaVacia
    jne  Torre_Ilegal
    jmp  Torre_DerechaIter
 
Torre_MismaColumna:
    cmp  esi, edi
    jb   Torre_AbajoLoop
    mov  ecx, edi
Torre_ArribaLoop:
    add  ecx, 8
    cmp  ecx, esi
    jge  Torre_Legal
    mov  eax, ecx
    call Tablero_EstaVacia
    jne  Torre_Ilegal
    jmp  Torre_ArribaLoop
 
Torre_AbajoLoop:
    mov  ecx, esi
Torre_AbajoIter:
    add  ecx, 8
    cmp  ecx, edi
    jge  Torre_Legal
    mov  eax, ecx
    call Tablero_EstaVacia
    jne  Torre_Ilegal
    jmp  Torre_AbajoIter
 
Torre_Legal:
    mov  al, 1
    jmp  Torre_Fin
Torre_Ilegal:
    mov  al, 0
Torre_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_Torre ENDP
 
 
; ===========================================================================
; Validar_Caballo — EAX=origen, EBX=destino → AL=1/0
; ===========================================================================
Validar_Caballo PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
 
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  eax, ecx
    mov  ebx, edx
    pop  edx
    pop  ecx
 
    mov  esi, eax
    sub  esi, ecx
    js   Cab_NegFila
    jmp  Cab_PosFila
Cab_NegFila:
    neg  esi
Cab_PosFila:
 
    mov  edi, ebx
    sub  edi, edx
    js   Cab_NegCol
    jmp  Cab_PosCol
Cab_NegCol:
    neg  edi
Cab_PosCol:
 
    cmp  esi, 1
    jne  Cab_Verificar2
    cmp  edi, 2
    je   Cab_Legal
    jmp  Cab_Ilegal
 
Cab_Verificar2:
    cmp  esi, 2
    jne  Cab_Ilegal
    cmp  edi, 1
    jne  Cab_Ilegal
 
Cab_Legal:
    mov  al, 1
    jmp  Cab_Fin
Cab_Ilegal:
    mov  al, 0
Cab_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_Caballo ENDP
 
 
; ===========================================================================
; Validar_Alfil_Completo — EAX=origen, EBX=destino → AL=1/0
; Versión robusta: guarda índice origen desde el inicio.
; ===========================================================================
Validar_Alfil_Completo PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax               ; ESI = índice origen
    mov  edi, ebx               ; EDI = índice destino
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al               ; ECX = fila origen
    movzx edx, ah               ; EDX = columna origen
 
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx ecx, al               ; fila destino
    movzx edx, ah               ; columna destino
 
    pop  eax                    ; EAX = columna origen
    pop  ebx                    ; EBX = fila origen
 
    mov  edi, ecx
    sub  edi, ebx               ; EDI = dFila
    mov  esi, edx
    sub  esi, eax               ; ESI = dCol
 
    ; |dFila|
    mov  ecx, edi
    js   Alfil2_AbsFila
    jmp  Alfil2_PosFila
Alfil2_AbsFila:
    neg  ecx
Alfil2_PosFila:
 
    ; |dCol|
    mov  edx, esi
    js   Alfil2_AbsCol
    jmp  Alfil2_PosCol
Alfil2_AbsCol:
    neg  edx
Alfil2_PosCol:
 
    cmp  ecx, edx
    jne  Alfil2_Ilegal
    cmp  ecx, 0
    je   Alfil2_Ilegal
 
    ; Paso en el vector lineal
    xor  eax, eax
    cmp  edi, 0
    jg   Alfil2_FilaArriba
    add  eax, 8
    jmp  Alfil2_VerCol
Alfil2_FilaArriba:
    sub  eax, 8
 
Alfil2_VerCol:
    cmp  esi, 0
    jg   Alfil2_ColDerecha
    dec  eax
    jmp  Alfil2_Recorrer
Alfil2_ColDerecha:
    inc  eax
 
Alfil2_Recorrer:
    mov  ecx, eax               ; ECX = paso
 
    ; Recuperar índices: indiceOrigenTemp / indiceDestinoTemp
    ; (fueron puestos por el llamador antes de llamar a este proc)
    movzx eax, indiceOrigenTemp
    movzx ebx, indiceDestinoTemp
 
Alfil2_BucleRecorrido:
    add  eax, ecx
    cmp  eax, ebx
    je   Alfil2_Legal
    cmp  eax, BOARD_SIZE
    jae  Alfil2_Ilegal
    push ecx
    push ebx
    call Tablero_EstaVacia
    pop  ebx
    pop  ecx
    jne  Alfil2_Ilegal
    jmp  Alfil2_BucleRecorrido
 
Alfil2_Legal:
    mov  al, 1
    jmp  Alfil2_Fin
Alfil2_Ilegal:
    mov  al, 0
Alfil2_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_Alfil_Completo ENDP
 
 
; ===========================================================================
; Validar_Reina — EAX=origen, EBX=destino → AL=1/0
; ===========================================================================
Validar_Reina PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    ; Guardar para Alfil_Completo
    mov  indiceOrigenTemp,  al
    mov  indiceDestinoTemp, bl
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
 
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    pop  eax
    pop  ebx
 
    cmp  ebx, ecx
    je   Reina_ComoTorre
    cmp  eax, edx
    je   Reina_ComoTorre
 
    mov  esi, ecx
    sub  esi, ebx
    js   Reina_AbsFila
    jmp  Reina_PosFila
Reina_AbsFila:
    neg  esi
Reina_PosFila:
 
    mov  edi, edx
    sub  edi, eax
    js   Reina_AbsCol
    jmp  Reina_PosCol
Reina_AbsCol:
    neg  edi
Reina_PosCol:
 
    cmp  esi, edi
    je   Reina_ComoAlfil
    jmp  Reina_Ilegal
 
Reina_ComoTorre:
    movzx eax, indiceOrigenTemp
    movzx ebx, indiceDestinoTemp
    call Validar_Torre
    jmp  Reina_Fin
 
Reina_ComoAlfil:
    movzx eax, indiceOrigenTemp
    movzx ebx, indiceDestinoTemp
    call Validar_Alfil_Completo
    jmp  Reina_Fin
 
Reina_Ilegal:
    mov  al, 0
Reina_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_Reina ENDP
 
 
; ===========================================================================
; Validar_Rey — EAX=origen, EBX=destino → AL=1/0
; ===========================================================================
Validar_Rey PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
 
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    pop  eax
    pop  ebx
 
    mov  esi, ecx
    sub  esi, ebx
    js   Rey_AbsFila
    jmp  Rey_PosFila
Rey_AbsFila:
    neg  esi
Rey_PosFila:
 
    mov  edi, edx
    sub  edi, eax
    js   Rey_AbsCol
    jmp  Rey_PosCol
Rey_AbsCol:
    neg  edi
Rey_PosCol:
 
    cmp  esi, 1
    ja   Rey_Ilegal
    cmp  edi, 1
    ja   Rey_Ilegal
 
    mov  eax, esi
    add  eax, edi
    cmp  eax, 0
    je   Rey_Ilegal
 
    mov  al, 1
    jmp  Rey_Fin
 
Rey_Ilegal:
    mov  al, 0
Rey_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_Rey ENDP
 
 
; ===========================================================================
; Simular_Y_VerificarJaque — EAX=origen, EBX=destino
; Retorna: AL=1 rey seguro, AL=0 rey en jaque
; ===========================================================================
Simular_Y_VerificarJaque PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    ; Guardar pieza en destino
    mov  eax, edi
    call Tablero_ObtenerPieza
    mov  piezaCapturadaTemp, al
 
    ; Obtener color del jugador que mueve
    mov  eax, esi
    call Tablero_ObtenerColor
    mov  dl, al                 ; DL = color jugador
 
    ; Mover
    mov  eax, esi
    mov  ebx, edi
    call Tablero_MoverPieza
 
    ; Posición del rey tras el movimiento
    mov  al, dl
    call Tablero_ObtenerPosRey
    movzx eax, al
 
    ; ¿Rey en jaque?
    movzx ebx, dl
    call Verificar_ReyEnJaque
    mov  ch, al
 
    ; Revertir
    mov  eax, edi
    mov  ebx, esi
    call Tablero_MoverPieza
 
    mov  eax, edi
    mov  bl, piezaCapturadaTemp
    call Tablero_EstablecerPieza
 
    cmp  ch, 1
    je   SimJaque_Inseguro
    mov  al, 1
    jmp  SimJaque_Fin
 
SimJaque_Inseguro:
    mov  al, 0
SimJaque_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Simular_Y_VerificarJaque ENDP
 
 
; ===========================================================================
; Verificar_ReyEnJaque — EAX=posición rey, EBX=color rey
; Retorna: AL=1 en jaque, AL=0 no
; ===========================================================================
Verificar_ReyEnJaque PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  ecx, edi
    xor  ecx, 1                 ; color enemigo
 
    xor  edx, edx
 
Jaque_BucleTablero:
    cmp  edx, BOARD_SIZE
    jae  Jaque_NoHayJaque
 
    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, ecx
    jne  Jaque_SiguienteCasilla
 
    push ecx
    push edx
    mov  eax, edx
    mov  ebx, esi
    call Validar_Ataque
    pop  edx
    pop  ecx
 
    cmp  al, 1
    je   Jaque_HayJaque
 
Jaque_SiguienteCasilla:
    inc  edx
    jmp  Jaque_BucleTablero
 
Jaque_HayJaque:
    mov  al, 1
    jmp  Jaque_Fin
Jaque_NoHayJaque:
    mov  al, 0
Jaque_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Verificar_ReyEnJaque ENDP
 
 
; ===========================================================================
; Validar_Ataque — EAX=origen atacante, EBX=destino (rey)
; Retorna: AL=1 puede atacar, AL=0 no
; ===========================================================================
Validar_Ataque PROC
    push ecx
    push edx
    push esi
    push edi
 
    mov  esi, eax
    mov  edi, ebx
 
    mov  indiceOrigenTemp,  al
    mov  indiceDestinoTemp, bl
 
    mov  eax, esi
    call Tablero_ObtenerPieza
    movzx ecx, al
 
    mov  eax, esi
    mov  ebx, edi
 
    cmp  ecx, PEON_BLANCO
    je   Ataque_PeonBlanco
    cmp  ecx, PEON_NEGRO
    je   Ataque_PeonNegro
    cmp  ecx, TORRE_BLANCA
    je   Ataque_Torre
    cmp  ecx, TORRE_NEGRA
    je   Ataque_Torre
    cmp  ecx, CABALLO_BLANCO
    je   Ataque_Caballo
    cmp  ecx, CABALLO_NEGRO
    je   Ataque_Caballo
    cmp  ecx, ALFIL_BLANCO
    je   Ataque_Alfil
    cmp  ecx, ALFIL_NEGRO
    je   Ataque_Alfil
    cmp  ecx, REINA_BLANCA
    je   Ataque_Reina
    cmp  ecx, REINA_NEGRA
    je   Ataque_Reina
    cmp  ecx, REY_BLANCO
    je   Ataque_Rey
    cmp  ecx, REY_NEGRO
    je   Ataque_Rey
    jmp  Ataque_No
 
Ataque_PeonBlanco:
    mov  eax, esi
    sub  eax, 7
    cmp  eax, edi
    je   Ataque_Si
    mov  eax, esi
    sub  eax, 9
    cmp  eax, edi
    je   Ataque_Si
    jmp  Ataque_No
 
Ataque_PeonNegro:
    mov  eax, esi
    add  eax, 7
    cmp  eax, edi
    je   Ataque_Si
    mov  eax, esi
    add  eax, 9
    cmp  eax, edi
    je   Ataque_Si
    jmp  Ataque_No
 
Ataque_Torre:
    mov  eax, esi
    mov  ebx, edi
    call Validar_Torre
    jmp  Ataque_Fin
 
Ataque_Caballo:
    mov  eax, esi
    mov  ebx, edi
    call Validar_Caballo
    jmp  Ataque_Fin
 
Ataque_Alfil:
    mov  eax, esi
    mov  ebx, edi
    call Validar_Alfil_Completo
    jmp  Ataque_Fin
 
Ataque_Reina:
    mov  eax, esi
    mov  ebx, edi
    call Validar_Reina
    jmp  Ataque_Fin
 
Ataque_Rey:
    mov  eax, esi
    mov  ebx, edi
    call Validar_Rey
    jmp  Ataque_Fin
 
Ataque_Si:
    mov  al, 1
    jmp  Ataque_Fin
Ataque_No:
    mov  al, 0
Ataque_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Validar_Ataque ENDP
 
 
; ===========================================================================
; Verificar_JaqueMate — AL=color → AL=1 si jaque mate, AL=0 si no
; FIX: Tablero_ObtenerPosRey recibe AL (byte), no EAX.
; ===========================================================================
Verificar_JaqueMate PROC
    push ecx
    push edx
    push esi
    push edi
 
    movzx edi, al
 
    ; ¿Está en jaque?
    mov  eax, edi               ; EAX = color
    call Tablero_ObtenerPosRey
    movzx eax, al
    mov  ebx, edi               ; EBX = color
    call Verificar_ReyEnJaque
    cmp  al, 0
    je   JaqueMate_No
 
    xor  edx, edx
 
JM_BucleOrigen:
    cmp  edx, BOARD_SIZE
    jae  JaqueMate_Si
 
    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, edi
    jne  JM_SiguienteOrigen
 
    xor  ecx, ecx
 
JM_BucleDestino:
    cmp  ecx, BOARD_SIZE
    jae  JM_SiguienteOrigen
 
    push ecx
    push edx
    mov  eax, edx
    mov  ebx, ecx
    call Validar_Movimiento
    pop  edx
    pop  ecx
 
    cmp  al, 1
    je   JaqueMate_No
 
    inc  ecx
    jmp  JM_BucleDestino
 
JM_SiguienteOrigen:
    inc  edx
    jmp  JM_BucleOrigen
 
JaqueMate_Si:
    mov  al, 1
    jmp  JM_Fin
JaqueMate_No:
    mov  al, 0
JM_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Verificar_JaqueMate ENDP
 
 
; ===========================================================================
; Verificar_Tablas — AL=color → AL=1 si tablas, AL=0 si no
; FIX: mismo fix que JaqueMate para Tablero_ObtenerPosRey.
; ===========================================================================
Verificar_Tablas PROC
    push ecx
    push edx
    push esi
    push edi
 
    movzx edi, al
 
    ; Si está en jaque → no son tablas
    mov  eax, edi               ; EAX = color
    call Tablero_ObtenerPosRey
    movzx eax, al
    mov  ebx, edi               ; EBX = color
    call Verificar_ReyEnJaque
    cmp  al, 1
    je   Tablas_No
 
    xor  edx, edx
 
Tablas_BucleOrigen:
    cmp  edx, BOARD_SIZE
    jae  Tablas_Si
 
    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, edi
    jne  Tablas_SiguienteOrigen
 
    xor  ecx, ecx
 
Tablas_BucleDestino:
    cmp  ecx, BOARD_SIZE
    jae  Tablas_SiguienteOrigen
 
    push ecx
    push edx
    mov  eax, edx
    mov  ebx, ecx
    call Validar_Movimiento
    pop  edx
    pop  ecx
 
    cmp  al, 1
    je   Tablas_No
 
    inc  ecx
    jmp  Tablas_BucleDestino
 
Tablas_SiguienteOrigen:
    inc  edx
    jmp  Tablas_BucleOrigen
 
Tablas_Si:
    mov  al, 1
    jmp  Tablas_Fin
Tablas_No:
    mov  al, 0
Tablas_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Verificar_Tablas ENDP
 
END