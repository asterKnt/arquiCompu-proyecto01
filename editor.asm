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
    FULL_REDRAW_REQ     DB 1            ; 1 = Requiere invalidar y limpiar pantalla completa
    CURSOR_VISIBLE      DB 1            ; Estado del cursor visual
    CURSOR_VISIBLE_STATE DB 1           ; 1 = Cursor ON, 0 = Cursor OFF (fase de parpadeo)
    CURSOR_BLINK_PHASE  DB 0FFH         ; Ultima fase detectada del temporizador de BIOS
    MENU_SEL            DB 1            ; Opcion seleccionada en menu (1..3)

    ; -----------------------------------------------------------------------
    ; Dimensiones y Buffer del Documento (Nano-like multilinea)
    ; -----------------------------------------------------------------------
    MAX_LINES           EQU 80          ; Hasta 80 renglones de documento
    MAX_COLS            EQU 40          ; 40 caracteres por renglon (320px / 8px)
    VISIBLE_ROWS        EQU 24          ; 24 filas visibles en el lienzo (Y: 8..199)

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
    DRAW_TRANS_COLOR    DB 48

    ; -----------------------------------------------------------------------
    ; Variables para Renderizado Diferencial (Shadow Buffer y Cache)
    ; -----------------------------------------------------------------------
    PREV_VIEW_START_LINE DW 0FFFFH      ; Deteccion de scroll vertical en viewport
    PREV_STATUS_LN      DW 0FFFFH       ; Cache de linea para barra superior
    PREV_STATUS_COL     DW 0FFFFH       ; Cache de columna para barra superior
    PREV_STATUS_FG      DB 0FFH         ; Cache de color FG en barra superior
    PREV_STATUS_BG      DB 0FFH         ; Cache de color BG en barra superior
    CELL_CHANGED_FLAG   DB 0            ; 1 si alguna celda cambio en el ciclo
    IS_CUR_ROW_FLAG     DB 0            ; 1 si la fila actual de pantalla contiene al cursor
    DOC_ROW_BASE_OFF    DW 0            ; Offset base de linea de documento
    SHADOW_ROW_BASE_OFF DW 0            ; Offset base de linea de pantalla

    VISIBLE_CELLS       EQU 960         ; 24 filas * 40 columnas
    SHADOW_CHARS        DB VISIBLE_CELLS DUP(0FFH)
    SHADOW_FG           DB VISIBLE_CELLS DUP(0FFH)
    SHADOW_BG           DB VISIBLE_CELLS DUP(0FFH)

    ; Dimensiones originales de las imagenes
    IMG1_W              DW 44           ; Imagen 1: Arch Linux (44x36)
    IMG1_H              DW 36
    IMG2_W              DW 50           ; Imagen 2: Honkai (50x48)
    IMG2_H              DW 48
    IMG3_W              DW 12           ; Imagen 3: Personaje 1 (12x18)
    IMG3_H              DW 18
    IMG4_W              DW 14           ; Imagen 4: Personaje 2 (14x20)
    IMG4_H              DW 20

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

    TXT_LBL_FILE        DB 'DOC:', 0
    TXT_LBL_LN          DB ' L:', 0
    TXT_LBL_COL         DB ' C:', 0
    TXT_LBL_FG          DB ' FG:', 0
    TXT_LBL_BG          DB ' BG:', 0

    ; Cadenas de la Ventana de Ayuda Categorizada
    TXT_HELP_T          DB '--- AYUDA: ATAJOS DE TECLADO ---', 0
    TXT_H_SEC1          DB '[ NAVEGACION Y CURSOR ]', 0
    TXT_H_C             DB 'Alt+C    : Centrar cursor en linea', 0
    TXT_H_U             DB 'Alt+U    : Ir al primer renglon', 0
    TXT_H_D             DB 'Alt+D    : Ir al ultimo renglon', 0
    TXT_H_NAV           DB 'Flechas  : Moverse | BS: Borrar', 0

    TXT_H_SEC2          DB '[ FORMATO Y PIXEL ART ]', 0
    TXT_H_M             DB 'Alt+M    : Color de texto (FG)', 0
    TXT_H_N             DB 'Alt+N    : Color de fondo (BG)', 0
    TXT_H_IMG           DB 'Alt+I/J  : Menu Pixel Art (4 img)', 0

    TXT_H_SEC3          DB '[ SISTEMA Y ARCHIVO ]', 0
    TXT_H_B             DB 'Alt+B    : Buscar y reemplazar', 0
    TXT_H_S             DB 'Alt+S    : Guardar y salir al DOS', 0
    TXT_H_RET           DB '[ Presione una tecla para volver ]', 0

    TXT_SR_TITLE        DB 'BUSCAR Y REEMPLAZAR', 0
    TXT_SR_PROMPT_F     DB 'Buscar palabra: ', 0
    TXT_SR_PROMPT_R     DB 'Reemplazar por: ', 0
    TXT_IMG_MENU_T      DB 'SELECCIONAR IMAGEN PIXEL ART', 0
    TXT_IMG_OPT1        DB '  [1] Arch Linux  (44x36)', 0
    TXT_IMG_OPT2        DB '  [2] Honkai Star (50x48)', 0
    TXT_IMG_OPT3        DB '  [3] Personaje 1 (12x18)', 0
    TXT_IMG_OPT4        DB '  [4] Personaje 2 (14x20)', 0
    TXT_IMG_HINT        DB '[1-4] Elegir   [Alt+Z/Esc] Salir', 0

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

    ; -----------------------------------------------------------------------
    ; Imagen 3: Personaje 1 (12x18) - perso1
    ; -----------------------------------------------------------------------
    IMG3_DATA LABEL BYTE
    db 0,0,9,9,9,9,9,9,9,9,0,0
    db 0,0,9,9,9,9,9,9,9,9,0,0
    db 9,9,9,9,9,9,9,9,9,9,9,9
    db 0,0,15,15,15,15,15,15,15,15,0,0
    db 0,0,15,0,15,15,0,15,15,15,0,0
    db 0,0,15,15,15,15,15,15,15,15,0,0
    db 0,0,15,0,0,0,0,15,15,15,0,0
    db 15,15,15,15,15,15,15,15,15,15,15,15
    db 15,9,9,15,15,15,15,15,15,15,15,15
    db 15,9,9,15,15,15,15,15,15,15,15,15
    db 15,15,15,15,15,15,15,9,9,15,15,15
    db 15,15,15,15,15,15,15,9,9,15,15,15
    db 15,15,15,15,15,15,15,15,15,15,15,15
    db 0,0,15,15,0,0,15,15,0,0,0,0
    db 0,0,15,15,0,0,0,0,15,15,0,0
    db 0,0,15,15,0,0,0,0,15,15,0,0
    db 0,0,9,9,0,0,0,0,9,9,0,0
    db 0,0,9,9,0,0,0,0,9,9,0,0

    ; -----------------------------------------------------------------------
    ; Imagen 4: Personaje 2 (14x20) - perso2
    ; -----------------------------------------------------------------------
    IMG4_DATA LABEL BYTE
    db 0,0,0,9,9,9,9,0,0,0,0,0,0,0
    db 0,0,0,9,9,9,9,0,0,0,0,0,0,0
    db 0,0,0,9,9,9,9,0,0,0,0,0,0,0
    db 0,0,0,9,9,9,9,0,0,0,0,0,0,0
    db 0,9,9,9,9,9,9,9,9,9,0,0,0,0
    db 0,9,9,15,0,15,0,15,9,9,0,0,0,0
    db 0,9,9,15,0,0,0,15,9,9,0,0,0,0
    db 0,9,9,15,15,15,15,15,9,9,0,0,0,0
    db 0,9,9,0,15,15,15,0,9,9,0,0,0,0
    db 0,9,9,0,0,15,0,0,9,9,0,0,0,0
    db 15,15,15,9,9,9,9,9,9,9,0,0,0,0
    db 15,15,15,9,9,9,9,9,9,9,15,15,15,0
    db 15,15,15,9,9,9,9,9,9,9,15,15,15,0
    db 0,0,0,9,9,9,9,9,9,9,15,15,15,0
    db 0,0,0,9,9,9,9,9,9,9,0,0,0,0
    db 0,0,0,9,9,9,9,9,9,9,0,0,0,0
    db 0,0,0,9,9,9,9,9,9,9,0,0,0,0
    db 0,0,0,15,15,0,0,0,15,15,0,0,0,0
    db 0,0,0,15,15,0,0,0,0,0,0,0,0,0
    db 0,0,0,15,15,0,0,0,0,0,0,0,0,0

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
    CLD

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
    CLD

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
    PUSH BP

    MOV BP, DX              ; BP = Coordenada Y original fija (ej: 0)

    ; Dividir AX / 10
    XOR AH, AH
    MOV BL, 10
    DIV BL                  ; AL = decenas, AH = unidades

    PUSH AX                 ; Preservar decenas en AL y unidades en AH

    ; 1. Dibujar decenas
    ADD AL, '0'
    MOV DX, BP              ; Y fija
    MOV BL, 15              ; Blanco
    MOV BH, 0               ; Fondo negro
    CALL DRAW_CHAR_8X8

    ; 2. Dibujar unidades
    POP AX                  ; Recuperar AL=decenas, AH=unidades
    MOV AL, AH
    ADD AL, '0'
    ADD CX, 8               ; Desplazar X en 8 pixeles a la derecha
    MOV DX, BP              ; Y fija
    MOV BL, 15              ; Blanco
    MOV BH, 0               ; Fondo negro
    CALL DRAW_CHAR_8X8

    POP BP
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

    ; Alt+Z (Scan Code 2Ch) o Ctrl+Z (AL=1Ah) -> Cancelar solo si es atajo real
    CMP AH, 2CH
    JNE RSI_CHK_ENTER
    CMP AL, 0
    JE  RSI_CANCEL
    CMP AL, 1AH             ; Ctrl+Z
    JE  RSI_CANCEL
    PUSH AX
    MOV AH, 02H
    INT 16H
    TEST AL, 08H            ; Alt sostenido
    POP AX
    JNZ RSI_CANCEL
    JMP RSI_CHK_ENTER

