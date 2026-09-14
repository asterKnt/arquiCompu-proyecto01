; ============================================================================
; UNIVERSIDAD FRANCISCO MARROQUIN
; Arquitectura y Diseno de Computadoras
; Proyecto 1: Editor de Texto x8086
; ============================================================================

.286                        ; Instrucciones extendidas habilitadas para TASM
JUMPS                       ; Resolucion automatica de saltos lejanos
.MODEL SMALL
.STACK 200h

.DATA
    ; ------------------------------------------------------------------------
    ; MENSAJES Y CADENAS
    ; ------------------------------------------------------------------------
    TITULO_MENU     DB " EDITOR DE TEXTO UFM ", 0
    OPC_1           DB " Crear un archivo nuevo ", 0
    OPC_2           DB " Abrir archivo existente ", 0
    OPC_3           DB " Salir ", 0
    FOOTER_MENU     DB "Seleccione con <Flechas> y presione <Enter>. <Alt+X> para salir.", 0

    MSG_PEDIR_NOM   DB "Ingrese el nombre del archivo (max 8 chars): ", 0
    MSG_ERR_CREAR   DB "Error: No se pudo crear el archivo. Presione una tecla...", 0
    MSG_ERR_EXISTE  DB "Error: El archivo ya existe. Presione una tecla...", 0
    MSG_ERR_ABRIR   DB "Error: El archivo no existe. Presione una tecla...", 0
    
    MSG_HELP_TITLE  DB "--- AYUDA DE ATAJOS ---", 0
    MSG_HELP_1      DB "Alt+C: Centrar cursor   Alt+U: Primer renglon", 0
    MSG_HELP_2      DB "Alt+D: Ultimo renglon  Alt+S: Guardar y Salir", 0
    MSG_HELP_3      DB "Alt+M: Cambiar color texto  Alt+N: Color fondo", 0
    MSG_HELP_4      DB "Alt+I: Corazon (Img 1) Alt+J: Carita (Img 2)", 0
    MSG_HELP_5      DB "Alt+B: Buscar/Reemplaz Alt+H: Esta pantalla", 0

    TITULO_COLOR_M  DB " COLOR DE TEXTO ", 0
    M_COL_0         DB " 1. Blanco ", 0
    M_COL_1         DB " 2. Negro ", 0
    M_COL_2         DB " 3. Cian ", 0
    M_COL_3         DB " 4. Rojo ", 0
    M_COL_4         DB " 5. Verde ", 0

    ; ------------------------------------------------------------------------
    ; VARIABLES DE ESTADO Y BUFFERS
    ; ------------------------------------------------------------------------
    OPCION_SEL      DB 0            
    BUFFER_NOMBRE   DB 13 DUP(0)    
    BUFFER_TEXTO    DB 4000 DUP(0)  
    BUFFER_VENTANA  DB 1000 DUP(0)  
    HANDLE_FILE     DW 0
    
    CURSOR_X        DB 0
    CURSOR_Y        DB 0
    COLOR_ACTUAL    DB 0Fh          
    
    PALETA_TEXTO    DB 0Fh, 00h, 0Bh, 0Ch, 0Ah
    IDX_TEXTO       DB 0            
    
    PALETA_FONDO    DB 00h, 05h, 07h
    IDX_FONDO       DB 0            

.CODE

; ----------------------------------------------------------------------------
; MACRO POSICIONAR CURSOR EN PANTALLA
; ----------------------------------------------------------------------------
GOTOXY MACRO X, Y
    PUSH AX
    PUSH BX
    PUSH DX
    MOV AH, 02h
    MOV BH, 0
    MOV DH, Y
    MOV DL, X
    INT 10h
    POP DX
    POP BX
    POP AX
ENDM

; ----------------------------------------------------------------------------
; LECTURA DE TECLADO ESTRICTA
; ----------------------------------------------------------------------------
LEER_TECLA_ESTRICTA PROC
    MOV AH, 00h
    INT 16h
    CMP AL, 00h             
    JE ES_EXTENDIDA
    CMP AL, 0E0h            
    JE ES_EXTENDIDA
    MOV BH, 0               
    RET
ES_EXTENDIDA:
    MOV BH, 1               
    RET
LEER_TECLA_ESTRICTA ENDP

; ----------------------------------------------------------------------------
; MAIN
; ----------------------------------------------------------------------------
MAIN PROC
    MOV AX, @DATA
    MOV DS, AX
    MOV ES, AX

MENU_LOOP:
    CALL CONFIGURAR_MODO_TEXTO
    CALL DIBUJAR_MENU

CAPTURAR_TECLA_MENU:
    CALL LEER_TECLA_ESTRICTA

    CMP BH, 1
    JNE VERIFICAR_ENTER
    CMP AH, 2Dh             ; Alt+X
    JE SALIR_PROGRAMA

VERIFICAR_ENTER:
    CMP AH, 1Ch             ; Enter
    JE EJECUTAR_OPCION

    CMP AH, 48h             ; Flecha Arriba
    JE FLECHA_ARRIBA

    CMP AH, 50h             ; Flecha Abajo
    JE FLECHA_ABAJO

    JMP CAPTURAR_TECLA_MENU

FLECHA_ARRIBA:
    CMP OPCION_SEL, 0
    JE CAPTURAR_TECLA_MENU
    DEC OPCION_SEL
    CALL DIBUJAR_MENU
    JMP CAPTURAR_TECLA_MENU

