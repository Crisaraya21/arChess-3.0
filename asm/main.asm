; ===========================================================================
; main.asm — Punto de Entrada y Coordinador General del Programa
;
;   - Inicializar todos los módulos del sistema al arranque
;   - Coordinar el flujo principal del juego (bucle de partida)
;   - Orquestar la secuencia: mostrar tablero → leer movimiento →
;     validar → aplicar → detectar fin de partida → alternar turno
;   - Delegar cada responsabilidad a su módulo correspondiente:
;       board.asm         → estado del tablero
;       move_validator.asm → validación de movimientos y detección de fin
;       ui_console.asm    → visualización e interacción con el usuario
;       input_handler.asm → lectura e interpretación del teclado
;       sync_manager.asm  → sincronización con Firebase vía Python
;       engine_connector.asm → integración con IA / pistas
;
;
;
; Flujo general:
;   Inicio
;     │
;     ▼
;   Inicializar módulos
;     │
;     ▼
;   Mostrar menú principal
;     │
;     ├─ Jugar en línea (2 jugadores) ─────────────────────────────────-─┐
;     ├─ Jugar vs IA                                                     │
;     └─ Salir                                                           │
;                                                                        │
;   ┌──────────────────────────────────────────────────────────────────┐ │
;   │                  BUCLE PRINCIPAL DE PARTIDA                      │ │
;   │  Mostrar tablero                                                 │ │
;   │  Mostrar turno / estado de jaque / reloj                         │ │
;   │  Mostrar historial                                               │ │
;   │  Si es turno de IA → pedir jugada a engine_connector             │ │
;   │  Si es turno humano → leer movimiento UCI del teclado            │ │
;   │  Validar movimiento                                              │ │
;   │  Si legal → aplicar → sincronizar → cambiar turno                │ │
;   │  Detectar jaque / jaque mate / tablas                            │ │
;   │  Si fin de partida → mostrar resultado → salir del bucle         │ │
;   └──────────────────────────────────────────────────────────────────┘ │
;     │                                                                  │
;     └──────────────────────────────────────────────────────────────────┘
;
; Dependencias directas:
;   board.asm, move_validator.asm, ui_console.asm, input_handler.asm,
;   sync_manager.asm, engine_connector.asm
; ===========================================================================

INCLUDE Irvine32.inc

; ---------------------------------------------------------------------------
; Constantes (deben coincidir con board.asm)
; ---------------------------------------------------------------------------
COLOR_BLANCO        EQU 0
COLOR_NEGRO         EQU 1

; Estados del juego (deben coincidir con board.asm)
ESTADO_EN_CURSO     EQU 0
ESTADO_GANA_BLANCAS EQU 1
ESTADO_GANA_NEGRAS  EQU 2
ESTADO_TABLAS       EQU 3

; Modos de juego
MODO_EN_LINEA       EQU 0       ; dos jugadores humanos por red
MODO_VS_IA          EQU 1       ; jugador humano vs motor IA
MODO_LOCAL          EQU 2       ; dos jugadores locales (sin red)

; Límite de pistas disponibles por partida
MAX_PISTAS          EQU 3

; ---------------------------------------------------------------------------
; Referencias externas — board.asm
; ---------------------------------------------------------------------------
EXTERN Tablero_Inicializar              : PROC
EXTERN Tablero_ObtenerTurno             : PROC
EXTERN Tablero_CambiarTurno             : PROC
EXTERN Tablero_MoverPieza               : PROC
EXTERN Tablero_ObtenerEstado            : PROC
EXTERN Tablero_EstablecerEstado         : PROC
EXTERN Tablero_ObtenerJaque             : PROC
EXTERN Tablero_EstablecerJaque          : PROC
EXTERN Tablero_ObtenerPosRey            : PROC
EXTERN Tablero_UCIAIndice               : PROC
EXTERN Tablero_ObtenerContadorMovimientos : PROC

