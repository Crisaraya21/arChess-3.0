; ===========================================================================
; move_validator.asm - Modulo de Validacion de Movimientos (CORREGIDO)
;
; BUGS CORREGIDOS:
;
;   1. Validar_Alfil: La version vieja tenia un desbalance de pila
;      catastrofico (push/pop no coincidian) y nunca recorria
;      correctamente las casillas intermedias. ELIMINADA y reemplazada
;      por un wrapper a Validar_Alfil_Completo.
;
;   2. Validar_Alfil_Completo: REESCRITO COMPLETAMENTE. Los indices
;      origen/destino se perdian tras calcular coordenadas porque los
;      registros se sobreescribian. Ahora se guardan en variables
;      locales de pila (ebp-4, ebp-8) desde el inicio.
;      Se elimino la dependencia de indiceOrigenTemp/indiceDestinoTemp
;      que solo se seteaban desde algunos llamadores.
;
;   3. Validar_Reina: REESCRITO COMPLETAMENTE. La version vieja usaba
;      cdq que sobreescribia EDX (que contenia columna origen),
;      corrompiendo el calculo de |dCol|. Ahora usa variables locales
;      de pila y calcula las diferencias absolutas de forma segura.
;
;   4. Validar_Ataque (peones): La deteccion de ataque diagonal del
;      peon no verificaba wrapping de columna. Un peon en columna 'a'
;      podia "atacar" a la izquierda envolviendo a columna 'h'.
;      Ahora se validan las columnas origen y destino.
;
;   5. Simular_Y_VerificarJaque: Despues de revertir el movimiento,
;      la pieza de destino original se restaura con EstablecerPieza
;      y la pieza movida vuelve con MoverPieza, lo cual actualiza
;      correctamente la posicion del rey si era un rey.
;
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
Tablero_ObtenerPieza PROTO
Tablero_ObtenerColor PROTO
Tablero_EstaVacia PROTO
Tablero_IndiceACoord PROTO
Tablero_MoverPieza PROTO
Tablero_EstablecerPieza PROTO
Tablero_ObtenerPosRey PROTO
Tablero_ObtenerTurno PROTO

; ---------------------------------------------------------------------------
; Declaraciones PUBLIC
; ---------------------------------------------------------------------------
PUBLIC Validar_Movimiento
PUBLIC Verificar_ReyEnJaque
PUBLIC Verificar_JaqueMate
PUBLIC Verificar_Tablas
PUBLIC Validar_Ataque

; ---------------------------------------------------------------------------
; Segmento de datos local
; ---------------------------------------------------------------------------
.data

piezaCapturadaTemp  BYTE 0

; ===========================================================================
.code


; ===========================================================================
; Validar_Movimiento
; EAX = origen (0-63), EBX = destino (0-63)
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Movimiento PROC
    push ebp
    mov  ebp, esp
    sub  esp, 12                ; [ebp-4]=origen, [ebp-8]=destino, [ebp-12]=colorJugador
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  DWORD PTR [ebp-4], eax
    mov  DWORD PTR [ebp-8], ebx

    ; --- Verificar que origen no este vacio ---
    call Tablero_EstaVacia
    je   VM_Ilegal

    ; --- Obtener pieza en origen ---
    mov  eax, [ebp-4]
    call Tablero_ObtenerPieza
    movzx ecx, al               ; ECX = pieza

    ; --- Verificar que la pieza sea del jugador en turno ---
    mov  eax, [ebp-4]
    call Tablero_ObtenerColor
    movzx edx, al               ; EDX = color pieza
    mov  DWORD PTR [ebp-12], edx

    call Tablero_ObtenerTurno
    movzx eax, al
    cmp  eax, edx
    jne  VM_Ilegal

    ; --- Verificar que destino no sea pieza propia ---
    mov  eax, [ebp-8]
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, edx
    je   VM_Ilegal

    ; --- Delegar segun tipo de pieza ---
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]

    cmp  ecx, PEON_BLANCO
    je   VM_PeonBlanco
    cmp  ecx, PEON_NEGRO
    je   VM_PeonNegro
    cmp  ecx, TORRE_BLANCA
    je   VM_Torre
    cmp  ecx, TORRE_NEGRA
    je   VM_Torre
    cmp  ecx, CABALLO_BLANCO
    je   VM_Caballo
    cmp  ecx, CABALLO_NEGRO
    je   VM_Caballo
    cmp  ecx, ALFIL_BLANCO
    je   VM_Alfil
    cmp  ecx, ALFIL_NEGRO
    je   VM_Alfil
    cmp  ecx, REINA_BLANCA
    je   VM_Reina
    cmp  ecx, REINA_NEGRA
    je   VM_Reina
    cmp  ecx, REY_BLANCO
    je   VM_Rey
    cmp  ecx, REY_NEGRO
    je   VM_Rey
    jmp  VM_Ilegal

