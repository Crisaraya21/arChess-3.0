; ===========================================================================
; sync_manager.asm - Modulo Puente MASM <-> Python
;
; CAMBIO: Usa cmdPythonSync de path_resolver.asm en vez de rutas
;         hardcodeadas. Funciona en cualquier computadora.
; ===========================================================================

INCLUDE Irvine32.inc

POLL_INTERVAL_MS        EQU 1000
PROCESS_TIMEOUT_MS      EQU 15000
NORMAL_PRIORITY_CLS     EQU 08000020h
STARTF_USE_SHOWWINDOW   EQU 00000001h
SW_HIDE_WIN             EQU 0

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

CreateProcessA PROTO,
    lpAppName:DWORD, lpCmdLine:DWORD,
    lpProcAttr:DWORD, lpThreadAttr:DWORD,
    bInheritHandles:DWORD, dwCreationFlags:DWORD,
    lpEnvironment:DWORD, lpCurrentDir:DWORD,
    lpStartupInfo:DWORD,
    lpProcInfo:DWORD

WaitForSingleObject PROTO, hHandle:DWORD, dwMilliseconds:DWORD
CloseHandle PROTO, hObject:DWORD
TerminateProcess PROTO, hProcess:DWORD, uExitCode:DWORD
Sleep PROTO, dwMilliseconds:DWORD

EXTERNDEF archivoGameId    : BYTE
EXTERNDEF archivoVersion   : DWORD
EXTERNDEF archivoTurno     : BYTE
EXTERNDEF archivoFEN       : BYTE
EXTERNDEF archivoLastMove  : BYTE
EXTERNDEF archivoStatus    : BYTE
EXTERNDEF archivoUpdatedAt : BYTE

; --- Ruta dinamica de path_resolver.asm ---
EXTERNDEF cmdPythonSync    : BYTE

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
.data

sufUpload       BYTE "upload ", 0
sufDownload     BYTE "download ", 0
sufListen       BYTE "listen ", 0

cmdBuffer       BYTE 512 DUP(0)

startInf        STARTUPINFO_S <>
procInf         PROCESS_INFO_S <>

PUBLIC syncRolCliente
syncRolCliente  BYTE 'a'

PUBLIC syncLastMove
syncLastMove    BYTE 8 DUP(0)

syncActiva      BYTE 0
listenProcHandle DWORD 0

msgSyncOk       BYTE "  [SYNC] Sincronizacion exitosa.", 0Dh, 0Ah, 0
msgSyncErr      BYTE "  [SYNC] Error de sincronizacion.", 0Dh, 0Ah, 0

; ===========================================================================
.code

PUBLIC Sync_IniciarSesion
PUBLIC Sync_TerminarSesion
PUBLIC Sync_PublicarEstado
PUBLIC Sync_LeerEstadoRemoto
PUBLIC Sync_RegistrarMovimiento
PUBLIC Sync_VerificarActualizacion

; ===========================================================================
; Sync_ConstruirComando
; Construye: cmdPythonSync + sufijo + rol
; cmdPythonSync ya tiene: python.exe "...\sync_service.py"
; Le concatenamos: upload/download/listen + a/b
; ===========================================================================
Sync_ConstruirComando PROC
    push eax
    push esi
    push edi
    lea  edi, cmdBuffer

    ; Copiar cmdPythonSync (base del comando)
    push esi
    lea  esi, cmdPythonSync
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

    ; Copiar sufijo (upload/download/listen)
Cmd_CopiarSufijo:
    mov  al, [esi]
    cmp  al, 0
    je   Cmd_SufijoDone
    mov  [edi], al
    inc  esi
    inc  edi
    jmp  Cmd_CopiarSufijo
Cmd_SufijoDone:

    ; Agregar rol (a/b)
    mov  al, syncRolCliente
    mov  [edi], al
    inc  edi
    mov  BYTE PTR [edi], 0

    pop  edi
    pop  esi
    pop  eax
    ret
Sync_ConstruirComando ENDP

Sync_PrepararEstructuras PROC
    push eax
    push ecx
    push edi
    lea  edi, startInf
    mov  ecx, SIZEOF STARTUPINFO_S
    xor  al, al
    rep  stosb
    mov  startInf.sCb, SIZEOF STARTUPINFO_S
    mov  startInf.sDwFlags, STARTF_USE_SHOWWINDOW
    mov  startInf.sShowWindow, SW_HIDE_WIN
    lea  edi, procInf
    mov  ecx, SIZEOF PROCESS_INFO_S
    xor  al, al
    rep  stosb
    pop  edi
    pop  ecx
    pop  eax
    ret
Sync_PrepararEstructuras ENDP

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
    lea  esi, sufUpload
    call Sync_ConstruirComando
    lea  edx, cmdBuffer
    call Sync_LanzarProceso
    cmp  al, 0
    je   IniciarSesion_Error
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
; Sync_TerminarSesion
; Termina el proceso listener y libera su handle.
; Llamar al salir del modo online.
; ===========================================================================
Sync_TerminarSesion PROC
    push eax
    cmp  listenProcHandle, 0
    je   TermSesion_Fin
    INVOKE TerminateProcess, listenProcHandle, 0
    INVOKE CloseHandle, listenProcHandle
    mov  listenProcHandle, 0
    mov  syncActiva, 0
TermSesion_Fin:
    pop  eax
    ret
Sync_TerminarSesion ENDP

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

Sync_LeerEstadoRemoto PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi
    call Archivo_LeerEstado
    cmp  al, 0
    je   LeerRemoto_Error
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

Sync_RegistrarMovimiento PROC
    push eax
    push edx
    lea  edx, archivoLastMove
    call Archivo_RegistrarMovimiento
    pop  edx
    pop  eax
    ret
Sync_RegistrarMovimiento ENDP

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

Sync_LanzarProceso PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov  esi, edx
    call Sync_PrepararEstructuras
    INVOKE CreateProcessA,
        NULL, esi, NULL, NULL, 0,
        NORMAL_PRIORITY_CLS, NULL, NULL,
        ADDR startInf, ADDR procInf
    cmp  eax, 0
    je   LanzarProc_Error
    INVOKE WaitForSingleObject, procInf.piProcess, PROCESS_TIMEOUT_MS
    cmp  eax, 0                         ; WAIT_OBJECT_0 = proceso termino ok
    je   LanzarProc_Cerrar
    INVOKE TerminateProcess, procInf.piProcess, 1  ; timeout: matar proceso
LanzarProc_Cerrar:
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

Sync_LanzarListener PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi
    lea  esi, sufListen
    call Sync_ConstruirComando
    call Sync_PrepararEstructuras

    ; --- DEBUG: ver comando construido ---
    mov  edx, OFFSET cmdBuffer
    call WriteString
    call Crlf
    call WaitMsg
    ; --- FIN DEBUG ---

    INVOKE CreateProcessA,
        NULL, ADDR cmdBuffer, NULL, NULL, 0,
        NORMAL_PRIORITY_CLS, NULL, NULL,
        ADDR startInf, ADDR procInf
    cmp  eax, 0
    je   LanzarListen_Error
    mov  eax, procInf.piProcess
    mov  listenProcHandle, eax
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