TITLE Proyecto 1 - Editor de Texto en Modo Grafico 13h (x8086)
; ===========================================================================
; Universidad Francisco Marroquin
; Arquitectura y Diseno de Computadoras - Ing. Gustavo Sanchez
; Proyecto 1: Editor de Texto interactivo estilo Nano en Modo VGA 13h (320x200)
;
; Caracteristicas Principales:
; - Modo 13h nativo (320x200, 256 colores)
; - Renderizado de tipografia grafica 8x8 mediante tabla ROM de BIOS
; - Edicion de texto enriquecido (color de texto y fondo personalizable por celda)
; - Scroll vertical continuo y navegacion libre con flechas
; - Salto de linea (Enter) y borrado/fusion de lineas (Backspace)
; - Modulo de imagenes Pixel Art (Arch Linux y Honkai) dibujadas sobre el texto
;   con soporte de transformaciones matriciales (rotacion 90 grados y espejo)
; - Persistencia binaria completa en disco (Encabezado 'ED86', tuplas [Char,FG,BG],
;   y metadatos de imagenes)
; - Menu principal interactivo y atajos Alt:
;   Alt+C, Alt+U, Alt+D, Alt+S, Alt+M, Alt+N, Alt+I, Alt+J, Alt+B, Alt+H, Alt+X, Alt+Z
; ===========================================================================

.MODEL SMALL
.386
JUMPS
.STACK 800H

; ===========================================================================
; SEGMENTO DE DATOS
; ===========================================================================
.DATA

    ; -----------------------------------------------------------------------
    ; Puntero a la Tabla de Fuentes 8x8 de la BIOS
    ; -----------------------------------------------------------------------
    FONT_SEG            DW 0
    FONT_OFF            DW 0

    ; -----------------------------------------------------------------------
    ; Variables de Control Global y Modo de Video
    ; -----------------------------------------------------------------------
    OLD_VIDEO_MODE      DB ?
    PROGRAM_STATE       DB 0            ; 0 = Menu Principal, 1 = Editor, 2 = Salir
    REDRAW_REQ          DB 1            ; 1 = Requiere repintar pantalla completa
    CURSOR_VISIBLE      DB 1            ; Estado del cursor visual
    MENU_SEL            DB 1            ; Opcion seleccionada en menu (1..3)

    ; -----------------------------------------------------------------------
    ; Dimensiones y Buffer del Documento (Nano-like multilinea)
    ; -----------------------------------------------------------------------
    MAX_LINES           EQU 80          ; Hasta 80 renglones de documento
    MAX_COLS            EQU 40          ; 40 caracteres por renglon (320px / 8px)
    VISIBLE_ROWS        EQU 23          ; 23 filas visibles en el lienzo (Y: 8..191)

    DOC_LINE_COUNT      DW 1            ; Cantidad total de lineas activas
    CUR_ROW             DW 0            ; Fila actual del cursor en el documento (0..79)
    CUR_COL             DW 0            ; Columna actual del cursor (0..39)
    VIEW_START_LINE     DW 0            ; Primera linea visible en el viewport

    ; Buffers alineados celda por celda
    DOC_CHARS           DB MAX_LINES * MAX_COLS DUP(' ')
    DOC_FG              DB MAX_LINES * MAX_COLS DUP(15)     ; Color de texto por celda
    DOC_BG              DB MAX_LINES * MAX_COLS DUP(0)      ; Color de fondo por celda
    LINE_LENGTHS        DW MAX_LINES DUP(0)                 ; Longitud activa de cada linea

    ; -----------------------------------------------------------------------
    ; Paletas Predefinidas de 3 Colores
    ; -----------------------------------------------------------------------
    CUR_FG_IDX          DB 0            ; Indice 0..2
    FG_COLORS           DB 15, 14, 10   ; 15=Blanco, 14=Amarillo, 10=Verde claro

    CUR_BG_IDX          DB 0            ; Indice 0..2
    BG_COLORS           DB 0, 1, 8      ; 0=Negro, 1=Azul marino, 8=Gris oscuro

    ; -----------------------------------------------------------------------
    ; Modulo de Imagenes Pixel Art (Heredado de Lab 6)
    ; -----------------------------------------------------------------------
    MAX_PLACED          EQU 32          ; Maximo de imagenes insertables en doc
    ENTRY_SIZE          EQU 7           ; ID(1B), X(2B), Y(2B), Flip(1B), Rot(1B)
    PLACED_COUNT        DW 0            ; Cantidad actual de imagenes insertadas
    PLACED_TABLE        DB MAX_PLACED * ENTRY_SIZE DUP(0)

    ; Variables de trabajo para renderizado de imagenes
    DRAW_IMG_ID         DB ?
    DRAW_POSX           DW ?
    DRAW_POSY           DW ?
    DRAW_FLIP           DB ?
    DRAW_ROT            DB ?
    DRAW_W              DW ?
    DRAW_H              DW ?
    DRAW_EFF_W          DW ?
    DRAW_EFF_H          DW ?
    DRAW_DATA_PTR       DW ?
    DRAW_TX             DW ?
    DRAW_TY             DW ?
    DRAW_SX             DW ?
    DRAW_SY             DW ?
    SCREEN_X            DW ?
    SCREEN_Y            DW ?
    ROW_VRAM_OFFSET     DW ?

    ; Dimensiones originales de las 2 imagenes
    IMG1_W              DW 44           ; Imagen 1: Arch Linux (44x36)
    IMG1_H              DW 36
    IMG2_W              DW 50           ; Imagen 2: Honkai (50x48)
    IMG2_H              DW 48

    ; -----------------------------------------------------------------------
    ; Archivos y Persistencia en Disco
    ; -----------------------------------------------------------------------
    CURRENT_FILENAME    DB 32 DUP(0)
    INPUT_BUFFER        DB 32 DUP(0)
    SEARCH_BUFFER       DB 32 DUP(0)
    REPLACE_BUFFER      DB 32 DUP(0)
    FILE_HANDLE         DW 0
    MAGIC_HEADER        DB 'E', 'D', '8', '6'
    HEADER_BUF          DB 8 DUP(0)
    FORCE_UPPER         DB 1            ; 1 = Convertir entrada a mayusculas, 0 = Mantener
    DRAW_LINE_ABS       DW 0            ; Fila absoluta renderizandose en editor
    DRAW_ROW_Y          DW 0            ; Coordenada Y de pantalla para la fila actual
    SR_LEN_S            DW 0            ; Longitud de cadena a buscar
    SR_LEN_R            DW 0            ; Longitud de cadena de reemplazo

    ; -----------------------------------------------------------------------
    ; Cadenas de Texto para Interfaces y Modales (Terminadas en 0)
    ; -----------------------------------------------------------------------
    TXT_APP_TITLE       DB '=== EDITOR DE TEXTO X8086 ===', 0
    TXT_APP_SUB         DB 'MODO GRAFICO 13H (320x200)', 0
    TXT_MENU_BOX_TOP    DB '+------------------------------+', 0
    TXT_MENU_OPT1       DB '  [1] Crear un archivo nuevo   ', 0
    TXT_MENU_OPT2       DB '  [2] Abrir archivo existente  ', 0
    TXT_MENU_OPT3       DB '  [3] Salir                    ', 0
    TXT_MENU_HINT       DB '[Arriba/Abajo] Elegir [Enter] Ir [Alt+X] Salir', 0

    TXT_MODAL_NEW_T     DB 'CREAR NUEVO ARCHIVO', 0
    TXT_MODAL_NEW_P     DB 'Nombre de archivo:', 0
    TXT_MODAL_OPEN_T    DB 'ABRIR ARCHIVO EXISTENTE', 0
    TXT_MODAL_OPEN_P    DB 'Nombre de archivo:', 0
    TXT_MODAL_CANCEL    DB '[Alt+Z] Cancelar y volver al menu', 0
    TXT_ERR_CREATE      DB 'Error al crear archivo en disco!', 0
    TXT_ERR_OPEN        DB 'Error: Archivo no encontrado o invalido!', 0
    TXT_PRESS_KEY       DB 'Presione cualquier tecla...', 0

    TXT_CHEATSHEET      DB '^S:Guard ^H:Ayuda ^B:Buscar ^I/^J:Img ^M:FG ^N:BG', 0
    TXT_LBL_FILE        DB 'DOC:', 0
    TXT_LBL_LN          DB ' L:', 0
    TXT_LBL_COL         DB ' C:', 0
    TXT_LBL_FG          DB ' FG:', 0
    TXT_LBL_BG          DB ' BG:', 0

    TXT_HELP_T          DB '=== AYUDA - ATAJOS DE TECLADO ===', 0
    TXT_H_C             DB 'Alt+C: Centrar cursor en renglon', 0
    TXT_H_U             DB 'Alt+U: Ir al primer renglon del doc', 0
    TXT_H_D             DB 'Alt+D: Ir al ultimo renglon del doc', 0
    TXT_H_S             DB 'Alt+S: Guardar en disco y salir', 0
    TXT_H_M             DB 'Alt+M: Alternar color de letra (FG)', 0
    TXT_H_N             DB 'Alt+N: Alternar color de fondo (BG)', 0
    TXT_H_I             DB 'Alt+I: Insertar Imagen 1 (Arch)', 0
    TXT_H_J             DB 'Alt+J: Insertar Imagen 2 (Honkai)', 0
    TXT_H_B             DB 'Alt+B: Buscar y Reemplazar texto', 0
    TXT_H_H             DB 'Alt+H: Mostrar esta ayuda', 0
    TXT_H_ED            DB 'Flechas: Moverse | Enter: Salto | BS: Borrar', 0

    TXT_SR_TITLE        DB 'BUSCAR Y REEMPLAZAR', 0
    TXT_SR_PROMPT_F     DB 'Buscar palabra: ', 0
    TXT_SR_PROMPT_R     DB 'Reemplazar por: ', 0

    ; -----------------------------------------------------------------------
    ; Matrices de Pixeles de las Imagenes (Color 48 = Transparente)
    ; -----------------------------------------------------------------------
    IMG1_DATA LABEL BYTE
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,15,15,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,15,15,15,15,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,15,15,15,15,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,15,15,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,55,55,55,55,15,15,55,55,55,55,55,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,55,55,15,15,15,15,55,55,55,55,55,48,48,48,48,48,48,48
    db 48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,55,55,48,48,15,15,15,15,55,55,55,55,48,48,48,48,48,48
    db 48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,55,48,48,48,48,15,15,55,55,55,55,55,48,48,48,48,48
    db 48,48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48
    db 48,55,55,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,55,48,48,48
    db 48,55,55,55,55,55,55,55,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,55,55,55,55,55,55,55,55,48,48
    db 48,48,48,55,55,55,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,55,55,55,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,8,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,8,48,8,48,48,48,48,48,48,48,48,48,48,48,8,48,48,48,48,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 8,8,8,8,8,48,48,48,48,48,48,48,48,48,48,8,48,48,48,48,55,48,48,48,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 8,48,48,48,8,48,8,8,8,48,48,8,8,8,48,8,8,8,48,48,55,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 8,48,48,48,8,48,8,48,48,48,8,48,48,48,8,8,48,48,8,48,55,48,48,48,55,48,55,55,8,48,55,48,48,55,48,55,48,48,55,48,48,48,48,48
    db 8,8,8,8,8,48,8,48,48,48,8,48,48,48,48,8,48,48,8,48,55,48,48,48,55,48,55,48,55,48,55,48,48,55,48,48,55,55,48,48,55,48,55,48
    db 8,48,48,48,8,48,8,48,48,48,8,48,48,48,48,8,48,48,8,48,55,48,48,48,55,48,55,48,55,48,55,48,48,55,48,48,48,55,48,48,48,55,48,48
    db 8,48,48,48,8,48,8,48,48,48,8,48,48,48,8,8,48,48,8,48,55,48,48,48,55,48,55,48,55,48,55,48,48,55,48,48,55,55,48,48,55,48,55,48
    db 8,48,48,48,8,48,8,48,48,48,48,8,8,8,48,8,48,48,8,48,55,55,55,48,55,48,55,48,55,48,48,55,55,48,55,48,55,48,55,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48

    IMG2_DATA LABEL BYTE
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,15,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,15,7,24,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,24,24,24,7,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,7,24,24,24,24,24,7,7,7,7,7,7,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,15,7,7,48,48,48,48,48,48,48,48,48,48,48,48,7,24,7,48,48,48,48,48,7,24,42,42,42,42,42,42,42,42,42,42,42,8,7,48,48,48,48,48,48
    db 48,48,48,48,48,48,7,7,7,7,48,48,48,48,48,48,48,48,48,48,15,24,7,24,7,48,48,48,48,24,42,42,42,42,42,42,42,42,42,42,42,42,8,7,48,48,48,48,7,15
    db 48,48,48,48,48,7,7,15,7,7,48,48,48,48,48,48,48,48,48,48,7,7,15,7,7,48,48,48,7,24,42,42,42,42,42,42,42,42,42,42,42,7,24,48,48,48,48,7,7,24
    db 48,48,48,48,48,7,7,15,7,15,7,7,7,48,48,48,48,48,48,7,24,15,7,7,48,48,48,48,7,24,8,24,24,24,24,24,24,42,42,42,42,8,7,15,15,15,7,7,7,7
    db 48,48,48,48,7,7,15,7,7,7,7,7,7,7,15,15,15,15,7,24,7,15,7,7,15,15,15,7,7,24,24,24,24,24,8,24,24,42,42,42,24,24,24,24,24,8,7,15,24,15
    db 48,48,48,7,24,15,7,7,7,24,7,15,7,24,24,24,24,24,8,7,15,15,7,24,24,24,24,7,7,15,7,24,24,8,7,7,7,24,42,42,8,7,15,7,7,24,15,7,7,48
    db 48,48,48,24,7,15,7,15,7,7,15,7,7,8,24,24,7,24,7,15,7,7,7,15,7,24,7,15,15,7,24,24,24,24,7,15,7,7,42,42,7,7,7,7,7,7,7,24,7,15
    db 48,48,15,7,15,7,7,7,24,7,7,7,7,7,24,7,15,7,7,7,15,7,7,7,7,7,15,15,7,7,7,7,7,7,15,7,24,42,42,42,7,7,7,7,7,15,7,24,24,7
    db 48,48,7,7,15,7,7,7,7,7,7,7,7,7,7,7,7,7,7,15,7,7,15,7,7,15,7,7,7,15,7,7,7,7,15,7,42,42,42,42,7,7,7,7,7,7,24,24,24,15
    db 48,15,7,15,7,7,7,7,7,7,7,24,8,24,7,7,7,7,7,7,7,7,7,7,15,7,7,7,7,7,7,7,7,15,7,24,42,42,24,24,42,7,24,24,7,7,24,24,7,48
    db 48,7,7,7,7,7,24,7,15,7,7,24,8,24,7,7,7,7,15,7,7,7,24,24,7,7,7,7,24,7,7,7,7,15,7,8,7,8,24,24,8,42,42,24,7,7,48,48,48,48
    db 7,7,15,7,15,7,24,7,15,7,7,7,7,7,7,7,7,15,7,7,7,7,24,24,7,7,15,7,7,15,7,7,15,7,24,24,24,8,11,11,8,42,42,24,7,7,15,48,48,48
    db 7,7,7,7,7,24,7,7,7,7,24,7,7,7,7,24,24,7,7,7,15,7,7,7,15,7,7,7,7,7,7,7,7,7,8,24,7,8,24,24,8,42,7,7,7,7,15,48,48,48
    db 7,15,7,15,7,8,24,24,24,24,8,24,7,7,7,24,24,7,7,15,15,7,15,7,7,7,7,24,24,7,24,24,24,8,8,24,24,42,24,24,42,42,24,7,7,7,48,48,48,48
    db 7,7,7,7,24,24,8,24,24,24,24,24,7,7,24,24,24,24,7,7,7,24,7,15,7,7,15,7,8,24,24,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,24,15,48,48
    db 7,7,7,7,15,7,24,24,24,24,24,24,7,7,24,8,24,24,24,24,24,8,8,7,15,7,7,15,7,8,7,15,15,15,15,15,7,7,7,7,7,15,15,15,15,24,7,48,48,48
    db 48,48,48,48,48,48,15,15,15,15,7,24,7,15,24,7,24,24,24,24,24,24,24,24,24,7,15,7,7,24,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,24,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,7,7,7,7,48,48,15,15,15,15,15,15,15,7,24,7,15,7,7,8,24,24,24,42,42,42,42,42,42,8,24,7,7,7,15,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,7,24,48,48,48,48,48,48,48,48,48,48,48,7,24,7,15,15,7,7,48,7,42,42,42,42,42,24,24,7,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,24,7,15,7,24,24,42,42,42,42,42,7,7,15,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,15,24,7,15,7,7,42,42,42,42,42,8,15,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,15,24,24,24,42,42,42,42,7,24,7,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,42,42,42,7,24,7,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,7,42,42,7,7,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,24,42,42,42,7,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,42,42,42,24,15,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,7,7,42,24,7,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,15,7,7,7,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48
    db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48