VM_PeonBlanco:
    call Validar_PeonBlanco
    jmp  VM_PostValidar
VM_PeonNegro:
    call Validar_PeonNegro
    jmp  VM_PostValidar
VM_Torre:
    call Validar_Torre
    jmp  VM_PostValidar
VM_Caballo:
    call Validar_Caballo
    jmp  VM_PostValidar
VM_Alfil:
    call Validar_Alfil_Completo
    jmp  VM_PostValidar
VM_Reina:
    call Validar_Reina
    jmp  VM_PostValidar
VM_Rey:
    call Validar_Rey

VM_PostValidar:
    cmp  al, 0
    je   VM_Ilegal

    ; --- Simular y verificar que no deje al rey en jaque ---
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Simular_Y_VerificarJaque
    cmp  al, 1
    jne  VM_Ilegal

    mov  al, 1
    jmp  VM_Fin

VM_Ilegal:
    mov  al, 0

VM_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    add  esp, 12
    pop  ebp
    ret
Validar_Movimiento ENDP


; ===========================================================================
; Validar_PeonBlanco
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
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
    movzx ecx, al               ; fila origen
    movzx edx, ah               ; columna origen

    ; ---- Avance simple (destino = origen - 8) ----
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
    ; Solo desde fila 2: indices 48-55
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
    ; Obtener columna destino
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx eax, ah               ; EAX = columna destino

    ; Diagonal izquierda (origen - 9): col_dest = col_orig - 1
    mov  ecx, edx
    dec  ecx
    cmp  eax, ecx
    jne  PeonB_CapDer

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

PeonB_CapDer:
    ; Diagonal derecha (origen - 7): col_dest = col_orig + 1
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
; Validar_PeonNegro
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
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

    ; Avance simple (destino = origen + 8)
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
    ; Solo desde fila 7: indices 8-15
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
    movzx eax, ah               ; col destino

    ; Diagonal izquierda (origen + 7): col - 1
    mov  ecx, edx
    dec  ecx
    cmp  eax, ecx
    jne  PeonN_CapDer

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

PeonN_CapDer:
    ; Diagonal derecha (origen + 9): col + 1
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
; Validar_Torre
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Torre PROC
    push ebp
    mov  ebp, esp
    sub  esp, 8                 ; [ebp-4]=origen, [ebp-8]=destino
    push ecx
    push edx
    push esi
    push edi

    mov  DWORD PTR [ebp-4], eax
    mov  DWORD PTR [ebp-8], ebx

    ; Coordenadas origen
    call Tablero_IndiceACoord
    movzx ecx, al               ; fila origen
    movzx edx, ah               ; col origen

    ; Coordenadas destino
    push ecx
    push edx
    mov  eax, [ebp-8]
    call Tablero_IndiceACoord
    movzx esi, al               ; fila destino
    movzx edi, ah               ; col destino
    pop  edx                    ; col origen
    pop  ecx                    ; fila origen

    ; Misma fila?
    cmp  ecx, esi
    je   Torre_MismaFila
    ; Misma columna?
    cmp  edx, edi
    je   Torre_MismaColumna
    jmp  Torre_Ilegal

