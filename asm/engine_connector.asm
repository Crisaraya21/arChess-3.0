; ===========================================================================
; engine_connector.asm - Modulo de Conexion con Motor IA
;
; CAMBIO: Rutas corregidas a la ubicacion real del proyecto:
;   C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\
;
; Lee hint.json DIRECTAMENTE con su propio mini-parser.
; Busca el substring bestMove, avanza hasta la comilla
; de apertura del valor, y copia los siguientes 4 caracteres.
; ===========================================================================

INCLUDE Irvine32.inc

EC_NORMAL_PRIORITY      EQU 00000020h
EC_STARTF_SHOWWINDOW    EQU 00000001h
EC_SW_HIDE              EQU 0
EC_PROCESS_TIMEOUT      EQU 20000

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

CreateProcessA PROTO,
    lpAppName:DWORD, lpCmdLine:DWORD,
    lpProcAttr:DWORD, lpThreadAttr:DWORD,
    bInheritHandles:DWORD, dwCreationFlags:DWORD,
    lpEnvironment:DWORD, lpCurrentDir:DWORD,
    lpStartupInfo:DWORD,
    lpProcInfo:DWORD

WaitForSingleObject PROTO, hHandle:DWORD, dwMilliseconds:DWORD
CloseHandle PROTO, hObject:DWORD

; --- file_manager.asm (solo para GenerarFEN y EscribirEstado) ---
Archivo_GenerarFEN      PROTO
Archivo_EscribirEstado  PROTO

; --- main.asm ---
EXTERNDEF bufferMovUCI : BYTE

; --- ui_console.asm ---
EXTERNDEF hintBuf : BYTE

; ===========================================================================
.data

; >>> RUTAS CORREGIDAS <<<
cmdAIService    BYTE "C:\Users\Usuario\AppData\Local\Programs\Python\Python313\python.exe C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\services\ai_service.py", 0
rutaHintEC      BYTE "C:\Users\Usuario\Documentos\TEC\Proyecto\arChess-3.0\data\hint.json", 0

ecStartInf      EC_STARTUPINFO <>
ecProcInf       EC_PROCESS_INFO <>

; Buffer propio para leer hint.json (512 bytes)
ecHintBuffer    BYTE 512 DUP(0)
ecBytesRead     DWORD 0

; Substring a buscar en el JSON
ecKeyBestMove   BYTE "bestMove", 0

motorDisponible BYTE 0
motorBestMove   BYTE 8 DUP(0)

msgMotorInicio  BYTE "  [IA] Consultando motor de ajedrez...", 0Dh, 0Ah, 0
msgMotorOk      BYTE "  [IA] Jugada obtenida: ", 0
msgMotorError   BYTE "  [IA] Error al obtener jugada.", 0Dh, 0Ah, 0
msgMotorNL      BYTE 0Dh, 0Ah, 0

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
; EC_LeerHintDirecto - Lee hint.json directamente y extrae bestMove
;
; Abre hint.json, lee contenido, busca "bestMove", extrae 4 chars UCI.
;
; Retorna: AL = 1 exito (motorBestMove lleno), 0 error
; ===========================================================================
EC_LeerHintDirecto PROC
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; --- Limpiar buffer ---
    lea  edi, ecHintBuffer
    mov  ecx, 512
    xor  al, al
    rep  stosb

    ; --- Abrir hint.json ---
    mov  edx, OFFSET rutaHintEC
    call OpenInputFile
    cmp  eax, 0FFFFFFFFh
    je   HintDir_Error
    mov  ebx, eax

    ; --- Leer contenido ---
    mov  eax, ebx
    lea  edx, ecHintBuffer
    mov  ecx, 510
    call ReadFromFile
    mov  ecHintBuffer[eax], 0
    mov  ecBytesRead, eax

    ; --- Cerrar archivo ---
    mov  eax, ebx
    call CloseFile

    ; --- Verificar que leimos algo ---
    cmp  ecBytesRead, 10
    jb   HintDir_Error

    ; --- Buscar "bestMove" en el buffer ---
    lea  esi, ecHintBuffer

HintDir_BuscarLoop:
    cmp  BYTE PTR [esi], 0
    je   HintDir_Error

    cmp  BYTE PTR [esi+0], 'b'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+1], 'e'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+2], 's'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+3], 't'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+4], 'M'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+5], 'o'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+6], 'v'
    jne  HintDir_Siguiente
    cmp  BYTE PTR [esi+7], 'e'
    jne  HintDir_Siguiente

    add  esi, 8
    jmp  HintDir_BuscarDosPuntos

HintDir_Siguiente:
    inc  esi
    jmp  HintDir_BuscarLoop

HintDir_BuscarDosPuntos:
    cmp  BYTE PTR [esi], 0
    je   HintDir_Error
    cmp  BYTE PTR [esi], ':'
    je   HintDir_BuscarComilla
    inc  esi
    jmp  HintDir_BuscarDosPuntos

HintDir_BuscarComilla:
    inc  esi
HintDir_ComillaLoop:
    cmp  BYTE PTR [esi], 0
    je   HintDir_Error
    cmp  BYTE PTR [esi], '"'
    je   HintDir_ExtraerMove
    inc  esi
    jmp  HintDir_ComillaLoop

HintDir_ExtraerMove:
    inc  esi

    cmp  BYTE PTR [esi], 'a'
    jb   HintDir_Error
    cmp  BYTE PTR [esi], 'h'
    ja   HintDir_Error

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

    cmp  BYTE PTR [edi+0], '0'
    jne  HintDir_Exito
    cmp  BYTE PTR [edi+1], '0'
    jne  HintDir_Exito
    jmp  HintDir_Error

HintDir_Exito:
    mov  motorDisponible, 1
    mov  al, 1
    jmp  HintDir_Fin

HintDir_Error:
    mov  motorDisponible, 0
    lea  edi, motorBestMove
    mov  DWORD PTR [edi], 0
    mov  BYTE PTR [edi+4], 0
    mov  al, 0

HintDir_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    ret
EC_LeerHintDirecto ENDP


; ===========================================================================
; Motor_SolicitarJugada - Modo vs IA
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

    call EC_LeerHintDirecto
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
; Motor_SolicitarPista - Modo pista (hint)
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

    call EC_LeerHintDirecto
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