; ===========================================================================
; SEGMENTO DE CODIGO
; ===========================================================================
.CODE

; ---------------------------------------------------------------------------
; PROCEDIMIENTO PRINCIPAL (ENTRY POINT)
; ---------------------------------------------------------------------------
MAIN PROC FAR
    MOV AX, @DATA
    MOV DS, AX
    MOV ES, AX

    ; Guardar modo de video actual de DOS para restaurarlo al salir
    MOV AH, 0FH
    INT 10H
    MOV OLD_VIDEO_MODE, AL

    ; Obtener puntero a la fuente 8x8 de BIOS en ROM
    CALL INIT_FONT_POINTER

    ; Cambiar a modo grafico VGA 13h (320x200, 256 colores)
    CALL SET_VIDEO_MODE

    ; Inicializar estado en Menu Principal
    MOV PROGRAM_STATE, 0
    MOV REDRAW_REQ, 1

MAIN_LOOP:
    CMP PROGRAM_STATE, 2
    JE  EXIT_APP

    CMP PROGRAM_STATE, 0
    JE  EXEC_MENU_CYCLE

    ; Estado 1: Pantalla de Edicion
    CALL RUN_EDITOR_CYCLE
    JMP MAIN_LOOP

EXEC_MENU_CYCLE:
    CALL RUN_MENU_CYCLE
    JMP MAIN_LOOP

EXIT_APP:
    ; Restaurar modo de video original
    CALL RESTORE_VIDEO_MODE

    ; Salir a DOS limpiamente
    MOV AX, 4C00H
    INT 21H
MAIN ENDP

; ---------------------------------------------------------------------------
; INIT_FONT_POINTER: Obtiene direccion ES:BP de la tabla 8x8 de BIOS
; ---------------------------------------------------------------------------
INIT_FONT_POINTER PROC NEAR
    PUSH ES
    PUSH BP
    MOV AX, 1130H
    MOV BH, 03H             ; Tabla 8x8 de caracteres
    INT 10H
    MOV FONT_SEG, ES
    MOV FONT_OFF, BP
    POP BP
    POP ES
    RET
INIT_FONT_POINTER ENDP

; ---------------------------------------------------------------------------
; SET_VIDEO_MODE / RESTORE_VIDEO_MODE
; ---------------------------------------------------------------------------
SET_VIDEO_MODE PROC NEAR
    MOV AX, 0013H
    INT 10H
    RET
SET_VIDEO_MODE ENDP

RESTORE_VIDEO_MODE PROC NEAR
    MOV AH, 00H
    MOV AL, OLD_VIDEO_MODE
    INT 10H
    RET
RESTORE_VIDEO_MODE ENDP

; ===========================================================================
; MOTOR GRAFICO BASICO EN MODO 13H (VRAM = 0A000h)
; ===========================================================================

; ---------------------------------------------------------------------------
; DRAW_CHAR_8X8: Renderiza un caracter 8x8 usando la fuente en ROM directamente a VRAM
; Entrada: AL = Caracter ASCII
;          CX = Coordenada X (0..312)
;          DX = Coordenada Y (0..192)
;          BL = Color de Fuente (FG, 0..255)
;          BH = Color de Fondo (BG, 0..255, 0FFh = Transparente)
; ---------------------------------------------------------------------------
DRAW_CHAR_8X8 PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI
    PUSH DS
    PUSH ES

    ; Verificacion de limites de pantalla
    CMP CX, 312
    JA  DC8_EXIT
    CMP DX, 192
    JA  DC8_EXIT

    ; Calcular direccion del glifo en la tabla FONT_SEG:FONT_OFF + (AL * 8)
    MOV AH, 0
    SHL AX, 3               ; AX = AL * 8
    ADD AX, FONT_OFF
    MOV SI, AX
    MOV DS, FONT_SEG

    ; ES apunta a memoria de video 0A000h
    MOV AX, 0A000H
    MOV ES, AX

    ; Offset VRAM inicial = DX * 320 + CX
    MOV AX, DX
    MOV DI, AX
    SHL DI, 8               ; DX * 256
    SHL AX, 6               ; DX * 64
    ADD DI, AX
    ADD DI, CX

    ; Bucle exterior: 8 filas del caracter
    MOV CH, 8
DC8_ROW_LOOP:
    LODSB                   ; AL = mascara de 8 bits de la fila
    MOV AH, AL

    ; Bucle interior: 8 pixeles de izquierda a derecha (bit 7 a bit 0)
    MOV CL, 8
DC8_PIX_LOOP:
    TEST AH, 80H
    JZ  DC8_IS_BG
    ; Pixel de fuente (FG)
    MOV ES:[DI], BL
    JMP DC8_ADV_PIX

DC8_IS_BG:
    CMP BH, 0FFH            ; 0FFh significa no pintar fondo (transparente)
    JE  DC8_ADV_PIX
    MOV ES:[DI], BH

DC8_ADV_PIX:
    INC DI
    SHL AH, 1
    DEC CL
    JNZ DC8_PIX_LOOP

    ; Siguiente fila en VRAM: +320 - 8 = +312
    ADD DI, 312
    DEC CH
    JNZ DC8_ROW_LOOP

DC8_EXIT:
    POP ES
    POP DS
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_CHAR_8X8 ENDP

; ---------------------------------------------------------------------------
; DRAW_STRING_8X8: Renderiza cadena terminada en 0
; Entrada: DS:SI = Puntero a cadena
;          CX = X inicial
;          DX = Y inicial
;          BL = Color FG
;          BH = Color BG
; ---------------------------------------------------------------------------
DRAW_STRING_8X8 PROC NEAR
    PUSH AX
    PUSH CX
    PUSH SI
DS8_LOOP:
    LODSB
    CMP AL, 0
    JE  DS8_DONE
    CALL DRAW_CHAR_8X8
    ADD CX, 8
    CMP CX, 312
    JA  DS8_DONE
    JMP DS8_LOOP
DS8_DONE:
    POP SI
    POP CX
    POP AX
    RET
DRAW_STRING_8X8 ENDP

; ---------------------------------------------------------------------------
; FILL_RECT: Rellena rectangulo solido en VRAM
; Entrada: CX = X (0..319)
;          DX = Y (0..199)
;          SI = Ancho (Width)
;          BP = Alto (Height)
;          AL = Color
; ---------------------------------------------------------------------------
FILL_RECT PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH DI
    PUSH ES
    PUSH BP

    MOV BX, 0A000H
    MOV ES, BX

FR_ROW_LOOP:
    CMP BP, 0
    JE  FR_DONE
    CMP DX, 200
    JAE FR_DONE

    ; Offset = DX * 320 + CX
    MOV BX, DX
    MOV DI, BX
    SHL DI, 8
    SHL BX, 6
    ADD DI, BX
    ADD DI, CX

    ; Rellenar fila de SI pixeles
    PUSH CX
    MOV CX, SI
    PUSH DI
    REP STOSB
    POP DI
    POP CX

    INC DX
    DEC BP
    JMP FR_ROW_LOOP

FR_DONE:
    POP BP
    POP ES
    POP DI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
FILL_RECT ENDP

; ---------------------------------------------------------------------------
; DRAW_DEC_2DIG: Dibuja numero de 2 digitos (AX en 0..99) en posicion (CX, DX)
; ---------------------------------------------------------------------------
DRAW_DEC_2DIG PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    XOR AH, AH
    MOV BL, 10
    DIV BL                  ; AL = decenas, AH = unidades
    MOV DL, AH              ; DL = unidades
    PUSH DX                 ; Guardar unidades en la pila

    ; Dibujar decenas
    ADD AL, '0'
    MOV BL, 15              ; Blanco
    MOV BH, 0               ; Negro
    CALL DRAW_CHAR_8X8

    ; Dibujar unidades
    ADD CX, 8
    POP DX                  ; DL = unidades
    MOV AL, DL
    ADD AL, '0'
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_CHAR_8X8

    POP DX
    POP CX
    POP BX
    POP AX
    RET