Torre_MismaFila:
    ; Horizontal: verificar celdas intermedias
    mov  eax, [ebp-4]          ; origen
    mov  ebx, [ebp-8]          ; destino
    cmp  eax, ebx
    jb   Torre_HorizDer
    ; Izquierda: destino < origen
    mov  ecx, ebx               ; cursor = destino
Torre_HorizIzqLoop:
    inc  ecx
    cmp  ecx, eax               ; llegamos a origen?
    jge  Torre_Legal
    push eax
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  eax
    jne  Torre_Ilegal
    jmp  Torre_HorizIzqLoop

Torre_HorizDer:
    ; Derecha: origen < destino
    mov  ecx, eax               ; cursor = origen
Torre_HorizDerLoop:
    inc  ecx
    cmp  ecx, ebx               ; llegamos a destino?
    jge  Torre_Legal
    push ebx
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  ebx
    jne  Torre_Ilegal
    jmp  Torre_HorizDerLoop

Torre_MismaColumna:
    ; Vertical: paso +-8
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    cmp  eax, ebx
    jb   Torre_VertAbajo
    ; Arriba: destino < origen (indice menor = fila visual mas alta)
    mov  ecx, ebx
Torre_VertArribaLoop:
    add  ecx, 8
    cmp  ecx, eax
    jge  Torre_Legal
    push eax
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  eax
    jne  Torre_Ilegal
    jmp  Torre_VertArribaLoop

Torre_VertAbajo:
    ; Abajo: origen < destino
    mov  ecx, eax
Torre_VertAbajoLoop:
    add  ecx, 8
    cmp  ecx, ebx
    jge  Torre_Legal
    push ebx
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  ebx
    jne  Torre_Ilegal
    jmp  Torre_VertAbajoLoop

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
    add  esp, 8
    pop  ebp
    ret
Validar_Torre ENDP


; ===========================================================================
; Validar_Caballo
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Caballo PROC
    push ecx
    push edx
    push esi
    push edi

    mov  esi, eax
    mov  edi, ebx

    ; Coordenadas origen
    mov  eax, esi
    call Tablero_IndiceACoord
    movzx ecx, al               ; fila origen
    movzx edx, ah               ; col origen

    ; Coordenadas destino
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx esi, al               ; fila destino
    movzx edi, ah               ; col destino
    pop  edx                    ; col origen
    pop  ecx                    ; fila origen

    ; |dFila|
    mov  eax, esi
    sub  eax, ecx
    jns  Cab_PosFila
    neg  eax
Cab_PosFila:
    mov  esi, eax               ; ESI = |dFila|

    ; |dCol|
    mov  eax, edi
    sub  eax, edx
    jns  Cab_PosCol
    neg  eax
Cab_PosCol:
    mov  edi, eax               ; EDI = |dCol|

    ; L: (1,2) o (2,1)
    cmp  esi, 1
    jne  Cab_Ver2
    cmp  edi, 2
    je   Cab_Legal
    jmp  Cab_Ilegal
Cab_Ver2:
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
; Validar_Alfil_Completo — REESCRITO COMPLETAMENTE
;
; Usa variables locales de pila para indices, evitando que se pierdan
; cuando Tablero_IndiceACoord sobreescribe registros.
;
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Alfil_Completo PROC
    push ebp
    mov  ebp, esp
    sub  esp, 24                ; variables locales:
                                ; [ebp-4]  = indice origen
                                ; [ebp-8]  = indice destino
                                ; [ebp-12] = fila origen
                                ; [ebp-16] = col origen
                                ; [ebp-20] = fila destino
                                ; [ebp-24] = col destino
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; --- Guardar indices INMEDIATAMENTE ---
    mov  [ebp-4], eax
    mov  [ebp-8], ebx

    ; --- Coordenadas origen ---
    call Tablero_IndiceACoord   ; EAX ya tiene origen
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-12], ecx          ; fila origen
    mov  [ebp-16], edx          ; col origen

    ; --- Coordenadas destino ---
    mov  eax, [ebp-8]
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-20], ecx          ; fila destino
    mov  [ebp-24], edx          ; col destino

    ; --- dFila = fila_dest - fila_orig ---
    mov  eax, [ebp-20]
    sub  eax, [ebp-12]
    mov  esi, eax               ; ESI = dFila (con signo)

    ; --- dCol = col_dest - col_orig ---
    mov  eax, [ebp-24]
    sub  eax, [ebp-16]
    mov  edi, eax               ; EDI = dCol (con signo)

    ; --- |dFila| == |dCol| y != 0 ---
    mov  eax, esi
    jns  A2_AbsFila
    neg  eax
