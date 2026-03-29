; ===========================================================================
; engine_connector.asm - Modulo de Conexion con Motor IA (Persona B Parte 4)
;
; Funcionalidad:
;   - Lanza "python services\ai_service.py" como proceso hijo
;   - Espera a que termine (con timeout)
;   - Lee data\hint.json mediante Archivo_LeerPista (file_manager.asm)
;   - Expone bestMove al modulo main.asm (para modo vs IA)
;   - Expone bestMove al modulo ui_console.asm (para pistas visuales)
;
; Procedimientos exportados:
;   Motor_SolicitarJugada         - modo vs IA
;   Motor_SolicitarPista          - modo pista (hint)
;   Motor_ObtenerMejorMovimiento  - copia bestMove a hintBuf
; ===========================================================================
 
INCLUDE Irvine32.inc
 
; ---------------------------------------------------------------------------
; Constantes Win32
; ---------------------------------------------------------------------------
EC_NORMAL_PRIORITY      EQU 00000020h
EC_STARTF_SHOWWINDOW    EQU 00000001h
EC_SW_HIDE              EQU 0
EC_PROCESS_TIMEOUT      EQU 20000
 
; ---------------------------------------------------------------------------
; Estructuras Win32
; ---------------------------------------------------------------------------
EC_STARTUPINFO STRUCT
    eCb              DWORD ?
    eReserved        DWORD ?
    eDesktop         DWORD ?
    eTitle           DWORD ?
    eDwX             DWORD ?
    eDwY             DWORD ?
    eDwXSize         DWORD ?
    eDwYSize         DWORD ?
    eDwXCountChars   DWORD ?
    eDwYCountChars   DWORD ?
    eDwFillAttr      DWORD ?
    eDwFlags         DWORD ?
    eShowWindow      WORD  ?
    eCbReserved2     WORD  ?
    eReserved2       DWORD ?
    eStdInput        DWORD ?
    eStdOutput       DWORD ?
    eStdError        DWORD ?
EC_STARTUPINFO ENDS
 
EC_PROCESS_INFO STRUCT
    epProcess    DWORD ?
    epThread     DWORD ?
    epProcessId  DWORD ?
    epThreadId   DWORD ?
EC_PROCESS_INFO ENDS
 
; ---------------------------------------------------------------------------
; Prototipos Win32
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
 
; ---------------------------------------------------------------------------
; Referencias externas - file_manager.asm
; ---------------------------------------------------------------------------
EXTERNDEF archivoPista      : BYTE
EXTERNDEF archivoPistaScore : SDWORD
EXTERNDEF archivoPistaDepth : DWORD
 
Archivo_LeerPista       PROTO
Archivo_GenerarFEN      PROTO
Archivo_EscribirEstado  PROTO
 
; ---------------------------------------------------------------------------
; Referencias externas - main.asm
; ---------------------------------------------------------------------------
EXTERNDEF bufferMovUCI : BYTE
 
; ---------------------------------------------------------------------------
; Referencias externas - ui_console.asm
; ---------------------------------------------------------------------------
EXTERNDEF hintBuf : BYTE
 
; ===========================================================================
;                       SEGMENTO DE DATOS
; ===========================================================================
.data
    ; El ..\ es clave porque el script está una carpeta atrás de donde corre el juego
    cmdAIService BYTE '"C:\Users\Usuario\AppData\Local\Programs\Python\Python313\python.exe" ..\services\ai_service.py', 0
 
ecStartInf      EC_STARTUPINFO <>
ecProcInf       EC_PROCESS_INFO <>
 
motorDisponible BYTE 0
motorBestMove   BYTE 8 DUP(0)
 
msgMotorInicio  BYTE "  [IA] Consultando motor de ajedrez...", 0Dh, 0Ah, 0
msgMotorOk      BYTE "  [IA] Jugada obtenida: ", 0
msgMotorError   BYTE "  [IA] Error al obtener jugada.", 0Dh, 0Ah, 0
msgMotorNL      BYTE 0Dh, 0Ah, 0
 
; ===========================================================================
;                       SEGMENTO DE CODIGO
; ===========================================================================
.code
 
PUBLIC Motor_SolicitarJugada
PUBLIC Motor_SolicitarPista
PUBLIC Motor_ObtenerMejorMovimiento
 
 
; ===========================================================================
; EC_PrepararEstructuras
; ===========================================================================
EC_PrepararEstructuras PROC
    push eax
    push ecx
    push edi
 
    lea  edi, ecStartInf
    mov  ecx, SIZEOF EC_STARTUPINFO
    xor  al, al
    rep  stosb
 
    mov  ecStartInf.eCb, SIZEOF EC_STARTUPINFO
    mov  ecStartInf.eDwFlags, EC_STARTF_SHOWWINDOW
    mov  ecStartInf.eShowWindow, EC_SW_HIDE
 
    lea  edi, ecProcInf
    mov  ecx, SIZEOF EC_PROCESS_INFO
    xor  al, al
    rep  stosb
 
    pop  edi
    pop  ecx
    pop  eax
    ret
EC_PrepararEstructuras ENDP
 
 
; ===========================================================================
; EC_LanzarAIService - Lanza ai_service.py y espera
; Retorna: AL = 1 exito, 0 error
; ===========================================================================
EC_LanzarAIService PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi
 
    call EC_PrepararEstructuras
 
    INVOKE CreateProcessA,
        NULL, ADDR cmdAIService, NULL, NULL, 0,
        EC_NORMAL_PRIORITY, NULL, NULL,
        ADDR ecStartInf, ADDR ecProcInf
 
    cmp  eax, 0
    je   LanzarAI_Error
 
    INVOKE WaitForSingleObject, ecProcInf.epProcess, EC_PROCESS_TIMEOUT
 
    INVOKE CloseHandle, ecProcInf.epThread
    INVOKE CloseHandle, ecProcInf.epProcess
 
    mov  al, 1
    jmp  LanzarAI_Fin
 