; ---------------------------------------------------------------------------
; Referencias externas — move_validator.asm
; ---------------------------------------------------------------------------
EXTERN Validar_Movimiento               : PROC
EXTERN Verificar_ReyEnJaque             : PROC
EXTERN Verificar_JaqueMate              : PROC
EXTERN Verificar_Tablas                 : PROC

; ---------------------------------------------------------------------------
; Referencias externas — ui_console.asm  (Persona B)
; ---------------------------------------------------------------------------
EXTERN UI_MostrarTablero                : PROC
EXTERN UI_MostrarMenuPrincipal          : PROC
EXTERN UI_MostrarTurno                  : PROC
EXTERN UI_MostrarJaque                  : PROC
EXTERN UI_MostrarJaqueMate              : PROC
EXTERN UI_MostrarTablas                 : PROC
EXTERN UI_MostrarMovimientoIlegal       : PROC
EXTERN UI_MostrarHistorial              : PROC
EXTERN UI_MostrarReloj                  : PROC
EXTERN UI_MostrarPista                  : PROC
EXTERN UI_MostrarPistasAgotadas         : PROC
EXTERN UI_ActualizarReloj               : PROC
EXTERN UI_LimpiarPantalla               : PROC

; ---------------------------------------------------------------------------
; Referencias externas — input_handler.asm  (Persona B)
; ---------------------------------------------------------------------------
EXTERN Entrada_LeerMovimientoUCI        : PROC
EXTERN Entrada_LeerOpcionMenu           : PROC
EXTERN Entrada_SolicitoPista            : PROC

; ---------------------------------------------------------------------------
; Referencias externas — sync_manager.asm  (Persona A – Parte 3)
; ---------------------------------------------------------------------------
EXTERN Sync_IniciarSesion               : PROC
EXTERN Sync_PublicarEstado              : PROC
EXTERN Sync_LeerEstadoRemoto            : PROC
EXTERN Sync_RegistrarMovimiento         : PROC
EXTERN Sync_VerificarActualizacion      : PROC

; ---------------------------------------------------------------------------
; Referencias externas — engine_connector.asm  (Persona B – Parte 4)
; ---------------------------------------------------------------------------
EXTERN Motor_SolicitarJugada            : PROC
EXTERN Motor_SolicitarPista             : PROC
EXTERN Motor_ObtenerMejorMovimiento     : PROC

; ---------------------------------------------------------------------------
; Segmento de datos
; ---------------------------------------------------------------------------
.data

; Modo de juego seleccionado
modoJuego           BYTE MODO_LOCAL

; Indica si el turno de negras lo controla la IA (modo vs IA)
turnoIA             BYTE 0          ; 0 = humano, 1 = IA

; Buffer para movimiento UCI ingresado: "e2e4" + nulo = 5 bytes
bufferMovUCI        BYTE 5 DUP(0)

; Índices origen y destino tras parsear el movimiento UCI
indiceOrigen        DWORD 0
indiceDestino       DWORD 0

; Contador de pistas usadas en la partida actual
pistasUsadas        BYTE 0

; Bandera: partida en curso (1) o terminada (0)
partidaActiva       BYTE 0

; Bandera: hay actualización remota pendiente de procesar
actualizacionPendiente BYTE 0

; Mensajes de texto del menú principal
msgBienvenida       BYTE "╔══════════════════════════════╗", 0Dh, 0Ah
                    BYTE "║       arChess  3.0           ║", 0Dh, 0Ah
                    BYTE "║  IC3101 – Arq. Computadoras  ║", 0Dh, 0Ah
                    BYTE "╚══════════════════════════════╝", 0Dh, 0Ah, 0

msgMenuOpciones     BYTE "  1. Jugar en linea (2 jugadores)", 0Dh, 0Ah
                    BYTE "  2. Jugar vs IA", 0Dh, 0Ah
                    BYTE "  3. Jugar local (sin red)", 0Dh, 0Ah
                    BYTE "  0. Salir", 0Dh, 0Ah
                    BYTE "  Opcion: ", 0

