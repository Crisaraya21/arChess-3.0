; ===========================================================================
; path_resolver.asm - Resolucion Dinamica de Rutas
;
; PROBLEMA: Las rutas hardcodeadas (C:\Users\josti\...) solo funcionan
;           en UNA computadora. Cada miembro del equipo tiene rutas
;           diferentes.
;
; SOLUCION: Detectar en TIEMPO DE EJECUCION donde esta el .exe usando
;           GetModuleFileNameA, subir 2 niveles de directorio
;           (Debug\ -> arChess\ -> raiz del proyecto), y construir
;           las rutas a data\ y services\ dinamicamente.
;
; USO: Llamar Rutas_Inicializar UNA VEZ al inicio del programa.
;      Despues, las variables publicas contienen las rutas listas:
;        rutaGameState  -> "...\data\game_state.json"
;        rutaMovesLog   -> "...\data\moves.log"
;        rutaHintJson   -> "...\data\hint.json"
;        rutaSyncFlag   -> "...\data\sync_flag.txt"
;        cmdPythonAI    -> "python.exe ...\services\ai_service.py"
;        cmdPythonSync  -> "python.exe ...\services\sync_service.py "
;        rutaProyecto   -> "...\arChess-3.0\"
;
; ESTRUCTURA ESPERADA:
;   <proyecto>\arChess\Debug\arChess.exe   <- el .exe
;   <proyecto>\data\                        <- archivos JSON
;   <proyecto>\services\                    <- scripts Python
;
; ===========================================================================

INCLUDE Irvine32.inc

GetModuleFileNameA PROTO, hModule:DWORD, lpFilename:DWORD, nSize:DWORD

NIVELES_SUBIR   EQU 2       ; Debug\ -> arChess\ -> raiz

; ===========================================================================
.data

PUBLIC rutaProyecto
PUBLIC rutaGameState
PUBLIC rutaMovesLog
PUBLIC rutaHintJson
PUBLIC rutaSyncFlag
PUBLIC cmdPythonAI
PUBLIC cmdPythonSync

; Buffer para la ruta del ejecutable
rutaExe         BYTE 512 DUP(0)

; Ruta raiz del proyecto (hasta el ultimo backslash)
rutaProyecto    BYTE 512 DUP(0)

; Rutas completas a archivos de datos
rutaGameState   BYTE 512 DUP(0)
rutaMovesLog    BYTE 512 DUP(0)
rutaHintJson    BYTE 512 DUP(0)
rutaSyncFlag    BYTE 512 DUP(0)

; Comandos completos para CreateProcessA
cmdPythonAI     BYTE 512 DUP(0)
cmdPythonSync   BYTE 512 DUP(0)

; Sufijos relativos
sufGameState    BYTE "data\game_state.json", 0
sufMovesLog     BYTE "data\moves.log", 0
sufHintJson     BYTE "data\hint.json", 0
sufSyncFlag     BYTE "data\sync_flag.txt", 0
sufAIService    BYTE "services\ai_service.py", 0
sufSyncService  BYTE 'services\sync_service.py" ', 0

; Prefijo para comandos Python (python esta en PATH)
prefPython      BYTE 'python.exe "', 0

msgRutaOk       BYTE "  [PATH] Raiz: ", 0
msgRutaNL       BYTE 0Dh, 0Ah, 0

; ===========================================================================
.code

PUBLIC Rutas_Inicializar

; ===========================================================================
; Rutas_Inicializar
;
; 1. Obtiene ruta del .exe con GetModuleFileNameA
; 2. Sube NIVELES_SUBIR directorios (quita \Debug\arChess.exe -> \arChess\)
; 3. Concatena sufijos para cada archivo
; 4. Construye comandos Python
; ===========================================================================
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

    ; --- Paso 2: Encontrar la raiz del proyecto ---
    ; Copiar rutaExe a rutaProyecto
    lea  esi, rutaExe
    lea  edi, rutaProyecto
    call PR_CopiarStr

    ; Subir NIVELES_SUBIR directorios
    ; Cada nivel: buscar el ultimo '\' y poner null ahi
    mov  ecx, NIVELES_SUBIR

Rutas_SubirLoop:
    cmp  ecx, 0
    je   Rutas_SubirDone

    ; Encontrar el ultimo '\' en rutaProyecto
    lea  esi, rutaProyecto
    call PR_BuscarUltimoBackslash
    ; ESI apunta al ultimo '\'
    cmp  esi, 0
    je   Rutas_Fin              ; error: no hay backslash
    mov  BYTE PTR [esi], 0      ; cortar ahi

    dec  ecx
    jmp  Rutas_SubirLoop

Rutas_SubirDone:
    ; Agregar '\' final a rutaProyecto
    lea  esi, rutaProyecto
    call PR_FinStr               ; ESI apunta al null final
    mov  BYTE PTR [esi], '\'
    inc  esi
    mov  BYTE PTR [esi], 0

    ; --- Paso 3: Construir rutas de archivos ---
    ; rutaGameState = rutaProyecto + "data\game_state.json"
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

Rutas_Fin:
    pop  edi
    pop  esi
    pop  edx
    pop  ecx
    pop  ebx
    pop  eax
    ret
Rutas_Inicializar ENDP


; ===========================================================================
; PR_CopiarStr — Copia ESI -> EDI incluyendo null
; ===========================================================================
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


; ===========================================================================
; PR_FinStr — Avanza ESI (= EDI al entrar) hasta el null terminator
; Entrada: EDI = inicio del string
; Salida:  ESI = posicion del null (para concatenar)
; ===========================================================================
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


; ===========================================================================
; PR_BuscarUltimoBackslash — Busca el ultimo '\' en el string
; Entrada: ESI = inicio del string
; Salida:  ESI = posicion del ultimo '\', o 0 si no hay
; ===========================================================================
PR_BuscarUltimoBackslash PROC
    push eax
    push edi

    mov  edi, 0                 ; EDI = posicion del ultimo '\' encontrado

PR_BUB_Loop:
    mov  al, [esi]
    cmp  al, 0
    je   PR_BUB_Fin
    cmp  al, '\'
    jne  PR_BUB_Sig
    mov  edi, esi               ; guardar posicion
PR_BUB_Sig:
    inc  esi
    jmp  PR_BUB_Loop

PR_BUB_Fin:
    mov  esi, edi               ; retornar ultimo '\' encontrado

    pop  edi
    pop  eax
    ret
PR_BuscarUltimoBackslash ENDP

END