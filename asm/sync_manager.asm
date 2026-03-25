; ===========================================================================
; sync_manager.asm — Módulo Puente MASM ↔ Python (con Subespacios a/b)
;
; Sistema de subespacios:
;   Cada cliente tiene un rol: 'a' o 'b'.
;   - Cliente A escribe en /cliente_a/ y lee de /cliente_b/
;   - Cliente B escribe en /cliente_b/ y lee de /cliente_a/
;   Los comandos Python ahora incluyen el rol:
;     "python services\sync_service.py upload a"
;     "python services\sync_service.py listen b"
;
; Dependencias:
;   - file_manager.asm
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

POLL_INTERVAL_MS    EQU 1000
PROCESS_TIMEOUT_MS  EQU 15000

; ---------------------------------------------------------------------------
; Estructuras Win32
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
    lpAppName:PTR BYTE, lpCmdLine:PTR BYTE,
    lpProcAttr:DWORD, lpThreadAttr:DWORD,
    bInheritHandles:DWORD, dwCreationFlags:DWORD,
    lpEnvironment:DWORD, lpCurrentDir:DWORD,
    lpStartupInfo:PTR STARTUPINFO,
    lpProcInfo:PTR PROCESS_INFORMATION

WaitForSingleObject PROTO, hHandle:DWORD, dwMilliseconds:DWORD
CloseHandle PROTO, hObject:DWORD
Sleep PROTO, dwMilliseconds:DWORD

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

Tablero_ObtenerTurno               PROTO
Tablero_ObtenerContadorMovimientos PROTO

; ===========================================================================
;                       SEGMENTO DE DATOS
; ===========================================================================
.data

; --- Plantillas de comandos (sin rol, se completan en runtime) ---
; El formato final será: "python services\sync_service.py upload a\0"
; Usamos buffers de 64 bytes para construir el comando completo.

cmdBase         BYTE "python services\sync_service.py ", 0

; Sufijos de comando (se concatenan después del base + comando + espacio + rol)
sufUpload       BYTE "upload ", 0
sufDownload     BYTE "download ", 0
sufListen       BYTE "listen ", 0

; Buffer donde se construye el comando completo antes de lanzar
cmdBuffer       BYTE 80 DUP(0)

; --- Estructuras Win32 ---
si              STARTUPINFO <>
pi              PROCESS_INFORMATION <>

; --- Rol del cliente: 'a' o 'b' (seteado por main.asm) ---
PUBLIC syncRolCliente
syncRolCliente  BYTE 'a'           ; por defecto 'a', main.asm lo cambia

; --- Buffer para último movimiento UCI (compartido con main) ---
PUBLIC syncLastMove
syncLastMove    BYTE 8 DUP(0)

; --- Estado interno ---
syncActiva      BYTE 0
listenProcHandle DWORD 0

; --- Mensajes ---
msgSyncOk       BYTE "  [SYNC] Sincronizacion exitosa.", 0Dh, 0Ah, 0
msgSyncErr      BYTE "  [SYNC] Error de sincronizacion.", 0Dh, 0Ah, 0

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
; Sync_ConstruirComando — Construye el comando completo en cmdBuffer.
;
; Formato: "python services\sync_service.py <sufijo><rol>\0"
;
; Parámetros: ESI = puntero al sufijo (ej: "upload ", "listen ")
; Usa:        syncRolCliente para agregar 'a' o 'b' al final
; Resultado:  cmdBuffer contiene el comando listo para CreateProcessA
; ===========================================================================
Sync_ConstruirComando PROC
    push eax
    push esi
    push edi

    ; Destino: cmdBuffer
    lea  edi, cmdBuffer

    ; Copiar base: "python services\sync_service.py "
    push esi                   ; guardar sufijo
    lea  esi, cmdBase
Cmd_CopiarBase:
    mov  al, [esi]
    cmp  al, 0
    je   Cmd_BaseDone
    mov  [edi], al
    inc  esi
    inc  edi
    jmp  Cmd_CopiarBase
Cmd_BaseDone:
    pop  esi                   ; restaurar sufijo

    ; Copiar sufijo: "upload " o "listen " etc.
Cmd_CopiarSufijo:
    mov  al, [esi]
    cmp  al, 0
    je   Cmd_SufijoDone
    mov  [edi], al
    inc  esi
    inc  edi
    jmp  Cmd_CopiarSufijo
Cmd_SufijoDone:

    ; Agregar rol: 'a' o 'b'
    mov  al, syncRolCliente
    mov  [edi], al
    inc  edi

    ; Null terminator
    mov  BYTE PTR [edi], 0

    pop  edi
    pop  esi
    pop  eax
    ret
Sync_ConstruirComando ENDP