RSI_CANCEL:
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
    MOV FULL_REDRAW_REQ, 1
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
    MOV CUR_ROW, 0
    MOV CUR_COL, 0
    MOV VIEW_START_LINE, 0
    MOV CUR_FG_IDX, 0
    MOV CUR_BG_IDX, 0
    MOV CURSOR_VISIBLE_STATE, 1
    MOV CURSOR_BLINK_PHASE, 0FFH
    MOV PROGRAM_STATE, 1
    MOV REDRAW_REQ, 1
    MOV FULL_REDRAW_REQ, 1
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
    MOV CUR_FG_IDX, 0
    MOV CUR_BG_IDX, 0
    MOV CURSOR_VISIBLE_STATE, 1
    MOV CURSOR_BLINK_PHASE, 0FFH

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
    ; 1. Verificar si hay peticion de redibujado forzado o scroll de pantalla
    CMP FULL_REDRAW_REQ, 1
    JE  REC_DO_REDRAW
    CMP REDRAW_REQ, 1
    JE  REC_DO_REDRAW
    MOV AX, VIEW_START_LINE
    CMP AX, PREV_VIEW_START_LINE
    JE  REC_CHECK_KEY

REC_DO_REDRAW:
    MOV FULL_REDRAW_REQ, 1
    CALL UPDATE_EDITOR_DISPLAY

REC_CHECK_KEY:
    ; 2. Consultar si hay tecla lista en el buffer de teclado (sin bloqueo)
    MOV AH, 01H
    INT 16H
    JNZ REC_KEY_AVAILABLE

    ; --- ESTADO INACTIVO (IDLE): CONTROL DE PARPADEO DEL CURSOR ---
    ; Leer contador de ticks del reloj de BIOS (INT 1Ah, AH=00h)
    ; DX retorna los 16 bits bajos del contador de ticks (~18.2 ticks por segundo)
    MOV AH, 00H
    INT 1AH

    ; El bit 3 de DX conmuta aproximadamente cada 8 ticks (~440 ms = ~1.14 Hz)
    MOV AL, DL
    AND AL, 08H
    CMP AL, CURSOR_BLINK_PHASE
    JE  REC_IDLE_YIELD       ; Mantiene la misma fase de parpadeo

    ; Cambio de fase: alternar visibilidad del cursor
    MOV CURSOR_BLINK_PHASE, AL
    XOR CURSOR_VISIBLE_STATE, 1
    ; Actualizar pantalla diferencialmente (solo se redibujara la celda del cursor)
    CALL UPDATE_EDITOR_DISPLAY
    RET