msgMovimientoIlegal BYTE "  [!] Movimiento ilegal. Intente de nuevo.", 0Dh, 0Ah, 0
msgPistaSolicitada  BYTE "  [?] Solicitando pista...", 0Dh, 0Ah, 0
msgSinPistas        BYTE "  [!] No quedan pistas disponibles.", 0Dh, 0Ah, 0
msgFinPartida       BYTE "  Partida finalizada. Gracias por jugar.", 0Dh, 0Ah, 0
msgSincronizando    BYTE "  [~] Sincronizando con servidor...", 0Dh, 0Ah, 0
msgEsperandoRival   BYTE "  [~] Esperando movimiento del rival...", 0Dh, 0Ah, 0

; ---------------------------------------------------------------------------
; Segmento de código
; ---------------------------------------------------------------------------
.code

; ===========================================================================
; Procedimiento : main
; Descripción   : Punto de entrada del programa. Muestra el menú, configura
;                 el modo de juego y lanza el bucle de partida.
; ===========================================================================
main PROC
    ; --- Inicializar la pila y el marco de activación ---
    push ebp
    mov  ebp, esp

    ; --- Mostrar bienvenida y menú principal ---
    call Principal_MostrarBienvenida

    ; --- Leer opción del usuario ---
    call Entrada_LeerOpcionMenu     ; AL = opción elegida (0-3)
    movzx eax, al

    cmp  eax, 0
    je   Principal_Salir
    cmp  eax, 1
    je   Principal_ModoEnLinea
    cmp  eax, 2
    je   Principal_ModoVsIA
    cmp  eax, 3
    je   Principal_ModoLocal
    jmp  Principal_Salir            ; opción inválida → salir

Principal_ModoEnLinea:
    mov  modoJuego, MODO_EN_LINEA
    mov  turnoIA,   0
    call Principal_IniciarPartida
    jmp  Principal_Salir

Principal_ModoVsIA:
    mov  modoJuego, MODO_VS_IA
    mov  turnoIA,   1               ; las negras las mueve la IA
    call Principal_IniciarPartida
    jmp  Principal_Salir

Principal_ModoLocal:
    mov  modoJuego, MODO_LOCAL
    mov  turnoIA,   0
    call Principal_IniciarPartida

Principal_Salir:
    ; Limpiar y terminar
    call UI_LimpiarPantalla
   lea  eax, msgFinPartida
    call WriteString
    pop  ebp
    INVOKE ExitProcess, 0
main ENDP


; ===========================================================================
; Procedimiento : Principal_MostrarBienvenida
; Descripción   : Limpia la pantalla y muestra el banner de bienvenida
;                 junto con el menú de opciones.
; Parámetros    : Ninguno
; Retorna       : Ninguno
; ===========================================================================
Principal_MostrarBienvenida PROC
    push eax

    call UI_LimpiarPantalla

    ; Mostrar banner
    mov  eax, OFFSET msgBienvenida
    call WriteString

    ; Mostrar opciones del menú
    mov  eax, OFFSET msgMenuOpciones
    call WriteString

    pop  eax
    ret
Principal_MostrarBienvenida ENDP


; ===========================================================================
; Procedimiento : Principal_IniciarPartida
; Descripción   : Inicializa todos los módulos necesarios para una partida
;                 y lanza el bucle principal de juego.
; Parámetros    : Ninguno (usa modoJuego y turnoIA globales)
; Retorna       : Ninguno
; ===========================================================================
Principal_IniciarPartida PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx

    ; --- 1. Inicializar tablero (board.asm) ---
    call Tablero_Inicializar

    ; --- 2. Reiniciar estado interno ---
    mov  pistasUsadas,          0
    mov  partidaActiva,         1
    mov  actualizacionPendiente,0

    ; --- 3. Si modo en línea: autenticar con Firebase y publicar estado inicial ---
    cmp  modoJuego, MODO_EN_LINEA
    jne  IniciarPartida_SkipSync

    mov  eax, OFFSET msgSincronizando
    call WriteString
    call Sync_IniciarSesion         ; autentica con Firebase Auth
    call Sync_PublicarEstado        ; sube game_state.json inicial

