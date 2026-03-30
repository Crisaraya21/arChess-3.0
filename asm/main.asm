; ===========================================================================
; main.asm - Punto de Entrada y Coordinador General
;
; MODO VS IA:
;   - Humano juega BLANCAS, IA juega NEGRAS
;   - Cuando es turno de negras, llama Motor_SolicitarJugada
;   - Si la IA falla (API caida, etc), deja al humano jugar por negras
;   - Los movimientos de la IA se registran en el historial
;
; FIX PISTA:
;   - Tecla 'h' se detecta despues de leer input (no con SolicitoPista)
;   - WaitMsg despues de mostrar pista para que el usuario la vea
; ===========================================================================

INCLUDE Irvine32.inc

COLOR_BLANCO        EQU 0
COLOR_NEGRO         EQU 1
ESTADO_EN_CURSO     EQU 0
ESTADO_GANA_BLANCAS EQU 1
ESTADO_GANA_NEGRAS  EQU 2
ESTADO_TABLAS       EQU 3
MODO_EN_LINEA       EQU 0
MODO_VS_IA          EQU 1
MODO_LOCAL          EQU 2
MAX_PISTAS          EQU 3

Tablero_Inicializar              PROTO
Tablero_ObtenerTurno             PROTO
Tablero_CambiarTurno             PROTO
Tablero_MoverPieza               PROTO
Tablero_ObtenerEstado            PROTO
Tablero_EstablecerEstado         PROTO
Tablero_ObtenerJaque             PROTO
Tablero_EstablecerJaque          PROTO
Tablero_ObtenerPosRey            PROTO
Tablero_UCIAIndice               PROTO
Tablero_ObtenerContadorMovimientos PROTO

Validar_Movimiento               PROTO
Verificar_ReyEnJaque             PROTO
Verificar_JaqueMate              PROTO
Verificar_Tablas                 PROTO

UI_MostrarTablero                PROTO
UI_MostrarMenuPrincipal          PROTO
UI_MostrarTurno                  PROTO
UI_MostrarJaque                  PROTO
UI_MostrarJaqueMate              PROTO
UI_MostrarTablas                 PROTO
UI_MostrarMovimientoIlegal       PROTO
UI_MostrarHistorial              PROTO
UI_MostrarReloj                  PROTO
UI_MostrarPista                  PROTO
UI_MostrarPistasAgotadas         PROTO
UI_ActualizarReloj               PROTO
UI_IniciarReloj                  PROTO
UI_LimpiarPantalla               PROTO

Entrada_LeerMovimientoUCI        PROTO
Entrada_LeerOpcionMenu           PROTO
Entrada_SolicitoPista            PROTO

Sync_IniciarSesion               PROTO
Sync_PublicarEstado              PROTO
Sync_LeerEstadoRemoto            PROTO
Sync_RegistrarMovimiento         PROTO
Sync_VerificarActualizacion      PROTO

Archivo_InicializarEstado        PROTO
Archivo_EscribirEstado           PROTO
Archivo_LeerEstado               PROTO
Archivo_ActualizarLastMove       PROTO
Archivo_RegistrarMovimiento      PROTO
Archivo_LeerBandera              PROTO
Archivo_EscribirBandera          PROTO
Archivo_LeerPista                PROTO
Archivo_GenerarFEN               PROTO
Archivo_IncrementarVersion       PROTO

Motor_SolicitarJugada            PROTO
Motor_SolicitarPista             PROTO
Motor_ObtenerMejorMovimiento     PROTO
Rutas_Inicializar                PROTO

EXTERNDEF syncLastMove     : BYTE
EXTERNDEF syncRolCliente   : BYTE
EXTERNDEF necesitaRedibujo : BYTE

; Para registrar movimientos de la IA en el historial
EXTERNDEF uiMoveHistory    : BYTE
EXTERNDEF uiMoveCount      : DWORD

; ===========================================================================
.data

modoJuego           BYTE MODO_LOCAL
turnoIA             BYTE 0

PUBLIC bufferMovUCI
bufferMovUCI        BYTE 5 DUP(0)

indiceOrigen        DWORD 0
indiceDestino       DWORD 0
pistasUsadas        BYTE 0
partidaActiva       BYTE 0
actualizacionPendiente BYTE 0