A2_AbsFila:
    mov  ecx, eax               ; ECX = |dFila|

    mov  eax, edi
    jns  A2_AbsCol
    neg  eax
A2_AbsCol:                      ; EAX = |dCol|

    cmp  ecx, eax
    jne  A2_Ilegal
    cmp  ecx, 0
    je   A2_Ilegal

    ; --- Calcular paso diagonal en vector lineal ---
    ; fila visual sube (dFila>0) -> indice BAJA -> paso -8
    ; fila visual baja (dFila<0) -> indice SUBE -> paso +8
    xor  ecx, ecx
    cmp  esi, 0
    jg   A2_FilaArriba
    add  ecx, 8                 ; dFila < 0: indice sube
    jmp  A2_VerCol
A2_FilaArriba:
    sub  ecx, 8                 ; dFila > 0: indice baja

A2_VerCol:
    cmp  edi, 0
    jg   A2_ColDer
    dec  ecx                    ; dCol < 0: indice -1
    jmp  A2_Recorrer
A2_ColDer:
    inc  ecx                    ; dCol > 0: indice +1

A2_Recorrer:
    ; ECX = paso diagonal
    mov  eax, [ebp-4]           ; cursor = indice origen
    mov  ebx, [ebp-8]           ; destino

A2_BucleRecorrido:
    add  eax, ecx               ; avanzar un paso
    cmp  eax, ebx               ; llegamos al destino?
    je   A2_Legal
    cmp  eax, 0
    jl   A2_Ilegal
    cmp  eax, BOARD_SIZE
    jae  A2_Ilegal

    push ecx
    push ebx
    call Tablero_EstaVacia
    pop  ebx
    pop  ecx
    jne  A2_Ilegal              ; casilla intermedia ocupada
    jmp  A2_BucleRecorrido

A2_Legal:
    mov  al, 1
    jmp  A2_Fin

A2_Ilegal:
    mov  al, 0

A2_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    add  esp, 24
    pop  ebp
    ret
Validar_Alfil_Completo ENDP


; ===========================================================================
; Validar_Reina — REESCRITO COMPLETAMENTE
;
; La reina combina torre + alfil.
; Usa variables locales de pila para no perder datos con cdq/div.
;
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Reina PROC
    push ebp
    mov  ebp, esp
    sub  esp, 24                ; [ebp-4]=origen, [ebp-8]=destino
                                ; [ebp-12]=filaOrig, [ebp-16]=colOrig
                                ; [ebp-20]=filaDest, [ebp-24]=colDest
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  [ebp-4], eax
    mov  [ebp-8], ebx

    ; --- Coordenadas origen ---
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-12], ecx
    mov  [ebp-16], edx

    ; --- Coordenadas destino ---
    mov  eax, [ebp-8]
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-20], ecx
    mov  [ebp-24], edx

    ; --- Misma fila o misma columna? -> Torre ---
    mov  eax, [ebp-12]
    cmp  eax, [ebp-20]
    je   Reina_ComoTorre
    mov  eax, [ebp-16]
    cmp  eax, [ebp-24]
    je   Reina_ComoTorre

    ; --- Diagonal? |dFila| == |dCol| ---
    mov  eax, [ebp-20]
    sub  eax, [ebp-12]         ; dFila
    jns  Reina_AbsFila
    neg  eax
Reina_AbsFila:
    mov  esi, eax               ; ESI = |dFila|

    mov  eax, [ebp-24]
    sub  eax, [ebp-16]         ; dCol
    jns  Reina_AbsCol
    neg  eax
