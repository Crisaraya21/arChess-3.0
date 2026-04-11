; ===========================================================================
; move_validator.asm - Modulo de Validacion de Movimientos (CORREGIDO v2)
;
; BUG CRITICO CORREGIDO EN ESTA VERSION:
;
;   Tablero_EstaVacia DESTRUYE EAX (lo usa como input y lo sobreescribe).
;   En los bucles de recorrido del alfil y la torre, EAX se usaba como
;   cursor (posicion actual en la diagonal/linea). Despues de llamar a
;   Tablero_EstaVacia, EAX quedaba con basura y el bucle se perdia.
;
;   FIX: Se agrega push eax / pop eax alrededor de CADA llamada a
;   Tablero_EstaVacia en los bucles de recorrido.
;
;   Tambien se corrigio Simular_Y_VerificarJaque para guardar el
;   resultado de jaque en una variable de pila en vez de CL, que
;   podia ser destruido por las llamadas posteriores.
;
; ===========================================================================

INCLUDE Irvine32.inc

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

EXTERN board                    : BYTE
Tablero_ObtenerPieza PROTO
Tablero_ObtenerColor PROTO
Tablero_EstaVacia PROTO
Tablero_IndiceACoord PROTO
Tablero_MoverPieza PROTO
Tablero_EstablecerPieza PROTO
Tablero_ObtenerPosRey PROTO
Tablero_ObtenerTurno PROTO

PUBLIC Validar_Movimiento
PUBLIC Verificar_ReyEnJaque
PUBLIC Verificar_JaqueMate
PUBLIC Verificar_Tablas
PUBLIC Validar_Ataque

.data

piezaCapturadaTemp  BYTE 0

.code


; ===========================================================================
; Validar_Movimiento
; EAX = origen (0-63), EBX = destino (0-63)
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Movimiento PROC
    push ebp
    mov  ebp, esp
    sub  esp, 12
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  DWORD PTR [ebp-4], eax
    mov  DWORD PTR [ebp-8], ebx

    call Tablero_EstaVacia
    je   VM_Ilegal

    mov  eax, [ebp-4]
    call Tablero_ObtenerPieza
    movzx ecx, al

    mov  eax, [ebp-4]
    call Tablero_ObtenerColor
    movzx edx, al
    mov  DWORD PTR [ebp-12], edx

    call Tablero_ObtenerTurno
    movzx eax, al
    cmp  eax, edx
    jne  VM_Ilegal

    mov  eax, [ebp-8]
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, edx
    je   VM_Ilegal

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
;
; FIX: Cada llamada a Tablero_EstaVacia preserva cursor y limites.
; ===========================================================================
Validar_Torre PROC
    push ebp
    mov  ebp, esp
    sub  esp, 8
    push ecx
    push edx
    push esi
    push edi

    mov  DWORD PTR [ebp-4], eax
    mov  DWORD PTR [ebp-8], ebx

    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah

    push ecx
    push edx
    mov  eax, [ebp-8]
    call Tablero_IndiceACoord
    movzx esi, al
    movzx edi, ah
    pop  edx
    pop  ecx

    cmp  ecx, esi
    je   Torre_MismaFila
    cmp  edx, edi
    je   Torre_MismaColumna
    jmp  Torre_Ilegal

Torre_MismaFila:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    cmp  eax, ebx
    jb   Torre_HorizDer

    mov  ecx, ebx
Torre_HorizIzqLoop:
    inc  ecx
    cmp  ecx, eax
    jge  Torre_Legal
    push eax
    push ecx
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  ecx
    pop  eax
    jne  Torre_Ilegal
    jmp  Torre_HorizIzqLoop

Torre_HorizDer:
    mov  ecx, eax
Torre_HorizDerLoop:
    inc  ecx
    cmp  ecx, ebx
    jge  Torre_Legal
    push ebx
    push ecx
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  ecx
    pop  ebx
    jne  Torre_Ilegal
    jmp  Torre_HorizDerLoop

Torre_MismaColumna:
    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    cmp  eax, ebx
    jb   Torre_VertAbajo

    mov  ecx, ebx
Torre_VertArribaLoop:
    add  ecx, 8
    cmp  ecx, eax
    jge  Torre_Legal
    push eax
    push ecx
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  ecx
    pop  eax
    jne  Torre_Ilegal
    jmp  Torre_VertArribaLoop

Torre_VertAbajo:
    mov  ecx, eax