msgBienvenida       BYTE "================================",0Dh,0Ah
                    BYTE "       arChess  3.0             ",0Dh,0Ah
                    BYTE "  IC3101 - Arq. Computadoras    ",0Dh,0Ah
                    BYTE "================================",0Dh,0Ah,0

msgMenuOpciones     BYTE "  1. Jugar en linea (2 jugadores)",0Dh,0Ah
                    BYTE "  2. Jugar vs IA",0Dh,0Ah
                    BYTE "  3. Jugar local (sin red)",0Dh,0Ah
                    BYTE "  0. Salir",0Dh,0Ah
                    BYTE "  Opcion: ",0

msgElegirCliente    BYTE 0Dh, 0Ah
                    BYTE "  Seleccione su cliente:",0Dh,0Ah
                    BYTE "  a. Cliente A (juega blancas)",0Dh,0Ah
                    BYTE "  b. Cliente B (juega negras)",0Dh,0Ah
                    BYTE "  Opcion (a/b): ",0

msgClienteA         BYTE "  -> Usted es Cliente A",0Dh,0Ah,0
msgClienteB         BYTE "  -> Usted es Cliente B",0Dh,0Ah,0
msgClienteInvalido  BYTE "  Opcion invalida. Use 'a' o 'b'.",0Dh,0Ah,0

msgMovimientoIlegal BYTE "  [!] Movimiento ilegal.",0Dh,0Ah,0
msgFinPartida       BYTE "  Partida finalizada. Gracias por jugar.",0Dh,0Ah,0
msgSincronizando    BYTE "  [~] Sincronizando con servidor...",0Dh,0Ah,0
msgEsperandoRival   BYTE "  [~] Esperando movimiento del rival...",0Dh,0Ah,0

; Mensajes modo vs IA
msgIAPensando       BYTE "  [IA] Pensando...",0Dh,0Ah,0
msgIAJugo           BYTE "  [IA] Jugo: ",0
msgIAFallo          BYTE "  [!] IA no pudo jugar. Ingrese movimiento para negras.",0Dh,0Ah,0
msgNL               BYTE 0Dh, 0Ah, 0

; ===========================================================================
.code

main PROC
push ebp
    mov  ebp, esp
    call Rutas_Inicializar
    call Principal_MostrarBienvenida
    call Entrada_LeerOpcionMenu
    movzx eax, al
    cmp  eax, 0
    je   Principal_Salir
    cmp  eax, 1
    je   Principal_ModoEnLinea
    cmp  eax, 2
    je   Principal_ModoVsIA
    cmp  eax, 3
    je   Principal_ModoLocal
    jmp  Principal_Salir
Principal_ModoEnLinea:
    mov  modoJuego, MODO_EN_LINEA
    mov  turnoIA,   0
    call Principal_ElegirCliente
    call Principal_IniciarPartida
    jmp  Principal_Salir
Principal_ModoVsIA:
    mov  modoJuego, MODO_VS_IA
    mov  turnoIA,   1
    call Principal_IniciarPartida
    jmp  Principal_Salir
Principal_ModoLocal:
    mov  modoJuego, MODO_LOCAL
    mov  turnoIA,   0
    call Principal_IniciarPartida
Principal_Salir:
    call UI_LimpiarPantalla
    mov  edx, OFFSET msgFinPartida
    call WriteString
    pop  ebp
    INVOKE ExitProcess, 0
main ENDP


Principal_ElegirCliente PROC
    push eax
    push edx
ElegirCliente_Loop:
    mov  edx, OFFSET msgElegirCliente
    call WriteString
    call ReadChar
    call WriteChar
    push eax
    mov  al, 0Dh
    call WriteChar
    mov  al, 0Ah
    call WriteChar
    pop  eax
    cmp  al, 'a'
    je   ElegirCliente_A
    cmp  al, 'A'
    je   ElegirCliente_A
    cmp  al, 'b'
    je   ElegirCliente_B
    cmp  al, 'B'
    je   ElegirCliente_B
    mov  edx, OFFSET msgClienteInvalido
    call WriteString
    jmp  ElegirCliente_Loop