FLECHA_ABAJO:
    CMP OPCION_SEL, 2
    JE CAPTURAR_TECLA_MENU
    INC OPCION_SEL
    CALL DIBUJAR_MENU
    JMP CAPTURAR_TECLA_MENU

EJECUTAR_OPCION:
    CMP OPCION_SEL, 0
    JE OPC_CREAR
    CMP OPCION_SEL, 1
    JE OPC_ABRIR
    JMP SALIR_PROGRAMA

OPC_CREAR:
    CALL SOLICITAR_NOMBRE
    JC MENU_LOOP
    CALL CREAR_ARCHIVO_NUEVO
    JC MENU_LOOP
    CALL PANTALLA_EDICION
    JMP MENU_LOOP

OPC_ABRIR:
    CALL SOLICITAR_NOMBRE
    JC MENU_LOOP
    CALL ABRIR_ARCHIVO_EXISTENTE
    JC MENU_LOOP
    CALL PANTALLA_EDICION
    JMP MENU_LOOP

SALIR_PROGRAMA:
    MOV AH, 00h
    MOV AL, 03h
    INT 10h
    MOV AX, 4C00h
    INT 21h
MAIN ENDP

; ----------------------------------------------------------------------------
; CONFIGURACION DE PANTALLA Y MENU
; ----------------------------------------------------------------------------
CONFIGURAR_MODO_TEXTO PROC
    MOV AH, 00h
    MOV AL, 03h
    INT 10h
    RET
CONFIGURAR_MODO_TEXTO ENDP

DIBUJAR_MENU PROC
    MOV AX, 0600h
    MOV BH, 60h
    MOV CX, 0000h
    MOV DX, 184Fh
    INT 10h

    MOV AX, 0600h
    MOV BH, 00h
    MOV CX, 081Dh
    MOV DX, 1137h
    INT 10h

    MOV AX, 0600h
    MOV BH, 1Fh
    MOV CX, 071Bh
    MOV DX, 1035h
    INT 10h

    GOTOXY 29, 8
    LEA SI, TITULO_MENU
    CALL IMPRIMIR_CADENA

    GOTOXY 28, 10
    CMP OPCION_SEL, 0
    JNE DIB_O1
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 24
    INT 10h
DIB_O1:
    LEA SI, OPC_1
    CALL IMPRIMIR_CADENA

    GOTOXY 28, 12
    CMP OPCION_SEL, 1
    JNE DIB_O2
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 24
    INT 10h
DIB_O2:
    LEA SI, OPC_2
    CALL IMPRIMIR_CADENA

    GOTOXY 28, 14
    CMP OPCION_SEL, 2
    JNE DIB_O3
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 24
    INT 10h
DIB_O3:
    LEA SI, OPC_3
    CALL IMPRIMIR_CADENA

    MOV AX, 0600h
    MOV BH, 70h
    MOV CX, 1600h
    MOV DX, 174Fh
    INT 10h

    GOTOXY 2, 22
    LEA SI, FOOTER_MENU
    CALL IMPRIMIR_CADENA
    RET
DIBUJAR_MENU ENDP

; ----------------------------------------------------------------------------
; CAPTURA DE NOMBRE DE ARCHIVO
; ----------------------------------------------------------------------------
SOLICITAR_NOMBRE PROC
    CALL CONFIGURAR_MODO_TEXTO
    GOTOXY 5, 5
    LEA SI, MSG_PEDIR_NOM
    CALL IMPRIMIR_CADENA

    MOV DI, OFFSET BUFFER_NOMBRE
    MOV CX, 0

LEER_CHAR_NOM:
    CALL LEER_TECLA_ESTRICTA

    CMP BH, 1
    JNE EVAL_TECLAS_NOM
    CMP AH, 2Ch             ; Alt+Z (Cancelar)
    JE CANCELAR_NOMBRE

EVAL_TECLAS_NOM:
    CMP AL, 0Dh             ; Enter
    JE FIN_NOMBRE

    CMP AL, 08h             ; Backspace
    JE BORRAR_CHAR_NOM

    CMP CX, 8
    JAE LEER_CHAR_NOM

    CMP AL, 'a'
    JB GUARDAR_CHAR_NOM
    CMP AL, 'z'
    JA GUARDAR_CHAR_NOM
    SUB AL, 20h

GUARDAR_CHAR_NOM:
    CMP AL, ' '
    JB LEER_CHAR_NOM
    MOV [DI], AL
    INC DI
    INC CX

    MOV AH, 0Eh
    INT 10h
    JMP LEER_CHAR_NOM

BORRAR_CHAR_NOM:
    CMP CX, 0
    JE LEER_CHAR_NOM
    DEC DI
    DEC CX
    MOV AH, 0Eh
    MOV AL, 08h
    INT 10h
    MOV AL, ' '
    INT 10h
    MOV AL, 08h
    INT 10h
    JMP LEER_CHAR_NOM

CANCELAR_NOMBRE:
    STC
    RET

FIN_NOMBRE:
    CMP CX, 0
    JE LEER_CHAR_NOM
    MOV BYTE PTR [DI], '.'
    MOV BYTE PTR [DI+1], 'U'
    MOV BYTE PTR [DI+2], 'F'
    MOV BYTE PTR [DI+3], 'M'
    MOV BYTE PTR [DI+4], 0
    CLC
    RET
SOLICITAR_NOMBRE ENDP

