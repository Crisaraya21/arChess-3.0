; ===========================================================================
; main.asm - Punto de Entrada y Coordinador General del Programa
;
; CAMBIOS DE INTEGRACIÓN:
;   - Agregados PROTO de file_manager.asm
;   - Se llama Archivo_ActualizarLastMove antes de Sync_RegistrarMovimiento
;   - Se llama Archivo_InicializarEstado al inicio de TODA partida (no solo online)
;   - Principal_EsperarRivalSiCorresponde copia syncLastMove a bufferMovUCI
;     antes de llamar Principal_ParsearUCI
;   - Se llama Archivo_EscribirEstado al finalizar partida (persistir estado)
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

; -----------------------------------------------------------------------
; board.asm
; -----------------------------------------------------------------------
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

; -----------------------------------------------------------------------
; move_validator.asm
; -----------------------------------------------------------------------
Validar_Movimiento               PROTO
Verificar_ReyEnJaque             PROTO
Verificar_JaqueMate              PROTO
Verificar_Tablas                 PROTO

; -----------------------------------------------------------------------
; ui_console.asm
; -----------------------------------------------------------------------
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
UI_LimpiarPantalla               PROTO

; -----------------------------------------------------------------------
; input_handler.asm
; -----------------------------------------------------------------------
Entrada_LeerMovimientoUCI        PROTO
Entrada_LeerOpcionMenu           PROTO
Entrada_SolicitoPista            PROTO

; -----------------------------------------------------------------------
; sync_manager.asm
; -----------------------------------------------------------------------
Sync_IniciarSesion               PROTO
Sync_PublicarEstado              PROTO
Sync_LeerEstadoRemoto            PROTO
Sync_RegistrarMovimiento         PROTO
Sync_VerificarActualizacion      PROTO

; -----------------------------------------------------------------------
; file_manager.asm  (NUEVO — necesarios para integración)
; -----------------------------------------------------------------------
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

; -----------------------------------------------------------------------
; engine_connector.asm
; -----------------------------------------------------------------------
Motor_SolicitarJugada            PROTO
Motor_SolicitarPista             PROTO
Motor_ObtenerMejorMovimiento     PROTO

; -----------------------------------------------------------------------
; Variables externas de sync_manager.asm
; -----------------------------------------------------------------------
EXTERNDEF syncLastMove : BYTE

; -----------------------------------------------------------------------
; Variables externas de input_handler.asm
; -----------------------------------------------------------------------
EXTERNDEF necesitaRedibujo : BYTE

; ===========================================================================
;                       SEGMENTO DE DATOS
; ===========================================================================
.data

modoJuego           BYTE MODO_LOCAL
turnoIA             BYTE 0
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

msgMovimientoIlegal BYTE "  [!] Movimiento ilegal. Intente de nuevo.",0Dh,0Ah,0
msgPistaSolicitada  BYTE "  [?] Solicitando pista...",0Dh,0Ah,0
msgSinPistas        BYTE "  [!] No quedan pistas disponibles.",0Dh,0Ah,0
msgFinPartida       BYTE "  Partida finalizada. Gracias por jugar.",0Dh,0Ah,0
msgSincronizando    BYTE "  [~] Sincronizando con servidor...",0Dh,0Ah,0
msgEsperandoRival   BYTE "  [~] Esperando movimiento del rival...",0Dh,0Ah,0

; ===========================================================================
;                       SEGMENTO DE CÓDIGO
; ===========================================================================
.code

main PROC
    push ebp
    mov  ebp, esp

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


; ===========================================================================
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


; ===========================================================================
Principal_IniciarPartida PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx

    call Tablero_Inicializar
    call Archivo_InicializarEstado     ; FIX: inicializar estado de archivo
                                        ;      en TODOS los modos, no solo online
    mov  pistasUsadas,           0
    mov  partidaActiva,          1
    mov  actualizacionPendiente, 0

    cmp  modoJuego, MODO_EN_LINEA
    jne  IniciarPartida_NoOnline

    ; --- Modo online: sincronizar ---
    mov  edx, OFFSET msgSincronizando
    call WriteString
    call Sync_IniciarSesion
    call Sync_PublicarEstado
    jmp  IniciarPartida_Jugar

IniciarPartida_NoOnline:
    ; Escribir game_state.json inicial (para modos local y vs IA también)
    call Archivo_EscribirEstado

IniciarPartida_Jugar:
    call Principal_BucleJuego

    pop  ebx
    pop  eax
    pop  ebp
    ret
Principal_IniciarPartida ENDP


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

    ; FIX: verificar si input_handler pidió redibujo (toggle de estilo)
    cmp  necesitaRedibujo, 0
    je   Bucle_SkipRedibujo
    mov  necesitaRedibujo, 0
Bucle_SkipRedibujo:

    call UI_LimpiarPantalla
    call UI_MostrarTablero
    call UI_MostrarTurno
    call UI_MostrarReloj
    call UI_MostrarHistorial

    call Tablero_ObtenerJaque
    cmp  al, 0
    je   Bucle_SinJaque
    call UI_MostrarJaque

Bucle_SinJaque:
    ; --- Modo online: esperar rival si corresponde ---
    cmp  modoJuego, MODO_EN_LINEA
    jne  Bucle_EscogerFuente
    call Principal_EsperarRivalSiCorresponde
    cmp  al, 1
    je   Bucle_PostMovimiento