Torre_VertAbajoLoop:
    add  ecx, 8
    cmp  ecx, ebx
    jge  Torre_Legal
    push ebx
    push ecx
    mov  eax, ecx
    call Tablero_EstaVacia
    pop  ecx
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
    movzx esi, al
    movzx edi, ah
    pop  edx
    pop  ecx

    mov  eax, esi
    sub  eax, ecx
    jns  Cab_PosFila
    neg  eax
Cab_PosFila:
    mov  esi, eax

    mov  eax, edi
    sub  eax, edx
    jns  Cab_PosCol
    neg  eax
Cab_PosCol:
    mov  edi, eax

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
; Validar_Alfil_Completo
;
; FIX CRITICO: push eax / pop eax alrededor de Tablero_EstaVacia
;   para preservar el cursor del recorrido diagonal.
;
; EAX = origen, EBX = destino
; Retorna: AL = 1 legal, 0 ilegal
; ===========================================================================
Validar_Alfil_Completo PROC
    push ebp
    mov  ebp, esp
    sub  esp, 24
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  [ebp-4], eax
    mov  [ebp-8], ebx

    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-12], ecx
    mov  [ebp-16], edx

    mov  eax, [ebp-8]
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-20], ecx
    mov  [ebp-24], edx

    ; dFila = fila_dest - fila_orig
    mov  eax, [ebp-20]
    sub  eax, [ebp-12]
    mov  esi, eax

    ; dCol = col_dest - col_orig
    mov  eax, [ebp-24]
    sub  eax, [ebp-16]
    mov  edi, eax

    ; |dFila| == |dCol| y != 0
    mov  eax, esi
    cmp  eax, 0
    jns  A2_AbsFila
    neg  eax
A2_AbsFila:
    mov  ecx, eax

    mov  eax, edi
    cmp  eax, 0
    jns  A2_AbsCol
    neg  eax
A2_AbsCol:

    cmp  ecx, eax
    jne  A2_Ilegal
    cmp  ecx, 0
    je   A2_Ilegal

    ; --- Calcular paso diagonal usando INDICES directamente ---
    xor  ecx, ecx
    mov  eax, [ebp-8]
    cmp  eax, [ebp-4]
    jl   A2_FilaArriba
    add  ecx, 8
    jmp  A2_VerCol
A2_FilaArriba:
    sub  ecx, 8

A2_VerCol:
    cmp  edi, 0
    jg   A2_ColDer
    dec  ecx
    jmp  A2_Recorrer
A2_ColDer:
    inc  ecx

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

    ; FIX CRITICO: preservar EAX (cursor), ECX (paso), EBX (destino)
    push eax
    push ecx
    push ebx
    call Tablero_EstaVacia
    pop  ebx
    pop  ecx
    pop  eax                    ; EAX restaurado = cursor intacto
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
; Validar_Reina
; ===========================================================================
Validar_Reina PROC
    push ebp
    mov  ebp, esp
    sub  esp, 24
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  [ebp-4], eax
    mov  [ebp-8], ebx

    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-12], ecx
    mov  [ebp-16], edx

    mov  eax, [ebp-8]
    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah
    mov  [ebp-20], ecx
    mov  [ebp-24], edx

    mov  eax, [ebp-12]
    cmp  eax, [ebp-20]
    je   Reina_ComoTorre
    mov  eax, [ebp-16]
    cmp  eax, [ebp-24]
    je   Reina_ComoTorre

    mov  eax, [ebp-20]
    sub  eax, [ebp-12]
    jns  Reina_AbsFila
    neg  eax
Reina_AbsFila:
    mov  esi, eax

    mov  eax, [ebp-24]
    sub  eax, [ebp-16]
    jns  Reina_AbsCol
    neg  eax
Reina_AbsCol:

    cmp  esi, eax
    jne  Reina_Ilegal

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
; ===========================================================================
Validar_Rey PROC
    push ecx
    push edx
    push esi
    push edi

    mov  esi, eax
    mov  edi, ebx

    call Tablero_IndiceACoord
    movzx ecx, al
    movzx edx, ah

    push ecx
    push edx
    mov  eax, edi
    call Tablero_IndiceACoord
    movzx esi, al
    movzx edi, ah
    pop  edx
    pop  ecx

    mov  eax, esi
    sub  eax, ecx
    jns  Rey_PosFila
    neg  eax
Rey_PosFila:
    mov  esi, eax

    mov  eax, edi
    sub  eax, edx
    jns  Rey_PosCol
    neg  eax