; ----------------------------------------------------------------------------
; RUTINAS ARCHIVOS Y LIMPIEZA DE PANTALLA
; ----------------------------------------------------------------------------
LIMPIAR_BUFFER_TEXTO PROC
    PUSH DI
    PUSH CX
    PUSH AX
    MOV DI, OFFSET BUFFER_TEXTO
    MOV CX, 2000
LIMPIAR_PAIR:
    MOV BYTE PTR [DI], ' '       
    MOV BYTE PTR [DI+1], 0Fh     
    ADD DI, 2
    LOOP LIMPIAR_PAIR

    POP AX
    POP CX
    POP DI
    RET
LIMPIAR_BUFFER_TEXTO ENDP

CREAR_ARCHIVO_NUEVO PROC
    MOV AH, 43h
    MOV AL, 00h
    LEA DX, BUFFER_NOMBRE
    INT 21h
    JNC ARCHIVO_YA_EXISTE

    MOV AH, 3Ch
    MOV CX, 0
    LEA DX, BUFFER_NOMBRE
    INT 21h
    JC ERR_CREAR_DOS

    MOV HANDLE_FILE, AX
    MOV AH, 3Eh
    MOV BX, HANDLE_FILE
    INT 21h

    CALL LIMPIAR_BUFFER_TEXTO
    MOV IDX_FONDO, 0
    CALL LIMPIAR_PANTALLA_EDITOR
    CLC
    RET

ARCHIVO_YA_EXISTE:
    GOTOXY 5, 10
    LEA SI, MSG_ERR_EXISTE
    CALL IMPRIMIR_CADENA
    CALL LEER_TECLA_ESTRICTA
    STC
    RET

ERR_CREAR_DOS:
    GOTOXY 5, 10
    LEA SI, MSG_ERR_CREAR
    CALL IMPRIMIR_CADENA
    CALL LEER_TECLA_ESTRICTA
    STC
    RET
CREAR_ARCHIVO_NUEVO ENDP

ABRIR_ARCHIVO_EXISTENTE PROC
    CALL LIMPIAR_BUFFER_TEXTO

    MOV AH, 3Dh
    MOV AL, 00h
    LEA DX, BUFFER_NOMBRE
    INT 21h
    JC ERR_ABRIR_DOS

    MOV HANDLE_FILE, AX

    MOV AH, 3Fh
    MOV BX, HANDLE_FILE
    MOV CX, 4000
    LEA DX, BUFFER_TEXTO
    INT 21h

    MOV AH, 3Eh
    MOV BX, HANDLE_FILE
    INT 21h

    MOV AL, BUFFER_TEXTO[1]
    AND AL, 70h                 
    SHR AL, 4                   
    
    CMP AL, 05h                 
    JE ES_FONDO_1
    CMP AL, 07h                 
    JE ES_FONDO_2
    MOV IDX_FONDO, 0            
    JMP FIN_DETECTAR_FONDO

ES_FONDO_1:
    MOV IDX_FONDO, 1
    JMP FIN_DETECTAR_FONDO

ES_FONDO_2:
    MOV IDX_FONDO, 2

FIN_DETECTAR_FONDO:
    CALL ACTUALIZAR_COLOR

    CMP AX, 4000
    JAE VOLCAR_A_VIDEO

    MOV DI, OFFSET BUFFER_TEXTO
    ADD DI, AX
    MOV CX, 4000
    SUB CX, AX
    SHR CX, 1

    CMP CX, 0
    JE VOLCAR_A_VIDEO

    MOV BL, COLOR_ACTUAL

RELLENAR_FALTANTES:
    MOV BYTE PTR [DI], ' '
    MOV BYTE PTR [DI+1], BL
    ADD DI, 2
    LOOP RELLENAR_FALTANTES

VOLCAR_A_VIDEO:
    PUSH ES
    MOV AX, 0B800h
    MOV ES, AX
    MOV SI, OFFSET BUFFER_TEXTO
    MOV DI, 0
    MOV CX, 2000

DIBUJAR_TEXTO_CARGADO:
    MOV AX, [SI]                 
    MOV ES:[DI], AX              
    ADD SI, 2
    ADD DI, 2
    LOOP DIBUJAR_TEXTO_CARGADO

    POP ES

    MOV CURSOR_X, 0
    MOV CURSOR_Y, 0
    CALL IR_AL_FINAL_DEL_DOCUMENTO
    CLC
    RET

ERR_ABRIR_DOS:
    GOTOXY 5, 10
    LEA SI, MSG_ERR_ABRIR
    CALL IMPRIMIR_CADENA
    CALL LEER_TECLA_ESTRICTA
    STC
    RET
ABRIR_ARCHIVO_EXISTENTE ENDP

GUARDAR_ARCHIVO PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH ES

    MOV AX, 0B800h
    MOV ES, AX
    MOV SI, 0
    MOV DI, OFFSET BUFFER_TEXTO
    MOV CX, 2000

COPIAR_PANTALLA_A_BUFFER:
    MOV AX, ES:[SI]              
    MOV [DI], AX                 
    ADD SI, 2
    ADD DI, 2
    LOOP COPIAR_PANTALLA_A_BUFFER

    MOV AH, 3Ch
    MOV CX, 0
    LEA DX, BUFFER_NOMBRE
    INT 21h
    JC FIN_GUARDAR
    MOV HANDLE_FILE, AX

    MOV AH, 40h
    MOV BX, HANDLE_FILE
    MOV CX, 4000
    LEA DX, BUFFER_TEXTO
    INT 21h

    MOV AH, 3Eh
    MOV BX, HANDLE_FILE
    INT 21h