REC_IDLE_YIELD:
    ; Liberar ciclos de CPU en DOSBox esperando a la siguiente interrupcion de hardware
    STI
    HLT
    RET

REC_KEY_AVAILABLE:
    ; --- TECLA PRESIONADA ---
    ; Extraer la tecla del buffer del BIOS (AH = Scan Code, AL = ASCII)
    MOV AH, 00H
    INT 16H

    ; Preservar el codigo de tecla en AX
    PUSH AX

    ; Sincronizar fase de parpadeo con el reloj y garantizar cursor visible
    MOV AH, 00H
    INT 1AH
    MOV AL, DL
    AND AL, 08H
    MOV CURSOR_BLINK_PHASE, AL
    MOV CURSOR_VISIBLE_STATE, 1

    ; Recuperar la tecla para ser procesada
    POP AX

    ; Despachar la accion de la tecla
    CALL DISPATCH_EDITOR_KEY

    ; Actualizar pantalla diferencialmente de inmediato
    CALL UPDATE_EDITOR_DISPLAY
    RET
RUN_EDITOR_CYCLE ENDP

; ---------------------------------------------------------------------------
; DISPATCH_EDITOR_KEY: Manejo completo de atajos Alt, flechas, Enter y Backspace
; ---------------------------------------------------------------------------
DISPATCH_EDITOR_KEY PROC NEAR
    ; 1. Consultar banderas de teclas especiales (Shift / Alt / Ctrl)
    PUSH AX
    MOV AH, 02H
    INT 16H
    MOV BL, AL              ; BL = Shift flags (bit 3=Alt, bit 2=Ctrl)
    POP AX

    ; Si la tecla Alt (08h) o Ctrl (04h) esta presionada, procesar atajo directamente
    TEST BL, 08H
    JNZ DEK_CHECK_ALT_OR_ARROWS
    TEST BL, 04H
    JNZ DEK_CHECK_ALT_OR_ARROWS

    ; 2. Verificar teclas extendidas de BIOS (AL=0 o AL=E0h)
    CMP AL, 0
    JE  DEK_CHECK_ALT_OR_ARROWS
    CMP AL, 0E0H
    JE  DEK_CHECK_ALT_OR_ARROWS

    ; 3. Caracteres de control (< 32 / espacio)
    CMP AL, ' '
    JB  DEK_CHECK_CTRL_CODES

    ; 4. Caracteres imprimibles (32 a 126, incluye espacios y toda la puntuacion)
    CMP AL, 126
    JA  DEK_RET

    ; Insertar caracter en el buffer directamente
    CALL INSERT_CHAR_AT_CURSOR
    RET

DEK_CHECK_CTRL_CODES:
    CMP AL, 08H             ; Backspace normal
    JE  DEK_BKSP
    CMP AL, 0DH             ; Enter normal
    JE  DEK_ENTER

    ; Si es otro codigo de control ASCII (^S, ^B, ^I, ^J, ^M, ^N, etc.), verificar atajo
    JMP DEK_CHECK_ALT_OR_ARROWS

DEK_BKSP:
    CALL HANDLE_BACKSPACE
    RET

DEK_ENTER:
    CALL HANDLE_ENTER
    RET

DEK_CHECK_ALT_OR_ARROWS:
    ; Flechas de direccion (Escaneos 48h, 50h, 4Bh, 4Dh)
    CMP AH, 48H             ; Flecha Arriba
    JE  DEK_ARROW_UP
    CMP AH, 50H             ; Flecha Abajo
    JE  DEK_ARROW_DOWN
    CMP AH, 4BH             ; Flecha Izquierda
    JE  DEK_ARROW_LEFT
    CMP AH, 4DH             ; Flecha Derecha
    JE  DEK_ARROW_RIGHT

    ; -----------------------------------------------------------------------
    ; Atajos de Teclado Organizados por Categoria (Alt y Ctrl)
    ; -----------------------------------------------------------------------
    ; 1. NAVEGACION Y CURSOR
    CMP AH, 2EH             ; C: Alt+C o Ctrl+C -> Centrar cursor en linea
    JE  DEK_ALT_C
    CMP AL, 03H             ; Ctrl+C
    JE  DEK_ALT_C

    CMP AH, 16H             ; U: Alt+U o Ctrl+U -> Cursor a primera linea
    JE  DEK_ALT_U
    CMP AL, 15H             ; Ctrl+U
    JE  DEK_ALT_U

    CMP AH, 20H             ; D: Alt+D o Ctrl+D -> Cursor a ultima linea
    JE  DEK_ALT_D
    CMP AL, 04H             ; Ctrl+D
    JE  DEK_ALT_D

    ; 2. FORMATO Y PIXEL ART
    CMP AH, 32H             ; M: Alt+M o Ctrl+M -> Ciclar color de texto (FG)
    JE  DEK_ALT_M

    CMP AH, 31H             ; N: Alt+N o Ctrl+N -> Ciclar color de fondo (BG)
    JE  DEK_ALT_N
    CMP AL, 0EH             ; Ctrl+N
    JE  DEK_ALT_N

    CMP AH, 17H             ; I: Alt+I o Ctrl+I -> Menu Pixel Art
    JE  DEK_ALT_IMG
    CMP AL, 09H             ; Ctrl+I (Tab)
    JE  DEK_ALT_IMG

    CMP AH, 24H             ; J: Alt+J o Ctrl+J -> Menu Pixel Art (Alias unificado)
    JE  DEK_ALT_IMG
    CMP AL, 0AH             ; Ctrl+J
    JE  DEK_ALT_IMG

    ; 3. SISTEMA Y ARCHIVO
    CMP AH, 30H             ; B: Alt+B o Ctrl+B -> Buscar y Reemplazar
    JE  DEK_ALT_B
    CMP AL, 02H             ; Ctrl+B
    JE  DEK_ALT_B

    CMP AH, 23H             ; H: Alt+H -> Mostrar ventana de ayuda
    JE  DEK_ALT_H

    CMP AH, 1FH             ; S: Alt+S o Ctrl+S -> Guardar y salir
    JE  DEK_ALT_S
    CMP AL, 13H             ; Ctrl+S
    JE  DEK_ALT_S

    CMP AH, 2DH             ; X: Alt+X o Ctrl+X -> Guardar y salir (Alias DOS)
    JE  DEK_ALT_S
    CMP AL, 18H             ; Ctrl+X
    JE  DEK_ALT_S

