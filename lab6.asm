TITLE Lab 6 - Creador de Imagenes Pixel Art (Modo 13h)

.MODEL SMALL
.386
JUMPS
.STACK 200H

; ===========================================================================
; SEGMENTO DE DATOS
; ===========================================================================
.DATA

    ; -----------------------------------------------------------------------
    ; Instructivos / Cheatsheets de pantalla (40 columnas exactas)
    ; -----------------------------------------------------------------------
    TXT_TOP         DB '[i/o/p]Img [u]Espejo [y]Rot90 [z]Fondo '
    TXT_BOT         DB '[hjkl]Mover [Enter]Poner [c]Clr [x]Exit'

    ; -----------------------------------------------------------------------
    ; Variables de Estado del Editor
    ; -----------------------------------------------------------------------
    CUR_IMG         DB 1                ; Imagen activa: 1=Arch, 2=Honkai, 3=Escudo
    CUR_X           DW 130              ; Coordenada X actual de la imagen activa
    CUR_Y           DW 75               ; Coordenada Y actual de la imagen activa
    CUR_FLIP        DB 0                ; 0 = Normal, 1 = Volteado horizontal
    CUR_ROT         DB 0                ; 0 = 0 deg, 1 = 90 deg, 2 = 180 deg, 3 = 270 deg
    EFF_W           DW 44               ; Ancho efectivo actual con rotacion
    EFF_H           DW 36               ; Alto efectivo actual con rotacion
    MOVE_STEP       EQU 8               ; Pixeles de desplazamiento por movimiento

    REFRESH         DB 1                ; 1 = Requiere repintar pantalla completa
    EXIT_FLAG       DB 0                ; 1 = Salir del programa
    OLD_VIDEO_MODE  DB ?                ; Modo de video previo para restaurar al salir

    ; -----------------------------------------------------------------------
    ; Colores de Fondo (Alterna entre 3 colores)
    ; -----------------------------------------------------------------------
    BG_COLOR_IDX    DB 0                ; Indice del color actual (0..2)
    BG_COLORS       DB 53, 0, 2         ; 53=Celeste/Azul claro, 0=Negro, 2=Verde

    ; -----------------------------------------------------------------------
    ; Buffer de Imagenes Colocadas (Estampadas)
    ; -----------------------------------------------------------------------
    MAX_PLACED      EQU 64              ; Maximo de imagenes que se pueden colocar
    ENTRY_SIZE      EQU 7               ; Tamano en bytes por registro:
                                        ;   Offset 0: ID (1B)
                                        ;   Offset 1: X (2B)
                                        ;   Offset 3: Y (2B)
                                        ;   Offset 5: Flip (1B)
                                        ;   Offset 6: Rotacion (1B)
    PLACED_COUNT    DW 0                ; Cantidad de imagenes estampadas actualmente
    PLACED_TABLE    DB MAX_PLACED * ENTRY_SIZE DUP(0)
    CURRENT_PLACED  DW 0                ; Indice auxiliar para recorrido

    ; -----------------------------------------------------------------------
    ; Variables de Trabajo para la Rutina de Dibujo
    ; -----------------------------------------------------------------------
    DRAW_IMG_ID     DB ?
    DRAW_POSX       DW ?
    DRAW_POSY       DW ?
    DRAW_FLIP       DB ?
    DRAW_ROT        DB ?

    DRAW_W          DW ?                ; Ancho original
    DRAW_H          DW ?                ; Alto original
    DRAW_EFF_W      DW ?                ; Ancho destino segun rotacion
    DRAW_EFF_H      DW ?                ; Alto destino segun rotacion
    DRAW_DATA_PTR   DW ?                ; Puntero en memoria a los pixeles

    DRAW_TX         DW ?                ; Coordenada X destino local (0..EFF_W-1)
    DRAW_TY         DW ?                ; Coordenada Y destino local (0..EFF_H-1)
    DRAW_SX         DW ?                ; Coordenada X calculada en origen
    DRAW_SY         DW ?                ; Coordenada Y calculada en origen
    SCREEN_X        DW ?                ; Coordenada X absoluta en pantalla
    SCREEN_Y        DW ?                ; Coordenada Y absoluta en pantalla
    ROW_VRAM_OFFSET DW ?                ; Offset precalculado de la fila (screenY * 320)

    ; -----------------------------------------------------------------------
    ; Metadatos de las 3 Imagenes Pixel Art
    ; -----------------------------------------------------------------------
    IMG1_W          DW 44               ; Imagen 1: Arch Linux (44x36)
    IMG1_H          DW 36

    IMG2_W          DW 50               ; Imagen 2: Honkai (50x48)
    IMG2_H          DW 48

    IMG3_W          DW 32               ; Imagen 3: Escudo (32x32)
    IMG3_H          DW 32

    ; -----------------------------------------------------------------------
    ; Matrices de Pixeles (Color 48 = Transparente)
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

    IMG3_DATA LABEL BYTE
    db 48,48,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,44,48,48
            db 48,48,44,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,44,48,48
            db 48,48,44,0,55,55,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,55,55,0,44,48,48
            db 48,48,44,0,55,55,15,9,9,9,9,9,9,15,15,15,15,15,15,9,9,9,9,9,9,15,55,55,0,44,48,48
            db 48,48,44,0,55,55,15,9,9,9,9,9,9,15,15,47,47,15,15,9,9,9,9,9,9,15,55,55,0,44,48,48
            db 48,48,44,0,55,55,15,9,9,9,9,9,9,15,15,15,15,15,15,9,9,9,9,9,9,15,55,55,0,44,48,48
            db 48,48,44,0,55,55,15,15,15,15,15,15,15,15,2,15,15,15,15,15,15,15,15,15,15,15,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,55,55,2,55,55,55,55,55,55,55,55,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,55,14,2,2,55,55,55,55,55,55,55,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,55,55,2,55,2,55,55,55,55,55,55,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,55,55,4,55,55,2,55,55,55,2,55,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,55,4,55,2,2,2,2,2,2,55,55,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,55,55,55,55,55,2,2,2,2,55,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,55,55,0,0,0,0,55,55,55,55,55,55,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,0,0,15,15,15,15,0,55,55,55,55,55,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,0,0,15,0,15,15,0,15,15,0,0,55,55,55,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,0,0,15,15,15,15,15,15,15,0,0,55,55,55,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,0,0,15,15,0,0,15,15,15,0,0,55,55,55,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,0,0,15,0,15,15,0,15,15,0,0,55,55,2,2,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,55,55,55,55,0,0,15,15,15,15,0,55,55,2,2,2,55,55,55,55,55,55,0,44,48,48
            db 48,48,44,0,55,55,0,0,55,55,55,55,0,0,0,0,2,2,2,2,55,55,55,55,55,55,0,0,0,44,48,48
            db 48,48,44,0,0,0,15,15,0,0,55,55,55,55,55,55,55,55,55,55,55,55,0,0,15,15,0,0,0,44,48,48
            db 48,48,48,44,44,0,15,15,15,15,0,0,55,55,55,55,55,55,55,55,0,0,15,15,15,15,0,44,44,48,48,48
            db 48,48,48,48,44,44,0,15,15,15,15,15,0,0,55,55,55,55,0,0,15,15,15,15,15,0,44,44,48,48,48,48
            db 48,48,48,48,48,44,44,0,15,15,15,15,15,15,0,0,0,0,15,15,15,15,15,15,0,44,44,48,48,48,48,48
            db 48,48,48,48,48,48,44,44,0,15,15,15,15,15,15,15,15,15,15,15,15,15,15,0,44,44,48,48,48,48,48,48
            db 48,48,48,48,48,48,48,44,44,0,15,15,15,15,15,15,15,15,15,15,15,15,0,44,44,48,48,48,48,48,48,48
            db 48,48,48,48,48,48,48,48,44,44,0,0,15,15,15,15,15,15,15,15,0,0,44,44,48,48,48,48,48,48,48,48
            db 48,48,48,48,48,48,48,48,48,44,44,44,0,0,15,15,15,15,0,0,44,44,44,48,48,48,48,48,48,48,48,48
            db 48,48,48,48,48,48,48,48,48,48,48,44,0,0,0,0,0,0,0,0,44,48,48,48,48,48,48,48,48,48,48,48
            db 48,48,48,48,48,48,48,48,48,48,48,44,44,44,44,44,44,44,44,44,44,48,48,48,48,48,48,48,48,48,48,48
            db 48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48,48