DRAW_DEC_2DIG ENDP

; ===========================================================================
; MENU PRINCIPAL
; ===========================================================================

RUN_MENU_CYCLE PROC NEAR
    CMP REDRAW_REQ, 1
    JNE RM_WAIT_KEY
    CALL DRAW_MAIN_MENU
    MOV REDRAW_REQ, 0

RM_WAIT_KEY:
    MOV AH, 00H
    INT 16H

    ; Atajo Alt+X (Scan Code 2Dh) para salida directa
    CMP AH, 2DH
    JE  RM_EXIT_ACTION

    ; Teclas de flecha Arriba (48h) y Abajo (50h)
    CMP AH, 48H
    JE  RM_UP
    CMP AH, 50H
    JE  RM_DOWN

    ; Enter (AL = 0Dh)
    CMP AL, 0DH
    JE  RM_SELECT

    ; Opciones rapidas '1', '2', '3'
    CMP AL, '1'
    JE  RM_OP1
    CMP AL, '2'
    JE  RM_OP2
    CMP AL, '3'
    JE  RM_OP3
    CMP AL, 'x'
    JE  RM_EXIT_ACTION
    CMP AL, 'X'
    JE  RM_EXIT_ACTION

    RET

RM_UP:
    CMP MENU_SEL, 1
    JBE RM_UP_WRAP
    DEC MENU_SEL
    JMP RM_CHANGE
RM_UP_WRAP:
    MOV MENU_SEL, 3
RM_CHANGE:
    MOV REDRAW_REQ, 1
    RET

RM_DOWN:
    CMP MENU_SEL, 3
    JAE RM_DN_WRAP
    INC MENU_SEL
    JMP RM_CHANGE
RM_DN_WRAP:
    MOV MENU_SEL, 1
    JMP RM_CHANGE

RM_OP1:
    MOV MENU_SEL, 1
    JMP RM_SELECT
RM_OP2:
    MOV MENU_SEL, 2
    JMP RM_SELECT
RM_OP3:
    MOV MENU_SEL, 3
    JMP RM_SELECT

RM_SELECT:
    CMP MENU_SEL, 1
    JE  RM_ACT_NEW
    CMP MENU_SEL, 2
    JE  RM_ACT_OPEN
    JMP RM_EXIT_ACTION

RM_ACT_NEW:
    CALL FLOW_CREATE_NEW_FILE
    RET

RM_ACT_OPEN:
    CALL FLOW_OPEN_FILE
    RET

RM_EXIT_ACTION:
    MOV PROGRAM_STATE, 2
    RET
RUN_MENU_CYCLE ENDP

; ---------------------------------------------------------------------------
; DRAW_MAIN_MENU: Renderiza interfaz grafica pulida del menu principal
; ---------------------------------------------------------------------------
DRAW_MAIN_MENU PROC NEAR
    ; 1. Limpiar pantalla con azul oscuro (color 1)
    MOV CX, 0
    MOV DX, 0
    MOV SI, 320
    MOV BP, 200
    MOV AL, 1
    CALL FILL_RECT

    ; 2. Barra de titulo superior (negro con linea dorada)
    MOV CX, 0
    MOV DX, 12
    MOV SI, 320
    MOV BP, 24
    MOV AL, 0
    CALL FILL_RECT

    MOV CX, 44
    MOV DX, 16
    LEA SI, TXT_APP_TITLE
    MOV BL, 14              ; Amarillo
    MOV BH, 0               ; Fondo negro
    CALL DRAW_STRING_8X8

    MOV CX, 60
    MOV DX, 26
    LEA SI, TXT_APP_SUB
    MOV BL, 11              ; Cian
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 3. Ventana central del menu con sombra visual
    ; Sombra oscura
    MOV CX, 38
    MOV DX, 62
    MOV SI, 252
    MOV BP, 94
    MOV AL, 0
    CALL FILL_RECT

    ; Cuadro principal gris oscuro/azul (color 8 o 24)
    MOV CX, 34
    MOV DX, 58
    MOV SI, 252
    MOV BP, 94
    MOV AL, 8
    CALL FILL_RECT

    ; Borde interior
    MOV CX, 36
    MOV DX, 60
    MOV SI, 248
    MOV BP, 90
    MOV AL, 7               ; Gris claro
    CALL FILL_RECT

    ; Interior negro
    MOV CX, 38
    MOV DX, 62
    MOV SI, 244
    MOV BP, 86
    MOV AL, 0
    CALL FILL_RECT

    ; 4. Opciones de texto con selector destacado
    ; Opcion 1
    MOV CX, 50
    MOV DX, 76
    CMP MENU_SEL, 1
    JNE DMM_OPT1_NORM
    ; Destacado
    MOV BL, 0               ; Letra negra
    MOV BH, 14              ; Fondo amarillo
    JMP DMM_P1
DMM_OPT1_NORM:
    MOV BL, 15              ; Blanco
    MOV BH, 0               ; Negro
DMM_P1:
    LEA SI, TXT_MENU_OPT1
    CALL DRAW_STRING_8X8

    ; Opcion 2
    MOV CX, 50
    MOV DX, 96
    CMP MENU_SEL, 2
    JNE DMM_OPT2_NORM
    MOV BL, 0
    MOV BH, 14
    JMP DMM_P2
DMM_OPT2_NORM:
    MOV BL, 15
    MOV BH, 0
DMM_P2:
    LEA SI, TXT_MENU_OPT2
    CALL DRAW_STRING_8X8

    ; Opcion 3
    MOV CX, 50
    MOV DX, 116
    CMP MENU_SEL, 3
    JNE DMM_OPT3_NORM
    MOV BL, 0
    MOV BH, 14
    JMP DMM_P3
DMM_OPT3_NORM:
    MOV BL, 15
    MOV BH, 0
DMM_P3:
    LEA SI, TXT_MENU_OPT3
    CALL DRAW_STRING_8X8

    ; 5. Barra inferior con instructivo
    MOV CX, 0
    MOV DX, 184
    MOV SI, 320
    MOV BP, 16
    MOV AL, 0
    CALL FILL_RECT

    MOV CX, 12
    MOV DX, 188
    LEA SI, TXT_MENU_HINT
    MOV BL, 11              ; Cian
    MOV BH, 0
    CALL DRAW_STRING_8X8

    RET
DRAW_MAIN_MENU ENDP

; ===========================================================================
; FLUJOS DE GESTION DE ARCHIVOS (CREAR / ABRIR)
; ===========================================================================

; ---------------------------------------------------------------------------
; READ_STRING_INPUT: Lee texto en recuadro grafico.
; Soporta: Backspace, Enter, y Alt+Z para cancelar.
; Salida: AX = Longitud leida, o 0FFFFh si se presiono Alt+Z.
; ---------------------------------------------------------------------------
READ_STRING_INPUT PROC NEAR
    ; Limpiar buffer de entrada
    XOR BX, BX
RSI_CLR_BUF:
    MOV INPUT_BUFFER[BX], 0
    INC BX
    CMP BX, 32
    JB  RSI_CLR_BUF

    XOR BX, BX              ; BX = cursor/longitud en buffer
RSI_KEY_LOOP:
    ; Dibujar cadena actual en pantalla (X=50, Y=104)
    PUSH BX
    ; Limpiar caja de texto (fondo negro)
    MOV CX, 48
    MOV DX, 102
    MOV SI, 220
    MOV BP, 12
    MOV AL, 0
    CALL FILL_RECT

    ; Dibujar texto ingresado
    MOV CX, 50
    MOV DX, 104
    LEA SI, INPUT_BUFFER
    MOV BL, 15              ; Blanco
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Dibujar cursor parpadeante / subrayado
    POP BX
    PUSH BX
    MOV CX, BX
    SHL CX, 3               ; BX * 8
    ADD CX, 50
    MOV DX, 111
    MOV SI, 8
    MOV BP, 2
    MOV AL, 14              ; Barra amarilla
    CALL FILL_RECT
    POP BX

    ; Esperar pulsacion de tecla
    MOV AH, 00H
    INT 16H

    ; Alt+Z (Scan Code 2Ch) -> Cancelar
    CMP AH, 2CH
    JNE RSI_CHK_ENTER
    MOV AX, 0FFFFH
    RET

RSI_CHK_ENTER:
    CMP AL, 0DH             ; Enter
    JE  RSI_FINISH

    CMP AL, 08H             ; Backspace
    JE  RSI_BKSP

    ; Validar caracteres imprimibles y extensiones
    CMP AL, 32
    JB  RSI_KEY_LOOP
    CMP AL, 126
    JA  RSI_KEY_LOOP

    ; Forzar mayusculas solo si FORCE_UPPER esta activo
    CMP FORCE_UPPER, 1
    JNE RSI_ADD_CHAR
    CMP AL, 'a'
    JB  RSI_ADD_CHAR
    CMP AL, 'z'
    JA  RSI_ADD_CHAR
    SUB AL, 20H             ; Convertir a mayuscula obligatoriamente

RSI_ADD_CHAR:
    CMP BX, 24              ; Maximo 24 caracteres de nombre
    JAE RSI_KEY_LOOP
    MOV INPUT_BUFFER[BX], AL
    INC BX
    MOV INPUT_BUFFER[BX], 0
    JMP RSI_KEY_LOOP

RSI_BKSP:
    CMP BX, 0
    JE  RSI_KEY_LOOP
    DEC BX
    MOV INPUT_BUFFER[BX], 0
    JMP RSI_KEY_LOOP

RSI_FINISH:
    MOV AX, BX
    RET
READ_STRING_INPUT ENDP

; ---------------------------------------------------------------------------
; FLOW_CREATE_NEW_FILE: Flujo para crear un archivo nuevo (Mayusculas obligatorias)
; ---------------------------------------------------------------------------
FLOW_CREATE_NEW_FILE PROC NEAR
FCN_RETRY:
    ; Dibujar recuadro de dialogo
    CALL DRAW_FILE_DIALOG_BOX
    MOV CX, 70
    MOV DX, 76
    LEA SI, TXT_MODAL_NEW_T
    MOV BL, 14
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 50
    MOV DX, 92
    LEA SI, TXT_MODAL_NEW_P
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 50
    MOV DX, 122
    LEA SI, TXT_MODAL_CANCEL
    MOV BL, 11
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Leer nombre de archivo (Mayusculas obligatorias)
    MOV FORCE_UPPER, 1
    CALL READ_STRING_INPUT
    CMP AX, 0FFFFH          ; Cancelo con Alt+Z
    JE  FCN_CANCEL

    CMP AX, 0               ; Si envio vacio, reintentar
    JE  FCN_RETRY

    ; Copiar a CURRENT_FILENAME
    XOR BX, BX
FCN_COPY_NAME:
    MOV AL, INPUT_BUFFER[BX]
    MOV CURRENT_FILENAME[BX], AL
    INC BX
    CMP BX, 32
    JB  FCN_COPY_NAME

    ; Intentar crear archivo fisico en disco mediante DOS INT 21h, AH=3Ch
    MOV AH, 3CH
    MOV CX, 0000H           ; Atributo normal
    LEA DX, CURRENT_FILENAME
    INT 21H
    JC  FCN_ERROR

    ; Cerrar archivo recien creado
    MOV BX, AX
    MOV AH, 3EH
    INT 21H

    ; Inicializar estado del documento en blanco
    CALL RESET_DOCUMENT_BUFFER

    ; Pasar a pantalla de edicion
    MOV PROGRAM_STATE, 1
    MOV REDRAW_REQ, 1
    RET

FCN_ERROR:
    ; Notificar error en pantalla
    MOV CX, 50
    MOV DX, 134
    LEA SI, TXT_ERR_CREATE
    MOV BL, 12              ; Rojo claro
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 50
    MOV DX, 144
    LEA SI, TXT_PRESS_KEY
    MOV BL, 7
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV AH, 00H
    INT 16H
    JMP FCN_RETRY

FCN_CANCEL:
    MOV PROGRAM_STATE, 0
    MOV REDRAW_REQ, 1
    RET
FLOW_CREATE_NEW_FILE ENDP