IniciarPartida_SkipSync:
    ; --- 4. Lanzar el bucle principal ---
    call Principal_BucleJuego

    pop  ebx
    pop  eax
    pop  ebp
    ret
Principal_IniciarPartida ENDP


; ===========================================================================
; Procedimiento : Principal_BucleJuego
; Descripción   : Bucle central de la partida. Se repite hasta que el estado
;                 del juego deje de ser ESTADO_EN_CURSO.
;
;   Cada iteración:
;     1. Limpiar pantalla y redibujar tablero + info
;     2. Si modo en línea y no es mi turno → esperar actualización remota
;     3. Si turno IA → pedir jugada al motor
;        Si turno humano → leer UCI del teclado (con opción de pedir pista)
;     4. Parsear movimiento UCI → índices
;     5. Validar movimiento
;     6. Aplicar movimiento al tablero
;     7. Detectar jaque / jaque mate / tablas
;     8. Sincronizar si modo en línea
;     9. Cambiar turno
; ===========================================================================
Principal_BucleJuego PROC
    push ebp
    mov  ebp, esp
    push eax
    push ebx
    push ecx

Bucle_Inicio:
    ; ---- Verificar si la partida terminó ----
    call Tablero_ObtenerEstado      ; AL = estado
    cmp  al, ESTADO_EN_CURSO
    jne  Bucle_FinPartida

    ; ---- Redibujar interfaz ----
    call UI_LimpiarPantalla
    call UI_MostrarTablero          ; dibuja el tablero ASCII
    call UI_MostrarTurno            ; "Turno: Blancas / Negras"
    call UI_MostrarReloj            ; reloj de turno
    call UI_MostrarHistorial        ; lista lateral de movimientos

    ; ---- Mostrar jaque si corresponde ----
    call Tablero_ObtenerJaque       ; AL = bandera de jaque
    cmp  al, 0
    je   Bucle_SinJaque
    call UI_MostrarJaque            ; "[!] ¡JAQUE!"

Bucle_SinJaque:

    ; ---- Modo en línea: si no es mi turno, esperar al rival ----
    cmp  modoJuego, MODO_EN_LINEA
    jne  Bucle_EscogerFuente

    call Principal_EsperarRivalSiCorresponde
    cmp  al, 1                      ; AL=1 → movimiento remoto ya aplicado
    je   Bucle_PostMovimiento       ; saltar la lectura de teclado

Bucle_EscogerFuente:

    ; ---- Verificar si el turno lo juega la IA ----
    call Tablero_ObtenerTurno       ; AL = turno actual
    cmp  al, COLOR_NEGRO
    jne  Bucle_TurnoHumano          ; si es blancas, siempre humano
    cmp  turnoIA, 1
    jne  Bucle_TurnoHumano

    ; ---- Turno de la IA ----
    call Principal_TurnoIA
    jmp  Bucle_PostMovimiento

Bucle_TurnoHumano:
    ; ---- Verificar si el usuario solicita pista ----
    call Entrada_SolicitoPista      ; AL = 1 si presionó tecla de pista
    cmp  al, 1
    jne  Bucle_LeerMovimiento

    ; El usuario quiere una pista
    call Principal_ManejarPista
    jmp  Bucle_Inicio               ; redibujar con la pista visible