; ===========================================================================
; SEGMENTO DE CODIGO
; ===========================================================================
.CODE

; ---------------------------------------------------------------------------
; PROCEDIMIENTO PRINCIPAL (MAIN)
; ---------------------------------------------------------------------------
MAIN PROC FAR
    MOV AX, @DATA
    MOV DS, AX
    MOV ES, AX

    ; Guardar modo de video actual antes de cambiar a modo 13h
    MOV AH, 0FH
    INT 10H
    MOV OLD_VIDEO_MODE, AL

    ; Cambiar a modo grafico VGA 13h (320x200, 256 colores)
    CALL SET_VIDEO_MODE

    ; Calcular dimensiones iniciales de la imagen activa
    CALL GET_ACTIVE_DIMS
    CALL CLAMP_POSITION

MAIN_LOOP:
    ; Si se marco solicitud de refresco, redibujar toda la pantalla
    CMP REFRESH, 0
    JE WAIT_KEY_EVENT
    CALL REDRAW_SCREEN
    MOV REFRESH, 0

WAIT_KEY_EVENT:
    ; Leer tecla del usuario y despachar accion correspondiente
    CALL HANDLE_KEY

    ; Verificar si el usuario solicito salir
    CMP EXIT_FLAG, 1
    JE EXIT_PROGRAM

    JMP MAIN_LOOP