DEK_RET:
    RET

; Despachos directos organizados
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

; Navegacion
DEK_ALT_C:
    CALL ACTION_CENTER_CURSOR
    RET
DEK_ALT_U:
    CALL ACTION_GOTO_FIRST_LINE
    RET
DEK_ALT_D:
    CALL ACTION_GOTO_LAST_LINE
    RET

; Formato y Pixel Art
DEK_ALT_M:
    CALL ACTION_CYCLE_FG
    RET
DEK_ALT_N:
    CALL ACTION_CYCLE_BG
    RET
DEK_ALT_IMG:
    CALL ACTION_OPEN_IMAGE_MENU
    RET

; Sistema y Archivo
DEK_ALT_B:
    CALL ACTION_SEARCH_REPLACE
    RET
DEK_ALT_H:
    CALL ACTION_SHOW_HELP
    RET
DEK_ALT_S:
    CALL ACTION_SAVE_AND_EXIT
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
; INSERT_CHAR_AT_CURSOR: Insercion estilo nano con auto-wrap garantizado
; ---------------------------------------------------------------------------
INSERT_CHAR_AT_CURSOR PROC NEAR
    PUSH AX

    ; 1. Si CUR_COL ya esta en o supera la columna 39, hacer wrap antes de insertar
    CMP CUR_COL, 39
    JB  ICA_CHECK_ROW_FULL

    ; Descender a siguiente linea
    MOV AX, CUR_ROW
    INC AX
    CMP AX, MAX_LINES
    JAE ICA_RET                 ; Limite maximo de lineas alcanzado

    CMP AX, DOC_LINE_COUNT
    JB  ICA_DO_WRAP_EXISTING

    CALL INSERT_DOC_EMPTY_LINE
    JMP ICA_DO_WRAP_NEW

ICA_DO_WRAP_EXISTING:
    NOP

ICA_DO_WRAP_NEW:
    INC CUR_ROW
    MOV CUR_COL, 0

ICA_CHECK_ROW_FULL:
    ; 2. Validar si la linea actual ya tiene 39 o mas caracteres
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]
    CMP CX, 39
    JB  ICA_HAVE_ROOM

    ; Linea llena: pasar a siguiente linea
    MOV AX, CUR_ROW
    INC AX
    CMP AX, MAX_LINES
    JAE ICA_RET

    CMP AX, DOC_LINE_COUNT
    JB  ICA_FULL_EXISTING

    CALL INSERT_DOC_EMPTY_LINE
    JMP ICA_FULL_NEW

ICA_FULL_EXISTING:
    NOP

ICA_FULL_NEW:
    INC CUR_ROW
    MOV CUR_COL, 0

ICA_HAVE_ROOM:
    ; 3. Offset base de la fila = CUR_ROW * MAX_COLS (40)
    MOV AX, CUR_ROW
    MOV DX, MAX_COLS
    MUL DX
    MOV DI, AX                  ; DI = Offset base de la fila

    ; 4. Si el cursor esta en medio del texto, desplazar hacia la derecha
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV CX, LINE_LENGTHS[SI]

    CMP CX, CUR_COL
    JBE ICA_NO_SHIFT

    PUSH CX
ICA_SHIFT_LOOP:
    MOV SI, DI
    ADD SI, CX
    DEC SI                      ; SI = DI + CX - 1

    CMP CX, 39
    JAE ICA_SHIFT_SKIP

    MOV DL, DOC_CHARS[SI]
    MOV DOC_CHARS[SI+1], DL

    MOV DL, DOC_FG[SI]
    MOV DOC_FG[SI+1], DL

    MOV DL, DOC_BG[SI]
    MOV DOC_BG[SI+1], DL

ICA_SHIFT_SKIP:
    DEC CX
    CMP CX, CUR_COL
    JA  ICA_SHIFT_LOOP
    POP CX

ICA_NO_SHIFT:
    ; 5. Insertar caracter y atributos de color
    POP AX                      ; Recuperar caracter a insertar
    PUSH AX
    MOV SI, DI
    ADD SI, CUR_COL
    MOV DOC_CHARS[SI], AL

    ; Color de fuente
    XOR BX, BX
    MOV BL, CUR_FG_IDX
    MOV DL, FG_COLORS[BX]
    MOV DOC_FG[SI], DL

    ; Color de fondo
    MOV BL, CUR_BG_IDX
    MOV DL, BG_COLORS[BX]
    MOV DOC_BG[SI], DL

    ; Actualizar longitud de la linea actual (maximo 39)
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, CUR_COL
    INC AX                      ; Longitud minima requerida tras escribir en CUR_COL
    CMP AX, LINE_LENGTHS[SI]
    JBE ICA_LEN_CHECK_SHIFT

    CMP AX, 39
    JBE ICA_SET_LEN
    MOV AX, 39
ICA_SET_LEN:
    MOV LINE_LENGTHS[SI], AX
    JMP ICA_LEN_CLAMPED

ICA_LEN_CHECK_SHIFT:
    CMP WORD PTR LINE_LENGTHS[SI], 39
    JAE ICA_LEN_CLAMPED
    INC WORD PTR LINE_LENGTHS[SI]