LanzarAI_Error:
    mov  al, 0
 
LanzarAI_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
EC_LanzarAIService ENDP
 
 
; ===========================================================================
; EC_LeerYCopiarHint - Lee hint.json y copia bestMove
; Retorna: AL = 1 exito, 0 error
; ===========================================================================
EC_LeerYCopiarHint PROC
    push esi
    push edi
 
    call Archivo_LeerPista
    cmp  al, 0
    je   LeerHint_Error
 
    lea  esi, archivoPista
    cmp  BYTE PTR [esi], '0'
    jne  LeerHint_Copiar
    cmp  BYTE PTR [esi+1], '0'
    jne  LeerHint_Copiar
    cmp  BYTE PTR [esi+2], '0'
    jne  LeerHint_Copiar
    cmp  BYTE PTR [esi+3], '0'
    jne  LeerHint_Copiar
    jmp  LeerHint_Error
 
LeerHint_Copiar:
    lea  edi, motorBestMove
    mov  al, [esi+0]
    mov  [edi+0], al
    mov  al, [esi+1]
    mov  [edi+1], al
    mov  al, [esi+2]
    mov  [edi+2], al
    mov  al, [esi+3]
    mov  [edi+3], al
    mov  BYTE PTR [edi+4], 0
 
    mov  motorDisponible, 1
    mov  al, 1
    jmp  LeerHint_Fin
 
LeerHint_Error:
    mov  motorDisponible, 0
    mov  al, 0
 
LeerHint_Fin:
    pop  edi
    pop  esi
    ret
EC_LeerYCopiarHint ENDP
 
 
; ===========================================================================
; Motor_SolicitarJugada - Modo vs IA
;   Actualiza game_state.json, lanza ai_service.py, lee hint.json,
;   copia bestMove a bufferMovUCI para que main.asm lo ejecute.
; Retorna: AL = 1 exito, 0 error
; ===========================================================================
Motor_SolicitarJugada PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi
 
    mov  edx, OFFSET msgMotorInicio
    call WriteString
 
    call Archivo_GenerarFEN
    call Archivo_EscribirEstado
 
    call EC_LanzarAIService
    cmp  al, 0
    je   SolJugada_Error
 
    call EC_LeerYCopiarHint
    cmp  al, 0
    je   SolJugada_Error
 
    lea  esi, motorBestMove
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
 
    mov  edx, OFFSET msgMotorOk
    call WriteString
    mov  edx, OFFSET motorBestMove
    call WriteString
    mov  edx, OFFSET msgMotorNL
    call WriteString
 
    mov  al, 1
    jmp  SolJugada_Fin
 
SolJugada_Error:
    mov  edx, OFFSET msgMotorError
    call WriteString
    mov  al, 0
 
SolJugada_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Motor_SolicitarJugada ENDP
 
 
; ===========================================================================
; Motor_SolicitarPista - Modo pista
;   Igual que SolicitarJugada pero NO copia a bufferMovUCI.
; Retorna: AL = 1 exito, 0 error
; ===========================================================================
Motor_SolicitarPista PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi
 
    mov  edx, OFFSET msgMotorInicio
    call WriteString
 
    call Archivo_GenerarFEN
    call Archivo_EscribirEstado
 
    call EC_LanzarAIService
    cmp  al, 0
    je   SolPista_Error
 
    call EC_LeerYCopiarHint
    cmp  al, 0
    je   SolPista_Error
 
    mov  edx, OFFSET msgMotorOk
    call WriteString
    mov  edx, OFFSET motorBestMove
    call WriteString
    mov  edx, OFFSET msgMotorNL
    call WriteString
 
    mov  al, 1
    jmp  SolPista_Fin
 
SolPista_Error:
    mov  edx, OFFSET msgMotorError
    call WriteString
    mov  al, 0
 
SolPista_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
Motor_SolicitarPista ENDP
 
 
; ===========================================================================
; Motor_ObtenerMejorMovimiento - Copia bestMove a hintBuf de ui_console
; Retorna: AL = 1 hay jugada, 0 no hay
; ===========================================================================
Motor_ObtenerMejorMovimiento PROC
    push esi
    push edi
 
    cmp  motorDisponible, 0
    je   ObtenerMov_NoHay
 
    lea  esi, motorBestMove
    lea  edi, hintBuf
    mov  al, [esi+0]
    mov  [edi+0], al
    mov  al, [esi+1]
    mov  [edi+1], al
    mov  al, [esi+2]
    mov  [edi+2], al
    mov  al, [esi+3]
    mov  [edi+3], al
    mov  BYTE PTR [edi+4], 0
 
    mov  al, 1
    jmp  ObtenerMov_Fin
 
ObtenerMov_NoHay:
    lea  edi, hintBuf
    mov  BYTE PTR [edi+0], '-'
    mov  BYTE PTR [edi+1], '-'
    mov  BYTE PTR [edi+2], '-'
    mov  BYTE PTR [edi+3], '-'
    mov  BYTE PTR [edi+4], 0
    mov  al, 0
 
ObtenerMov_Fin:
    pop  edi
    pop  esi
    ret
Motor_ObtenerMejorMovimiento ENDP
 
END