FIN_GUARDAR:
    POP ES
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
GUARDAR_ARCHIVO ENDP

LIMPIAR_PANTALLA_EDITOR PROC
    PUSH ES
    PUSH DI
    PUSH CX
    PUSH AX

    CALL ACTUALIZAR_COLOR

    MOV AX, 0B800h
    MOV ES, AX
    MOV DI, 0
    MOV CX, 2000
    MOV AH, COLOR_ACTUAL        
    MOV AL, ' '

LIMPIAR_RAM_VIDEO:
    MOV ES:[DI], AX
    ADD DI, 2
    LOOP LIMPIAR_RAM_VIDEO

    MOV CURSOR_X, 0
    MOV CURSOR_Y, 0
    MOV IDX_TEXTO, 0
    GOTOXY 0, 0

    POP AX
    POP CX
    POP DI
    POP ES
    RET
LIMPIAR_PANTALLA_EDITOR ENDP

; ----------------------------------------------------------------------------
; RUTINAS DE INSERCION Y BORRADO GLOBAL (EMPUJA Y JALA TODO EL TEXTO ABAJO)
; ----------------------------------------------------------------------------

; Insertar caracter o espacio: Desplaza TODO el buffer a la derecha desde la pos. del cursor
INSERTAR_CHAR_COLOR PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH ES

    MOV BL, AL                  ; BL = Carácter a insertar

    ; Posición de inicio en bytes del cursor: (Y * 80 + X) * 2
    MOV AL, CURSOR_Y
    MOV DH, 80
    MUL DH
    MOV DL, CURSOR_X
    MOV DH, 0
    ADD AX, DX
    SHL AX, 1
    MOV DI, AX                  ; DI = Offset del cursor

    MOV AX, 0B800h
    MOV ES, AX

    MOV SI, 3998                 ; SI = Última celda visible (24, 79)

LOOP_EMPUJAR_GLOBAL:
    CMP SI, DI
    JBE FIN_EMPUJAR_GLOBAL

    MOV AX, ES:[SI-2]
    MOV ES:[SI], AX
    SUB SI, 2
    JMP LOOP_EMPUJAR_GLOBAL

FIN_EMPUJAR_GLOBAL:
    ; Colocar el nuevo carácter en la posición actual
    MOV ES:[DI], BL
    MOV BH, COLOR_ACTUAL
    MOV ES:[DI+1], BH

    POP ES
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
INSERTAR_CHAR_COLOR ENDP

; Borrar carácter: Jala TODO el texto global a la izquierda desde la pos. del cursor
ELIMINAR_CHAR_COLOR PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH ES

    ; Posición de inicio en bytes del cursor: (Y * 80 + X) * 2
    MOV AL, CURSOR_Y
    MOV DH, 80
    MUL DH
    MOV DL, CURSOR_X
    MOV DH, 0
    ADD AX, DX
    SHL AX, 1
    MOV DI, AX                  ; DI = Offset del cursor

    MOV AX, 0B800h
    MOV ES, AX

LOOP_JALAR_GLOBAL:
    CMP DI, 3998
    JAE LIMPIAR_ULTIMA_CELDA

    MOV AX, ES:[DI+2]
    MOV ES:[DI], AX
    ADD DI, 2
    JMP LOOP_JALAR_GLOBAL

LIMPIAR_ULTIMA_CELDA:
    MOV BYTE PTR ES:[3998], ' '
    MOV BL, COLOR_ACTUAL
    MOV BYTE PTR ES:[3999], BL

    POP ES
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
ELIMINAR_CHAR_COLOR ENDP

ESCRIBIR_CHAR_COLOR PROC
    PUSH AX
    PUSH BX
    PUSH DX
    PUSH ES
    PUSH DI

    MOV BL, AL

    MOV AL, CURSOR_Y
    MOV DH, 80
    MUL DH
    MOV DL, CURSOR_X
    MOV DH, 0
    ADD AX, DX
    SHL AX, 1
    MOV DI, AX

    MOV AX, 0B800h
    MOV ES, AX

    MOV ES:[DI], BL
    MOV BH, COLOR_ACTUAL
    MOV ES:[DI+1], BH

    POP DI
    POP ES
    POP DX
    POP BX
    POP AX
    RET
ESCRIBIR_CHAR_COLOR ENDP

; ----------------------------------------------------------------------------
; CONTROLADOR DE MOVIMIENTO
; ----------------------------------------------------------------------------
PROCESAR_MOVIMIENTO_CURSOR PROC
    CMP AH, 48h                 ; Arriba
    JE CHK_MOVE_UP
    CMP AH, 50h                 ; Abajo
    JE CHK_MOVE_DOWN
    CMP AH, 4Bh                 ; Izquierda
    JE CHK_MOVE_LEFT
    CMP AH, 4Dh                 ; Derecha
    JE CHK_MOVE_RIGHT
    
    CLC
    RET

CHK_MOVE_UP:
    CMP CURSOR_Y, 0
    JE FIN_MOV
    DEC CURSOR_Y
    JMP FIN_MOV

CHK_MOVE_DOWN:
    CMP CURSOR_Y, 24
    JE FIN_MOV
    INC CURSOR_Y
    JMP FIN_MOV