EXIT_PROGRAM:
    ; Restaurar modo de video original
    CALL RESTORE_VIDEO_MODE

    ; Retornar control al DOS limpiamente
    MOV AX, 4C00H
    INT 21H
MAIN ENDP

; ---------------------------------------------------------------------------
; SET_VIDEO_MODE: Establece modo de video VGA 13h (320x200, 256 colores)
; ---------------------------------------------------------------------------
SET_VIDEO_MODE PROC NEAR
    MOV AX, 0013H
    INT 10H
    RET
SET_VIDEO_MODE ENDP

; ---------------------------------------------------------------------------
; RESTORE_VIDEO_MODE: Restaura el modo de video original que tenia el sistema
; ---------------------------------------------------------------------------
RESTORE_VIDEO_MODE PROC NEAR
    MOV AH, 00H
    MOV AL, OLD_VIDEO_MODE
    INT 10H
    RET
RESTORE_VIDEO_MODE ENDP

; ---------------------------------------------------------------------------
; REDRAW_SCREEN: Limpia el lienzo con el fondo actual, imprime barras de
; instructivo superior e inferior, dibuja imagenes estampadas y la activa.
; ---------------------------------------------------------------------------
REDRAW_SCREEN PROC NEAR
    ; 1. Limpiar pantalla en memoria de video (0A000h)
    MOV AX, 0A000H
    MOV ES, AX

    ; Barra superior: filas 0..7 (offset 0..2559) -> color 0 (negro para contraste maximo)
    XOR DI, DI
    MOV AL, 00H
    MOV AH, AL
    MOV CX, 1280        ; 2560 bytes / 2 = 1280 palabras
    REP STOSW

    ; Lienzo central: filas 8..191 (offset 2560..61439) -> color de fondo activo
    XOR BX, BX
    MOV BL, BG_COLOR_IDX
    MOV AL, BG_COLORS[BX]
    MOV AH, AL
    MOV CX, 29440       ; 58880 bytes / 2 = 29440 palabras
    REP STOSW

    ; Barra inferior: filas 192..199 (offset 61440..63999) -> color 0 (negro)
    MOV AL, 00H
    MOV AH, AL
    MOV CX, 1280        ; 2560 bytes / 2 = 1280 palabras
    REP STOSW

    ; 2. Dibujar instructivos de texto mediante BIOS INT 10h (AH=1300h)
    PUSH DS
    POP ES              ; ES debe apuntar a @DATA para ES:BP

    ; Instructivo Inferior (Fila 24, Columna 0, Cian claro 0Bh)
    ; Se imprime primero y con 39 caracteres para evitar el salto de linea y scroll
    MOV AX, 1300H
    MOV BX, 000BH       ; Pagina 0, Color 0Bh
    MOV CX, 39          ; Longitud de 39 evita scroll al llegar a la esquina inferior
    MOV DX, 1800H       ; Fila 24 (18h), Columna 0
    LEA BP, TXT_BOT
    INT 10H

    ; Instructivo Superior (Fila 0, Columna 0, Amarillo 0Eh)
    ; Se imprime despues para garantizar que permanezca visible e intacto en fila 0
    MOV AX, 1300H
    MOV BX, 000EH       ; Pagina 0, Color 0Eh
    MOV CX, 39          ; Longitud de 39 caracteres
    MOV DX, 0000H       ; Fila 0, Columna 0
    LEA BP, TXT_TOP
    INT 10H

    ; 3. Dibujar todas las imagenes ya colocadas
    MOV AX, 0A000H
    MOV ES, AX          ; ES vuelve a apuntar a la VRAM

    MOV CURRENT_PLACED, 0