Reina_AbsCol:                  ; EAX = |dCol|

    cmp  esi, eax
    jne  Reina_Ilegal

    ; Es diagonal -> Alfil
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Alfil_Completo
    jmp  Reina_Fin

Reina_ComoTorre:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Torre
    jmp  Reina_Fin

Reina_Ilegal:
    mov  al, 0

Reina_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    add  esp, 24
    pop  ebp
    ret
Validar_Reina ENDP


; ===========================================================================
; Validar_Rey
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Rey PROC
    push ecx
    push edx
    push esi
    push edi

    mov  esi, eax
    mov  edi, ebx

    ; Coordenadas origen
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah

    ; Coordenadas destino
    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx esi, al               ; fila destino
    movzx edi, ah               ; col destino
    pop  edx                    ; col origen
    pop  ecx                    ; fila origen

    ; |dFila|
    mov  eax, esi
    sub  eax, ecx
    jns  Rey_PosFila
    neg  eax
Rey_PosFila:
    mov  esi, eax               ; ESI = |dFila|

    ; |dCol|
    mov  eax, edi
    sub  eax, edx
    jns  Rey_PosCol
    neg  eax
Rey_PosCol:
    mov  edi, eax               ; EDI = |dCol|

    cmp  esi, 1
    ja   Rey_Ilegal
    cmp  edi, 1
    ja   Rey_Ilegal

    ; No movimiento nulo
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
; Simular_Y_VerificarJaque
; Simula movimiento, verifica jaque propio, revierte.
;
; EAX = origen, EBX = destino
; Retorna: AL = 1 si rey NO queda en jaque (seguro)
;          AL = 0 si rey SI queda en jaque (inseguro)
; ===========================================================================
Simular_Y_VerificarJaque PROC
    push ebp
    mov  ebp, esp
    sub  esp, 12                ; [ebp-4]=origen, [ebp-8]=destino, [ebp-12]=color
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  DWORD PTR [ebp-4], eax
    mov  DWORD PTR [ebp-8], ebx

    ; Guardar pieza en destino
    mov  eax, [ebp-8]
    call Tablero_ObtenerPieza
    mov  piezaCapturadaTemp, al

    ; Color del jugador que mueve
    mov  eax, [ebp-4]
    call Tablero_ObtenerColor
    movzx edx, al
    mov  DWORD PTR [ebp-12], edx

    ; Realizar movimiento simulado
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Tablero_MoverPieza

    ; Obtener posicion del rey del jugador que movio
    mov  eax, [ebp-12]
    call Tablero_ObtenerPosRey
    movzx eax, al

    ; Verificar jaque
    mov  ebx, [ebp-12]
    call Verificar_ReyEnJaque
    mov  cl, al                 ; CL = 1 si en jaque

    ; --- REVERTIR: mover pieza de vuelta ---
    mov  eax, [ebp-8]           ; destino -> origen
    mov  ebx, [ebp-4]
    call Tablero_MoverPieza     ; esto actualiza posicion del rey si es rey

    ; Restaurar pieza capturada en destino
    mov  eax, [ebp-8]
    mov  bl, piezaCapturadaTemp
    call Tablero_EstablecerPieza

    ; Retornar
    cmp  cl, 1
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
    pop  ebx
    add  esp, 12
    pop  ebp
    ret
Simular_Y_VerificarJaque ENDP


; ===========================================================================
; Verificar_ReyEnJaque
; EAX = indice del rey, EBX = color del rey
; Retorna: AL = 1 si en jaque, 0 si no
; ===========================================================================
Verificar_ReyEnJaque PROC
    push ecx
    push edx
    push esi
    push edi

    mov  esi, eax               ; ESI = posicion del rey
    mov  edi, ebx               ; EDI = color del rey

    ; Color enemigo
    mov  ecx, edi
    xor  ecx, 1

    xor  edx, edx               ; EDX = indice casilla (0-63)