ICA_LEN_CLAMPED:

    ; 6. Avanzar cursor a la derecha
    INC CUR_COL
    CMP CUR_COL, 39
    JB  ICA_DONE

    ; Auto-wrap automatico al alcanzar la columna 39:
    ; Pasa directamente a la siguiente fila en columna 0
    MOV AX, CUR_ROW
    INC AX
    CMP AX, MAX_LINES
    JAE ICA_WRAP_CLAMP

    CMP AX, DOC_LINE_COUNT
    JB  ICA_NEXT_EXISTING

    CALL INSERT_DOC_EMPTY_LINE
    INC CUR_ROW
    MOV CUR_COL, 0
    JMP ICA_DONE

ICA_NEXT_EXISTING:
    INC CUR_ROW
    MOV CUR_COL, 0
    JMP ICA_DONE

ICA_WRAP_CLAMP:
    MOV CUR_COL, 38

ICA_DONE:
    CALL ADJUST_VIEWPORT

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
    CMP DX, 39
    JB  HB_SET_DX
    MOV DX, 38
HB_SET_DX:
    MOV CUR_COL, DX

    ; Eliminar linea actual del buffer y subir las siguientes
    MOV AX, CUR_ROW
    INC AX
    CALL DELETE_DOC_LINE

    CALL ADJUST_VIEWPORT
    RET

HB_MOVE_TO_PREV_END:
    DEC CUR_ROW
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    CMP AX, 39
    JB  HB_SET_AX
    MOV AX, 38
HB_SET_AX:
    MOV CUR_COL, AX
    CALL ADJUST_VIEWPORT

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

    MOV BX, CUR_ROW
    SHL BX, 1
    MOV CX, LINE_LENGTHS[BX]       ; Total previo

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
    MOV BX, CUR_ROW
    INC BX
    SHL BX, 1
    MOV LINE_LENGTHS[BX], DX

    ; Acortar longitud de la linea actual a CUR_COL
    MOV BX, CUR_ROW
    SHL BX, 1
    MOV AX, CUR_COL
    MOV LINE_LENGTHS[BX], AX

    ; Mover cursor al inicio de la siguiente linea
    INC CUR_ROW
    MOV CUR_COL, 0
    CALL ADJUST_VIEWPORT

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
    PUSH BP

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

    POP BP
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
    CMP AX, 39
    JB  MCU_CHK_MAX
    MOV AX, 38
MCU_CHK_MAX:
    CMP CUR_COL, AX
    JBE MCU_ADJ
    MOV CUR_COL, AX
MCU_ADJ:
    CALL ADJUST_VIEWPORT
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
    CMP AX, 39
    JB  MCD_CHK_MAX
    MOV AX, 38
MCD_CHK_MAX:
    CMP CUR_COL, AX
    JBE MCD_ADJ
    MOV CUR_COL, AX
MCD_ADJ:
    CALL ADJUST_VIEWPORT
MCD_RET:
    RET
MOVE_CURSOR_DOWN ENDP

MOVE_CURSOR_LEFT PROC NEAR
    CMP CUR_COL, 0
    JE  MCL_WRAP
    DEC CUR_COL
    RET
MCL_WRAP:
    CMP CUR_ROW, 0
    JE  MCL_RET
    DEC CUR_ROW
    MOV SI, CUR_ROW
    SHL SI, 1
    MOV AX, LINE_LENGTHS[SI]
    CMP AX, 39
    JB  MCL_CHK_MAX
    MOV AX, 38
MCL_CHK_MAX:
    MOV CUR_COL, AX
    CALL ADJUST_VIEWPORT
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
    CMP CUR_COL, 39
    JAE MCR_WRAP
    RET

MCR_WRAP:
    ; Avanzar al siguiente renglon en columna 0
    MOV AX, CUR_ROW
    INC AX
    CMP AX, MAX_LINES
    JAE MCR_RET

    CMP AX, DOC_LINE_COUNT
    JB  MCR_NEXT_EXISTS

    CALL INSERT_DOC_EMPTY_LINE

MCR_NEXT_EXISTS:
    INC CUR_ROW
    MOV CUR_COL, 0
    CALL ADJUST_VIEWPORT
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
    CMP AX, 39
    JB  ACC_OK
    MOV AX, 38
ACC_OK:
    MOV CUR_COL, AX
    RET
ACTION_CENTER_CURSOR ENDP

ACTION_GOTO_FIRST_LINE PROC NEAR
    ; Alt+U: Ir a la primera linea del documento
    MOV CUR_ROW, 0
    MOV CUR_COL, 0
    MOV VIEW_START_LINE, 0
    RET
ACTION_GOTO_FIRST_LINE ENDP

ACTION_GOTO_LAST_LINE PROC NEAR
    ; Alt+D: Ir a la ultima linea activa del documento
    MOV AX, DOC_LINE_COUNT
    DEC AX
    MOV CUR_ROW, AX
    MOV CUR_COL, 0
    CALL ADJUST_VIEWPORT
    RET
ACTION_GOTO_LAST_LINE ENDP

ACTION_CYCLE_FG PROC NEAR
    ; Alt+M: Alternar color de fuente (ciclo 0..2)
    INC CUR_FG_IDX
    CMP CUR_FG_IDX, 3
    JB  ACF_OK
    MOV CUR_FG_IDX, 0
ACF_OK:
    RET
ACTION_CYCLE_FG ENDP

ACTION_CYCLE_BG PROC NEAR
    ; Alt+N: Alternar color de fondo (ciclo 0..2)
    INC CUR_BG_IDX
    CMP CUR_BG_IDX, 3
    JB  ACB_OK
    MOV CUR_BG_IDX, 0
ACB_OK:
    RET
ACTION_CYCLE_BG ENDP