DRAW_PLACED_LOOP:
    MOV AX, CURRENT_PLACED
    CMP AX, PLACED_COUNT
    JAE DRAW_ACTIVE_PREVIEW

    ; Calcular posicion en tabla: CURRENT_PLACED * ENTRY_SIZE (7 bytes)
    MOV CX, ENTRY_SIZE
    MUL CX
    LEA SI, PLACED_TABLE
    ADD SI, AX

    ; Cargar datos de la imagen colocada
    MOV AL, [SI]
    MOV DRAW_IMG_ID, AL
    MOV AX, [SI+1]
    MOV DRAW_POSX, AX
    MOV AX, [SI+3]
    MOV DRAW_POSY, AX
    MOV AL, [SI+5]
    MOV DRAW_FLIP, AL
    MOV AL, [SI+6]
    MOV DRAW_ROT, AL

    CALL DRAW_TRANSFORMED_IMAGE

    INC CURRENT_PLACED
    JMP DRAW_PLACED_LOOP

DRAW_ACTIVE_PREVIEW:
    ; 4. Dibujar la imagen activa (cursor actual)
    MOV AL, CUR_IMG
    MOV DRAW_IMG_ID, AL
    MOV AX, CUR_X
    MOV DRAW_POSX, AX
    MOV AX, CUR_Y
    MOV DRAW_POSY, AX
    MOV AL, CUR_FLIP
    MOV DRAW_FLIP, AL
    MOV AL, CUR_ROT
    MOV DRAW_ROT, AL

    CALL DRAW_TRANSFORMED_IMAGE

    ; 5. Dibujar indicadores visuales de seleccion en las esquinas activas
    CALL DRAW_CURSOR_BRACKETS

    RET
REDRAW_SCREEN ENDP

; ---------------------------------------------------------------------------
; GET_IMG_INFO: Retorna puntero de datos y dimensiones originales de la imagen.
; Entrada: AL = ID de la imagen (1, 2, 3)
; Salida:  SI = Offset de los datos de pixeles
;          BX = Ancho original (W)
;          DX = Alto original (H)
; ---------------------------------------------------------------------------
GET_IMG_INFO PROC NEAR
    CMP AL, 1
    JNE CHECK_INFO_IMG2
    LEA SI, IMG1_DATA
    MOV BX, IMG1_W
    MOV DX, IMG1_H
    RET

CHECK_INFO_IMG2:
    CMP AL, 2
    JNE CHECK_INFO_IMG3
    LEA SI, IMG2_DATA
    MOV BX, IMG2_W
    MOV DX, IMG2_H
    RET

CHECK_INFO_IMG3:
    LEA SI, IMG3_DATA
    MOV BX, IMG3_W
    MOV DX, IMG3_H
    RET
GET_IMG_INFO ENDP