Bucle_LeerMovimiento:
    ; ---- Leer movimiento UCI del teclado ----
    ; Entrada_LeerMovimientoUCI llena bufferMovUCI con el texto "e2e4"
    mov  eax, OFFSET bufferMovUCI
    call Entrada_LeerMovimientoUCI  ; AL = 1 si hay movimiento válido, 0 si escapó

    cmp  al, 0
    je   Bucle_Inicio               ; ESC o entrada vacía → redibujar

    ; ---- Parsear UCI → índices ----
    call Principal_ParsearUCI       ; llena indiceOrigen e indiceDestino
    cmp  al, 0
    je   Bucle_MovimientoIlegal     ; formato inválido

    ; ---- Validar movimiento ----
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento         ; AL = 1 legal, 0 ilegal
    cmp  al, 0
    je   Bucle_MovimientoIlegal

    ; ---- Aplicar movimiento ----
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    ; ---- Registrar en historial ----
    call Sync_RegistrarMovimiento   ; escribe en moves.log

    jmp  Bucle_PostMovimiento

Bucle_MovimientoIlegal:
    call UI_MostrarMovimientoIlegal
    call WaitMsg                    ; pausa para que el usuario lea el mensaje
    jmp  Bucle_Inicio

Bucle_PostMovimiento:
    ; ---- Actualizar reloj ----
    call UI_ActualizarReloj

    ; ---- Detectar jaque al rey rival ----
    call Tablero_ObtenerTurno       ; AL = turno actual (antes de cambiar)
    xor  al, 1                      ; color rival = contrario al que acaba de mover
    movzx eax, al
    call Tablero_ObtenerPosRey      ; AL = posición del rey rival
    movzx ebx, al                   ; EBX = color rival (para Verificar_ReyEnJaque)
    call Tablero_ObtenerTurno
    xor  al, 1
    movzx ebx, al
    movzx eax, BYTE PTR [indiceDestino] ; re-obtener pos rey desde tabla
    ; Llamada correcta: posición del rey rival
    call Tablero_ObtenerTurno
    xor  al, 1                          ; color rival
    push eax
    movzx eax, al
    call Tablero_ObtenerPosRey          ; AL = índice del rey rival
    movzx eax, al
    pop  ebx                            ; EBX = color rival
    call Verificar_ReyEnJaque           ; AL = 1 si en jaque

    cmp  al, 1
    jne  Bucle_SinJaquePost

    ; Hay jaque al rival: actualizar bandera
    call Tablero_ObtenerTurno
    xor  al, 1                      ; color del rey en jaque
    inc  al                         ; bandera: 1=jaque blancas, 2=jaque negras
    call Tablero_EstablecerJaque

    ; ---- Verificar jaque mate ----
    call Tablero_ObtenerTurno
    xor  al, 1                      ; color del rey en jaque
    call Verificar_JaqueMate        ; AL = 1 si hay jaque mate
    cmp  al, 1
    jne  Bucle_SinJaquePost

    ; Jaque mate: determinar ganador y actualizar estado
    call Tablero_ObtenerTurno       ; AL = turno del que acaba de mover
    cmp  al, COLOR_BLANCO
    je   Bucle_GananBlancas

    ; Ganan las negras
    mov  al, ESTADO_GANA_NEGRAS
    call Tablero_EstablecerEstado
    call UI_MostrarJaqueMate
    jmp  Bucle_SincronizarFin

Bucle_GananBlancas:
    mov  al, ESTADO_GANA_BLANCAS
    call Tablero_EstablecerEstado
    call UI_MostrarJaqueMate
    jmp  Bucle_SincronizarFin

Bucle_SinJaquePost:
    ; Sin jaque: limpiar bandera de jaque
    mov  al, 0
    call Tablero_EstablecerJaque

    ; ---- Verificar tablas (ahogado) ----
    call Tablero_ObtenerTurno
    xor  al, 1                      ; color rival
    call Verificar_Tablas           ; AL = 1 si tablas
    cmp  al, 1
    jne  Bucle_CambiarTurno

    mov  al, ESTADO_TABLAS
    call Tablero_EstablecerEstado
    call UI_MostrarTablas
    jmp  Bucle_SincronizarFin