Jaque_Bucle:
    cmp  edx, BOARD_SIZE
    jae  Jaque_No

    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, ecx               ; pieza enemiga?
    jne  Jaque_Sig

    ; Pieza enemiga en EDX: puede atacar al rey en ESI?
    push ecx
    push edx
    mov  eax, edx               ; origen = pieza enemiga
    mov  ebx, esi               ; destino = rey
    call Validar_Ataque
    pop  edx
    pop  ecx

    cmp  al, 1
    je   Jaque_Si

Jaque_Sig:
    inc  edx
    jmp  Jaque_Bucle

Jaque_Si:
    mov  al, 1
    jmp  Jaque_Fin

Jaque_No:
    mov  al, 0

Jaque_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    ret
Verificar_ReyEnJaque ENDP


; ===========================================================================
; Validar_Ataque — CORREGIDO
; Verifica si la pieza en origen puede atacar destino.
; Para peones, ahora verifica columnas para evitar wrapping.
;
; EAX = origen (atacante), EBX = destino (rey)
; Retorna: AL = 1 si puede atacar, 0 si no
; ===========================================================================
Validar_Ataque PROC
    push ebp
    mov  ebp, esp
    sub  esp, 8                 ; [ebp-4]=origen, [ebp-8]=destino
    push ecx
    push edx
    push esi
    push edi

    mov  [ebp-4], eax
    mov  [ebp-8], ebx

    ; Obtener pieza atacante
    call Tablero_ObtenerPieza
    movzx ecx, al

    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]

    cmp  ecx, PEON_BLANCO
    je   Atq_PeonB
    cmp  ecx, PEON_NEGRO
    je   Atq_PeonN
    cmp  ecx, TORRE_BLANCA
    je   Atq_Torre
    cmp  ecx, TORRE_NEGRA
    je   Atq_Torre
    cmp  ecx, CABALLO_BLANCO
    je   Atq_Caballo
    cmp  ecx, CABALLO_NEGRO
    je   Atq_Caballo
    cmp  ecx, ALFIL_BLANCO
    je   Atq_Alfil
    cmp  ecx, ALFIL_NEGRO
    je   Atq_Alfil
    cmp  ecx, REINA_BLANCA
    je   Atq_Reina
    cmp  ecx, REINA_NEGRA
    je   Atq_Reina
    cmp  ecx, REY_BLANCO
    je   Atq_Rey
    cmp  ecx, REY_NEGRO
    je   Atq_Rey
    jmp  Atq_No

Atq_PeonB:
    ; Peon blanco ataca diagonal: origen-7 (col+1) y origen-9 (col-1)
    ; FIX: verificar columnas para evitar wrapping
    mov  eax, [ebp-4]
    call Tablero_IndiceACoord
    movzx edx, ah               ; EDX = col origen del peon

    ; Ataque diagonal derecha (origen-7): col_orig < 7
    cmp  edx, 7
    jge  Atq_PeonB_Izq
    mov  eax, [ebp-4]
    sub  eax, 7
    cmp  eax, [ebp-8]
    je   Atq_Si

Atq_PeonB_Izq:
    ; Ataque diagonal izquierda (origen-9): col_orig > 0
    cmp  edx, 0
    jle  Atq_No
    mov  eax, [ebp-4]
    sub  eax, 9
    cmp  eax, [ebp-8]
    je   Atq_Si
    jmp  Atq_No

Atq_PeonN:
    ; Peon negro ataca diagonal: origen+7 (col-1) y origen+9 (col+1)
    mov  eax, [ebp-4]
    call Tablero_IndiceACoord
    movzx edx, ah               ; EDX = col origen del peon

    ; Ataque diagonal izquierda (origen+7): col_orig > 0
    cmp  edx, 0
    jle  Atq_PeonN_Der
    mov  eax, [ebp-4]
    add  eax, 7
    cmp  eax, [ebp-8]
    je   Atq_Si

Atq_PeonN_Der:
    ; Ataque diagonal derecha (origen+9): col_orig < 7
    cmp  edx, 7
    jge  Atq_No
    mov  eax, [ebp-4]
    add  eax, 9
    cmp  eax, [ebp-8]
    je   Atq_Si
    jmp  Atq_No