; ---------------------------------------------------------------------------
; GET_ACTIVE_DIMS: Calcula ancho y alto efectivos de la imagen activa segun
; su rotacion actual (0, 90, 180, 270 grados).
; Salida: Actualiza variables globales EFF_W y EFF_H.
; ---------------------------------------------------------------------------
GET_ACTIVE_DIMS PROC NEAR
    MOV AL, CUR_IMG
    CALL GET_IMG_INFO

    CMP CUR_ROT, 1
    JE  GAD_ROTATED
    CMP CUR_ROT, 3
    JE  GAD_ROTATED

    ; Rotacion 0 o 180 grados: mantiene ancho y alto
    MOV EFF_W, BX
    MOV EFF_H, DX
    RET

GAD_ROTATED:
    ; Rotacion 90 o 270 grados: intercambia ancho y alto
    MOV EFF_W, DX
    MOV EFF_H, BX
    RET
GET_ACTIVE_DIMS ENDP

; ---------------------------------------------------------------------------
; CLAMP_POSITION: Asegura que la coordenada de la imagen activa se mantenga
; estrictamente dentro de los limites visibles del lienzo (X: 0..319, Y: 8..191).
; ---------------------------------------------------------------------------
CLAMP_POSITION PROC NEAR
    ; Limite izquierdo X >= 0
    CMP CUR_X, 0
    JGE CP_CHK_X_MAX
    MOV CUR_X, 0

CP_CHK_X_MAX:
    ; Limite derecho X + EFF_W <= 320
    MOV AX, 320
    SUB AX, EFF_W
    CMP CUR_X, AX
    JLE CP_CHK_Y_MIN
    MOV CUR_X, AX

CP_CHK_Y_MIN:
    ; Limite superior Y >= 8 (abajo de la barra superior)
    CMP CUR_Y, 8
    JGE CP_CHK_Y_MAX
    MOV CUR_Y, 8

CP_CHK_Y_MAX:
    ; Limite inferior Y + EFF_H <= 192 (arriba de la barra inferior)
    MOV AX, 192
    SUB AX, EFF_H
    CMP CUR_Y, AX
    JLE CP_DONE
    MOV CUR_Y, AX

CP_DONE:
    RET
CLAMP_POSITION ENDP

; ---------------------------------------------------------------------------
; RUTINAS DE MOVIMIENTO (Paso de 8 pixeles con validacion de limites)
; ---------------------------------------------------------------------------
MOVE_LEFT PROC NEAR
    CALL GET_ACTIVE_DIMS
    MOV AX, CUR_X
    CMP AX, MOVE_STEP
    JAE ML_OK
    MOV CUR_X, 0
    JMP ML_FIN
ML_OK:
    SUB CUR_X, MOVE_STEP
ML_FIN:
    MOV REFRESH, 1
    RET
MOVE_LEFT ENDP

MOVE_RIGHT PROC NEAR
    CALL GET_ACTIVE_DIMS
    MOV AX, 320
    SUB AX, EFF_W
    ADD CUR_X, MOVE_STEP
    CMP CUR_X, AX
    JBE MR_FIN
    MOV CUR_X, AX
MR_FIN:
    MOV REFRESH, 1
    RET
MOVE_RIGHT ENDP

MOVE_UP PROC NEAR
    CALL GET_ACTIVE_DIMS
    MOV AX, CUR_Y
    CMP AX, 8 + MOVE_STEP
    JAE MU_OK
    MOV CUR_Y, 8
    JMP MU_FIN
MU_OK:
    SUB CUR_Y, MOVE_STEP
MU_FIN:
    MOV REFRESH, 1
    RET
MOVE_UP ENDP

MOVE_DOWN PROC NEAR
    CALL GET_ACTIVE_DIMS
    MOV AX, 192
    SUB AX, EFF_H
    ADD CUR_Y, MOVE_STEP
    CMP CUR_Y, AX
    JBE MD_FIN
    MOV CUR_Y, AX
MD_FIN:
    MOV REFRESH, 1
    RET
MOVE_DOWN ENDP

; ---------------------------------------------------------------------------
; TRANSFORMACIONES DE IMAGEN ACTIVA
; ---------------------------------------------------------------------------
TOGGLE_FLIP PROC NEAR
    XOR CUR_FLIP, 1     ; Alternar entre 0 y 1
    MOV REFRESH, 1
    RET