CHK_MOVE_LEFT:
    CMP CURSOR_X, 0
    JE CHK_IZQ_SUBIR
    DEC CURSOR_X
    JMP FIN_MOV

CHK_IZQ_SUBIR:
    CMP CURSOR_Y, 0
    JE FIN_MOV
    DEC CURSOR_Y
    MOV CURSOR_X, 79
    JMP FIN_MOV

CHK_MOVE_RIGHT:
    CMP CURSOR_X, 79
    JE CHK_DER_BAJAR
    INC CURSOR_X
    JMP FIN_MOV

CHK_DER_BAJAR:
    CMP CURSOR_Y, 24
    JE FIN_MOV
    INC CURSOR_Y
    MOV CURSOR_X, 0

FIN_MOV:
    GOTOXY CURSOR_X, CURSOR_Y
    STC
    RET
PROCESAR_MOVIMIENTO_CURSOR ENDP

; ----------------------------------------------------------------------------
; ATAJOS ALT+C, ALT+U, ALT+D
; ----------------------------------------------------------------------------
CENTRAR_CURSOR_LINEA PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH ES
    PUSH DI

    MOV AX, 0B800h
    MOV ES, AX

    MOV AL, CURSOR_Y
    MOV DH, 80
    MUL DH
    SHL AX, 1
    MOV DI, AX

    MOV CX, 80
    ADD DI, 158

BUSCAR_FIN_LINEA:
    CMP BYTE PTR ES:[DI], ' '
    JNE LINEA_CON_TEXTO
    SUB DI, 2
    LOOP BUSCAR_FIN_LINEA

    MOV CURSOR_X, 0
    JMP FIN_CENTRAR

LINEA_CON_TEXTO:
    MOV AX, CX
    SHR AX, 1
    MOV CURSOR_X, AL

FIN_CENTRAR:
    GOTOXY CURSOR_X, CURSOR_Y
    POP DI
    POP ES
    POP DX
    POP CX
    POP BX
    POP AX
    RET
CENTRAR_CURSOR_LINEA ENDP

IR_AL_FINAL_DEL_DOCUMENTO PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH ES
    PUSH DI

    MOV AX, 0B800h
    MOV ES, AX

    MOV DI, 3998
    MOV CX, 2000

BUSCAR_ULTIMO_CARACTER_DOC:
    CMP BYTE PTR ES:[DI], ' '
    JNE ENCONTRADO_ULTIMO
    SUB DI, 2
    LOOP BUSCAR_ULTIMO_CARACTER_DOC

    MOV CURSOR_X, 0
    MOV CURSOR_Y, 0
    JMP APLICAR_POSICION_DOC

ENCONTRADO_ULTIMO:
    MOV AX, DI
    SHR AX, 1
    INC AX

    CMP AX, 2000
    JAE ULTIMO_LIMITE_PANTALLA

    MOV CL, 80
    DIV CL
    MOV CURSOR_Y, AL
    MOV CURSOR_X, AH
    JMP APLICAR_POSICION_DOC

ULTIMO_LIMITE_PANTALLA:
    MOV CURSOR_Y, 24
    MOV CURSOR_X, 79

APLICAR_POSICION_DOC:
    GOTOXY CURSOR_X, CURSOR_Y

    POP DI
    POP ES
    POP DX
    POP CX
    POP BX
    POP AX
    RET
IR_AL_FINAL_DEL_DOCUMENTO ENDP

; ----------------------------------------------------------------------------
; BUCLE PRINCIPAL DEL EDITOR
; ----------------------------------------------------------------------------
PANTALLA_EDICION PROC
LOOP_EDITOR:
    GOTOXY CURSOR_X, CURSOR_Y
    CALL LEER_TECLA_ESTRICTA

    CALL PROCESAR_MOVIMIENTO_CURSOR
    JC LOOP_EDITOR

    CMP BH, 1
    JE PROCESAR_ATAJOS_ALT

    CMP AL, 0Dh
    JE EJECUTAR_ENTER
    CMP AH, 1Ch
    JE EJECUTAR_ENTER

    CMP AL, 08h
    JE TECLA_BACKSPACE
    CMP AH, 0Eh
    JE TECLA_BACKSPACE

    JMP PROCESAR_TECLAS_NORMALES

PROCESAR_ATAJOS_ALT:
    CMP AH, 1Fh                 ; Alt+S
    JNE CHK_ALT_C
    CALL GUARDAR_ARCHIVO
    RET

CHK_ALT_C:
    CMP AH, 2Eh                 ; Alt+C
    JNE CHK_ALT_U
    CALL CENTRAR_CURSOR_LINEA
    JMP LOOP_EDITOR

CHK_ALT_U:
    CMP AH, 16h                 ; Alt+U
    JNE CHK_ALT_D
    MOV CURSOR_X, 0
    MOV CURSOR_Y, 0
    GOTOXY CURSOR_X, CURSOR_Y
    JMP LOOP_EDITOR

CHK_ALT_D:
    CMP AH, 20h                 ; Alt+D
    JNE CHK_ALT_M
    CALL IR_AL_FINAL_DEL_DOCUMENTO
    JMP LOOP_EDITOR

CHK_ALT_M:
    CMP AH, 32h                 ; Alt+M
    JNE CHK_ALT_N
    CALL MOSTRAR_MENU_COLOR_TEXTO
    GOTOXY CURSOR_X, CURSOR_Y
    JMP LOOP_EDITOR

