; ===========================================================================
; sync_manager.asm — Módulo Puente entre MASM y Servicio Python
;
; Responsabilidades:
;   - Lanzar sync_service.py como proceso hijo (CreateProcessA)
;   - Coordinar la publicación del estado local a Firebase (upload)
;   - Coordinar la descarga del estado remoto desde Firebase (download)
;   - Detectar actualizaciones remotas leyendo sync_flag.txt (polling)
;   - Registrar movimientos en moves.log y actualizar game_state.json
;
; Flujo de sincronización:
;   1. MASM escribe game_state.json con Archivo_EscribirEstado
;   2. MASM lanza "python sync_service.py upload" como proceso hijo
;   3. Python lee game_state.json y lo sube a Firebase
;   4. Para recibir: Python (en modo listen) descarga el estado y
;      escribe sync_flag.txt = "1"
;   5. MASM detecta sync_flag.txt = "1" con polling
;   6. MASM lee game_state.json actualizado con Archivo_LeerEstado
;
; Dependencias:
;   - file_manager.asm (Archivo_EscribirEstado, Archivo_LeerEstado, etc.)
;   - Irvine32.inc
;   - Win32 API: CreateProcessA, WaitForSingleObject, CloseHandle, Sleep
; ===========================================================================

INCLUDE Irvine32.inc

; ---------------------------------------------------------------------------
; Constantes Win32
; ---------------------------------------------------------------------------
INFINITE_WAIT       EQU 0FFFFFFFFh
NORMAL_PRIORITY     EQU 00000020h
STARTF_USESHOWWINDOW EQU 00000001h
SW_HIDE             EQU 0
WAIT_TIMEOUT        EQU 00000102h

; Tiempo de espera entre polls (milisegundos)
POLL_INTERVAL_MS    EQU 1000       ; 1 segundo
; Tiempo máximo de espera para proceso hijo (ms)
PROCESS_TIMEOUT_MS  EQU 15000      ; 15 segundos

; ---------------------------------------------------------------------------
; Estructuras Win32 para CreateProcessA
; ---------------------------------------------------------------------------
STARTUPINFO STRUCT
    cb              DWORD ?
    lpReserved      DWORD ?
    lpDesktop       DWORD ?
    lpTitle         DWORD ?
    dwX             DWORD ?
    dwY             DWORD ?
    dwXSize         DWORD ?
    dwYSize         DWORD ?
    dwXCountChars   DWORD ?
    dwYCountChars   DWORD ?
    dwFillAttribute DWORD ?
    dwFlags         DWORD ?
    wShowWindow     WORD  ?
    cbReserved2     WORD  ?
    lpReserved2     DWORD ?
    hStdInput       DWORD ?
    hStdOutput      DWORD ?
    hStdError       DWORD ?
STARTUPINFO ENDS

PROCESS_INFORMATION STRUCT
    hProcess    DWORD ?
    hThread     DWORD ?
    dwProcessId DWORD ?
    dwThreadId  DWORD ?
PROCESS_INFORMATION ENDS

; ---------------------------------------------------------------------------
; Prototipos Win32
; ---------------------------------------------------------------------------
CreateProcessA PROTO,
    lpAppName:PTR BYTE,
    lpCmdLine:PTR BYTE,
    lpProcAttr:DWORD,
    lpThreadAttr:DWORD,
    bInheritHandles:DWORD,
    dwCreationFlags:DWORD,
    lpEnvironment:DWORD,
    lpCurrentDir:DWORD,
    lpStartupInfo:PTR STARTUPINFO,
    lpProcInfo:PTR PROCESS_INFORMATION

WaitForSingleObject PROTO,
    hHandle:DWORD,
    dwMilliseconds:DWORD

CloseHandle PROTO,
    hObject:DWORD

Sleep PROTO,
    dwMilliseconds:DWORD

; ---------------------------------------------------------------------------
; Referencias externas — file_manager.asm
; ---------------------------------------------------------------------------
EXTERNDEF archivoGameId    : BYTE
EXTERNDEF archivoVersion   : DWORD
EXTERNDEF archivoTurno     : BYTE
EXTERNDEF archivoFEN       : BYTE
EXTERNDEF archivoLastMove  : BYTE
EXTERNDEF archivoStatus    : BYTE
EXTERNDEF archivoUpdatedAt : BYTE

