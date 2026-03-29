; ===========================================================================
; sync_manager.asm — Modulo Puente MASM <-> Python (con Subespacios a/b)
;
; CORRECCIONES APLICADAS:
;   1. Variables "si" y "pi" renombradas a "startInf" y "procInf"
;      porque "si" es palabra reservada en MASM (registro SI de 16 bits).
;   2. Estructuras renombradas a STARTUPINFO_S y PROCESS_INFO_S para
;      evitar conflictos si windows.inc las define parcialmente.
;   3. Prototipos Win32 declarados con DWORD puro para evitar
;      "INVOKE argument type mismatch".
;   4. Constantes renombradas para evitar colisiones con windows.inc.
; ===========================================================================

INCLUDE Irvine32.inc

; ---------------------------------------------------------------------------
; Constantes Win32 (nombres unicos para no chocar con includes)
; ---------------------------------------------------------------------------
INFINITE_WAIT           EQU 0FFFFFFFFh
NORMAL_PRIORITY_CLS     EQU 00000020h
STARTF_USE_SHOWWINDOW   EQU 00000001h
SW_HIDE_WIN             EQU 0

POLL_INTERVAL_MS        EQU 1000
PROCESS_TIMEOUT_MS      EQU 15000

; ---------------------------------------------------------------------------
; Estructuras Win32 (nombres propios para evitar conflictos)
; ---------------------------------------------------------------------------
STARTUPINFO_S STRUCT
    sCb              DWORD ?
    sReserved        DWORD ?
    sDesktop         DWORD ?
    sTitle           DWORD ?
    sDwX             DWORD ?
    sDwY             DWORD ?
    sDwXSize         DWORD ?
    sDwYSize         DWORD ?
    sDwXCountChars   DWORD ?
    sDwYCountChars   DWORD ?
    sDwFillAttr      DWORD ?
    sDwFlags         DWORD ?
    sShowWindow      WORD  ?
    sCbReserved2     WORD  ?
    sReserved2       DWORD ?
    sStdInput        DWORD ?
    sStdOutput       DWORD ?
    sStdError        DWORD ?
STARTUPINFO_S ENDS

PROCESS_INFO_S STRUCT
    piProcess    DWORD ?
    piThread     DWORD ?
    piProcessId  DWORD ?
    piThreadId   DWORD ?
PROCESS_INFO_S ENDS

; ---------------------------------------------------------------------------
; Prototipos Win32 (todos los parametros como DWORD para evitar mismatch)
; ---------------------------------------------------------------------------
CreateProcessA PROTO,
    lpAppName:DWORD, lpCmdLine:DWORD,
    lpProcAttr:DWORD, lpThreadAttr:DWORD,
    bInheritHandles:DWORD, dwCreationFlags:DWORD,
    lpEnvironment:DWORD, lpCurrentDir:DWORD,
    lpStartupInfo:DWORD,
    lpProcInfo:DWORD

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

; --- Plantillas de comandos ---
cmdBase         BYTE "python services\sync_service.py ", 0

; Sufijos de comando
sufUpload       BYTE "upload ", 0
sufDownload     BYTE "download ", 0
sufListen       BYTE "listen ", 0

; Buffer donde se construye el comando completo
cmdBuffer       BYTE 80 DUP(0)

; --- Estructuras Win32 (nombres que NO son palabras reservadas) ---
startInf        STARTUPINFO_S <>
procInf         PROCESS_INFO_S <>

; --- Rol del cliente: 'a' o 'b' (seteado por main.asm) ---
PUBLIC syncRolCliente
syncRolCliente  BYTE 'a'

; --- Buffer para ultimo movimiento UCI (compartido con main) ---
PUBLIC syncLastMove
syncLastMove    BYTE 8 DUP(0)

; --- Estado interno ---
syncActiva      BYTE 0
listenProcHandle DWORD 0

; --- Mensajes ---
msgSyncOk       BYTE "  [SYNC] Sincronizacion exitosa.", 0Dh, 0Ah, 0
msgSyncErr      BYTE "  [SYNC] Error de sincronizacion.", 0Dh, 0Ah, 0