; ---------------------------------------------------------------------------
; FLOW_OPEN_FILE: Flujo para abrir archivo (Insensible a mayusculas/minusculas)
; ---------------------------------------------------------------------------
FLOW_OPEN_FILE PROC NEAR
FOF_RETRY:
    CALL DRAW_FILE_DIALOG_BOX
    MOV CX, 60
    MOV DX, 76
    LEA SI, TXT_MODAL_OPEN_T
    MOV BL, 14
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 50
    MOV DX, 92
    LEA SI, TXT_MODAL_OPEN_P
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 50
    MOV DX, 122
    LEA SI, TXT_MODAL_CANCEL
    MOV BL, 11
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Leer nombre de archivo (Normalizado a mayusculas para apertura insensible a caso)
    MOV FORCE_UPPER, 1
    CALL READ_STRING_INPUT
    CMP AX, 0FFFFH
    JE  FOF_CANCEL
    CMP AX, 0
    JE  FOF_RETRY

    ; Copiar a CURRENT_FILENAME
    XOR BX, BX
FOF_COPY_NAME:
    MOV AL, INPUT_BUFFER[BX]
    MOV CURRENT_FILENAME[BX], AL
    INC BX
    CMP BX, 32
    JB  FOF_COPY_NAME

    ; Intentar abrir archivo con DOS INT 21h, AH=3Dh (Modo lectura)
    MOV AH, 3DH
    MOV AL, 00H             ; Read only
    LEA DX, CURRENT_FILENAME
    INT 21H
    JC  FOF_ERROR

    MOV FILE_HANDLE, AX

    ; Cargar y deserializar estructura binaria del archivo
    CALL LOAD_BINARY_DOCUMENT
    JC  FOF_READ_ERROR

    ; Cerrar handle
    MOV AH, 3EH
    MOV BX, FILE_HANDLE
    INT 21H

    ; Ingresar a la pantalla de edicion
    MOV PROGRAM_STATE, 1
    MOV REDRAW_REQ, 1
    RET

FOF_READ_ERROR:
    MOV AH, 3EH
    MOV BX, FILE_HANDLE
    INT 21H

FOF_ERROR:
    MOV CX, 30
    MOV DX, 134
    LEA SI, TXT_ERR_OPEN
    MOV BL, 12              ; Rojo
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 50
    MOV DX, 144
    LEA SI, TXT_PRESS_KEY
    MOV BL, 7
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV AH, 00H
    INT 16H
    JMP FOF_RETRY

FOF_CANCEL:
    MOV PROGRAM_STATE, 0
    MOV REDRAW_REQ, 1
    RET
FLOW_OPEN_FILE ENDP

; ---------------------------------------------------------------------------
; DRAW_FILE_DIALOG_BOX: Dibuja ventana modal para nombres de archivos
; ---------------------------------------------------------------------------
DRAW_FILE_DIALOG_BOX PROC NEAR
    ; Fondo atenuado / sombra
    MOV CX, 24
    MOV DX, 64
    MOV SI, 276
    MOV BP, 96
    MOV AL, 0
    CALL FILL_RECT

    ; Cuadro principal
    MOV CX, 20
    MOV DX, 60
    MOV SI, 276
    MOV BP, 96
    MOV AL, 1               ; Azul
    CALL FILL_RECT

    ; Marco interior
    MOV CX, 22
    MOV DX, 62
    MOV SI, 272
    MOV BP, 92
    MOV AL, 15              ; Blanco
    CALL FILL_RECT

    MOV CX, 24
    MOV DX, 64
    MOV SI, 268
    MOV BP, 88
    MOV AL, 0               ; Interior negro
    CALL FILL_RECT
    RET
DRAW_FILE_DIALOG_BOX ENDP

; ===========================================================================
; SERIALIZACION Y DESERIALIZACION BINARIA DEL ARCHIVO (PERSISTENCIA)
; ===========================================================================

; ---------------------------------------------------------------------------
; RESET_DOCUMENT_BUFFER: Deja el documento en estado nuevo vacio
; ---------------------------------------------------------------------------
RESET_DOCUMENT_BUFFER PROC NEAR
    MOV DOC_LINE_COUNT, 1
    MOV CUR_ROW, 0
    MOV CUR_COL, 0
    MOV VIEW_START_LINE, 0
    MOV PLACED_COUNT, 0

    ; Rellenar todo el buffer de texto con espacios
    XOR BX, BX
RDB_CHARS:
    MOV DOC_CHARS[BX], ' '
    MOV DOC_FG[BX], 15
    MOV DOC_BG[BX], 0
    INC BX
    CMP BX, MAX_LINES * MAX_COLS
    JB  RDB_CHARS

    ; Limpiar longitudes
    XOR BX, BX
RDB_LENS:
    MOV LINE_LENGTHS[BX], 0
    ADD BX, 2
    CMP BX, MAX_LINES * 2
    JB  RDB_LENS

    RET
RESET_DOCUMENT_BUFFER ENDP

; ---------------------------------------------------------------------------
; SAVE_BINARY_DOCUMENT: Serializa a disco la estructura exacta requerida:
; 1. Encabezado (Magic 'ED86', DOC_LINE_COUNT, PLACED_COUNT)
; 2. Lineas de texto y atributos tupla [ASCII, FG, BG]
; 3. Bloque de metadatos de imagenes insertadas
; ---------------------------------------------------------------------------
SAVE_BINARY_DOCUMENT PROC NEAR
    ; Recrear / sobrescribir archivo
    MOV AH, 3CH
    MOV CX, 0000H
    LEA DX, CURRENT_FILENAME
    INT 21H
    JC  SBD_RET
    MOV FILE_HANDLE, AX

    ; 1. Escribir Encabezado (8 bytes)
    MOV HEADER_BUF[0], 'E'
    MOV HEADER_BUF[1], 'D'
    MOV HEADER_BUF[2], '8'
    MOV HEADER_BUF[3], '6'

    MOV AX, DOC_LINE_COUNT
    MOV WORD PTR HEADER_BUF[4], AX
    MOV AX, PLACED_COUNT
    MOV WORD PTR HEADER_BUF[6], AX

    MOV AH, 40H
    MOV BX, FILE_HANDLE
    MOV CX, 8
    LEA DX, HEADER_BUF
    INT 21H

    ; 2. Escribir Lineas de Texto
    XOR BP, BP              ; BP = indice de linea 0..DOC_LINE_COUNT-1
SBD_LINES_LOOP:
    CMP BP, DOC_LINE_COUNT
    JAE SBD_WRITE_IMAGES

    ; Escribir 1 byte con la longitud de esta linea
    MOV SI, BP
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    MOV INPUT_BUFFER[0], AL ; Guardar temporalmente en INPUT_BUFFER[0]

    MOV AH, 40H
    MOV BX, FILE_HANDLE
    MOV CX, 1
    LEA DX, INPUT_BUFFER
    INT 21H

    ; Si la longitud es mayor que cero, escribir tuplas [Char, FG, BG]
    MOV SI, BP
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    CMP CX, 0
    JE  SBD_NEXT_LINE

    ; Escribir N caracteres
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    LEA DX, DOC_CHARS
    ADD DX, AX
    MOV AH, 40H
    MOV BX, FILE_HANDLE
    ; CX ya tiene la longitud
    INT 21H

    ; Escribir N colores FG
    MOV SI, BP
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    LEA DX, DOC_FG
    ADD DX, AX
    MOV AH, 40H
    MOV BX, FILE_HANDLE
    INT 21H

    ; Escribir N colores BG
    MOV SI, BP
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    LEA DX, DOC_BG
    ADD DX, AX
    MOV AH, 40H
    MOV BX, FILE_HANDLE
    INT 21H

SBD_NEXT_LINE:
    INC BP
    JMP SBD_LINES_LOOP

SBD_WRITE_IMAGES:
    ; 3. Escribir Bloque de Metadatos de Imagenes
    MOV AX, PLACED_COUNT
    CMP AX, 0
    JE  SBD_CLOSE

    MOV CX, ENTRY_SIZE
    MUL CX                  ; AX = PLACED_COUNT * 7
    MOV CX, AX

    MOV AH, 40H
    MOV BX, FILE_HANDLE
    LEA DX, PLACED_TABLE
    INT 21H

SBD_CLOSE:
    MOV AH, 3EH
    MOV BX, FILE_HANDLE
    INT 21H

SBD_RET:
    RET
SAVE_BINARY_DOCUMENT ENDP

; ---------------------------------------------------------------------------
; LOAD_BINARY_DOCUMENT: Carga y valida el documento guardado en disco
; Salida: Carry flag = 1 en caso de error
; ---------------------------------------------------------------------------
LOAD_BINARY_DOCUMENT PROC NEAR
    ; 1. Leer Encabezado (8 bytes)
    MOV AH, 3FH
    MOV BX, FILE_HANDLE
    MOV CX, 8
    LEA DX, HEADER_BUF
    INT 21H
    JC  LBD_ERR
    CMP AX, 8
    JNE LBD_ERR

    ; Verificar Magic 'ED86'
    CMP HEADER_BUF[0], 'E'
    JNE LBD_ERR
    CMP HEADER_BUF[1], 'D'
    JNE LBD_ERR
    CMP HEADER_BUF[2], '8'
    JNE LBD_ERR
    CMP HEADER_BUF[3], '6'
    JNE LBD_ERR

    ; Limpiar buffers
    CALL RESET_DOCUMENT_BUFFER

    ; Extraer totales validados
    MOV AX, WORD PTR HEADER_BUF[4]
    CMP AX, MAX_LINES
    JBE LBD_LINES_OK
    MOV AX, MAX_LINES
LBD_LINES_OK:
    MOV DOC_LINE_COUNT, AX

    MOV AX, WORD PTR HEADER_BUF[6]
    CMP AX, MAX_PLACED
    JBE LBD_PLACED_OK
    MOV AX, MAX_PLACED
LBD_PLACED_OK:
    MOV PLACED_COUNT, AX

    ; 2. Leer Lineas de Texto
    XOR BP, BP
LBD_LINES_LOOP:
    CMP BP, DOC_LINE_COUNT
    JAE LBD_READ_IMAGES

    ; Leer 1 byte de longitud
    MOV AH, 3FH
    MOV BX, FILE_HANDLE
    MOV CX, 1
    LEA DX, INPUT_BUFFER
    INT 21H
    JC  LBD_ERR

    XOR AX, AX
    MOV AL, INPUT_BUFFER[0]
    CMP AX, MAX_COLS
    JBE LBD_STORE_LEN
    MOV AX, MAX_COLS
LBD_STORE_LEN:
    MOV SI, BP
    SHL SI, 1
    MOV LINE_LENGTHS[SI], AX

    CMP AX, 0
    JE  LBD_NEXT_LINE

    ; Leer caracteres
    MOV CX, AX
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    LEA DX, DOC_CHARS
    ADD DX, AX
    MOV AH, 3FH
    MOV BX, FILE_HANDLE
    INT 21H
    JC  LBD_ERR

    ; Leer colores FG
    MOV SI, BP
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    LEA DX, DOC_FG
    ADD DX, AX
    MOV AH, 3FH
    MOV BX, FILE_HANDLE
    INT 21H
    JC  LBD_ERR

    ; Leer colores BG
    MOV SI, BP
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    LEA DX, DOC_BG
    ADD DX, AX
    MOV AH, 3FH
    MOV BX, FILE_HANDLE
    INT 21H
    JC  LBD_ERR

LBD_NEXT_LINE:
    INC BP
    JMP LBD_LINES_LOOP

LBD_READ_IMAGES:
    ; 3. Leer imagenes si existen
    MOV AX, PLACED_COUNT
    CMP AX, 0
    JE  LBD_SUCCESS

    MOV CX, ENTRY_SIZE
    MUL CX
    MOV CX, AX
    MOV AH, 3FH
    MOV BX, FILE_HANDLE
    LEA DX, PLACED_TABLE
    INT 21H
    JC  LBD_ERR

LBD_SUCCESS:
    CLC
    RET

LBD_ERR:
    STC
    RET
LOAD_BINARY_DOCUMENT ENDP

; ===========================================================================
; PANTALLA DE EDICION (COMPORTAMIENTO TIPO NANO & GRAFICOS)
; ===========================================================================

RUN_EDITOR_CYCLE PROC NEAR
    CMP REDRAW_REQ, 1
    JNE REC_CHECK_KEY
    CALL REDRAW_EDITOR_SCREEN
    MOV REDRAW_REQ, 0

REC_CHECK_KEY:
    ; Leer tecla sin bloqueo o con INT 16h
    MOV AH, 00H
    INT 16H

    ; Despachar segun tipo de tecla (ASCII o Escaneo Extendido)
    CALL DISPATCH_EDITOR_KEY
    RET