Rey_PosCol:
    mov  edi, eax

    cmp  esi, 1
    ja   Rey_Ilegal

    cmp  edi, 1
    jbe  Rey_Normal

    cmp  edi, 2
    jne  Rey_Ilegal
    cmp  esi, 0
    jne  Rey_Ilegal

    mov  al, 1
    jmp  Rey_Fin

Rey_Normal:
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
; EAX = origen, EBX = destino
; Retorna: AL = 1 si rey NO queda en jaque, 0 si SI
;
; FIX: resultado de jaque se guarda en [ebp-16] (variable de pila)
;      en vez de CL, que podia ser destruido por llamadas posteriores.
; ===========================================================================
Simular_Y_VerificarJaque PROC
    push ebp
    mov  ebp, esp
    sub  esp, 16
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  DWORD PTR [ebp-4], eax
    mov  DWORD PTR [ebp-8], ebx

    mov  eax, [ebp-8]
    call Tablero_ObtenerPieza
    mov  piezaCapturadaTemp, al

    mov  eax, [ebp-4]
    call Tablero_ObtenerColor
    movzx edx, al
    mov  DWORD PTR [ebp-12], edx

    mov  eax, [ebp-4]
    mov  ebx, [ebp-8]
    call Tablero_MoverPieza

    mov  eax, [ebp-12]
    call Tablero_ObtenerPosRey
    movzx eax, al

    mov  ebx, [ebp-12]
    call Verificar_ReyEnJaque
    movzx eax, al
    mov  DWORD PTR [ebp-16], eax  ; guardar resultado en pila

    mov  eax, [ebp-8]
    mov  ebx, [ebp-4]
    call Tablero_MoverPieza

    mov  eax, [ebp-8]
    mov  bl, piezaCapturadaTemp
    call Tablero_EstablecerPieza

    cmp  DWORD PTR [ebp-16], 1
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
    add  esp, 16
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

    mov  esi, eax
    mov  edi, ebx

    mov  ecx, edi
    xor  ecx, 1

    xor  edx, edx

Jaque_Bucle:
    cmp  edx, BOARD_SIZE
    jae  Jaque_No

    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, ecx
    jne  Jaque_Sig

    push ecx
    push edx
    mov  eax, edx
    mov  ebx, esi
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
; Validar_Ataque
; EAX = origen (atacante), EBX = destino (rey)
; Retorna: AL = 1 si puede atacar, 0 si no
; ===========================================================================
Validar_Ataque PROC
    push ebp
    mov  ebp, esp
    sub  esp, 8
    push ecx
    push edx
    push esi
    push edi

    mov  [ebp-4], eax
    mov  [ebp-8], ebx

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
    mov  eax, [ebp-4]
    call Tablero_IndiceACoord
    movzx edx, ah

    cmp  edx, 7
    jge  Atq_PeonB_Izq
    mov  eax, [ebp-4]
    sub  eax, 7
    cmp  eax, [ebp-8]
    je   Atq_Si

Atq_PeonB_Izq:
    cmp  edx, 0
    jle  Atq_No
    mov  eax, [ebp-4]
    sub  eax, 9
    cmp  eax, [ebp-8]
    je   Atq_Si
    jmp  Atq_No

Atq_PeonN:
    mov  eax, [ebp-4]
    call Tablero_IndiceACoord
    movzx edx, ah

    cmp  edx, 0
    jle  Atq_PeonN_Der
    mov  eax, [ebp-4]
    add  eax, 7
    cmp  eax, [ebp-8]
    je   Atq_Si

Atq_PeonN_Der:
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
    sub  esp, 4
    push ecx
    push edx
    push esi
    push edi

    movzx eax, al
    mov  [ebp-4], eax

    mov  eax, [ebp-4]
    call Tablero_ObtenerPosRey
    movzx eax, al
    mov  ebx, [ebp-4]
    call Verificar_ReyEnJaque
    cmp  al, 0
    je   JM_No

    xor  edx, edx

JM_BucleOrigen:
    cmp  edx, BOARD_SIZE
    jae  JM_Si

    mov  eax, edx
    call Tablero_ObtenerColor
    movzx eax, al
    cmp  eax, [ebp-4]
    jne  JM_SigOrigen

    xor  ecx, ecx

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
    je   JM_No

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
    sub  esp, 4
    push ecx
    push edx
    push esi
    push edi

    movzx eax, al
    mov  [ebp-4], eax

    mov  eax, [ebp-4]
    call Tablero_ObtenerPosRey
    movzx eax, al
    mov  ebx, [ebp-4]
    call Verificar_ReyEnJaque
    cmp  al, 1
    je   Tab_No

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