TOGGLE_FLIP ENDP

ROTATE_CW PROC NEAR
    INC CUR_ROT
    AND CUR_ROT, 3      ; Ciclo: 0 -> 1 -> 2 -> 3 -> 0
    CALL GET_ACTIVE_DIMS
    CALL CLAMP_POSITION
    MOV REFRESH, 1
    RET
ROTATE_CW ENDP

CYCLE_BG PROC NEAR
    INC BG_COLOR_IDX
    CMP BG_COLOR_IDX, 3
    JB  CBG_OK
    MOV BG_COLOR_IDX, 0
CBG_OK:
    MOV REFRESH, 1
    RET
CYCLE_BG ENDP

STAMP_IMAGE PROC NEAR
    MOV AX, PLACED_COUNT
    CMP AX, MAX_PLACED
    JAE STAMP_FIN       ; Si el buffer esta lleno, ignorar

    ; Offset = PLACED_COUNT * ENTRY_SIZE (7 bytes)
    MOV CX, ENTRY_SIZE
    MUL CX
    LEA DI, PLACED_TABLE
    ADD DI, AX

    ; Guardar registro en la tabla
    MOV AL, CUR_IMG
    MOV [DI], AL
    MOV AX, CUR_X
    MOV [DI+1], AX
    MOV AX, CUR_Y
    MOV [DI+3], AX
    MOV AL, CUR_FLIP
    MOV [DI+5], AL
    MOV AL, CUR_ROT
    MOV [DI+6], AL

    INC PLACED_COUNT
    MOV REFRESH, 1
STAMP_FIN:
    RET
STAMP_IMAGE ENDP

CLEAR_ALL PROC NEAR
    MOV PLACED_COUNT, 0
    MOV REFRESH, 1
    RET
CLEAR_ALL ENDP

; ---------------------------------------------------------------------------
; DRAW_TRANSFORMED_IMAGE: Rutina generica de dibujo con soporte completo para
; rotaciones de 90, 180, 270 grados y modo espejo horizontal.
; Transparencia: El color 48 se omite para no pintar fondo no deseado.
; ---------------------------------------------------------------------------
DRAW_TRANSFORMED_IMAGE PROC NEAR
    ; Obtener puntero y dimensiones originales
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

    ; Recorte vertical: comprobar rango permitido [8, 191]
    CMP BX, 8
    JB  DTI_NEXT_TY
    CMP BX, 192
    JAE DTI_NEXT_TY

    ; Precalcular offset de fila: screenY * 320
    MOV DI, BX
    SHL DI, 8           ; BX * 256
    SHL BX, 6           ; BX * 64
    ADD DI, BX          ; screenY * 320
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

    ; Recorte horizontal: comprobar rango [0, 319]
    CMP CX, 320
    JAE DTI_NEXT_TX

    ; Mapeo matematico de coordenadas destino (tx, ty) a origen (sx, sy)
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
    JMP DTI_CALC_READY

DTI_CALC_READY:
    ; Offset en matriz de imagen = sy * DRAW_W + sx
    MOV AX, DRAW_SY
    MUL DRAW_W
    ADD AX, DRAW_SX
    MOV SI, DRAW_DATA_PTR
    ADD SI, AX

    ; Leer pixel de la matriz
    MOV AL, [SI]
    CMP AL, 48          ; 48 representa color transparente
    JE  DTI_NEXT_TX

    ; Escribir pixel directamente en memoria de video (0A000h)
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
    RET
DRAW_TRANSFORMED_IMAGE ENDP