RUN_EDITOR_CYCLE ENDP

; ---------------------------------------------------------------------------
; DISPATCH_EDITOR_KEY: Manejo completo de atajos Alt, flechas, Enter y Backspace
; ---------------------------------------------------------------------------
DISPATCH_EDITOR_KEY PROC NEAR
    ; 1. Verificar atajos extendidos de la tecla Alt (AL=0 o AL=E0h)
    CMP AL, 0
    JE  DEK_CHECK_ALT_OR_ARROWS
    CMP AL, 0E0H
    JE  DEK_CHECK_ALT_OR_ARROWS

    ; 2. Teclas de edicion basica
    CMP AL, 08H             ; Backspace
    JE  DEK_BKSP
    CMP AL, 0DH             ; Enter
    JE  DEK_ENTER

    ; 3. Entrada de texto regular (Alfanumericos y puntuacion permitida)
    ; Permitidos: 'A'..'Z', 'a'..'z', '0'..'9', espacio, '"', ',', '.', ':'
    CMP AL, ' '
    JB  DEK_CHECK_ALT_OR_ARROWS
    CMP AL, 126
    JA  DEK_RET

    ; Verificar si es puntuacion o alfanumerico
    CALL IS_ALLOWED_CHAR
    JNC DEK_RET             ; Si no esta permitido, descartar

    ; Insertar caracter en el buffer
    CALL INSERT_CHAR_AT_CURSOR
    RET

DEK_BKSP:
    CALL HANDLE_BACKSPACE
    RET

DEK_ENTER:
    CALL HANDLE_ENTER
    RET

DEK_CHECK_ALT_OR_ARROWS:
    ; Flechas de direccion
    CMP AH, 48H             ; Flecha Arriba
    JE  DEK_ARROW_UP
    CMP AH, 50H             ; Flecha Abajo
    JE  DEK_ARROW_DOWN
    CMP AH, 4BH             ; Flecha Izquierda
    JE  DEK_ARROW_LEFT
    CMP AH, 4DH             ; Flecha Derecha
    JE  DEK_ARROW_RIGHT

    ; Atajos Alt del Editor
    CMP AH, 2EH             ; Alt+C: Centrar cursor en linea actual
    JE  DEK_ALT_C
    CMP AH, 16H             ; Alt+U: Cursor a primera linea
    JE  DEK_ALT_U
    CMP AH, 20H             ; Alt+D: Cursor a ultima linea
    JE  DEK_ALT_D
    CMP AH, 1FH             ; Alt+S: Guardar y salir
    JE  DEK_ALT_S
    CMP AH, 32H             ; Alt+M: Ciclar color de fuente (FG)
    JE  DEK_ALT_M
    CMP AH, 31H             ; Alt+N: Ciclar color de fondo (BG)
    JE  DEK_ALT_N
    CMP AH, 17H             ; Alt+I: Insertar Imagen 1
    JE  DEK_ALT_I
    CMP AH, 24H             ; Alt+J: Insertar Imagen 2
    JE  DEK_ALT_J
    CMP AH, 30H             ; Alt+B: Buscar y Reemplazar
    JE  DEK_ALT_B
    CMP AH, 23H             ; Alt+H: Ventana de Ayuda
    JE  DEK_ALT_H

DEK_RET:
    RET

; Despachos directos
DEK_ARROW_UP:
    CALL MOVE_CURSOR_UP
    RET
DEK_ARROW_DOWN:
    CALL MOVE_CURSOR_DOWN
    RET
DEK_ARROW_LEFT:
    CALL MOVE_CURSOR_LEFT
    RET
DEK_ARROW_RIGHT:
    CALL MOVE_CURSOR_RIGHT
    RET

DEK_ALT_C:
    CALL ACTION_CENTER_CURSOR
    RET
DEK_ALT_U:
    CALL ACTION_GOTO_FIRST_LINE
    RET
DEK_ALT_D:
    CALL ACTION_GOTO_LAST_LINE
    RET
DEK_ALT_S:
    CALL ACTION_SAVE_AND_EXIT
    RET
DEK_ALT_M:
    CALL ACTION_CYCLE_FG
    RET
DEK_ALT_N:
    CALL ACTION_CYCLE_BG
    RET
DEK_ALT_I:
    CALL ACTION_INSERT_IMG1
    RET
DEK_ALT_J:
    CALL ACTION_INSERT_IMG2
    RET
DEK_ALT_B:
    CALL ACTION_SEARCH_REPLACE
    RET
DEK_ALT_H:
    CALL ACTION_SHOW_HELP
    RET
DISPATCH_EDITOR_KEY ENDP

; ---------------------------------------------------------------------------
; IS_ALLOWED_CHAR: Valida caracteres alfanumericos y puntuacion requerida
; Salida: Carry flag = 1 si es permitido, 0 si no
; ---------------------------------------------------------------------------
IS_ALLOWED_CHAR PROC NEAR
    ; Letras 'A'..'Z'
    CMP AL, 'A'
    JB  IAC_CHK_LOWER
    CMP AL, 'Z'
    JBE IAC_YES

IAC_CHK_LOWER:
    ; Letras 'a'..'z'
    CMP AL, 'a'
    JB  IAC_CHK_NUM
    CMP AL, 'z'
    JBE IAC_YES

IAC_CHK_NUM:
    ; Numeros '0'..'9'
    CMP AL, '0'
    JB  IAC_CHK_PUNCT
    CMP AL, '9'
    JBE IAC_YES

IAC_CHK_PUNCT:
    ; Puntuacion permitida: espacio (32), comillas (34), coma (44), punto (46), dos puntos (58)
    CMP AL, ' '
    JE  IAC_YES
    CMP AL, '"'
    JE  IAC_YES
    CMP AL, ','
    JE  IAC_YES
    CMP AL, '.'
    JE  IAC_YES
    CMP AL, ':'
    JE  IAC_YES

    CLC
    RET

IAC_YES:
    STC
    RET
IS_ALLOWED_CHAR ENDP

; ---------------------------------------------------------------------------
; INSERT_CHAR_AT_CURSOR: Insercion estilo nano con desplazamiento a la derecha
; ---------------------------------------------------------------------------
INSERT_CHAR_AT_CURSOR PROC NEAR
    PUSH AX
    ; Validar que la linea actual no sobrepase el limite de 40 caracteres
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    CMP CX, MAX_COLS
    JAE ICA_RET             ; Renglon lleno

    ; Calcular offset base de la linea: CUR_ROW * MAX_COLS
    MOV AX, CUR_ROW
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX              ; DI = Offset base de la fila

    ; Desplazar caracteres desde CX hasta CUR_COL hacia la derecha
    CMP CX, CUR_COL
    JBE ICA_NO_SHIFT

    PUSH CX
ICA_SHIFT_LOOP:
    MOV SI, DI
    ADD SI, CX
    DEC SI                  ; SI = DI + CX - 1

    MOV DL, DOC_CHARS[SI]
    MOV DOC_CHARS[SI+1], DL

    MOV DL, DOC_FG[SI]
    MOV DOC_FG[SI+1], DL

    MOV DL, DOC_BG[SI]
    MOV DOC_BG[SI+1], DL

    DEC CX
    CMP CX, CUR_COL
    JA  ICA_SHIFT_LOOP
    POP CX

ICA_NO_SHIFT:
    ; Insertar caracter y sus atributos activos
    POP AX                  ; Recuperar caracter a insertar
    PUSH AX
    MOV SI, DI
    ADD SI, CUR_COL
    MOV DOC_CHARS[SI], AL

    ; Asignar color de fuente activo
    XOR BX, BX
    MOV BL, CUR_FG_IDX
    MOV DL, FG_COLORS[BX]
    MOV DOC_FG[SI], DL

    ; Asignar color de fondo activo
    MOV BL, CUR_BG_IDX
    MOV DL, BG_COLORS[BX]
    MOV DOC_BG[SI], DL

    ; Incrementar longitud de la linea actual
    MOV SI, CUR_ROW
    SHL SI, 1
    INC LINE_LENGTHS[SI]

    ; Avanzar cursor a la derecha
    INC CUR_COL
    CMP CUR_COL, MAX_COLS
    JB  ICA_DONE
    MOV CUR_COL, MAX_COLS - 1

ICA_DONE:
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1

ICA_RET:
    POP AX
    RET
INSERT_CHAR_AT_CURSOR ENDP

; ---------------------------------------------------------------------------
; HANDLE_BACKSPACE: Borrado interactivo y reajuste/fusion de lineas
; ---------------------------------------------------------------------------
HANDLE_BACKSPACE PROC NEAR
    CMP CUR_COL, 0
    JE  HB_CHECK_LINE_MERGE

    ; Borrado dentro de la misma linea: retroceder y desplazar hacia la izquierda
    DEC CUR_COL
    MOV AX, CUR_ROW
    MOV DX, MAX_COLS
    MUL DX
    ADD AX, CUR_COL
    MOV DI, AX                     ; DI = CUR_ROW * 40 + CUR_COL

    MOV SI, CUR_ROW
    SHL SI, 1
    DEC LINE_LENGTHS[SI]

    ; CX = cantidad a desplazar = LINE_LENGTHS[SI] - CUR_COL
    MOV CX, LINE_LENGTHS[SI]
    SUB CX, CUR_COL
    JCXZ HB_PAD_ONE_SPACE

HB_SHIFT_LEFT:
    MOV DL, DOC_CHARS[DI + 1]
    MOV DOC_CHARS[DI], DL

    MOV DL, DOC_FG[DI + 1]
    MOV DOC_FG[DI], DL

    MOV DL, DOC_BG[DI + 1]
    MOV DOC_BG[DI], DL

    INC DI
    LOOP HB_SHIFT_LEFT

HB_PAD_ONE_SPACE:
    MOV DOC_CHARS[DI], ' '
    MOV REDRAW_REQ, 1
    RET

HB_CHECK_LINE_MERGE:
    ; Si estamos en la columna 0 y no es la primera linea, intentar fusionar
    CMP CUR_ROW, 0
    JE  HB_DONE

    ; Longitudes de linea actual y anterior
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]       ; Longitud actual

    MOV BX, CUR_ROW
    DEC BX
    SHL BX, 1
    MOV DX, LINE_LENGTHS[BX]       ; Longitud previa

    MOV AX, DX
    ADD AX, CX
    CMP AX, MAX_COLS
    JA  HB_MOVE_TO_PREV_END        ; No cabe la fusion completa

    ; Concatenar linea actual al final de la linea previa
    PUSH CX
    PUSH DX

    MOV AX, CUR_ROW
    DEC AX
    MOV DX, MAX_COLS
    MUL DX
    MOV BP, AX                     ; BP = Base de linea previa

    MOV AX, CUR_ROW
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX                     ; DI = Base de linea actual

    POP DX                         ; DX = prev_len
    POP CX                         ; CX = cur_len

    JCXZ HB_MERGE_COPIED           ; Si no hay caracteres que mover, terminar

    MOV SI, DI                     ; SI = origen (linea actual)
    ADD BP, DX
    MOV DI, BP                     ; DI = destino (linea previa + prev_len)

HB_MERGE_LOOP:
    MOV AL, DOC_CHARS[SI]
    MOV DOC_CHARS[DI], AL

    MOV AL, DOC_FG[SI]
    MOV DOC_FG[DI], AL

    MOV AL, DOC_BG[SI]
    MOV DOC_BG[DI], AL

    INC SI
    INC DI
    INC DX
    DEC CX
    JNZ HB_MERGE_LOOP

HB_MERGE_COPIED:
    ; Actualizar longitud de la linea anterior
    MOV BX, CUR_ROW
    DEC BX
    SHL BX, 1
    MOV LINE_LENGTHS[BX], DX

    ; Posicionar cursor donde inicio la fusion
    DEC CUR_ROW
    SUB DX, CX
    MOV CUR_COL, DX

    ; Eliminar linea actual del buffer y subir las siguientes
    MOV AX, CUR_ROW
    INC AX
    CALL DELETE_DOC_LINE

    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1
    RET

HB_MOVE_TO_PREV_END:
    DEC CUR_ROW
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    MOV CUR_COL, AX
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1

HB_DONE:
    RET
HANDLE_BACKSPACE ENDP