ElegirCliente_A:
    mov  syncRolCliente, 'a'
    mov  edx, OFFSET msgClienteA
    call WriteString
    jmp  ElegirCliente_Fin
ElegirCliente_B:
    mov  syncRolCliente, 'b'
    mov  edx, OFFSET msgClienteB
    call WriteString
ElegirCliente_Fin:
    pop  edx
    pop  eax
    ret
Principal_ElegirCliente ENDP


Principal_MostrarBienvenida PROC
    push eax
    call UI_LimpiarPantalla
    mov  edx, OFFSET msgBienvenida
    call WriteString
    mov  edx, OFFSET msgMenuOpciones
    call WriteString
    pop  eax
    ret
Principal_MostrarBienvenida ENDP


Principal_IniciarPartida PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx
    call Tablero_Inicializar
    call UI_IniciarReloj
    call Archivo_InicializarEstado
    mov  pistasUsadas,           0
    mov  partidaActiva,          1
    mov  actualizacionPendiente, 0
    cmp  modoJuego, MODO_EN_LINEA
    jne  IniciarPartida_NoOnline
    mov  edx, OFFSET msgSincronizando
    call WriteString
    call Sync_IniciarSesion
    call Sync_PublicarEstado
    jmp  IniciarPartida_Jugar
IniciarPartida_NoOnline:
    call Archivo_EscribirEstado
IniciarPartida_Jugar:
    call Principal_BucleJuego
    pop  ebx
    pop  eax
    pop  ebp
    ret
Principal_IniciarPartida ENDP


; ===========================================================================
; Principal_BucleJuego - Bucle principal
; ===========================================================================
Principal_BucleJuego PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx
    push ecx

Bucle_Inicio:
    call Tablero_ObtenerEstado
    cmp  al, ESTADO_EN_CURSO
    jne  Bucle_FinPartida

    call UI_LimpiarPantalla
    call UI_MostrarTablero
    call UI_MostrarTurno
    call UI_MostrarReloj
    call UI_ActualizarReloj
    call UI_MostrarHistorial

    call Tablero_ObtenerJaque
    cmp  al, 0
    je   Bucle_SinJaque
    call UI_MostrarJaque

Bucle_SinJaque:
    ; --- Modo online: esperar rival ---
    cmp  modoJuego, MODO_EN_LINEA
    jne  Bucle_EscogerFuente
    call Principal_EsperarRivalSiCorresponde
    cmp  al, 1
    je   Bucle_PostMovimiento

Bucle_EscogerFuente:
    ; --- Modo vs IA: turno de negras = IA juega ---
    call Tablero_ObtenerTurno
    cmp  al, COLOR_NEGRO
    jne  Bucle_TurnoHumano
    cmp  turnoIA, 1
    jne  Bucle_TurnoHumano

    ; Mostrar mensaje de IA pensando
    mov  edx, OFFSET msgIAPensando
    call WriteString

    ; Intentar que la IA juegue
    call Principal_TurnoIA
    cmp  al, 1
    je   Bucle_PostMovimiento

    ; IA fallo: dejar que el humano juegue por negras
    mov  edx, OFFSET msgIAFallo
    call WriteString
    ; Cae al turno humano para que ingrese movimiento manual

Bucle_TurnoHumano:
Bucle_LeerMovimiento:
    mov  edx, OFFSET bufferMovUCI
    call Entrada_LeerMovimientoUCI
    cmp  al, 0
    jne  Bucle_ValidarMovimiento

    ; AL=0: revisar si fue 'h' (pista) o 's' (estilo)
    cmp  BYTE PTR bufferMovUCI, 'h'
    je   Bucle_PistaDirecta
    jmp  Bucle_Inicio

Bucle_PistaDirecta:
    call Principal_ManejarPista
    call WaitMsg
    jmp  Bucle_Inicio

Bucle_ValidarMovimiento:
    call Principal_ParsearUCI
    cmp  al, 0
    je   Bucle_MovimientoIlegal

    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   Bucle_MovimientoIlegal

    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    mov  edx, OFFSET bufferMovUCI
    call Archivo_ActualizarLastMove
    call Sync_RegistrarMovimiento
    jmp  Bucle_PostMovimiento

Bucle_MovimientoIlegal:
    call UI_MostrarMovimientoIlegal
    call WaitMsg
    jmp  Bucle_Inicio