; ---------------------------------------------------------------------------
; DRAW_CURSOR_BRACKETS: Dibuja cuatro marcas de esquina en color blanco (15)
; alrededor del area de la imagen activa para indicar visualmente el cursor.
; ---------------------------------------------------------------------------
DRAW_CURSOR_BRACKETS PROC NEAR
    MOV AL, 15          ; Blanco brillante

    ; Esquina Superior Izquierda: (CUR_X, CUR_Y)
    MOV CX, CUR_X
    MOV DX, CUR_Y
    CALL PLOT_PIXEL_SAFE
    MOV CX, CUR_X
    INC CX
    MOV DX, CUR_Y
    CALL PLOT_PIXEL_SAFE
    MOV CX, CUR_X
    MOV DX, CUR_Y
    INC DX
    CALL PLOT_PIXEL_SAFE

    ; Esquina Superior Derecha: (CUR_X + EFF_W - 1, CUR_Y)
    MOV CX, CUR_X
    ADD CX, EFF_W
    DEC CX
    MOV DX, CUR_Y
    CALL PLOT_PIXEL_SAFE
    DEC CX
    CALL PLOT_PIXEL_SAFE
    INC CX
    INC DX
    CALL PLOT_PIXEL_SAFE

    ; Esquina Inferior Izquierda: (CUR_X, CUR_Y + EFF_H - 1)
    MOV CX, CUR_X
    MOV DX, CUR_Y
    ADD DX, EFF_H
    DEC DX
    CALL PLOT_PIXEL_SAFE
    INC CX
    CALL PLOT_PIXEL_SAFE
    DEC CX
    DEC DX
    CALL PLOT_PIXEL_SAFE

    ; Esquina Inferior Derecha: (CUR_X + EFF_W - 1, CUR_Y + EFF_H - 1)
    MOV CX, CUR_X
    ADD CX, EFF_W
    DEC CX
    MOV DX, CUR_Y
    ADD DX, EFF_H
    DEC DX
    CALL PLOT_PIXEL_SAFE
    DEC CX
    CALL PLOT_PIXEL_SAFE
    INC CX
    DEC DX
    CALL PLOT_PIXEL_SAFE

    RET
DRAW_CURSOR_BRACKETS ENDP

; ---------------------------------------------------------------------------
; PLOT_PIXEL_SAFE: Escribe un pixel en VRAM si esta dentro del lienzo seguro.
; Entrada: CX = X (0..319), DX = Y (8..191), AL = Color, ES = 0A000h
; ---------------------------------------------------------------------------
PLOT_PIXEL_SAFE PROC NEAR
    CMP CX, 320
    JAE PPS_RET
    CMP DX, 8
    JB  PPS_RET
    CMP DX, 192
    JAE PPS_RET

    PUSH BX
    PUSH DI
    MOV BX, DX
    MOV DI, BX
    SHL DI, 8
    SHL BX, 6
    ADD DI, BX
    ADD DI, CX
    MOV ES:[DI], AL
    POP DI
    POP BX
PPS_RET:
    RET
PLOT_PIXEL_SAFE ENDP

; ---------------------------------------------------------------------------
; HANDLE_KEY: Lee y procesa las teclas presionadas por el usuario.
; Soporta:
;   - Bloque Vim: h, j, k, l (y flechas)
;   - Fila superior: y (rotar), u (espejo), i/o/p (imagenes 1, 2, 3)
;   - Fijar imagen: Enter / Espacio
;   - Fila inferior: z (fondo), c (limpiar), x / Esc (salir)
;   - Compatibilidad con combinaciones Alt
; ---------------------------------------------------------------------------
HANDLE_KEY PROC NEAR
    MOV AH, 00H
    INT 16H             ; AL = Codigo ASCII, AH = Scan Code

    ; Si es tecla extendida (AL=0 o AL=E0h), verificar scan code directamente
    CMP AL, 0
    JE  CHECK_EXTENDED_KEYS
    CMP AL, 0E0H
    JE  CHECK_EXTENDED_KEYS

    ; Normalizar minusculas a mayusculas para comparacion rapida
    CMP AL, 'a'
    JB  DISPATCH_ASCII
    CMP AL, 'z'
    JA  DISPATCH_ASCII
    SUB AL, 20H