; ---------------------------------------------------------------------------
; ACTION_OPEN_IMAGE_MENU: Menu modal interactivo para elegir imagen Pixel Art
; ---------------------------------------------------------------------------
ACTION_OPEN_IMAGE_MENU PROC NEAR
    ; 1. Dibujar ventana modal centrada
    CALL DRAW_FILE_DIALOG_BOX

    ; 2. Titulo
    MOV CX, 36
    MOV DX, 68
    LEA SI, TXT_IMG_MENU_T
    MOV BL, 14              ; Amarillo
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 3. Opcion 1: Arch Linux
    MOV CX, 40
    MOV DX, 82
    LEA SI, TXT_IMG_OPT1
    MOV BL, 11              ; Cian
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 4. Opcion 2: Honkai
    MOV CX, 40
    MOV DX, 94
    LEA SI, TXT_IMG_OPT2
    MOV BL, 13              ; Magenta
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 5. Opcion 3: Personaje 1
    MOV CX, 40
    MOV DX, 106
    LEA SI, TXT_IMG_OPT3
    MOV BL, 10              ; Verde claro
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 6. Opcion 4: Personaje 2
    MOV CX, 40
    MOV DX, 118
    LEA SI, TXT_IMG_OPT4
    MOV BL, 9               ; Azul claro
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 7. Instrucciones
    MOV CX, 26
    MOV DX, 136
    LEA SI, TXT_IMG_HINT
    MOV BL, 7               ; Gris claro
    MOV BH, 0
    CALL DRAW_STRING_8X8

AOIM_KEY_LOOP:
    MOV AH, 00H
    INT 16H

    ; Si presiona '1': Insertar Imagen 1
    CMP AL, '1'
    JE  AOIM_CHOOSE_1

    ; Si presiona '2': Insertar Imagen 2
    CMP AL, '2'
    JE  AOIM_CHOOSE_2

    ; Si presiona '3': Insertar Imagen 3
    CMP AL, '3'
    JE  AOIM_CHOOSE_3

    ; Si presiona '4': Insertar Imagen 4
    CMP AL, '4'
    JE  AOIM_CHOOSE_4

    ; Cancelar con Esc (1Bh), Alt+Z (AH=2Ch) o Ctrl+Z (AL=1Ah)
    CMP AL, 1BH
    JE  AOIM_CANCEL
    CMP AH, 2CH
    JE  AOIM_CANCEL
    CMP AL, 1AH
    JE  AOIM_CANCEL

    JMP AOIM_KEY_LOOP

AOIM_CHOOSE_1:
    MOV AL, 1
    CALL INSERT_IMAGE_AT_DOC_POS
    JMP AOIM_CANCEL

AOIM_CHOOSE_2:
    MOV AL, 2
    CALL INSERT_IMAGE_AT_DOC_POS
    JMP AOIM_CANCEL

AOIM_CHOOSE_3:
    MOV AL, 3
    CALL INSERT_IMAGE_AT_DOC_POS
    JMP AOIM_CANCEL

AOIM_CHOOSE_4:
    MOV AL, 4
    CALL INSERT_IMAGE_AT_DOC_POS
    JMP AOIM_CANCEL

AOIM_CANCEL:
    MOV FULL_REDRAW_REQ, 1
    RET
ACTION_OPEN_IMAGE_MENU ENDP

; ---------------------------------------------------------------------------
; INSERT_IMAGE_AT_DOC_POS: Estampa imagen en las coordenadas actuales del cursor
; ---------------------------------------------------------------------------
INSERT_IMAGE_AT_DOC_POS PROC NEAR
    ; AL = ID (1 o 2)
    PUSH AX
    MOV AX, PLACED_COUNT
    CMP AX, MAX_PLACED
    JAE IIA_FULL

    ; 1. Calcular offset en PLACED_TABLE (PLACED_COUNT * ENTRY_SIZE)
    ; Se ejecuta antes del calculo de coordenadas para no sobreescribir DX con el producto
    MOV BX, ENTRY_SIZE
    MUL BX
    LEA DI, PLACED_TABLE
    ADD DI, AX

    ; 2. Coordenadas absolutas en pixeles del documento en la posicion del cursor:
    ; X = CUR_COL * 8
    ; Y = CUR_ROW * 8
    MOV AX, CUR_COL
    SHL AX, 3
    MOV CX, AX

    MOV AX, CUR_ROW
    SHL AX, 3
    MOV DX, AX

    POP AX                  ; Recuperar ID
    MOV [DI], AL
    MOV [DI+1], CX          ; doc_X
    MOV [DI+3], DX          ; doc_Y
    MOV BYTE PTR [DI+5], 0  ; Flip = 0
    MOV BYTE PTR [DI+6], 0  ; Rot = 0

    INC PLACED_COUNT
    MOV FULL_REDRAW_REQ, 1
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
    MOV FULL_REDRAW_REQ, 1
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

    ; 1. Titulo de la ayuda
    MOV CX, 32
    MOV DX, 22
    LEA SI, TXT_HELP_T
    MOV BL, 14              ; Amarillo brillante
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; 2. Seccion 1: Navegacion y Cursor
    MOV CX, 22
    MOV DX, 35
    LEA SI, TXT_H_SEC1
    MOV BL, 11              ; Cian
    MOV BH, 0
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 45
    LEA SI, TXT_H_C
    MOV BL, 15              ; Blanco
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 55
    LEA SI, TXT_H_U
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 65
    LEA SI, TXT_H_D
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 75
    LEA SI, TXT_H_NAV
    MOV BL, 7               ; Gris claro
    CALL DRAW_STRING_8X8

    ; 3. Seccion 2: Formato y Pixel Art
    MOV CX, 22
    MOV DX, 88
    LEA SI, TXT_H_SEC2
    MOV BL, 11              ; Cian
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 98
    LEA SI, TXT_H_M
    MOV BL, 15              ; Blanco
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 108
    LEA SI, TXT_H_N
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 118
    LEA SI, TXT_H_IMG
    CALL DRAW_STRING_8X8

    ; 4. Seccion 3: Sistema y Archivo
    MOV CX, 22
    MOV DX, 131
    LEA SI, TXT_H_SEC3
    MOV BL, 11              ; Cian
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 141
    LEA SI, TXT_H_B
    MOV BL, 15              ; Blanco
    CALL DRAW_STRING_8X8

    MOV CX, 24
    MOV DX, 151
    LEA SI, TXT_H_S
    CALL DRAW_STRING_8X8

    ; 5. Mensaje de retorno
    MOV CX, 24
    MOV DX, 163
    LEA SI, TXT_H_RET
    MOV BL, 10              ; Verde claro
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
    MOV FULL_REDRAW_REQ, 1
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
; RENDERIZADO DIFERENCIAL Y PARPADEO DE CURSOR EN EL LIENZO (MODO 13H)
; ===========================================================================