Bucle_PostMovimiento:
    call UI_ActualizarReloj
    call Tablero_CambiarTurno

    ; --- Detectar jaque ---
    call Tablero_ObtenerTurno
    movzx eax, al
    push eax
    call Tablero_ObtenerPosRey
    movzx eax, al
    pop  ebx
    call Verificar_ReyEnJaque
    cmp  al, 1
    jne  Bucle_SinJaquePost

    call Tablero_ObtenerTurno
    movzx eax, al
    inc  eax
    call Tablero_EstablecerJaque

    call Tablero_ObtenerTurno
    call Verificar_JaqueMate
    cmp  al, 1
    jne  Bucle_SinJaquePost

    call Tablero_ObtenerTurno
    cmp  al, COLOR_BLANCO
    je   Bucle_GananNegras
    mov  al, ESTADO_GANA_NEGRAS
    jmp  Bucle_SetMate
Bucle_GananNegras:
    mov  al, ESTADO_GANA_BLANCAS
Bucle_SetMate:
    call Tablero_EstablecerEstado
    call UI_MostrarJaqueMate
    jmp  Bucle_SincronizarFin

Bucle_SinJaquePost:
    mov  al, 0
    call Tablero_EstablecerJaque

    call Tablero_ObtenerTurno
    call Verificar_Tablas
    cmp  al, 1
    jne  Bucle_SincronizarFin

    mov  al, ESTADO_TABLAS
    call Tablero_EstablecerEstado
    call UI_MostrarTablas

Bucle_SincronizarFin:
    call Archivo_EscribirEstado
    cmp  modoJuego, MODO_EN_LINEA
    jne  Bucle_Inicio
    call Sync_PublicarEstado
    jmp  Bucle_Inicio

Bucle_FinPartida:
    call UI_MostrarTablero
    call WaitMsg
    pop  ecx
    pop  ebx
    pop  eax
    pop  ebp
    ret
Principal_BucleJuego ENDP


; ===========================================================================
; Principal_TurnoIA - Intenta que la IA haga su jugada
; Retorna: AL = 1 si la IA jugo exitosamente, 0 si fallo
; ===========================================================================
Principal_TurnoIA PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Intentar hasta 2 veces
    mov  ecx, 2

TurnoIA_Reintentar:
    push ecx

    call Motor_SolicitarJugada
    cmp  al, 0
    je   TurnoIA_FalloEsteIntento

    ; Parsear el movimiento UCI
    call Principal_ParsearUCI
    cmp  al, 0
    je   TurnoIA_FalloEsteIntento

    ; Validar que sea legal
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   TurnoIA_FalloEsteIntento

    ; --- Movimiento valido: ejecutar ---
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    ; Registrar en archivos
    mov  edx, OFFSET bufferMovUCI
    call Archivo_ActualizarLastMove
    call Sync_RegistrarMovimiento

    ; Registrar en historial visual
    call Main_RegistrarMovEnHistorial

    ; Mostrar que jugada hizo la IA
    mov  edx, OFFSET msgIAJugo
    call WriteString
    mov  edx, OFFSET bufferMovUCI
    call WriteString
    mov  edx, OFFSET msgNL
    call WriteString

    pop  ecx
    mov  al, 1           ; exito
    jmp  TurnoIA_Fin

TurnoIA_FalloEsteIntento:
    pop  ecx
    dec  ecx
    cmp  ecx, 0
    jg   TurnoIA_Reintentar

    ; Ambos intentos fallaron
    mov  al, 0

TurnoIA_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Principal_TurnoIA ENDP


; ===========================================================================
; Main_RegistrarMovEnHistorial - Agrega bufferMovUCI al historial visual
;   Escribe en uiMoveHistory (de input_handler.asm) para que la UI
;   lo muestre. Equivale a Inp_RegistrarMov pero llamable desde main.
; ===========================================================================
Main_RegistrarMovEnHistorial PROC
    push eax
    push ebx
    push esi

    ; offset = uiMoveCount * 5
    mov  eax, uiMoveCount
    imul eax, 5
    lea  ebx, uiMoveHistory
    add  ebx, eax

    ; copiar 4 chars de bufferMovUCI + null
    lea  esi, bufferMovUCI
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

    pop  esi
    pop  ebx
    pop  eax
    ret