Archivo_InicializarEstado    PROTO
Archivo_EscribirEstado       PROTO
Archivo_LeerEstado           PROTO
Archivo_ActualizarLastMove   PROTO
Archivo_RegistrarMovimiento  PROTO
Archivo_LeerBandera          PROTO
Archivo_EscribirBandera      PROTO
Archivo_GenerarFEN           PROTO
Archivo_IncrementarVersion   PROTO

; Referencias externas — board.asm
Tablero_ObtenerTurno               PROTO
Tablero_ObtenerContadorMovimientos PROTO

; ===========================================================================
;                       SEGMENTO DE DATOS
; ===========================================================================
.data

; --- Comandos para lanzar Python ---
; sync_service.py
cmdUpload       BYTE "python services\sync_service.py upload", 0
cmdDownload     BYTE "python services\sync_service.py download", 0
cmdListen       BYTE "python services\sync_service.py listen", 0

; --- Estructuras Win32 ---
si              STARTUPINFO <>
pi              PROCESS_INFORMATION <>

; --- Buffer para último movimiento UCI (compartido con main) ---
PUBLIC syncLastMove
syncLastMove    BYTE 8 DUP(0)

; --- Estado interno del módulo ---
syncActiva      BYTE 0         ; 1 si la sincronización está activa
listenProcHandle DWORD 0       ; Handle del proceso listen en background

; --- Mensajes de consola ---
msgSyncOk       BYTE "  [SYNC] Sincronizacion exitosa.", 0Dh, 0Ah, 0
msgSyncErr      BYTE "  [SYNC] Error de sincronizacion.", 0Dh, 0Ah, 0
msgSyncDetect   BYTE "  [SYNC] Cambio detectado.", 0Dh, 0Ah, 0

; ===========================================================================
;                       SEGMENTO DE CÓDIGO
; ===========================================================================
.code

PUBLIC Sync_IniciarSesion
PUBLIC Sync_PublicarEstado
PUBLIC Sync_LeerEstadoRemoto
PUBLIC Sync_RegistrarMovimiento
PUBLIC Sync_VerificarActualizacion


; ===========================================================================
; Procedimiento: Sync_IniciarSesion
; Descripción : Inicializa la sincronización al comenzar una partida online.
;               1. Inicializa el estado del archivo con valores por defecto
;               2. Escribe game_state.json inicial
;               3. Sube el estado a Firebase (upload)
;               4. Lanza el proceso Python en modo listen (background)
;               5. Limpia la bandera sync_flag.txt
;
; Parámetros  : Ninguno
; Retorna     : AL = 1 si éxito, 0 si error
; ===========================================================================
Sync_IniciarSesion PROC
    push ebx
    push ecx
    push edx

    ; Marcar sincronización como activa
    mov  syncActiva, 1

    ; Inicializar estado de la partida
    call Archivo_InicializarEstado

    ; Escribir game_state.json inicial
    call Archivo_EscribirEstado
    cmp  al, 0
    je   IniciarSesion_Error

    ; Limpiar bandera
    mov  al, '0'
    call Archivo_EscribirBandera

    ; Subir estado inicial a Firebase
    lea  edx, cmdUpload
    call Sync_LanzarProceso
    cmp  al, 0
    je   IniciarSesion_Error

    ; Lanzar listener en background (no esperamos a que termine)
    call Sync_LanzarListener

    mov  al, 1
    jmp  IniciarSesion_Fin

IniciarSesion_Error:
    mov  al, 0

IniciarSesion_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_IniciarSesion ENDP


; ===========================================================================
; Procedimiento: Sync_PublicarEstado
; Descripción : Publica el estado actual de la partida en Firebase.
;               1. Incrementa la versión
;               2. Actualiza FEN y turno
;               3. Escribe game_state.json
;               4. Lanza "python sync_service.py upload"
;
; Parámetros  : Ninguno
; Retorna     : AL = 1 si éxito, 0 si error
; ===========================================================================
Sync_PublicarEstado PROC
    push ebx
    push ecx
    push edx

    ; Verificar que sincronización esté activa
    cmp  syncActiva, 0
    je   PublicarEst_Skip

    ; Incrementar versión
    call Archivo_IncrementarVersion

    ; Escribir game_state.json actualizado
    call Archivo_EscribirEstado
    cmp  al, 0
    je   PublicarEst_Error

    ; Lanzar proceso de upload
    lea  edx, cmdUpload
    call Sync_LanzarProceso
    cmp  al, 0
    je   PublicarEst_Error

    mov  al, 1
    jmp  PublicarEst_Fin

