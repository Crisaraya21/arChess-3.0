INCLUDE Irvine32.inc

PUBLIC Entrada_LeerMovimientoUCI
PUBLIC Entrada_LeerOpcionMenu
PUBLIC Entrada_SolicitoPista

.code

Entrada_LeerMovimientoUCI PROC
    mov al, 0
    ret
Entrada_LeerMovimientoUCI ENDP

Entrada_LeerOpcionMenu PROC
    mov al, 3
    ret
Entrada_LeerOpcionMenu ENDP

Entrada_SolicitoPista PROC
    mov al, 0
    ret
Entrada_SolicitoPista ENDP

END