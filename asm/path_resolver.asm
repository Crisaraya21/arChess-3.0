; ===========================================================================
; path_resolver.asm - Resolucion Dinamica de Rutas
;
; FIX: NIVELES_SUBIR = 3 (no 2)
;
; Estructura real:
;   arChess-3.0\arChess\Debug\arChess.exe
;   Nivel 1: quitar arChess.exe  -> arChess-3.0\arChess\Debug\
;   Nivel 2: quitar Debug\       -> arChess-3.0\arChess\
;   Nivel 3: quitar arChess\     -> arChess-3.0\    <-- raiz correcta
;
; ===========================================================================

INCLUDE Irvine32.inc

GetModuleFileNameA PROTO, hModule:DWORD, lpFilename:DWORD, nSize:DWORD

NIVELES_SUBIR   EQU 3       ; arChess.exe -> Debug\ -> arChess\ -> raiz

; ===========================================================================
.data

PUBLIC rutaProyecto
PUBLIC rutaGameState
PUBLIC rutaMovesLog
PUBLIC rutaHintJson
PUBLIC rutaSyncFlag
PUBLIC cmdPythonAI
PUBLIC cmdPythonSync

rutaExe         BYTE 512 DUP(0)
rutaProyecto    BYTE 512 DUP(0)
rutaGameState   BYTE 512 DUP(0)
rutaMovesLog    BYTE 512 DUP(0)
rutaHintJson    BYTE 512 DUP(0)
rutaSyncFlag    BYTE 512 DUP(0)
cmdPythonAI     BYTE 512 DUP(0)
cmdPythonSync   BYTE 512 DUP(0)

sufGameState    BYTE "data\game_state.json", 0
sufMovesLog     BYTE "data\moves.log", 0
sufHintJson     BYTE "data\hint.json", 0
sufSyncFlag     BYTE "data\sync_flag.txt", 0    
sufAIService    BYTE "services\ai_service.py", 0
sufSyncService  BYTE "services\sync_service.py", 0

prefPython      BYTE '"C:\Users\Usuario\AppData\Local\Programs\Python\Python313\python.exe" "', 0

; ===========================================================================
.code

PUBLIC Rutas_Inicializar

Rutas_Inicializar PROC
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    ; --- Paso 1: Obtener ruta del ejecutable ---
    INVOKE GetModuleFileNameA, NULL, ADDR rutaExe, 510
    cmp  eax, 0
    je   Rutas_Fin

    ; --- Paso 2: Copiar a rutaProyecto y subir 3 niveles ---
    lea  esi, rutaExe
    lea  edi, rutaProyecto
    call PR_CopiarStr

    mov  ecx, NIVELES_SUBIR

Rutas_SubirLoop:
    cmp  ecx, 0
    je   Rutas_SubirDone

    lea  esi, rutaProyecto
    call PR_BuscarUltimoBackslash
    cmp  esi, 0
    je   Rutas_Fin
    mov  BYTE PTR [esi], 0

    dec  ecx
    jmp  Rutas_SubirLoop

Rutas_SubirDone:
    ; Agregar '\' final
    lea  edi, rutaProyecto 
    call PR_FinStr
    mov  BYTE PTR [esi], '\'
    inc  esi
    mov  BYTE PTR [esi], 0

    ; --- Paso 3: Construir rutas de archivos ---
    ; rutaGameState
    lea  edi, rutaGameState
    lea  esi, rutaProyecto
    call PR_CopiarStr
    lea  edi, rutaGameState
    call PR_FinStr
    mov  edi, esi
    lea  esi, sufGameState
    call PR_CopiarStr

    ; rutaMovesLog
    lea  edi, rutaMovesLog
    lea  esi, rutaProyecto
    call PR_CopiarStr
    lea  edi, rutaMovesLog
    call PR_FinStr
    mov  edi, esi
    lea  esi, sufMovesLog
    call PR_CopiarStr

    ; rutaHintJson
    lea  edi, rutaHintJson
    lea  esi, rutaProyecto
    call PR_CopiarStr
    lea  edi, rutaHintJson
    call PR_FinStr
    mov  edi, esi
    lea  esi, sufHintJson
    call PR_CopiarStr

    ; rutaSyncFlag
    lea  edi, rutaSyncFlag
    lea  esi, rutaProyecto
    call PR_CopiarStr
    lea  edi, rutaSyncFlag
    call PR_FinStr
    mov  edi, esi
    lea  esi, sufSyncFlag
    call PR_CopiarStr

    ; --- Paso 4: Construir comandos Python ---
    ; cmdPythonAI = 'python.exe "' + rutaProyecto + 'services\ai_service.py"'
    lea  edi, cmdPythonAI
    lea  esi, prefPython
    call PR_CopiarStr
    lea  edi, cmdPythonAI
    call PR_FinStr
    mov  edi, esi
    lea  esi, rutaProyecto
    call PR_CopiarStr
    lea  edi, cmdPythonAI
    call PR_FinStr
    mov  edi, esi
    lea  esi, sufAIService
    call PR_CopiarStr
    ; Agregar comilla de cierre
    lea  edi, cmdPythonAI
    call PR_FinStr
    mov  edi, esi
    mov  BYTE PTR [edi], '"'
    inc  edi
    mov  BYTE PTR [edi], 0

    ; cmdPythonSync = 'python.exe "' + rutaProyecto + 'services\sync_service.py" '
    lea  edi, cmdPythonSync
    lea  esi, prefPython
    call PR_CopiarStr
    lea  edi, cmdPythonSync
    call PR_FinStr
    mov  edi, esi
    lea  esi, rutaProyecto
    call PR_CopiarStr
    lea  edi, cmdPythonSync
    call PR_FinStr
    mov  edi, esi
    lea  esi, sufSyncService
    call PR_CopiarStr
    ; Agregar comilla de cierre + espacio
    lea  edi, cmdPythonSync
    call PR_FinStr
    mov  edi, esi
    mov  BYTE PTR [edi], '"'
    inc  edi
    mov  BYTE PTR [edi], ' '
    inc  edi
    mov  BYTE PTR [edi], 0

Rutas_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
Rutas_Inicializar ENDP


PR_CopiarStr PROC
    push eax
PR_CS_Loop:
    mov  al, [esi]
    mov  [edi], al
    cmp  al, 0
    je   PR_CS_Fin
    inc  esi
    inc  edi
    jmp  PR_CS_Loop
PR_CS_Fin:
    pop  eax
    ret
PR_CopiarStr ENDP


PR_FinStr PROC
    mov  esi, edi
PR_FS_Loop:
    cmp  BYTE PTR [esi], 0
    je   PR_FS_Fin
    inc  esi
    jmp  PR_FS_Loop
PR_FS_Fin:
    ret
PR_FinStr ENDP


PR_BuscarUltimoBackslash PROC
    push eax
    push edi

    mov  edi, 0

PR_BUB_Loop:
    mov  al, [esi]
    cmp  al, 0
    je   PR_BUB_Fin
    cmp  al, '\'
    jne  PR_BUB_Sig
    mov  edi, esi
PR_BUB_Sig:
    inc  esi
    jmp  PR_BUB_Loop

PR_BUB_Fin:
    mov  esi, edi

    pop  edi
    pop  eax
    ret
PR_BuscarUltimoBackslash ENDP

END