Bucle_EscogerFuente:
    ; --- Modo vs IA: turno de la máquina ---
    call Tablero_ObtenerTurno
    cmp  al, COLOR_NEGRO
    jne  Bucle_TurnoHumano
    cmp  turnoIA, 1
    jne  Bucle_TurnoHumano
    call Principal_TurnoIA
    jmp  Bucle_PostMovimiento

Bucle_TurnoHumano:
    ; --- Verificar si usuario pidió pista (tecla 'h') ---
    call Entrada_SolicitoPista
    cmp  al, 1
    jne  Bucle_LeerMovimiento
    call Principal_ManejarPista
    jmp  Bucle_Inicio

Bucle_LeerMovimiento:
    mov  edx, OFFSET bufferMovUCI
    call Entrada_LeerMovimientoUCI
    cmp  al, 0
    je   Bucle_Inicio

    ; --- Parsear entrada UCI ---
    call Principal_ParsearUCI
    cmp  al, 0
    je   Bucle_MovimientoIlegal

    ; --- Validar movimiento ---
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   Bucle_MovimientoIlegal

    ; --- Ejecutar movimiento ---
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    ; FIX: Actualizar lastMove ANTES de registrar
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

    ; Cambiar turno PRIMERO, luego verificar jaque/mate/tablas
    call Tablero_CambiarTurno

    ; Detectar jaque al rey del jugador que acaba de recibir el turno
    call Tablero_ObtenerTurno       ; AL = turno nuevo (el que recibe)
    movzx eax, al
    push eax
    call Tablero_ObtenerPosRey      ; AL = pos rey
    movzx eax, al
    pop  ebx                        ; EBX = color del rey
    call Verificar_ReyEnJaque
    cmp  al, 1
    jne  Bucle_SinJaquePost

    ; Hay jaque: establecer bandera
    call Tablero_ObtenerTurno
    movzx eax, al
    inc  eax                        ; 1 = jaque a blancas, 2 = jaque a negras
    call Tablero_EstablecerJaque

    ; Verificar jaque mate
    call Tablero_ObtenerTurno
    call Verificar_JaqueMate
    cmp  al, 1
    jne  Bucle_SinJaquePost

    ; Jaque mate: quien acaba de mover gana
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

    ; Verificar tablas
    call Tablero_ObtenerTurno
    call Verificar_Tablas
    cmp  al, 1
    jne  Bucle_SincronizarFin

    mov  al, ESTADO_TABLAS
    call Tablero_EstablecerEstado
    call UI_MostrarTablas

Bucle_SincronizarFin:
    ; Escribir estado actualizado a disco (todos los modos)
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
; Principal_ParsearUCI — Convierte bufferMovUCI (4 chars) a índices de tablero
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
; Principal_TurnoIA — La IA hace su movimiento
; ===========================================================================
Principal_TurnoIA PROC
    push eax
    push ebx

    call Motor_SolicitarJugada

    ; Motor_SolicitarJugada debe dejar el movimiento UCI en bufferMovUCI
    ; (esto lo implementará engine_connector.asm completo)
    call Principal_ParsearUCI
    cmp  al, 0
    je   TurnoIA_Fin

    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   TurnoIA_Fin

    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    ; FIX: Actualizar lastMove antes de registrar
    mov  edx, OFFSET bufferMovUCI
    call Archivo_ActualizarLastMove
    call Sync_RegistrarMovimiento

TurnoIA_Fin:
    pop  ebx
    pop  eax
    ret
Principal_TurnoIA ENDP


; ===========================================================================
; Principal_ManejarPista — Solicita y muestra una pista al jugador
; ===========================================================================
Principal_ManejarPista PROC
    push eax

    movzx eax, pistasUsadas
    cmp  eax, MAX_PISTAS
    jae  Pista_Agotadas

    call Motor_SolicitarPista
    call Motor_ObtenerMejorMovimiento
    call UI_MostrarPista
    inc  pistasUsadas
    jmp  Pista_Fin

Pista_Agotadas:
    call UI_MostrarPistasAgotadas

Pista_Fin:
    pop  eax
    ret
Principal_ManejarPista ENDP


; ===========================================================================
; Principal_EsperarRivalSiCorresponde
;   En modo online, si es turno del rival, hace polling hasta recibir
;   el movimiento remoto. Luego lo ejecuta localmente.
;
; Retorna: AL = 1 si se ejecutó movimiento del rival, 0 si es turno local
;
; FIX: Ahora copia syncLastMove → bufferMovUCI antes de parsear,
;      porque Principal_ParsearUCI lee de bufferMovUCI.
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

    ; Hay actualización: leer estado remoto
    call Sync_LeerEstadoRemoto

    ; FIX: Copiar syncLastMove → bufferMovUCI para que ParsearUCI funcione
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

    ; Parsear el movimiento del rival
    call Principal_ParsearUCI
    cmp  al, 0
    je   Esperar_ErrorRemoto

    ; Validar
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   Esperar_ErrorRemoto

    ; Ejecutar
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    ; Registrar (lastMove ya fue seteado por Sync_LeerEstadoRemoto)
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