; ---------------------------------------------------------------------------
; HANDLE_ENTER: Salto de linea (Split line estilo nano)
; ---------------------------------------------------------------------------
HANDLE_ENTER PROC NEAR
    MOV AX, DOC_LINE_COUNT
    CMP AX, MAX_LINES
    JAE HE_RET                     ; No exceder buffer maximo

    ; Insertar linea vacia despues de CUR_ROW
    MOV AX, CUR_ROW
    INC AX
    CALL INSERT_DOC_EMPTY_LINE

    ; Dividir contenido: lo que este a la derecha de CUR_COL pasa al nuevo renglon
    MOV AX, CUR_ROW
    MOV DX, MAX_COLS
    MUL DX
    ADD AX, CUR_COL
    MOV SI, AX                     ; SI = CUR_ROW * 40 + CUR_COL (origen)

    MOV AX, CUR_ROW
    INC AX
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX                     ; DI = (CUR_ROW + 1) * 40 (destino)

    MOV BP, CUR_ROW
    SHL BP, 1
    MOV CX, LINE_LENGTHS[BP]       ; Total previo

    CMP CUR_COL, CX
    JAE HE_SPLIT_NO_CHARS          ; Nada que mover

    SUB CX, CUR_COL                ; CX = cantidad de caracteres a mover
    MOV DX, CX                     ; DX = nueva longitud de linea siguiente

HE_SPLIT_LOOP:
    MOV AL, DOC_CHARS[SI]
    MOV DOC_CHARS[DI], AL
    MOV DOC_CHARS[SI], ' '

    MOV AL, DOC_FG[SI]
    MOV DOC_FG[DI], AL

    MOV AL, DOC_BG[SI]
    MOV DOC_BG[DI], AL

    INC SI
    INC DI
    DEC CX
    JNZ HE_SPLIT_LOOP
    JMP HE_SPLIT_DONE

HE_SPLIT_NO_CHARS:
    XOR DX, DX

HE_SPLIT_DONE:
    ; Asignar longitud a la nueva linea
    MOV BP, CUR_ROW
    INC BP
    SHL BP, 1
    MOV LINE_LENGTHS[BP], DX

    ; Acortar longitud de la linea actual a CUR_COL
    MOV BP, CUR_ROW
    SHL BP, 1
    MOV AX, CUR_COL
    MOV LINE_LENGTHS[BP], AX

    ; Mover cursor al inicio de la siguiente linea
    INC CUR_ROW
    MOV CUR_COL, 0
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1

HE_RET:
    RET
HANDLE_ENTER ENDP

; ---------------------------------------------------------------------------
; INSERT_DOC_EMPTY_LINE: Desplaza lineas hacia abajo para insertar una libre en AX
; ---------------------------------------------------------------------------
INSERT_DOC_EMPTY_LINE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV BP, AX                     ; BP = Fila destino que quedara vacia

    ; Desplazar desde DOC_LINE_COUNT - 1 hacia abajo hasta BP
    MOV BX, DOC_LINE_COUNT
IDEL_LOOP:
    CMP BX, BP
    JBE IDEL_CLEAR_TARGET

    ; Desplazar linea (BX-1) a linea BX
    MOV AX, BX
    DEC AX
    MOV DX, MAX_COLS
    MUL DX
    MOV SI, AX                     ; SI = Origen

    MOV AX, BX
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX                     ; DI = Destino

    MOV CX, MAX_COLS
IDEL_COPY_LINE:
    MOV AL, DOC_CHARS[SI]
    MOV DOC_CHARS[DI], AL
    MOV AL, DOC_FG[SI]
    MOV DOC_FG[DI], AL
    MOV AL, DOC_BG[SI]
    MOV DOC_BG[DI], AL
    INC SI
    INC DI
    LOOP IDEL_COPY_LINE

    ; Desplazar longitud
    MOV SI, BX
    DEC SI
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    MOV DI, BX
    SHL DI, 1
    MOV LINE_LENGTHS[DI], AX

    DEC BX
    JMP IDEL_LOOP

IDEL_CLEAR_TARGET:
    ; Limpiar la linea BP
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX
    MOV CX, MAX_COLS
IDEL_FILL_SPACE:
    MOV DOC_CHARS[DI], ' '
    MOV DOC_FG[DI], 15
    MOV DOC_BG[DI], 0
    INC DI
    LOOP IDEL_FILL_SPACE

    MOV SI, BP
    SHL SI, 1
    MOV LINE_LENGTHS[SI], 0

    INC DOC_LINE_COUNT

    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
INSERT_DOC_EMPTY_LINE ENDP

; ---------------------------------------------------------------------------
; DELETE_DOC_LINE: Elimina la linea AX y desplaza hacia arriba las inferiores
; ---------------------------------------------------------------------------
DELETE_DOC_LINE PROC NEAR
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    PUSH SI
    PUSH DI

    MOV BP, AX                     ; Fila a eliminar
DDL_LOOP:
    MOV AX, BP
    INC AX
    CMP AX, DOC_LINE_COUNT
    JAE DDL_TAIL_CLEAR

    ; Copiar de (BP + 1) a BP
    MOV AX, BP
    INC AX
    MOV DX, MAX_COLS
    MUL DX
    MOV SI, AX                     ; Origen

    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX                     ; Destino

    MOV CX, MAX_COLS
DDL_COPY_UP:
    MOV AL, DOC_CHARS[SI]
    MOV DOC_CHARS[DI], AL
    MOV AL, DOC_FG[SI]
    MOV DOC_FG[DI], AL
    MOV AL, DOC_BG[SI]
    MOV DOC_BG[DI], AL
    INC SI
    INC DI
    LOOP DDL_COPY_UP

    MOV SI, BP
    INC SI
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    MOV DI, BP
    SHL DI, 1
    MOV LINE_LENGTHS[DI], AX

    INC BP
    JMP DDL_LOOP

DDL_TAIL_CLEAR:
    DEC DOC_LINE_COUNT
    CMP DOC_LINE_COUNT, 0
    JNE DDL_FIN
    MOV DOC_LINE_COUNT, 1

DDL_FIN:
    POP DI
    POP SI
    POP DX
    POP CX
    POP BX
    POP AX
    RET
DELETE_DOC_LINE ENDP

; ---------------------------------------------------------------------------
; ADJUST_VIEWPORT: Auto-scroll vertical para mantener el cursor en pantalla
; ---------------------------------------------------------------------------
ADJUST_VIEWPORT PROC NEAR
    ; Rango visible: VIEW_START_LINE a (VIEW_START_LINE + VISIBLE_ROWS - 1)
    MOV AX, CUR_ROW
    CMP AX, VIEW_START_LINE
    JAE AV_CHK_LOWER

    ; El cursor esta por encima del viewport
    MOV VIEW_START_LINE, AX
    RET

AV_CHK_LOWER:
    MOV BX, VIEW_START_LINE
    ADD BX, VISIBLE_ROWS
    DEC BX
    CMP AX, BX
    JBE AV_DONE

    ; El cursor esta por debajo del viewport
    SUB AX, VISIBLE_ROWS
    INC AX
    MOV VIEW_START_LINE, AX

AV_DONE:
    RET
ADJUST_VIEWPORT ENDP

; ---------------------------------------------------------------------------
; MOVIMIENTO DE CURSOR CON FLECHAS
; ---------------------------------------------------------------------------
MOVE_CURSOR_UP PROC NEAR
    CMP CUR_ROW, 0
    JE  MCU_RET
    DEC CUR_ROW
    ; Ajustar columna si excede la longitud del renglon
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    CMP CUR_COL, AX
    JBE MCU_ADJ
    MOV CUR_COL, AX
MCU_ADJ:
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1
MCU_RET:
    RET
MOVE_CURSOR_UP ENDP

MOVE_CURSOR_DOWN PROC NEAR
    MOV AX, DOC_LINE_COUNT
    DEC AX
    CMP CUR_ROW, AX
    JAE MCD_RET
    INC CUR_ROW
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    CMP CUR_COL, AX
    JBE MCD_ADJ
    MOV CUR_COL, AX
MCD_ADJ:
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1
MCD_RET:
    RET
MOVE_CURSOR_DOWN ENDP

MOVE_CURSOR_LEFT PROC NEAR
    CMP CUR_COL, 0
    JE  MCL_WRAP
    DEC CUR_COL
    MOV REDRAW_REQ, 1
    RET
MCL_WRAP:
    CMP CUR_ROW, 0
    JE  MCL_RET
    DEC CUR_ROW
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    MOV CUR_COL, AX
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1
MCL_RET:
    RET
MOVE_CURSOR_LEFT ENDP

MOVE_CURSOR_RIGHT PROC NEAR
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    CMP CUR_COL, AX
    JAE MCR_WRAP
    INC CUR_COL
    MOV REDRAW_REQ, 1
    RET
MCR_WRAP:
    MOV AX, DOC_LINE_COUNT
    DEC AX
    CMP CUR_ROW, AX
    JAE MCR_RET
    INC CUR_ROW
    MOV CUR_COL, 0
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1
MCR_RET:
    RET
MOVE_CURSOR_RIGHT ENDP

; ---------------------------------------------------------------------------
; ACCIONES DE ATAJOS DE TECLADO (ALT + ...)
; ---------------------------------------------------------------------------

ACTION_CENTER_CURSOR PROC NEAR
    ; Alt+C: Centrar cursor en la linea actual (col = len / 2)
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    SHR AX, 1
    MOV CUR_COL, AX
    MOV REDRAW_REQ, 1
    RET
ACTION_CENTER_CURSOR ENDP

ACTION_GOTO_FIRST_LINE PROC NEAR
    ; Alt+U: Ir a la primera linea del documento
    MOV CUR_ROW, 0
    MOV CUR_COL, 0
    MOV VIEW_START_LINE, 0
    MOV REDRAW_REQ, 1
    RET
ACTION_GOTO_FIRST_LINE ENDP

ACTION_GOTO_LAST_LINE PROC NEAR
    ; Alt+D: Ir a la ultima linea activa del documento
    MOV AX, DOC_LINE_COUNT
    DEC AX
    MOV CUR_ROW, AX
    MOV CUR_COL, 0
    CALL ADJUST_VIEWPORT
    MOV REDRAW_REQ, 1
    RET
ACTION_GOTO_LAST_LINE ENDP

ACTION_CYCLE_FG PROC NEAR
    ; Alt+M: Alternar color de fuente (ciclo 0..2)
    INC CUR_FG_IDX
    CMP CUR_FG_IDX, 3
    JB  ACF_OK
    MOV CUR_FG_IDX, 0
ACF_OK:
    MOV REDRAW_REQ, 1
    RET
ACTION_CYCLE_FG ENDP

ACTION_CYCLE_BG PROC NEAR
    ; Alt+N: Alternar color de fondo (ciclo 0..2)
    INC CUR_BG_IDX
    CMP CUR_BG_IDX, 3
    JB  ACB_OK
    MOV CUR_BG_IDX, 0
ACB_OK:
    MOV REDRAW_REQ, 1
    RET
ACTION_CYCLE_BG ENDP

ACTION_INSERT_IMG1 PROC NEAR
    ; Alt+I: Insertar Imagen Pixel Art 1 (Arch Linux) en coordenadas del cursor
    MOV AL, 1
    CALL INSERT_IMAGE_AT_DOC_POS
    RET
ACTION_INSERT_IMG1 ENDP

ACTION_INSERT_IMG2 PROC NEAR
    ; Alt+J: Insertar Imagen Pixel Art 2 (Honkai) en coordenadas del cursor
    MOV AL, 2
    CALL INSERT_IMAGE_AT_DOC_POS
    RET
ACTION_INSERT_IMG2 ENDP

INSERT_IMAGE_AT_DOC_POS PROC NEAR
    ; AL = ID (1 o 2)
    PUSH AX
    MOV AX, PLACED_COUNT
    CMP AX, MAX_PLACED
    JAE IIA_FULL

    ; Coordenadas absolutas de pixeles en el documento:
    ; X = CUR_COL * 8
    ; Y = CUR_ROW * 8
    MOV AX, CUR_COL
    SHL AX, 3
    MOV CX, AX

    MOV AX, CUR_ROW
    SHL AX, 3
    MOV DX, AX

    ; Offset = PLACED_COUNT * ENTRY_SIZE
    MOV AX, PLACED_COUNT
    MOV BX, ENTRY_SIZE
    MUL BX
    LEA DI, PLACED_TABLE
    ADD DI, AX

    POP AX                  ; Recuperar ID
    MOV [DI], AL
    MOV [DI+1], CX          ; X
    MOV [DI+3], DX          ; Y
    MOV BYTE PTR [DI+5], 0  ; Flip = 0
    MOV BYTE PTR [DI+6], 0  ; Rot = 0

    INC PLACED_COUNT
    MOV REDRAW_REQ, 1
    RET