Atq_Torre:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Torre
    jmp  Atq_Fin

Atq_Caballo:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Caballo
    jmp  Atq_Fin

Atq_Alfil:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Alfil_Completo
    jmp  Atq_Fin

Atq_Reina:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Reina
    jmp  Atq_Fin

Atq_Rey:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Validar_Rey
    jmp  Atq_Fin

Atq_Si:
    mov  al, 1
    jmp  Atq_Fin

Atq_No:
    mov  al, 0

Atq_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    add  esp, 8
    pop  ebp
    ret
Validar_Ataque ENDP


; ===========================================================================
; Verificar_JaqueMate
; AL = color a verificar
; Retorna: AL = 1 si hay jaque mate, 0 si no
; ===========================================================================
Verificar_JaqueMate PROC
    push ebp
    mov  ebp, esp
    sub  esp, 4                 ; [ebp-4] = color
    push ecx
    push edx
    push esi
    push edi

    movzx eax, al
    mov  [ebp-4], eax           ; guardar color

    ; Primero: esta en jaque?
    mov  eax, [ebp-4]
    call Tablero_ObtenerPosRey
    movzx eax, al
    mov  ebx, [ebp-4]
    call Verificar_ReyEnJaque
    cmp  al, 0
    je   JM_No                  ; no hay jaque -> no puede ser jaque mate

    ; Segundo: tiene algun movimiento legal?
    xor  edx, edx               ; EDX = origen

JM_BucleOrigen:
    cmp  edx, BOARD_SIZE
    jae  JM_Si                  ; ningun movimiento -> jaque mate

    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, [ebp-4]
    jne  JM_SigOrigen

    xor  ecx, ecx               ; ECX = destino

JM_BucleDestino:
    cmp  ecx, BOARD_SIZE
    jae  JM_SigOrigen

    push ecx
    push edx
    mov  eax, edx
    mov  ebx, ecx
    call Validar_Movimiento
    pop  edx
    pop  ecx

    cmp  al, 1
    je   JM_No                  ; hay movimiento legal

    inc  ecx
    jmp  JM_BucleDestino

JM_SigOrigen:
    inc  edx
    jmp  JM_BucleOrigen

JM_Si:
    mov  al, 1
    jmp  JM_Fin

JM_No:
    mov  al, 0

JM_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    add  esp, 4
    pop  ebp
    ret
Verificar_JaqueMate ENDP


; ===========================================================================
; Verificar_Tablas
; AL = color a verificar
; Retorna: AL = 1 si tablas (ahogado), 0 si no
; ===========================================================================
Verificar_Tablas PROC
    push ebp
    mov  ebp, esp
    sub  esp, 4                 ; [ebp-4] = color
    push ecx
    push edx
    push esi
    push edi

    movzx eax, al
    mov  [ebp-4], eax

    ; Si esta en jaque, no son tablas
    mov  eax, [ebp-4]
    call Tablero_ObtenerPosRey
    movzx eax, al
    mov  ebx, [ebp-4]
    call Verificar_ReyEnJaque
    cmp  al, 1
    je   Tab_No

    ; Tiene algun movimiento legal?
    xor  edx, edx

Tab_BucleOrigen:
    cmp  edx, BOARD_SIZE
    jae  Tab_Si

    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, [ebp-4]
    jne  Tab_SigOrigen

    xor  ecx, ecx

Tab_BucleDestino:
    cmp  ecx, BOARD_SIZE
    jae  Tab_SigOrigen

    push ecx
    push edx
    mov  eax, edx
    mov  ebx, ecx
    call Validar_Movimiento
    pop  edx
    pop  ecx

    cmp  al, 1
    je   Tab_No

    inc  ecx
    jmp  Tab_BucleDestino

Tab_SigOrigen:
    inc  edx
    jmp  Tab_BucleOrigen

Tab_Si:
    mov  al, 1
    jmp  Tab_Fin

Tab_No:
    mov  al, 0

Tab_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    add  esp, 4
    pop  ebp
    ret
Verificar_Tablas ENDP

END