Bucle_CambiarTurno:
    call Tablero_CambiarTurno       ; alterna turno e incrementa contador

Bucle_SincronizarFin:
    ; ---- Sincronizar si modo en línea ----
    cmp  modoJuego, MODO_EN_LINEA
    jne  Bucle_Inicio
    call Sync_PublicarEstado        ; actualiza game_state.json en Firebase

    jmp  Bucle_Inicio               ; siguiente iteración

Bucle_FinPartida:
    ; Mostrar resultado final y esperar tecla
    call UI_MostrarTablero
    call WaitMsg

    pop  ecx
    pop  ebx
    pop  eax
    pop  ebp
    ret
Principal_BucleJuego ENDP


; ===========================================================================
; Procedimiento : Principal_ParsearUCI
; Descripción   : Interpreta los 4 bytes de bufferMovUCI ("e2e4") y
;                 convierte cada casilla a índice del vector.
;                 Usa Tablero_UCIAIndice de board.asm.
;
; Parámetros    : Ninguno (lee bufferMovUCI)
; Retorna       : AL = 1 si parseó OK, AL = 0 si formato inválido
;                 Escribe indiceOrigen e indiceDestino
; Registros usados: EAX, EBX
; ===========================================================================
Principal_ParsearUCI PROC
    push ebx
    push ecx

    ; bufferMovUCI[0] = columna origen  ('a'-'h')
    ; bufferMovUCI[1] = fila    origen  ('1'-'8')
    ; bufferMovUCI[2] = columna destino ('a'-'h')
    ; bufferMovUCI[3] = fila    destino ('1'-'8')

    ; Validar caracteres de columna (a-h)
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

    ; Validar caracteres de fila (1-8)
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

    ; Convertir origen: AL = col, AH = fila
    mov  al, bufferMovUCI[0]    ; columna origen
    mov  ah, bufferMovUCI[1]    ; fila origen
    call Tablero_UCIAIndice     ; EAX = índice origen
    cmp  eax, 0FFFFFFFFh
    je   ParsearUCI_Error
    mov  indiceOrigen, eax

    ; Convertir destino: AL = col, AH = fila
    mov  al, bufferMovUCI[2]    ; columna destino
    mov  ah, bufferMovUCI[3]    ; fila destino
    call Tablero_UCIAIndice     ; EAX = índice destino
    cmp  eax, 0FFFFFFFFh
    je   ParsearUCI_Error
    mov  indiceDestino, eax

    mov  al, 1                  ; éxito
    jmp  ParsearUCI_Fin

ParsearUCI_Error:
    mov  al, 0

ParsearUCI_Fin:
    pop  ecx
    pop  ebx
    ret
Principal_ParsearUCI ENDP


; ===========================================================================
; Procedimiento : Principal_TurnoIA
; Descripción   : Solicita al motor externo (engine_connector.asm / ai_service.py)
;                 la mejor jugada para el estado actual, la valida y la aplica.
;                 Si la IA no responde, el turno queda pendiente.
;
; Parámetros    : Ninguno
; Retorna       : Ninguno
; ===========================================================================
Principal_TurnoIA PROC
    push eax
    push ebx

    ; Pedir jugada al motor externo (escribe hint.json y lee bestMove)
    call Motor_SolicitarJugada      ; llena bufferMovUCI con la jugada sugerida

    ; Parsear la jugada devuelta
    call Principal_ParsearUCI       ; AL = 1 si OK
    cmp  al, 0
    je   TurnoIA_Error              ; motor no respondió o formato inválido

    ; Validar (por seguridad, aunque el motor debería dar jugadas legales)
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Validar_Movimiento
    cmp  al, 0
    je   TurnoIA_Error

    ; Aplicar
    mov  eax, indiceOrigen
    mov  ebx, indiceDestino
    call Tablero_MoverPieza

    ; Registrar en historial
    call Sync_RegistrarMovimiento

    jmp  TurnoIA_Fin