IIA_FULL:
    POP AX
    RET
INSERT_IMAGE_AT_DOC_POS ENDP

ACTION_SAVE_AND_EXIT PROC NEAR
    ; Alt+S: Guardar documento completo en disco y salir a DOS
    CALL SAVE_BINARY_DOCUMENT
    MOV PROGRAM_STATE, 2
    RET
ACTION_SAVE_AND_EXIT ENDP

ACTION_SHOW_HELP PROC NEAR
    ; Alt+H: Mostrar ventana modal con instrucciones y atajos
    CALL DRAW_HELP_WINDOW
    MOV AH, 00H
    INT 16H
    MOV REDRAW_REQ, 1
    RET
ACTION_SHOW_HELP ENDP

DRAW_HELP_WINDOW PROC NEAR
    ; Marco oscuro con fondo azul
    MOV CX, 14
    MOV DX, 18
    MOV SI, 292
    MOV BP, 164
    MOV AL, 0
    CALL FILL_RECT

    MOV CX, 10
    MOV DX, 14
    MOV SI, 292
    MOV BP, 164
    MOV AL, 1               ; Azul
    CALL FILL_RECT

    MOV CX, 12
    MOV DX, 16
    MOV SI, 288
    MOV BP, 160
    MOV AL, 15              ; Borde blanco
    CALL FILL_RECT

    MOV CX, 14
    MOV DX, 18
    MOV SI, 284
    MOV BP, 156
    MOV AL, 0               ; Interior negro
    CALL FILL_RECT

    ; Titulo
    MOV CX, 28
    MOV DX, 24
    LEA SI, TXT_HELP_T
    MOV BL, 14
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Lista de atajos
    MOV CX, 22
    MOV DX, 40
    LEA SI, TXT_H_C
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 50
    LEA SI, TXT_H_U
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 60
    LEA SI, TXT_H_D
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 70
    LEA SI, TXT_H_S
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 80
    LEA SI, TXT_H_M
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 90
    LEA SI, TXT_H_N
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 100
    LEA SI, TXT_H_I
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 110
    LEA SI, TXT_H_J
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 120
    LEA SI, TXT_H_B
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 130
    LEA SI, TXT_H_H
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 142
    LEA SI, TXT_H_ED
    MOV BL, 10              ; Verde
    CALL DRAW_STRING_8X8

    MOV CX, 22
    MOV DX, 156
    LEA SI, TXT_PRESS_KEY
    MOV BL, 11              ; Cian
    CALL DRAW_STRING_8X8

    RET
DRAW_HELP_WINDOW ENDP

; ---------------------------------------------------------------------------
; ACTION_SEARCH_REPLACE: Modal Buscar y Reemplazar (Alt+B)
; ---------------------------------------------------------------------------
ACTION_SEARCH_REPLACE PROC NEAR
    ; Cuadro modal
    MOV CX, 20
    MOV DX, 50
    MOV SI, 280
    MOV BP, 90
    MOV AL, 0
    CALL FILL_RECT

    MOV CX, 16
    MOV DX, 46
    MOV SI, 280
    MOV BP, 90
    MOV AL, 4               ; Rojo oscuro
    CALL FILL_RECT

    MOV CX, 18
    MOV DX, 48
    MOV SI, 276
    MOV BP, 86
    MOV AL, 14              ; Borde amarillo
    CALL FILL_RECT

    MOV CX, 20
    MOV DX, 50
    MOV SI, 272
    MOV BP, 82
    MOV AL, 0
    CALL FILL_RECT

    MOV CX, 80
    MOV DX, 56
    LEA SI, TXT_SR_TITLE
    MOV BL, 14
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Solicitar palabra a buscar
    MOV CX, 28
    MOV DX, 72
    LEA SI, TXT_SR_PROMPT_F
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Permitir mayusculas y minusculas exactas en busqueda
    MOV FORCE_UPPER, 0
    CALL READ_STRING_INPUT
    CMP AX, 0FFFFH
    JE  ASR_CANCEL
    CMP AX, 0
    JE  ASR_CANCEL

    ; Copiar a SEARCH_BUFFER
    XOR BX, BX
ASR_CP1:
    MOV DL, INPUT_BUFFER[BX]
    MOV SEARCH_BUFFER[BX], DL
    INC BX
    CMP BX, 32
    JB  ASR_CP1

    ; Solicitar palabra de reemplazo
    MOV CX, 28
    MOV DX, 92
    LEA SI, TXT_SR_PROMPT_R
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV FORCE_UPPER, 0
    CALL READ_STRING_INPUT
    CMP AX, 0FFFFH
    JE  ASR_CANCEL

    ; Copiar a REPLACE_BUFFER
    XOR BX, BX
ASR_CP2:
    MOV DL, INPUT_BUFFER[BX]
    MOV REPLACE_BUFFER[BX], DL
    INC BX
    CMP BX, 32
    JB  ASR_CP2

    ; Ejecutar reemplazo en todo el documento
    CALL EXECUTE_SEARCH_REPLACE

ASR_CANCEL:
    MOV FORCE_UPPER, 1      ; Restaurar modo mayusculas por defecto
    MOV REDRAW_REQ, 1
    RET
ACTION_SEARCH_REPLACE ENDP

; ---------------------------------------------------------------------------
; EXECUTE_SEARCH_REPLACE: Sustitucion de subcadenas en el buffer de lineas
; ---------------------------------------------------------------------------
EXECUTE_SEARCH_REPLACE PROC NEAR
    ; Calcular longitud de busqueda
    XOR BX, BX
ESR_LEN_S:
    CMP SEARCH_BUFFER[BX], 0
    JE  ESR_GOT_S_LEN
    INC BX
    CMP BX, 32
    JB  ESR_LEN_S
ESR_GOT_S_LEN:
    CMP BX, 0
    JE  ESR_RET
    MOV SR_LEN_S, BX

    ; Calcular longitud de reemplazo
    XOR BX, BX
ESR_LEN_R:
    CMP REPLACE_BUFFER[BX], 0
    JE  ESR_GOT_R_LEN
    INC BX
    CMP BX, 32
    JB  ESR_LEN_R
ESR_GOT_R_LEN:
    MOV SR_LEN_R, BX

    ; Recorrer cada linea del documento (0..DOC_LINE_COUNT-1)
    XOR BP, BP              ; BP = Fila
ESR_ROW_LOOP:
    CMP BP, DOC_LINE_COUNT
    JAE ESR_RET

    MOV SI, BP
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    CMP AX, 0
    JE  ESR_NEXT_ROW

    ; Recorrer columnas de la linea
    XOR BX, BX              ; BX = Columna actual
ESR_COL_LOOP:
    ; Verificar si queda suficiente espacio para comparar: BX + SR_LEN_S <= line_len
    MOV SI, BP
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    MOV DI, BX
    ADD DI, SR_LEN_S
    CMP DI, AX
    JA  ESR_NEXT_ROW

    ; Comparar subcadena en DOC_CHARS[BP*40 + BX] con SEARCH_BUFFER
    PUSH BX                 ; Preservar columna BX
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    ADD AX, BX
    MOV SI, AX              ; SI = Offset en DOC_CHARS

    XOR DI, DI
ESR_CMP_LOOP:
    CMP DI, SR_LEN_S
    JAE ESR_MATCH_FOUND
    MOV BX, SI
    ADD BX, DI
    MOV AL, DOC_CHARS[BX]
    CMP AL, SEARCH_BUFFER[DI]
    JNE ESR_NO_MATCH
    INC DI
    JMP ESR_CMP_LOOP

ESR_NO_MATCH:
    POP BX                  ; Restaurar columna BX
    INC BX
    JMP ESR_COL_LOOP

ESR_MATCH_FOUND:
    POP BX                  ; Restaurar columna BX

    ; Coincidencia encontrada en (BP, BX)
    ; Nueva longitud = line_len - SR_LEN_S + SR_LEN_R
    MOV SI, BP
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    SUB AX, SR_LEN_S
    ADD AX, SR_LEN_R
    CMP AX, MAX_COLS
    JA  ESR_ADVANCE_COL     ; Si excede el ancho de linea, no reemplazar

    ; Aplicar sustitucion:
    MOV AX, BP
    MOV DX, MAX_COLS
    MUL DX
    ADD AX, BX
    MOV DI, AX              ; DI = Offset destino en DOC_CHARS

    XOR SI, SI              ; SI = Indice en REPLACE_BUFFER
ESR_COPY_REP:
    CMP SI, SR_LEN_R
    JAE ESR_REP_DONE
    MOV AL, REPLACE_BUFFER[SI]
    MOV DOC_CHARS[DI], AL

    ; Asignar colores actuales a lo reemplazado
    PUSH BX
    XOR BX, BX
    MOV BL, CUR_FG_IDX
    MOV AL, FG_COLORS[BX]
    MOV DOC_FG[DI], AL

    MOV BL, CUR_BG_IDX
    MOV AL, BG_COLORS[BX]
    MOV DOC_BG[DI], AL
    POP BX

    INC SI
    INC DI
    JMP ESR_COPY_REP

ESR_REP_DONE:
    ; Actualizar longitud de la linea
    MOV SI, BP
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    SUB AX, SR_LEN_S
    ADD AX, SR_LEN_R
    MOV LINE_LENGTHS[SI], AX

    ; Avanzar columna despues de lo reemplazado
    ADD BX, SR_LEN_R
    CMP SR_LEN_R, 0
    JNE ESR_COL_LOOP

ESR_ADVANCE_COL:
    INC BX
    JMP ESR_COL_LOOP

ESR_NEXT_ROW:
    INC BP
    JMP ESR_ROW_LOOP

ESR_RET:
    RET
EXECUTE_SEARCH_REPLACE ENDP

; ===========================================================================
; RENDERIZADO COMPLETO DEL EDITOR (VIEWPORT, TEXTO, IMAGENES Y BARRAS)
; ===========================================================================

REDRAW_EDITOR_SCREEN PROC NEAR
    ; 1. Limpiar pantalla completa
    ; Barra superior: Y 0..7 (Negro)
    MOV CX, 0
    MOV DX, 0
    MOV SI, 320
    MOV BP, 8
    MOV AL, 0
    CALL FILL_RECT

    ; Lienzo de edicion: Y 8..191 (Color de fondo de celda por defecto = 0)
    MOV CX, 0
    MOV DX, 8
    MOV SI, 320
    MOV BP, 184
    MOV AL, 0
    CALL FILL_RECT

    ; Barra inferior: Y 192..199 (Negro)
    MOV CX, 0
    MOV DX, 192
    MOV SI, 320
    MOV BP, 8
    MOV AL, 0
    CALL FILL_RECT

    ; 2. Renderizar texto del Viewport (Lineas VIEW_START_LINE a VIEW_START_LINE + 22)
    XOR BP, BP              ; BP = Fila relativa en pantalla (0..22)
RES_TEXT_ROWS:
    CMP BP, VISIBLE_ROWS
    JAE RES_DRAW_IMAGES

    MOV AX, VIEW_START_LINE
    ADD AX, BP
    CMP AX, DOC_LINE_COUNT
    JAE RES_DRAW_IMAGES     ; Fin de lineas del documento

    ; Guardar variables de linea y fila
    MOV DRAW_LINE_ABS, AX

    ; Y de pantalla: DX = 8 + BP * 8
    MOV DX, BP
    SHL DX, 3
    ADD DX, 8
    MOV DRAW_ROW_Y, DX

    ; Offset base en matrices = DRAW_LINE_ABS * 40
    MOV AX, DRAW_LINE_ABS
    MOV BX, MAX_COLS
    MUL BX
    MOV DI, AX              ; DI = Offset base

    PUSH BP                 ; Preservar indice de fila en pantalla

    ; Renderizar las 40 columnas de la fila
    XOR CX, CX              ; CX = Columna de texto (0..39)