DISPATCH_ASCII:
    ; Salir: 'X' o Esc (1Bh)
    CMP AL, 'X'
    JE  HK_EXIT
    CMP AL, 1BH
    JE  HK_EXIT

    ; Movimiento estilo Vim: 'H', 'J', 'K', 'L'
    CMP AL, 'H'
    JE  HK_LEFT
    CMP AL, 'J'
    JE  HK_DOWN
    CMP AL, 'K'
    JE  HK_UP
    CMP AL, 'L'
    JE  HK_RIGHT

    ; Seleccionar Imagen: 'I', 'O', 'P' (o '1', '2', '3')
    CMP AL, 'I'
    JE  HK_IMG1
    CMP AL, '1'
    JE  HK_IMG1
    CMP AL, 'O'
    JE  HK_IMG2
    CMP AL, '2'
    JE  HK_IMG2
    CMP AL, 'P'
    JE  HK_IMG3
    CMP AL, '3'
    JE  HK_IMG3

    ; Modo Espejo (Flip horizontal): 'U'
    CMP AL, 'U'
    JE  HK_FLIP

    ; Rotar 90 grados: 'Y'
    CMP AL, 'Y'
    JE  HK_ROT

    ; Estampar / Fijar imagen: Enter (0Dh) o Barra Espaciadora (20h)
    CMP AL, 0DH
    JE  HK_STAMP
    CMP AL, 20H
    JE  HK_STAMP

    ; Cambiar fondo: 'Z'
    CMP AL, 'Z'
    JE  HK_BG

    ; Limpiar lienzo: 'C'
    CMP AL, 'C'
    JE  HK_CLEAR

CHECK_EXTENDED_KEYS:
    ; Flechas del teclado
    CMP AH, 4BH         ; Flecha Izquierda
    JE  HK_LEFT
    CMP AH, 50H         ; Flecha Abajo
    JE  HK_DOWN
    CMP AH, 48H         ; Flecha Arriba
    JE  HK_UP
    CMP AH, 4DH         ; Flecha Derecha
    JE  HK_RIGHT

    ; Atajos con Alt (compatibilidad total)
    CMP AH, 17H         ; Alt+I -> Imagen 1
    JE  HK_IMG1
    CMP AH, 24H         ; Alt+J -> Imagen 2
    JE  HK_IMG2
    CMP AH, 25H         ; Alt+K -> Imagen 3
    JE  HK_IMG3
    CMP AH, 16H         ; Alt+U -> Espejo
    JE  HK_FLIP
    CMP AH, 13H         ; Alt+R -> Espejo
    JE  HK_FLIP
    CMP AH, 26H         ; Alt+L -> Rotar 90
    JE  HK_ROT
    CMP AH, 32H         ; Alt+M -> Cambiar fondo
    JE  HK_BG
    CMP AH, 18H         ; Alt+O -> Limpiar pantalla
    JE  HK_CLEAR
    CMP AH, 2EH         ; Alt+C -> Limpiar pantalla
    JE  HK_CLEAR
    CMP AH, 2DH         ; Alt+X -> Salir
    JE  HK_EXIT

    RET

HK_EXIT:
    MOV EXIT_FLAG, 1
    RET

HK_LEFT:
    CALL MOVE_LEFT
    RET

HK_DOWN:
    CALL MOVE_DOWN
    RET

HK_UP:
    CALL MOVE_UP
    RET

HK_RIGHT:
    CALL MOVE_RIGHT
    RET

HK_IMG1:
    MOV CUR_IMG, 1
    CALL GET_ACTIVE_DIMS
    CALL CLAMP_POSITION
    MOV REFRESH, 1
    RET

HK_IMG2:
    MOV CUR_IMG, 2
    CALL GET_ACTIVE_DIMS
    CALL CLAMP_POSITION
    MOV REFRESH, 1
    RET

HK_IMG3:
    MOV CUR_IMG, 3
    CALL GET_ACTIVE_DIMS
    CALL CLAMP_POSITION
    MOV REFRESH, 1
    RET

HK_FLIP:
    CALL TOGGLE_FLIP
    RET

HK_ROT:
    CALL ROTATE_CW
    RET

HK_STAMP:
    CALL STAMP_IMAGE
    RET

HK_BG:
    CALL CYCLE_BG
    RET

HK_CLEAR:
    CALL CLEAR_ALL
    RET
HANDLE_KEY ENDP

END MAIN