PublicarEst_Error:
    mov  al, 0
    jmp  PublicarEst_Fin

PublicarEst_Skip:
    mov  al, 1                 ; no es error, simplemente no hay sync

PublicarEst_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_PublicarEstado ENDP


; ===========================================================================
; Procedimiento: Sync_LeerEstadoRemoto
; Descripción : Lee el estado remoto que ya fue descargado por el listener.
;               El listener (sync_service.py listen) ya escribió el
;               game_state.json actualizado cuando detectó cambios.
;               Este procedimiento solo necesita leer el archivo local.
;
;               También copia el lastMove del estado remoto a syncLastMove
;               para que main.asm pueda parsearlo como movimiento UCI.
;
; Parámetros  : Ninguno
; Retorna     : AL = 1 si éxito, 0 si error
; ===========================================================================
Sync_LeerEstadoRemoto PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Leer game_state.json actualizado por el listener
    call Archivo_LeerEstado
    cmp  al, 0
    je   LeerRemoto_Error

    ; Copiar lastMove a syncLastMove para que main pueda parsearlo
    lea  esi, archivoLastMove
    lea  edi, syncLastMove
    mov  al, [esi+0]
    mov  [edi+0], al
    mov  al, [esi+1]
    mov  [edi+1], al
    mov  al, [esi+2]
    mov  [edi+2], al
    mov  al, [esi+3]
    mov  [edi+3], al
    mov  BYTE PTR [edi+4], 0

    ; Limpiar bandera después de procesar
    mov  al, '0'
    call Archivo_EscribirBandera

    mov  al, 1
    jmp  LeerRemoto_Fin

LeerRemoto_Error:
    mov  al, 0

LeerRemoto_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_LeerEstadoRemoto ENDP


; ===========================================================================
; Procedimiento: Sync_RegistrarMovimiento
; Descripción : Registra un movimiento en moves.log y actualiza el
;               campo lastMove en el estado.
;               Se llama después de cada movimiento exitoso (humano o IA).
;
; Parámetros  : Ninguno (usa bufferMovUCI de main.asm indirectamente;
;               el lastMove ya fue seteado por main antes de llamar aquí)
;
; Nota: main.asm debe llamar Archivo_ActualizarLastMove ANTES de llamar
;       este procedimiento, o pasar EDX = puntero al movimiento UCI.
;       Por simplicidad, este proc lee archivoLastMove directamente.
; ===========================================================================
Sync_RegistrarMovimiento PROC
    push eax
    push edx

    ; Registrar en moves.log
    lea  edx, archivoLastMove
    call Archivo_RegistrarMovimiento

    pop  edx
    pop  eax
    ret
Sync_RegistrarMovimiento ENDP


; ===========================================================================
; Procedimiento: Sync_VerificarActualizacion
; Descripción : Verifica si hay un nuevo estado remoto disponible.
;               Lee sync_flag.txt — si contiene '1', hay actualización.
;               Incluye un Sleep para no saturar el CPU en el loop de polling.
;
; Parámetros  : Ninguno
; Retorna     : AL = 1 si hay actualización, 0 si no
; ===========================================================================
Sync_VerificarActualizacion PROC
    push ebx
    push ecx
    push edx

    ; Esperar un intervalo antes de verificar (evitar busy-wait)
    INVOKE Sleep, POLL_INTERVAL_MS

    ; Leer bandera
    call Archivo_LeerBandera
    cmp  al, '1'
    jne  VerificarAct_No

    mov  al, 1
    jmp  VerificarAct_Fin

VerificarAct_No:
    mov  al, 0

VerificarAct_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_VerificarActualizacion ENDP