; ===========================================================================
;                       SEGMENTO DE CODIGO
; ===========================================================================
.code

PUBLIC Sync_IniciarSesion
PUBLIC Sync_PublicarEstado
PUBLIC Sync_LeerEstadoRemoto
PUBLIC Sync_RegistrarMovimiento
PUBLIC Sync_VerificarActualizacion


; ===========================================================================
; Sync_ConstruirComando — Construye el comando completo en cmdBuffer.
; Parametros: ESI = puntero al sufijo (ej: "upload ", "listen ")
; ===========================================================================
Sync_ConstruirComando PROC
    push eax
    push esi
    push edi

    lea  edi, cmdBuffer

    ; Copiar base
    push esi
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
    pop  esi

    ; Copiar sufijo
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
; Sync_PrepararEstructuras — Limpia startInf y procInf, configura para
;                             ocultar la ventana del proceso hijo.
; ===========================================================================
Sync_PrepararEstructuras PROC
    push eax
    push ecx
    push edi

    ; Limpiar STARTUPINFO_S con ceros
    lea  edi, startInf
    mov  ecx, SIZEOF STARTUPINFO_S
    xor  al, al
    rep  stosb

    ; Configurar campos
    mov  startInf.sCb, SIZEOF STARTUPINFO_S
    mov  startInf.sDwFlags, STARTF_USE_SHOWWINDOW
    mov  startInf.sShowWindow, SW_HIDE_WIN

    ; Limpiar PROCESS_INFO_S con ceros
    lea  edi, procInf
    mov  ecx, SIZEOF PROCESS_INFO_S
    xor  al, al
    rep  stosb

    pop  edi
    pop  ecx
    pop  eax
    ret
Sync_PrepararEstructuras ENDP


; ===========================================================================
; Sync_IniciarSesion
; ===========================================================================
Sync_IniciarSesion PROC
    push ebx
    push ecx
    push edx

    mov  syncActiva, 1

    call Archivo_InicializarEstado
    call Archivo_EscribirEstado
    cmp  al, 0
    je   IniciarSesion_Error

    mov  al, '0'
    call Archivo_EscribirBandera

    ; Subir estado inicial
    lea  esi, sufUpload
    call Sync_ConstruirComando
    lea  edx, cmdBuffer
    call Sync_LanzarProceso
    cmp  al, 0
    je   IniciarSesion_Error

    ; Lanzar listener en background
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
; Sync_LanzarProceso — Lanza comando (en EDX) como proceso hijo y espera.
; Retorna: AL = 1 exito, 0 error
; ===========================================================================
Sync_LanzarProceso PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov  esi, edx

    ; Preparar estructuras Win32
    call Sync_PrepararEstructuras

    ; Crear proceso hijo
    INVOKE CreateProcessA,
        NULL, esi, NULL, NULL, 0,
        NORMAL_PRIORITY_CLS, NULL, NULL,
        ADDR startInf, ADDR procInf

    cmp  eax, 0
    je   LanzarProc_Error

    ; Esperar a que termine
    INVOKE WaitForSingleObject, procInf.piProcess, PROCESS_TIMEOUT_MS

    ; Cerrar handles
    INVOKE CloseHandle, procInf.piThread
    INVOKE CloseHandle, procInf.piProcess

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
; Retorna: AL = 1 exito, 0 error
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

    ; Preparar estructuras Win32
    call Sync_PrepararEstructuras

    ; Crear proceso en background (NO esperamos)
    INVOKE CreateProcessA,
        NULL, ADDR cmdBuffer, NULL, NULL, 0,
        NORMAL_PRIORITY_CLS, NULL, NULL,
        ADDR startInf, ADDR procInf

    cmp  eax, 0
    je   LanzarListen_Error

    ; Guardar handle del proceso
    mov  eax, procInf.piProcess
    mov  listenProcHandle, eax

    ; Cerrar handle del thread (no lo necesitamos)
    INVOKE CloseHandle, procInf.piThread

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