CHK_ALT_N:
    CMP AH, 31h                 ; Alt+N
    JNE CHK_ALT_I
    CALL CAMBIAR_COLOR_FONDO
    GOTOXY CURSOR_X, CURSOR_Y
    JMP LOOP_EDITOR

CHK_ALT_I:
    CMP AH, 17h                 ; Alt+I
    JNE CHK_ALT_J
    CALL DIBUJAR_IMAGEN_1
    JMP LOOP_EDITOR

CHK_ALT_J:
    CMP AH, 24h                 ; Alt+J
    JNE CHK_ALT_H
    CALL DIBUJAR_IMAGEN_2
    JMP LOOP_EDITOR

CHK_ALT_H:
    CMP AH, 23h                 ; Alt+H
    JNE LOOP_EDITOR
    CALL MOSTRAR_AYUDA
    JMP LOOP_EDITOR

PROCESAR_TECLAS_NORMALES:
    CMP AL, 32                  ; Incluye el Espacio (32)
    JB LOOP_EDITOR
    CMP AL, 126
    JA LOOP_EDITOR

    CALL INSERTAR_CHAR_COLOR

    INC CURSOR_X
    CMP CURSOR_X, 80
    JB ACTUALIZAR_POS_EDITOR

    MOV CURSOR_X, 0
    CMP CURSOR_Y, 24
    JAE CORREGIR_LIMITE_Y
    INC CURSOR_Y
    JMP ACTUALIZAR_POS_EDITOR

CORREGIR_LIMITE_Y:
    MOV CURSOR_Y, 24
    MOV CURSOR_X, 79

ACTUALIZAR_POS_EDITOR:
    GOTOXY CURSOR_X, CURSOR_Y
    JMP LOOP_EDITOR

TECLA_BACKSPACE:
    CMP CURSOR_X, 0
    JE RETROCEDER_LINEA_ARRIBA
    DEC CURSOR_X
    GOTOXY CURSOR_X, CURSOR_Y
    CALL ELIMINAR_CHAR_COLOR
    JMP LOOP_EDITOR

RETROCEDER_LINEA_ARRIBA:
    CMP CURSOR_Y, 0
    JE LOOP_EDITOR
    DEC CURSOR_Y
    MOV CURSOR_X, 79
    GOTOXY CURSOR_X, CURSOR_Y
    CALL ELIMINAR_CHAR_COLOR
    JMP LOOP_EDITOR

; ----------------------------------------------------------------------------
; RUTINA ENTER (INSERTA SALTO Y TRASLADA TEXTO INFERIOR Y DERECHO)
; ----------------------------------------------------------------------------
EJECUTAR_ENTER:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH ES

    MOV AX, 0B800h
    MOV ES, AX
    MOV SI, 0
    MOV DI, OFFSET BUFFER_TEXTO
    MOV CX, 2000

COPIAR_A_BUF_ENTER:
    MOV AX, ES:[SI]
    MOV [DI], AX
    ADD SI, 2
    ADD DI, 2
    LOOP COPIAR_A_BUF_ENTER

    MOV SI, 3838                
    
    MOV AL, CURSOR_Y
    INC AL
    MOV AH, 160
    MUL AH
    MOV CX, AX                  

DESPLAZAR_FILAS_ABAJO:
    CMP SI, CX
    JB ENTER_CORRECTO_BAJAR

    MOV DI, SI
    ADD DI, 160
    MOV AX, WORD PTR [BUFFER_TEXTO + SI]
    MOV WORD PTR [BUFFER_TEXTO + DI], AX
    SUB SI, 2
    JMP DESPLAZAR_FILAS_ABAJO

ENTER_CORRECTO_BAJAR:
    MOV AL, CURSOR_Y
    INC AL
    MOV AH, 160
    MUL AH
    MOV DI, AX
    MOV CX, 80
    MOV BL, COLOR_ACTUAL

LIMPIAR_FILA_DESTINO:
    MOV BYTE PTR [BUFFER_TEXTO + DI], ' '
    MOV BYTE PTR [BUFFER_TEXTO + DI + 1], BL
    ADD DI, 2
    LOOP LIMPIAR_FILA_DESTINO

    MOV AL, CURSOR_Y
    MOV AH, 80
    MUL AH
    MOV DL, CURSOR_X
    MOV DH, 0
    ADD AX, DX
    SHL AX, 1
    MOV SI, AX                  

    MOV DI, SI
    ADD DI, 160                 

    MOV AL, 80
    SUB AL, CURSOR_X
    MOV CL, AL
    MOV CH, 0                   

LOOP_MOVER_Y_LIMPIAR:
    CMP CX, 0
    JE ENTER_REFRESCAR_VIDEO

    MOV AX, WORD PTR [BUFFER_TEXTO + SI]
    MOV WORD PTR [BUFFER_TEXTO + DI], AX

    MOV BYTE PTR [BUFFER_TEXTO + SI], ' '
    MOV BL, COLOR_ACTUAL
    MOV BYTE PTR [BUFFER_TEXTO + SI + 1], BL

    ADD SI, 2
    ADD DI, 2
    LOOP LOOP_MOVER_Y_LIMPIAR

ENTER_REFRESCAR_VIDEO:
    MOV SI, OFFSET BUFFER_TEXTO
    MOV DI, 0
    MOV CX, 2000