TurnoIA_Error:
    ; Si el motor falla, se deja el turno al humano en la próxima iteración
    ; (no se cambia turno → el jugador puede introducir manualmente)

TurnoIA_Fin:
    pop  ebx
    pop  eax
    ret
Principal_TurnoIA ENDP


; ===========================================================================
; Procedimiento : Principal_ManejarPista
; Descripción   : Gestiona la solicitud de pista del jugador humano.
;                 Verifica que queden pistas disponibles (máx. 3 por partida),
;                 consulta al motor externo y muestra la jugada sugerida en UI.
;
; Parámetros    : Ninguno
; Retorna       : Ninguno
; ===========================================================================
Principal_ManejarPista PROC
    push eax

    ; Verificar si quedan pistas
    movzx eax, pistasUsadas
    cmp  eax, MAX_PISTAS
    jae  Pista_Agotadas

    ; Solicitar pista al motor (escribe hint.json)
    call Motor_SolicitarPista

    ; Leer la mejor jugada calculada
    call Motor_ObtenerMejorMovimiento   ; llena bufferMovUCI con bestMove

    ; Mostrar la pista en la UI (ui_console.asm la lee de bufferMovUCI)
    call UI_MostrarPista

    ; Incrementar contador de pistas usadas
    inc  pistasUsadas
    jmp  Pista_Fin

Pista_Agotadas:
    call UI_MostrarPistasAgotadas

Pista_Fin:
    pop  eax
    ret
Principal_ManejarPista ENDP


; ===========================================================================
; Procedimiento : Principal_EsperarRivalSiCorresponde
; Descripción   : En modo en línea, verifica si es el turno del rival remoto.
;                 Si es así, hace polling a Firebase hasta recibir un movimiento
;                 nuevo, lo aplica al tablero y retorna AL=1.
;                 Si es turno propio, retorna AL=0 sin bloquear.
;
; Parámetros    : Ninguno
; Retorna       : AL = 1 si se aplicó movimiento remoto
;                 AL = 0 si es turno del jugador local
; ===========================================================================
Principal_EsperarRivalSiCorresponde PROC
    push ebx
    push ecx

    ; Determinar si el turno actual corresponde al rival remoto
    ; Convención: este cliente siempre juega con blancas (COLOR_BLANCO=0)
    ; Si el turno es de negras → esperar al rival
    call Tablero_ObtenerTurno       ; AL = turno actual
    cmp  al, COLOR_NEGRO
    jne  Esperar_EsTurnoLocal       ; si es blancas, es turno local

    ; Mostrar mensaje de espera
    call UI_LimpiarPantalla
    call UI_MostrarTablero
    mov  eax, OFFSET msgEsperandoRival
    call WriteString

Esperar_PollLoop:
    ; Consultar Firebase: ¿hay nueva versión del estado?
    call Sync_VerificarActualizacion ; AL = 1 si hay actualización
    cmp  al, 1
    jne  Esperar_PollLoop           ; sin novedad → seguir esperando

    ; Leer el nuevo estado remoto (incluye lastMove en bufferMovUCI)
    call Sync_LeerEstadoRemoto

    ; Parsear y aplicar el movimiento remoto
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

    mov  al, 1                      ; AL = 1: movimiento remoto aplicado
    jmp  Esperar_Fin

Esperar_ErrorRemoto:
    ; Estado remoto inválido: ignorar y seguir esperando
    jmp  Esperar_PollLoop

Esperar_EsTurnoLocal:
    mov  al, 0                      ; AL = 0: es turno local

Esperar_Fin:
    pop  ecx
    pop  ebx
    ret
Principal_EsperarRivalSiCorresponde ENDP

END main