; ===========================================================================
; AGREGAR ESTE BLOQUE AL FINAL DE move_validator.asm, ANTES de END
; ===========================================================================
; Verificar_MaterialInsuficiente
; Detecta si no hay suficiente material para dar mate:
;   - Rey vs Rey
;   - Rey+Alfil vs Rey
;   - Rey+Caballo vs Rey
; Retorna: AL = 1 si material insuficiente (tablas), 0 si hay material
; ===========================================================================
PUBLIC Verificar_MaterialInsuficiente

Verificar_MaterialInsuficiente PROC
    push ebp
    mov  ebp, esp
    sub  esp, 20          ; variables locales
    push ebx
    push ecx
    push edx
    push esi

    ; [ebp-4]  = contPiezasBlancas (sin rey)
    ; [ebp-8]  = contPiezasNegras (sin rey)
    ; [ebp-12] = tieneAlfilB (blanco tiene alfil)
    ; [ebp-16] = tieneCaballoB (blanco tiene caballo)
    ; [ebp-20] = tieneAlfilN/tieneCaballoN

    mov  DWORD PTR [ebp-4],  0
    mov  DWORD PTR [ebp-8],  0
    mov  DWORD PTR [ebp-12], 0
    mov  DWORD PTR [ebp-16], 0
    mov  DWORD PTR [ebp-20], 0

    xor  edx, edx          ; indice del tablero

MI_Bucle:
    cmp  edx, BOARD_SIZE
    jae  MI_Evaluar

    push edx
    mov  eax, edx
    call Tablero_ObtenerPieza
    movzx ecx, al
    pop  edx

    cmp  ecx, EMPTY
    je   MI_Siguiente

    ; Ignorar reyes
    cmp  ecx, REY_BLANCO
    je   MI_Siguiente
    cmp  ecx, REY_NEGRO
    je   MI_Siguiente

    ; Si hay peon, torre o reina de cualquier color = material suficiente
    cmp  ecx, PEON_BLANCO
    je   MI_Suficiente
    cmp  ecx, PEON_NEGRO
    je   MI_Suficiente
    cmp  ecx, TORRE_BLANCA
    je   MI_Suficiente
    cmp  ecx, TORRE_NEGRA
    je   MI_Suficiente
    cmp  ecx, REINA_BLANCA
    je   MI_Suficiente
    cmp  ecx, REINA_NEGRA
    je   MI_Suficiente

    ; Contar piezas menores
    cmp  ecx, ALFIL_BLANCO
    jne  MI_NoBlancoAlfil
    inc  DWORD PTR [ebp-4]
    mov  DWORD PTR [ebp-12], 1
    jmp  MI_Siguiente
MI_NoBlancoAlfil:
    cmp  ecx, CABALLO_BLANCO
    jne  MI_NoBlancoCaballo
    inc  DWORD PTR [ebp-4]
    mov  DWORD PTR [ebp-16], 1
    jmp  MI_Siguiente
MI_NoBlancoCaballo:
    cmp  ecx, ALFIL_NEGRO
    jne  MI_NoNegroAlfil
    inc  DWORD PTR [ebp-8]
    mov  DWORD PTR [ebp-20], 1
    jmp  MI_Siguiente
MI_NoNegroAlfil:
    cmp  ecx, CABALLO_NEGRO
    jne  MI_Siguiente
    inc  DWORD PTR [ebp-8]
    mov  DWORD PTR [ebp-20], 1

MI_Siguiente:
    inc  edx
    jmp  MI_Bucle

MI_Evaluar:
    ; Caso 1: Rey vs Rey (ambos contadores = 0)
    mov  eax, [ebp-4]
    add  eax, [ebp-8]
    cmp  eax, 0
    je   MI_Insuficiente

    ; Caso 2: Rey+pieza_menor vs Rey (un lado tiene 1 pieza menor, otro 0)
    cmp  DWORD PTR [ebp-4], 1
    jne  MI_VerNegras
    cmp  DWORD PTR [ebp-8], 0
    je   MI_Insuficiente

MI_VerNegras:
    cmp  DWORD PTR [ebp-8], 1
    jne  MI_Suficiente
    cmp  DWORD PTR [ebp-4], 0
    je   MI_Insuficiente

MI_Suficiente:
    mov  al, 0
    jmp  MI_Fin

MI_Insuficiente:
    mov  al, 1

MI_Fin:
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    add  esp, 20
    pop  ebp
    ret
Verificar_MaterialInsuficiente ENDP

END