VOLCAR_VIDEO_ENTER:
    MOV AX, [SI]
    MOV ES:[DI], AX
    ADD SI, 2
    ADD DI, 2
    LOOP VOLCAR_VIDEO_ENTER

    POP ES
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX

    CMP CURSOR_Y, 24
    JAE LIMITE_Y_FINAL
    INC CURSOR_Y

LIMITE_Y_FINAL:
    GOTOXY CURSOR_X, CURSOR_Y
    JMP LOOP_EDITOR

PANTALLA_EDICION ENDP

; ----------------------------------------------------------------------------
; RESPALDO Y RESTAURACION DE VENTANA MODAL (Alt+M)
; ----------------------------------------------------------------------------
RESPALDAR_VENTANA_MODAL PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH ES

    MOV AX, 0B800h
    MOV ES, AX
    MOV DI, OFFSET BUFFER_VENTANA
    
    MOV DH, 5                   
RESPALDO_FILA:
    CMP DH, 16                  
    JAE FIN_RESPALDO
    
    MOV DL, 24                  
RESPALDO_COL:
    CMP DL, 57                  
    JAE SIG_FILA_RESP

    MOV AL, DH
    MOV BL, 80
    MUL BL
    MOV BL, DL
    MOV BH, 0
    ADD AX, BX
    SHL AX, 1
    MOV SI, AX                  

    MOV AX, ES:[SI]             
    MOV [DI], AX
    ADD DI, 2

    INC DL
    JMP RESPALDO_COL

SIG_FILA_RESP:
    INC DH
    JMP RESPALDO_FILA

FIN_RESPALDO:
    POP ES
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
RESPALDAR_VENTANA_MODAL ENDP

RESTAURAR_VENTANA_MODAL PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH ES

    MOV AX, 0B800h
    MOV ES, AX
    MOV SI, OFFSET BUFFER_VENTANA
    
    MOV DH, 5
REST_FILA:
    CMP DH, 16
    JAE FIN_RESTAURAR
    
    MOV DL, 24
REST_COL:
    CMP DL, 57
    JAE SIG_FILA_REST

    MOV AL, DH
    MOV BL, 80
    MUL BL
    MOV BL, DL
    MOV BH, 0
    ADD AX, BX
    SHL AX, 1
    MOV DI, AX                  

    MOV AX, [SI]                
    MOV ES:[DI], AX
    ADD SI, 2

    INC DL
    JMP REST_COL

SIG_FILA_REST:
    INC DH
    JMP REST_FILA

FIN_RESTAURAR:
    POP ES
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
RESTAURAR_VENTANA_MODAL ENDP

; ----------------------------------------------------------------------------
; MENU DE SELECCION DE COLOR DE TEXTO (Alt+M)
; ----------------------------------------------------------------------------
MOSTRAR_MENU_COLOR_TEXTO PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI

    CALL RESPALDAR_VENTANA_MODAL

DIBUJAR_MODAL_COLOR:
    MOV AX, 0600h
    MOV BH, 1Fh                 
    MOV CX, 0518h               
    MOV DX, 0F38h               
    INT 10h

    GOTOXY 28, 7
    LEA SI, TITULO_COLOR_M
    CALL IMPRIMIR_CADENA

    GOTOXY 29, 9
    CMP IDX_TEXTO, 0
    JNE DIB_MC0
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 11
    INT 10h
DIB_MC0:
    LEA SI, M_COL_0
    CALL IMPRIMIR_CADENA

    GOTOXY 29, 10
    CMP IDX_TEXTO, 1
    JNE DIB_MC1
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 11
    INT 10h
DIB_MC1:
    LEA SI, M_COL_1
    CALL IMPRIMIR_CADENA

    GOTOXY 29, 11
    CMP IDX_TEXTO, 2
    JNE DIB_MC2
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 11
    INT 10h
DIB_MC2:
    LEA SI, M_COL_2
    CALL IMPRIMIR_CADENA

    GOTOXY 29, 12
    CMP IDX_TEXTO, 3
    JNE DIB_MC3
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 11
    INT 10h
DIB_MC3:
    LEA SI, M_COL_3
    CALL IMPRIMIR_CADENA

    GOTOXY 29, 13
    CMP IDX_TEXTO, 4
    JNE DIB_MC4
    MOV AH, 09h
    MOV BH, 0
    MOV BL, 9Fh
    MOV CX, 11
    INT 10h
DIB_MC4:
    LEA SI, M_COL_4
    CALL IMPRIMIR_CADENA

LEER_TECLA_MODAL_COLOR:
    CALL LEER_TECLA_ESTRICTA

    CMP AH, 48h                 ; Flecha Arriba
    JE MODAL_ARRIBA

    CMP AH, 50h                 ; Flecha Abajo
    JE MODAL_ABAJO

    CMP AL, 0Dh                 ; Enter
    JE SELECCIONAR_COLOR_TEXTO

    JMP LEER_TECLA_MODAL_COLOR

MODAL_ARRIBA:
    CMP IDX_TEXTO, 0
    JE LEER_TECLA_MODAL_COLOR
    DEC IDX_TEXTO
    JMP DIBUJAR_MODAL_COLOR

MODAL_ABAJO:
    CMP IDX_TEXTO, 4
    JE LEER_TECLA_MODAL_COLOR
    INC IDX_TEXTO
    JMP DIBUJAR_MODAL_COLOR

SELECCIONAR_COLOR_TEXTO:
    CALL ACTUALIZAR_COLOR
    CALL RESTAURAR_VENTANA_MODAL

    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