; ===========================================================================
; Sync_IniciarSesion
; ===========================================================================
Sync_IniciarSesion PROC
    push ebx
    push ecx
    push edx

    mov  syncActiva, 1

    ; Inicializar estado de la partida
    call Archivo_InicializarEstado
    call Archivo_EscribirEstado
    cmp  al, 0
    je   IniciarSesion_Error

    ; Limpiar bandera
    mov  al, '0'
    call Archivo_EscribirBandera

    ; Subir estado inicial: "python ... upload a" (o b)
    lea  esi, sufUpload
    call Sync_ConstruirComando
    lea  edx, cmdBuffer
    call Sync_LanzarProceso
    cmp  al, 0
    je   IniciarSesion_Error

    ; Lanzar listener en background: "python ... listen a" (o b)
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
; Sync_PublicarEstado
; ===========================================================================
Sync_PublicarEstado PROC
    push ebx
    push ecx
    push edx

    cmp  syncActiva, 0
    je   PublicarEst_Skip

    call Archivo_IncrementarVersion
    call Archivo_EscribirEstado
    cmp  al, 0
    je   PublicarEst_Error

    ; Construir y lanzar: "python ... upload a"
    lea  esi, sufUpload
    call Sync_ConstruirComando
    lea  edx, cmdBuffer
    call Sync_LanzarProceso
    cmp  al, 0
    je   PublicarEst_Error

    mov  al, 1
    jmp  PublicarEst_Fin

PublicarEst_Error:
    mov  al, 0
    jmp  PublicarEst_Fin

PublicarEst_Skip:
    mov  al, 1

PublicarEst_Fin:
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_PublicarEstado ENDP


; ===========================================================================
; Sync_LeerEstadoRemoto
; ===========================================================================
Sync_LeerEstadoRemoto PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Leer game_state.json (ya actualizado por el listener)
    call Archivo_LeerEstado
    cmp  al, 0
    je   LeerRemoto_Error

    ; Copiar lastMove a syncLastMove
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

    ; Limpiar bandera
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
; Sync_RegistrarMovimiento
; ===========================================================================
Sync_RegistrarMovimiento PROC
    push eax
    push edx

    lea  edx, archivoLastMove
    call Archivo_RegistrarMovimiento

    pop  edx
    pop  eax
    ret
Sync_RegistrarMovimiento ENDP


; ===========================================================================
; Sync_VerificarActualizacion
; ===========================================================================
Sync_VerificarActualizacion PROC
    push ebx
    push ecx
    push edx

    INVOKE Sleep, POLL_INTERVAL_MS

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
; Sync_LanzarProceso — Lanza comando (en EDX) como proceso hijo, espera.
; ===========================================================================
Sync_LanzarProceso PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  esi, edx

    ; Limpiar STARTUPINFO
    lea  edi, si
    mov  ecx, SIZEOF STARTUPINFO
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    mov  si.cb, SIZEOF STARTUPINFO
    mov  si.dwFlags, STARTF_USESHOWWINDOW
    mov  si.wShowWindow, SW_HIDE

    ; Limpiar PROCESS_INFORMATION
    lea  edi, pi
    mov  ecx, SIZEOF PROCESS_INFORMATION
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    INVOKE CreateProcessA,
        NULL, esi, NULL, NULL, 0,
        NORMAL_PRIORITY, NULL, NULL,
        ADDR si, ADDR pi

    cmp  eax, 0
    je   LanzarProc_Error

    INVOKE WaitForSingleObject, pi.hProcess, PROCESS_TIMEOUT_MS
    INVOKE CloseHandle, pi.hThread
    INVOKE CloseHandle, pi.hProcess

    mov  al, 1
    jmp  LanzarProc_Fin

LanzarProc_Error:
    mov  al, 0

LanzarProc_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_LanzarProceso ENDP


; ===========================================================================
; Sync_LanzarListener — Lanza "python ... listen a/b" en background.
; ===========================================================================
Sync_LanzarListener PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; Construir comando: "python ... listen a"
    lea  esi, sufListen
    call Sync_ConstruirComando

    ; Limpiar STARTUPINFO
    lea  edi, si
    mov  ecx, SIZEOF STARTUPINFO
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    mov  si.cb, SIZEOF STARTUPINFO
    mov  si.dwFlags, STARTF_USESHOWWINDOW
    mov  si.wShowWindow, SW_HIDE

    ; Limpiar PROCESS_INFORMATION
    lea  edi, pi
    mov  ecx, SIZEOF PROCESS_INFORMATION
    xor  al, al
    push edi
    rep  stosb
    pop  edi

    INVOKE CreateProcessA,
        NULL, ADDR cmdBuffer, NULL, NULL, 0,
        NORMAL_PRIORITY, NULL, NULL,
        ADDR si, ADDR pi

    cmp  eax, 0
    je   LanzarListen_Error

    mov  eax, pi.hProcess
    mov  listenProcHandle, eax
    INVOKE CloseHandle, pi.hThread

    mov  al, 1
    jmp  LanzarListen_Fin

LanzarListen_Error:
    mov  al, 0

LanzarListen_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Sync_LanzarListener ENDP

END