Main_RegistrarMovEnHistorial ENDP


; ===========================================================================
; Principal_ParsearUCI
; ===========================================================================
Principal_ParsearUCI PROC
    push ebx
    push ecx
    movzx eax, bufferMovUCI[0]
    cmp  al, 'a'
    jb   ParsearUCI_Error
    cmp  al, 'h'
    ja   ParsearUCI_Error
    movzx ebx, bufferMovUCI[2]
    cmp  bl, 'a'
    jb   ParsearUCI_Error
    cmp  bl, 'h'
    ja   ParsearUCI_Error
    movzx ecx, bufferMovUCI[1]
    cmp  cl, '1'
    jb   ParsearUCI_Error
    cmp  cl, '8'
    ja   ParsearUCI_Error
    movzx ecx, bufferMovUCI[3]
    cmp  cl, '1'
    jb   ParsearUCI_Error
    cmp  cl, '8'
    ja   ParsearUCI_Error
    mov  al, bufferMovUCI[0]
    mov  ah, bufferMovUCI[1]
    call Tablero_UCIAIndice
    cmp  eax, 0FFFFFFFFh
    je   ParsearUCI_Error
    mov  indiceOrigen, eax
    mov  al, bufferMovUCI[2]
    mov  ah, bufferMovUCI[3]
    call Tablero_UCIAIndice
    cmp  eax, 0FFFFFFFFh
    je   ParsearUCI_Error
    mov  indiceDestino, eax
    mov  al, 1
    jmp  ParsearUCI_Fin
ParsearUCI_Error:
    mov  al, 0
ParsearUCI_Fin:
    pop  ecx
    pop  ebx
    ret
Principal_ParsearUCI ENDP


; ===========================================================================
; Principal_ManejarPista
; ===========================================================================
Principal_ManejarPista PROC
    push eax
    movzx eax, pistasUsadas
    cmp  eax, MAX_PISTAS
    jae  Pista_Agotadas
    call Motor_SolicitarPista
    cmp  al, 0
    je   Pista_ErrorMotor
    call Motor_ObtenerMejorMovimiento
    call UI_MostrarPista
    inc  pistasUsadas
    jmp  Pista_Fin
Pista_ErrorMotor:
    call Motor_ObtenerMejorMovimiento
    call UI_MostrarPista
    jmp  Pista_Fin
Pista_Agotadas:
    call UI_MostrarPistasAgotadas
Pista_Fin:
    pop  eax
    ret
Principal_ManejarPista ENDP


; ===========================================================================
; Principal_EsperarRivalSiCorresponde
; ===========================================================================
Principal_EsperarRivalSiCorresponde PROC
    push ebx
    push ecx
    push esi
    push edi
    call Tablero_ObtenerTurno
    cmp  al, COLOR_NEGRO
    jne  Esperar_EsTurnoLocal
    call UI_LimpiarPantalla
    call UI_MostrarTablero
    mov  edx, OFFSET msgEsperandoRival
    call WriteString
Esperar_PollLoop:
    call Sync_VerificarActualizacion
    cmp  al, 1
    jne  Esperar_PollLoop
    call Sync_LeerEstadoRemoto
    lea  esi, syncLastMove
    lea  edi, bufferMovUCI
    mov  al, [esi+0]
    mov  [edi+0], al
    mov  al, [esi+1]
    mov  [edi+1], al
    mov  al, [esi+2]
    mov  [edi+2], al
    mov  al, [esi+3]
    mov  [edi+3], al
    mov  BYTE PTR [edi+4], 0
    call Principal_ParsearUCI
    cmp  al, 0
    je   Esperar_ErrorRemoto
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   Esperar_ErrorRemoto
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza
    call Sync_RegistrarMovimiento
    mov  al, 1
    jmp  Esperar_Fin
Esperar_ErrorRemoto:
    jmp  Esperar_PollLoop
Esperar_EsTurnoLocal:
    mov  al, 0
Esperar_Fin:
    pop  edi
    pop  esi
    pop  ecx
    pop  ebx
    ret
Principal_EsperarRivalSiCorresponde ENDP

END main