; ===========================================================================
;           PROCEDIMIENTOS INTERNOS — Gestión de Procesos Win32
; ===========================================================================

; ===========================================================================
; Sync_LanzarProceso — Lanza un comando como proceso hijo y espera
;                       a que termine (bloqueante).
;
; Parámetros: EDX = puntero al comando (ej: "python sync_service.py upload")
; Retorna   : AL = 1 si el proceso se ejecutó correctamente, 0 si error
; ===========================================================================
Sync_LanzarProceso PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi                   ; FIX: preservar EDI (usado por rep stosb)

    mov  esi, edx              ; ESI = comando

    ; --- Inicializar STARTUPINFO ---
    ; Limpiar estructura a ceros
    lea  edi, si
    mov  ecx, SIZEOF STARTUPINFO
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    ; Configurar campos necesarios
    mov  si.cb, SIZEOF STARTUPINFO
    mov  si.dwFlags, STARTF_USESHOWWINDOW
    mov  si.wShowWindow, SW_HIDE   ; ocultar ventana del proceso

    ; --- Inicializar PROCESS_INFORMATION a ceros ---
    lea  edi, pi
    mov  ecx, SIZEOF PROCESS_INFORMATION
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    ; --- Crear proceso ---
    INVOKE CreateProcessA,
        NULL,                  ; lpApplicationName (NULL = usar cmdLine)
        esi,                   ; lpCommandLine
        NULL,                  ; lpProcessAttributes
        NULL,                  ; lpThreadAttributes
        0,                     ; bInheritHandles = FALSE
        NORMAL_PRIORITY,       ; dwCreationFlags
        NULL,                  ; lpEnvironment (heredar)
        NULL,                  ; lpCurrentDirectory (heredar)
        ADDR si,               ; lpStartupInfo
        ADDR pi                ; lpProcessInformation

    cmp  eax, 0
    je   LanzarProc_Error

    ; --- Esperar a que el proceso termine ---
    INVOKE WaitForSingleObject,
        pi.hProcess,
        PROCESS_TIMEOUT_MS

    ; --- Cerrar handles ---
    INVOKE CloseHandle, pi.hThread
    INVOKE CloseHandle, pi.hProcess

    mov  al, 1
    jmp  LanzarProc_Fin

LanzarProc_Error:
    mov  al, 0

LanzarProc_Fin:
    pop  edi                   ; FIX: restaurar EDI
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_LanzarProceso ENDP


; ===========================================================================
; Sync_LanzarListener — Lanza "python sync_service.py listen" en background.
;                        NO espera a que termine (el listener corre
;                        indefinidamente haciendo polling a Firebase).
;                        Guarda el handle del proceso para poder cerrarlo
;                        cuando la partida termine.
;
; Parámetros: Ninguno
; Retorna   : AL = 1 si éxito, 0 si error
; ===========================================================================
Sync_LanzarListener PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi                   ; FIX: preservar EDI

    ; --- Inicializar STARTUPINFO ---
    lea  edi, si
    mov  ecx, SIZEOF STARTUPINFO
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    mov  si.cb, SIZEOF STARTUPINFO
    mov  si.dwFlags, STARTF_USESHOWWINDOW
    mov  si.wShowWindow, SW_HIDE

    ; --- Inicializar PROCESS_INFORMATION ---
    lea  edi, pi
    mov  ecx, SIZEOF PROCESS_INFORMATION
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    ; --- Crear proceso listener ---
    INVOKE CreateProcessA,
        NULL,
        ADDR cmdListen,
        NULL,
        NULL,
        0,
        NORMAL_PRIORITY,
        NULL,
        NULL,
        ADDR si,
        ADDR pi

    cmp  eax, 0
    je   LanzarListen_Error

    ; Guardar handle del proceso (NO cerrarlo, lo necesitamos vivo)
    mov  eax, pi.hProcess
    mov  listenProcHandle, eax

    ; Cerrar handle del hilo (no lo necesitamos)
    INVOKE CloseHandle, pi.hThread

    mov  al, 1
    jmp  LanzarListen_Fin

LanzarListen_Error:
    mov  al, 0

LanzarListen_Fin:
    pop  edi                   ; FIX: restaurar EDI
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_LanzarListener ENDP

END