MOSTRAR_MENU_COLOR_TEXTO ENDP

; ----------------------------------------------------------------------------
; CAMBIO DE FONDO DE TODA LA PAGINA (Alt+N)
; ----------------------------------------------------------------------------
CAMBIAR_COLOR_FONDO PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DI
    PUSH ES

    INC IDX_FONDO
    CMP IDX_FONDO, 3
    JB APLICAR_FONDO_GLOBAL
    MOV IDX_FONDO, 0

APLICAR_FONDO_GLOBAL:
    CALL ACTUALIZAR_COLOR

    MOV SI, OFFSET PALETA_FONDO
    MOV AL, IDX_FONDO
    MOV AH, 0
    ADD SI, AX
    MOV BL, [SI]
    AND BL, 07h
    SHL BL, 4                   

    MOV AX, 0B800h
    MOV ES, AX
    MOV DI, 1                   
    MOV CX, 2000

REPETIR_REPINTE_FONDO:
    MOV AL, ES:[DI]             
    AND AL, 0Fh                 
    OR AL, BL                   
    MOV ES:[DI], AL             
    ADD DI, 2
    LOOP REPETIR_REPINTE_FONDO

    POP ES
    POP DI
    POP CX
    POP BX
    POP AX
    RET
CAMBIAR_COLOR_FONDO ENDP

; ----------------------------------------------------------------------------
; CALCULADOR DE ATRIBUTO DE COLOR ACTUAL
; ----------------------------------------------------------------------------
ACTUALIZAR_COLOR PROC
    PUSH AX
    PUSH BX
    PUSH SI

    MOV SI, OFFSET PALETA_TEXTO
    MOV AL, IDX_TEXTO
    MOV AH, 0
    ADD SI, AX
    MOV BL, [SI]
    AND BL, 0Fh

    MOV SI, OFFSET PALETA_FONDO
    MOV AL, IDX_FONDO
    MOV AH, 0
    ADD SI, AX
    MOV BH, [SI]
    AND BH, 07h
    SHL BH, 4                  

    OR BL, BH
    MOV COLOR_ACTUAL, BL

    POP SI
    POP BX
    POP AX
    RET
ACTUALIZAR_COLOR ENDP

; ----------------------------------------------------------------------------
; DIBUJOS Y AYUDA
; ----------------------------------------------------------------------------
DIBUJAR_IMAGEN_1 PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV BL, COLOR_ACTUAL
    MOV CL, CURSOR_X
    MOV CH, CURSOR_Y

    MOV COLOR_ACTUAL, 0Ch

    MOV AL, 3
    CALL ESCRIBIR_CHAR_COLOR
    ADD CURSOR_X, 2
    CALL ESCRIBIR_CHAR_COLOR

    SUB CURSOR_X, 2
    INC CURSOR_Y
    CALL ESCRIBIR_CHAR_COLOR
    INC CURSOR_X
    CALL ESCRIBIR_CHAR_COLOR
    INC CURSOR_X
    CALL ESCRIBIR_CHAR_COLOR

    DEC CURSOR_X
    INC CURSOR_Y
    CALL ESCRIBIR_CHAR_COLOR

    MOV CURSOR_X, CL
    MOV CURSOR_Y, CH
    ADD CURSOR_X, 4
    MOV COLOR_ACTUAL, BL

    GOTOXY CURSOR_X, CURSOR_Y

    POP DX
    POP CX
    POP BX
    POP AX
    RET
DIBUJAR_IMAGEN_1 ENDP

DIBUJAR_IMAGEN_2 PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV BL, COLOR_ACTUAL
    MOV CL, CURSOR_X
    MOV CH, CURSOR_Y

    MOV COLOR_ACTUAL, 0Eh

    MOV AL, 1
    CALL ESCRIBIR_CHAR_COLOR

    MOV CURSOR_X, CL
    MOV CURSOR_Y, CH
    ADD CURSOR_X, 2
    MOV COLOR_ACTUAL, BL

    GOTOXY CURSOR_X, CURSOR_Y

    POP DX
    POP CX
    POP BX
    POP AX
    RET
DIBUJAR_IMAGEN_2 ENDP

MOSTRAR_AYUDA PROC
    GOTOXY 15, 8
    LEA SI, MSG_HELP_TITLE
    CALL IMPRIMIR_CADENA
    GOTOXY 15, 10
    LEA SI, MSG_HELP_1
    CALL IMPRIMIR_CADENA
    GOTOXY 15, 11
    LEA SI, MSG_HELP_2
    CALL IMPRIMIR_CADENA
    GOTOXY 15, 12
    LEA SI, MSG_HELP_3
    CALL IMPRIMIR_CADENA
    GOTOXY 15, 13
    LEA SI, MSG_HELP_4
    CALL IMPRIMIR_CADENA
    GOTOXY 15, 14
    LEA SI, MSG_HELP_5
    CALL IMPRIMIR_CADENA
    CALL LEER_TECLA_ESTRICTA
    GOTOXY CURSOR_X, CURSOR_Y
    RET
MOSTRAR_AYUDA ENDP

IMPRIMIR_CADENA PROC
IMPR_LOOP:
    LODSB
    CMP AL, 0
    JE FIN_IMPR
    MOV AH, 0Eh
    INT 10h
    JMP IMPR_LOOP
FIN_IMPR:
    RET
IMPRIMIR_CADENA ENDP

END MAIN