; ---------------------------------------------------------------------------
; REDRAW_EDITOR_SCREEN: Forzar redibujado completo e invalidacion de pantalla
; ---------------------------------------------------------------------------
REDRAW_EDITOR_SCREEN PROC NEAR
    MOV FULL_REDRAW_REQ, 1
    CALL UPDATE_EDITOR_DISPLAY
    RET
REDRAW_EDITOR_SCREEN ENDP

; ---------------------------------------------------------------------------
; INVALIDATE_AND_CLEAR_SCREEN: Limpia VRAM y fuerza recarga de buffers sombra
; ---------------------------------------------------------------------------
INVALIDATE_AND_CLEAR_SCREEN PROC NEAR
    ; 1. Limpiar Barra Superior: Y 0..7 (Negro)
    MOV CX, 0
    MOV DX, 0
    MOV SI, 320
    MOV BP, 8
    MOV AL, 0
    CALL FILL_RECT

    ; 2. Limpiar Lienzo de Edicion: Y 8..199 (192 pixeles = 24 filas)
    MOV CX, 0
    MOV DX, 8
    MOV SI, 320
    MOV BP, 192
    MOV AL, 0
    CALL FILL_RECT

    ; 3. Invalidar todos los buffers sombra con 0FFh (960 celdas)
    PUSH ES
    PUSH DI
    MOV AX, DS
    MOV ES, AX
    CLD
    MOV AL, 0FFH

    LEA DI, SHADOW_CHARS
    MOV CX, VISIBLE_CELLS
    REP STOSB

    LEA DI, SHADOW_FG
    MOV CX, VISIBLE_CELLS
    REP STOSB

    LEA DI, SHADOW_BG
    MOV CX, VISIBLE_CELLS
    REP STOSB

    POP DI
    POP ES

    ; 4. Invalidar estado de la barra superior
    MOV PREV_STATUS_LN, 0FFFFH
    MOV PREV_STATUS_COL, 0FFFFH
    MOV PREV_STATUS_FG, 0FFH
    MOV PREV_STATUS_BG, 0FFH

    ; 5. Renderizar elementos estaticos de la barra superior (Fila 0)
    ; Etiqueta DOC:
    MOV CX, 4
    MOV DX, 0
    LEA SI, TXT_LBL_FILE
    MOV BL, 11              ; Cian
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Nombre de archivo
    MOV CX, 36
    MOV DX, 0
    LEA SI, CURRENT_FILENAME
    MOV BL, 14              ; Amarillo
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Etiqueta L:
    MOV CX, 150
    MOV DX, 0
    LEA SI, TXT_LBL_LN
    MOV BL, 7
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Etiqueta C:
    MOV CX, 198
    MOV DX, 0
    LEA SI, TXT_LBL_COL
    MOV BL, 7
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Etiqueta FG:
    MOV CX, 246
    MOV DX, 0
    LEA SI, TXT_LBL_FG
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    ; Etiqueta BG:
    MOV CX, 284
    MOV DX, 0
    LEA SI, TXT_LBL_BG
    MOV BL, 15
    MOV BH, 0
    CALL DRAW_STRING_8X8

    RET
INVALIDATE_AND_CLEAR_SCREEN ENDP

; ---------------------------------------------------------------------------
; UPDATE_EDITOR_DISPLAY: Actualizacion selectiva y diferencial de celdas
; ---------------------------------------------------------------------------
UPDATE_EDITOR_DISPLAY PROC NEAR
    ; 1. Verificar si hay peticion de invalidacion total o scroll de viewport
    CMP FULL_REDRAW_REQ, 1
    JE  UED_DO_FULL
    CMP REDRAW_REQ, 1
    JE  UED_DO_FULL
    MOV AX, VIEW_START_LINE
    CMP AX, PREV_VIEW_START_LINE
    JE  UED_DIFF_SCAN

UED_DO_FULL:
    CALL INVALIDATE_AND_CLEAR_SCREEN
    MOV FULL_REDRAW_REQ, 0
    MOV REDRAW_REQ, 0
    MOV AX, VIEW_START_LINE
    MOV PREV_VIEW_START_LINE, AX

UED_DIFF_SCAN:
    MOV CELL_CHANGED_FLAG, 0

    ; Recorrer las 24 filas visibles (BP = 0..23)
    XOR BP, BP
UED_ROW_LOOP:
    CMP BP, VISIBLE_ROWS
    JB  UED_ROW_CONTINUE
    JMP UED_ROWS_DONE

UED_ROW_CONTINUE:
    ; Fila absoluta del documento: AX = VIEW_START_LINE + BP
    MOV AX, VIEW_START_LINE
    ADD AX, BP
    MOV DRAW_LINE_ABS, AX

    ; Coordenada Y en pixeles: DX = 8 + BP * 8
    MOV DX, BP
    SHL DX, 3
    ADD DX, 8
    MOV DRAW_ROW_Y, DX

    ; Base en documento: AX = DRAW_LINE_ABS * 40
    MOV AX, DRAW_LINE_ABS
    MOV BX, MAX_COLS
    MUL BX
    MOV DOC_ROW_BASE_OFF, AX

    ; Base en buffer sombra: AX = BP * 40
    MOV AX, BP
    MOV BX, MAX_COLS
    MUL BX
    MOV SHADOW_ROW_BASE_OFF, AX

    ; Determinar si esta fila visible contiene al cursor
    MOV IS_CUR_ROW_FLAG, 0
    MOV AX, DRAW_LINE_ABS
    CMP AX, CUR_ROW
    JNE UED_START_COLS
    MOV IS_CUR_ROW_FLAG, 1

UED_START_COLS:
    ; Recorrer las 40 columnas (0..39)
    XOR CX, CX
UED_COL_LOOP:
    CMP CX, MAX_COLS
    JB  UED_COL_CONTINUE
    JMP UED_NEXT_ROW