RES_COLS_LOOP:
    CMP CX, MAX_COLS
    JAE RES_NEXT_TEXT_ROW

    ; Coordenada X = CX * 8
    MOV AX, CX
    SHL AX, 3
    MOV BX, AX              ; BX = Screen X

    ; Leer datos de la celda
    MOV SI, DI
    ADD SI, CX
    MOV AL, DOC_CHARS[SI]
    MOV DL, DOC_FG[SI]
    MOV DH, DOC_BG[SI]

    ; Si la celda es cursor activo, destacar cursor
    MOV SI, DRAW_LINE_ABS
    CMP SI, CUR_ROW
    JNE RES_DRAW_GLYPH
    CMP CX, CUR_COL
    JNE RES_DRAW_GLYPH

    ; Cursor activo: invertir colores para maximo contraste
    MOV AH, DL
    MOV DL, DH
    MOV DH, AH
    CMP DH, 0
    JNE RES_DRAW_GLYPH
    MOV DH, 14              ; Fondo amarillo si era negro

RES_DRAW_GLYPH:
    PUSH CX
    PUSH DI
    MOV CX, BX              ; Screen X
    MOV DX, DRAW_ROW_Y      ; Screen Y
    MOV BL, DL              ; Color FG
    MOV BH, DH              ; Color BG
    CALL DRAW_CHAR_8X8
    POP DI
    POP CX

    INC CX
    JMP RES_COLS_LOOP

RES_NEXT_TEXT_ROW:
    POP BP
    INC BP
    JMP RES_TEXT_ROWS

RES_DRAW_IMAGES:
    ; 3. Renderizar imagenes Pixel Art sobre el texto (Prioridad absoluta)
    CALL DRAW_PLACED_IMAGES_OVER_TEXT

    ; 4. Renderizar Barra Superior de Estado (Fila 0)
    ; Nombre de archivo
    MOV CX, 4
    MOV DX, 0
    LEA SI, TXT_LBL_FILE
    MOV BL, 11              ; Cian
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 36
    MOV DX, 0
    LEA SI, CURRENT_FILENAME
    MOV BL, 14              ; Amarillo
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Indicador de Linea
    MOV CX, 150
    MOV DX, 0
    LEA SI, TXT_LBL_LN
    MOV BL, 7
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV AX, CUR_ROW
    INC AX
    MOV CX, 178
    MOV DX, 0
    CALL DRAW_DEC_2DIG

    ; Indicador de Columna
    MOV CX, 198
    MOV DX, 0
    LEA SI, TXT_LBL_COL
    MOV BL, 7
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV AX, CUR_COL
    INC AX
    MOV CX, 226
    MOV DX, 0
    CALL DRAW_DEC_2DIG

    ; Indicador de Color FG activo
    MOV CX, 246
    MOV DX, 0
    LEA SI, TXT_LBL_FG
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Muestra visual del color FG
    MOV CX, 272
    MOV DX, 1
    MOV SI, 8
    MOV BP, 6
    XOR BX, BX
    MOV BL, CUR_FG_IDX
    MOV AL, FG_COLORS[BX]
    CALL FILL_RECT

    ; Indicador de Color BG activo
    MOV CX, 284
    MOV DX, 0
    LEA SI, TXT_LBL_BG
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 308
    MOV DX, 1
    MOV SI, 8
    MOV BP, 6
    XOR BX, BX
    MOV BL, CUR_BG_IDX
    MOV AL, BG_COLORS[BX]
    CALL FILL_RECT

    ; 5. Renderizar Barra Inferior Cheatsheet (Fila 24)
    MOV CX, 4
    MOV DX, 192
    LEA SI, TXT_CHEATSHEET
    MOV BL, 11              ; Cian claro
    MOV BH, 0
    CALL DRAW_STRING_8X8

    RET
REDRAW_EDITOR_SCREEN ENDP

; ---------------------------------------------------------------------------
; DRAW_PLACED_IMAGES_OVER_TEXT: Renderiza cada imagen estampada con transformaciones
; ---------------------------------------------------------------------------
DRAW_PLACED_IMAGES_OVER_TEXT PROC NEAR
    XOR BP, BP              ; BP = Indice de imagen en PLACED_TABLE
DPIO_LOOP:
    CMP BP, PLACED_COUNT
    JAE DPIO_DONE

    ; Offset = BP * ENTRY_SIZE (7)
    MOV AX, BP
    MOV BX, ENTRY_SIZE
    MUL BX
    LEA SI, PLACED_TABLE
    ADD SI, AX

    ; Cargar datos de la imagen
    MOV AL, [SI]
    MOV DRAW_IMG_ID, AL
    MOV AX, [SI+1]
    MOV DRAW_POSX, AX       ; doc_X

    ; Coordenada Y relativa al viewport:
    ; screen_Y = doc_Y - (VIEW_START_LINE * 8) + 8
    MOV AX, [SI+3]          ; doc_Y
    MOV BX, VIEW_START_LINE
    SHL BX, 3
    SUB AX, BX
    ADD AX, 8
    MOV DRAW_POSY, AX

    MOV AL, [SI+5]
    MOV DRAW_FLIP, AL
    MOV AL, [SI+6]
    MOV DRAW_ROT, AL

    ; Verificar si es visible en el lienzo [8..191]
    ; Dibujar usando rutina generica de transformacion (Lab 6)
    PUSH BP
    CALL DRAW_TRANSFORMED_IMAGE
    POP BP

    INC BP
    JMP DPIO_LOOP

DPIO_DONE:
    RET
DRAW_PLACED_IMAGES_OVER_TEXT ENDP

; ===========================================================================
; MOTOR MATRICIAL DE TRANSFORMACION Y DIBUJO DE PIXEL ART (LABORATORIO 6)
; ===========================================================================

; ---------------------------------------------------------------------------
; GET_IMG_INFO: Retorna puntero y dimensiones de la imagen segun ID
; ---------------------------------------------------------------------------
GET_IMG_INFO PROC NEAR
    CMP AL, 1
    JNE GII_CHK2
    LEA SI, IMG1_DATA
    MOV BX, IMG1_W
    MOV DX, IMG1_H
    RET
GII_CHK2:
    LEA SI, IMG2_DATA
    MOV BX, IMG2_W
    MOV DX, IMG2_H
    RET
GET_IMG_INFO ENDP

; ---------------------------------------------------------------------------
; DRAW_TRANSFORMED_IMAGE: Dibuja imagen con soporte de rotacion a 90 grados,
; espejo horizontal, transparencia (color 48) y recorte contra el lienzo (8..191).
; ---------------------------------------------------------------------------
DRAW_TRANSFORMED_IMAGE PROC NEAR
    PUSH ES
    MOV DX, 0A000H
    MOV ES, DX

    MOV AL, DRAW_IMG_ID
    CALL GET_IMG_INFO
    MOV DRAW_DATA_PTR, SI
    MOV DRAW_W, BX
    MOV DRAW_H, DX

    ; Calcular dimensiones rotadas
    CMP DRAW_ROT, 1
    JE  DTI_ROT_DIMS
    CMP DRAW_ROT, 3
    JE  DTI_ROT_DIMS
    MOV DRAW_EFF_W, BX
    MOV DRAW_EFF_H, DX
    JMP DTI_DIMS_OK
DTI_ROT_DIMS:
    MOV DRAW_EFF_W, DX
    MOV DRAW_EFF_H, BX
DTI_DIMS_OK:

    ; Bucle exterior por filas: ty de 0 a DRAW_EFF_H - 1
    MOV DRAW_TY, 0
DTI_LOOP_TY:
    MOV AX, DRAW_TY
    CMP AX, DRAW_EFF_H
    JAE DTI_FINISHED

    ; screenY = DRAW_POSY + DRAW_TY
    MOV BX, DRAW_POSY
    ADD BX, DRAW_TY
    MOV SCREEN_Y, BX

    ; Recorte vertical: lienzo permitido [8, 191]
    CMP BX, 8
    JB  DTI_NEXT_TY
    CMP BX, 192
    JAE DTI_NEXT_TY

    ; Precalcular offset de fila: screenY * 320
    MOV DI, BX
    SHL DI, 8
    SHL BX, 6
    ADD DI, BX
    MOV ROW_VRAM_OFFSET, DI

    ; Bucle interior por columnas: tx de 0 a DRAW_EFF_W - 1
    MOV DRAW_TX, 0
DTI_LOOP_TX:
    MOV AX, DRAW_TX
    CMP AX, DRAW_EFF_W
    JAE DTI_NEXT_TY

    ; screenX = DRAW_POSX + DRAW_TX
    MOV CX, DRAW_POSX
    ADD CX, DRAW_TX
    MOV SCREEN_X, CX

    ; Recorte horizontal: [0, 319]
    CMP CX, 320
    JAE DTI_NEXT_TX

    ; Mapeo matricial de coordenadas destino (tx, ty) a origen (sx, sy)
    MOV AX, DRAW_TX
    MOV BX, DRAW_TY

    CMP DRAW_FLIP, 0
    JNE DTI_CALC_FLIP1

DTI_CALC_FLIP0:
    CMP DRAW_ROT, 0
    JE  DTI_F0_R0
    CMP DRAW_ROT, 1
    JE  DTI_F0_R1
    CMP DRAW_ROT, 2
    JE  DTI_F0_R2

    ; Rot 3 (270 deg): sx = (W - 1) - ty, sy = tx
    MOV AX, DRAW_W
    DEC AX
    SUB AX, DRAW_TY
    MOV DRAW_SX, AX
    MOV AX, DRAW_TX
    MOV DRAW_SY, AX
    JMP DTI_CALC_READY

DTI_F0_R0:
    ; Rot 0: sx = tx, sy = ty
    MOV DRAW_SX, AX
    MOV DRAW_SY, BX
    JMP DTI_CALC_READY

DTI_F0_R1:
    ; Rot 1 (90 deg): sx = ty, sy = (H - 1) - tx
    MOV DRAW_SX, BX
    MOV AX, DRAW_H
    DEC AX
    SUB AX, DRAW_TX
    MOV DRAW_SY, AX
    JMP DTI_CALC_READY

DTI_F0_R2:
    ; Rot 2 (180 deg): sx = (W - 1) - tx, sy = (H - 1) - ty
    MOV AX, DRAW_W
    DEC AX
    SUB AX, DRAW_TX
    MOV DRAW_SX, AX
    MOV AX, DRAW_H
    DEC AX
    SUB AX, DRAW_TY
    MOV DRAW_SY, AX
    JMP DTI_CALC_READY

DTI_CALC_FLIP1:
    CMP DRAW_ROT, 0
    JE  DTI_F1_R0
    CMP DRAW_ROT, 1
    JE  DTI_F1_R1
    CMP DRAW_ROT, 2
    JE  DTI_F1_R2

    ; Rot 3 + Flip: sx = ty, sy = tx
    MOV DRAW_SX, BX
    MOV DRAW_SY, AX
    JMP DTI_CALC_READY

DTI_F1_R0:
    ; Rot 0 + Flip: sx = (W - 1) - tx, sy = ty
    MOV AX, DRAW_W
    DEC AX
    SUB AX, DRAW_TX
    MOV DRAW_SX, AX
    MOV DRAW_SY, BX
    JMP DTI_CALC_READY

DTI_F1_R1:
    ; Rot 1 + Flip: sx = (W - 1) - ty, sy = (H - 1) - tx
    MOV AX, DRAW_W
    DEC AX
    SUB AX, DRAW_TY
    MOV DRAW_SX, AX
    MOV AX, DRAW_H
    DEC AX
    SUB AX, DRAW_TX
    MOV DRAW_SY, AX
    JMP DTI_CALC_READY

DTI_F1_R2:
    ; Rot 2 + Flip: sx = tx, sy = (H - 1) - ty
    MOV DRAW_SX, AX
    MOV AX, DRAW_H
    DEC AX
    SUB AX, DRAW_TY
    MOV DRAW_SY, AX

DTI_CALC_READY:
    ; Offset en matriz de pixeles = sy * DRAW_W + sx
    MOV AX, DRAW_SY
    MUL DRAW_W
    ADD AX, DRAW_SX
    MOV SI, DRAW_DATA_PTR
    ADD SI, AX

    ; Leer pixel de la matriz
    MOV AL, [SI]
    CMP AL, 48              ; 48 representa color transparente en Lab 6
    JE  DTI_NEXT_TX

    ; Escribir pixel directamente en memoria de video 0A000h
    MOV DI, ROW_VRAM_OFFSET
    ADD DI, SCREEN_X
    MOV ES:[DI], AL

DTI_NEXT_TX:
    INC DRAW_TX
    JMP DTI_LOOP_TX

DTI_NEXT_TY:
    INC DRAW_TY
    JMP DTI_LOOP_TY

DTI_FINISHED:
    POP ES
    RET
DRAW_TRANSFORMED_IMAGE ENDP

END MAIN