UED_COL_CONTINUE:
    ; DI = Offset en buffer sombra (SHADOW_ROW_BASE_OFF + CX)
    MOV DI, SHADOW_ROW_BASE_OFF
    ADD DI, CX

    ; Obtener datos deseados para la celda
    MOV AX, DRAW_LINE_ABS
    CMP AX, DOC_LINE_COUNT
    JAE UED_EMPTY_CELL

    ; Celda con texto dentro del documento
    MOV SI, DOC_ROW_BASE_OFF
    ADD SI, CX
    MOV AL, DOC_CHARS[SI]
    MOV DL, DOC_FG[SI]
    MOV DH, DOC_BG[SI]
    JMP UED_CHECK_CURSOR

UED_EMPTY_CELL:
    MOV AL, ' '
    MOV DL, 7
    MOV DH, 0

UED_CHECK_CURSOR:
    ; Verificar si el cursor esta activo en esta celda
    CMP CURSOR_VISIBLE_STATE, 1
    JNE UED_COMPARE_SHADOW
    CMP IS_CUR_ROW_FLAG, 1
    JNE UED_COMPARE_SHADOW
    CMP CX, CUR_COL
    JNE UED_COMPARE_SHADOW

    ; Cursor activo visible: bloque amarillo brillante con letra en negro
    MOV DL, 0               ; Color de letra negro
    MOV DH, 14              ; Fondo amarillo brillante

UED_COMPARE_SHADOW:
    ; Comparar deseado (AL, DL, DH) contra el buffer sombra
    CMP AL, SHADOW_CHARS[DI]
    JNE UED_DRAW_CELL
    CMP DL, SHADOW_FG[DI]
    JNE UED_DRAW_CELL
    CMP DH, SHADOW_BG[DI]
    JE  UED_NEXT_COL        ; Coincide exactamente: no escribir en VRAM

UED_DRAW_CELL:
    ; Guardar nuevo contenido en buffer sombra
    MOV SHADOW_CHARS[DI], AL
    MOV SHADOW_FG[DI], DL
    MOV SHADOW_BG[DI], DH
    MOV CELL_CHANGED_FLAG, 1

    PUSH CX
    PUSH DX
    PUSH BP
    PUSH DI

    ; Colores: BL = Color de fuente (DL), BH = Color de fondo (DH)
    MOV BX, DX

    ; Coordenada X de pantalla: CX = Columna * 8
    SHL CX, 3

    ; Coordenada Y de pantalla: DX = DRAW_ROW_Y
    MOV DX, DRAW_ROW_Y

    CALL DRAW_CHAR_8X8

    POP DI
    POP BP
    POP DX
    POP CX

UED_NEXT_COL:
    INC CX
    JMP UED_COL_LOOP

UED_NEXT_ROW:
    INC BP
    JMP UED_ROW_LOOP

UED_ROWS_DONE:
    ; Redibujar imagenes sobre el texto si alguna celda cambio o si hay imagenes activas
    CMP PLACED_COUNT, 0
    JE  UED_UPDATE_STATUS
    CMP CELL_CHANGED_FLAG, 1
    JNE UED_UPDATE_STATUS
    CALL DRAW_PLACED_IMAGES_OVER_TEXT

UED_UPDATE_STATUS:
    CALL UPDATE_STATUS_BAR_DIFF
    RET
UPDATE_EDITOR_DISPLAY ENDP

; ---------------------------------------------------------------------------
; UPDATE_STATUS_BAR_DIFF: Redibuja selectivamente solo los indicadores cambiados
; ---------------------------------------------------------------------------
UPDATE_STATUS_BAR_DIFF PROC NEAR
    ; 1. Indicador de Linea (Ln: XX)
    MOV AX, CUR_ROW
    CMP AX, PREV_STATUS_LN
    JE  USBD_CHK_COL
    MOV PREV_STATUS_LN, AX
    INC AX                  ; Mostrar 1-based
    MOV CX, 178
    MOV DX, 0
    CALL DRAW_DEC_2DIG

USBD_CHK_COL:
    ; 2. Indicador de Columna (Col: XX)
    MOV AX, CUR_COL
    CMP AX, PREV_STATUS_COL
    JE  USBD_CHK_FG
    MOV PREV_STATUS_COL, AX
    INC AX                  ; Mostrar 1-based
    MOV CX, 226
    MOV DX, 0
    CALL DRAW_DEC_2DIG

USBD_CHK_FG:
    ; 3. Muestra de color FG
    MOV AL, CUR_FG_IDX
    CMP AL, PREV_STATUS_FG
    JE  USBD_CHK_BG
    MOV PREV_STATUS_FG, AL
    MOV CX, 272
    MOV DX, 1
    MOV SI, 8
    MOV BP, 6
    XOR BX, BX
    MOV BL, AL
    MOV AL, FG_COLORS[BX]
    CALL FILL_RECT

USBD_CHK_BG:
    ; 4. Muestra de color BG
    MOV AL, CUR_BG_IDX
    CMP AL, PREV_STATUS_BG
    JE  USBD_DONE
    MOV PREV_STATUS_BG, AL
    MOV CX, 308
    MOV DX, 1
    MOV SI, 8
    MOV BP, 6
    XOR BX, BX
    MOV BL, AL
    MOV AL, BG_COLORS[BX]
    CALL FILL_RECT

USBD_DONE:
    RET
UPDATE_STATUS_BAR_DIFF ENDP

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
    MOV DRAW_TRANS_COLOR, 48
    RET
GII_CHK2:
    CMP AL, 2
    JNE GII_CHK3
    LEA SI, IMG2_DATA
    MOV BX, IMG2_W
    MOV DX, IMG2_H
    MOV DRAW_TRANS_COLOR, 48
    RET
GII_CHK3:
    CMP AL, 3
    JNE GII_CHK4
    LEA SI, IMG3_DATA
    MOV BX, IMG3_W
    MOV DX, IMG3_H
    MOV DRAW_TRANS_COLOR, 0
    RET
GII_CHK4:
    LEA SI, IMG4_DATA
    MOV BX, IMG4_W
    MOV DX, IMG4_H
    MOV DRAW_TRANS_COLOR, 0
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
    CMP AL, DRAW_TRANS_COLOR ; Transparencia especifica (ej. 0 en personajes)
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
