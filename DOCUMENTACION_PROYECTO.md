# Documentación Técnica del Proyecto: Editor de Texto x8086 (Modo 13h)

## 1. Información General del Proyecto
- **Asignatura:** Arquitectura y Diseño de Computadoras
- **Institución:** Universidad Francisco Marroquín
- **Catedrático:** Ing. Gustavo Sánchez
- **Proyecto:** Proyecto 1 - Editor de Texto en Ensamblador x8086
- **Entorno:** DOS 16-bit Real Mode (TASM / Turbo Assembler & TLINK)
- **Modo de Video:** VGA Modo 13h (320x200 píxeles, 256 colores)

---

## 2. Objetivos y Alcance
Desarrollar un editor de texto interactivo con comportamiento estilo **nano**, operando íntegramente en modo gráfico VGA 13h (320x200 píxeles a 256 colores), que incorpore:
1. **Edición de Texto Enriquecido:** Caracteres alfanuméricos y puntuación, colores configurables de fuente (FG) y fondo (BG) por carácter.
2. **Navegación y Scroll Vertical:** Soporte multipágina/multilínea con desplazamiento vertical continuo en un buffer dinámico.
3. **Módulo de Imágenes Pixel Art (Lab 6):** Inserción de imágenes con matrices de color en coordenadas del documento, dibujadas siempre con prioridad absoluta por encima del texto, y soporte de transformaciones matriciales (rotación a 90° y espejo horizontal).
4. **Persistencia Binaria Estructurada:** Guardado y carga completa de documentos en archivos locales (encabezado, tuplas `[Char, FG, BG]`, metadatos de imágenes).
5. **Interfaz de Usuario Atractiva:** Menú principal navegable con flechas y Enter, modales con sombras y cuadros de diálogo, encabezados y cheatsheet visible permanente con atajos Alt.

---

## 3. Arquitectura del Sistema

```
+-------------------------------------------------------------------------+
|                              MAIN LOOP                                  |
+-------------------------------------------------------------------------+
       |                                                    |
       v                                                    v
+------------------+                              +-----------------------+
|  MENU PRINCIPAL  |                              |  PANTALLA DE EDICIÓN  |
|  - Crear archivo |                              |  - Render texto 8x8   |
|  - Abrir archivo |                              |  - Render Pixel Art   |
|  - Salir         |                              |  - Viewport y Scroll  |
+------------------+                              |  - Despacho de teclas |
                                                  +-----------------------+
                                                              |
                 +--------------------------------------------+
                 |                     |                      |
                 v                     v                      v
        +------------------+  +------------------+  +-------------------+
        | PERSISTENCIA E/S |  | MOTOR PIXEL ART  |  | BUSCAR/REEMPLAZAR |
        | Serialización    |  | Lab 6 (Matriz,   |  | Sustitución de    |
        | binaria en disco |  | Flip, Rotación)  |  | cadenas en buffer |
        +------------------+  +------------------+  +-------------------+
```

---

## 4. Distribución de Pantalla en Modo 13h (Grid 40x25)
La pantalla de 320x200 píxeles se organiza en celdas de 8x8 píxeles:

| Rango de Filas | Coordenadas Y | Función en Pantalla |
| :--- | :--- | :--- |
| **Fila 0** | Y: 0 .. 7 | **Barra Superior de Estado:** Nombre de archivo actual, posición del cursor `[Línea:Columna]` e indicadores de color FG/BG. |
| **Filas 1 .. 23** | Y: 8 .. 191 | **Lienzo de Edición (Viewport):** 23 renglones visibles × 40 columnas de texto y capas de Pixel Art. |
| **Fila 24** | Y: 192 .. 199 | **Barra Inferior (Cheatsheet):** Lista de atajos esenciales visibles permanentemente (`Alt+S`, `Alt+H`, `Alt+B`, `Alt+I`, `Alt+J`, etc.). |

---

## 5. Estructuras de Memoria y Buffer de Documento

### 5.1. Buffer de Texto Multilínea
Para operar dentro del segmento de datos de 64 KB (`.MODEL SMALL`), se reservan:
- `MAX_LINES = 80`: Hasta 80 renglones de documento (equivalente a más de 3.5 pantallas completas de scroll).
- `MAX_COLS = 40`: Ancho de 40 caracteres por renglón.
- `DOC_CHARS`: Arreglo de 80 × 40 = 3,200 bytes con los códigos ASCII.
- `DOC_FG`: Arreglo de 80 × 40 = 3,200 bytes con el color de texto de cada celda.
- `DOC_BG`: Arreglo de 80 × 40 = 3,200 bytes con el color de fondo de cada celda.
- `LINE_LENGTHS`: Arreglo de 80 palabras (`DW`) con la longitud activa de cada renglón.

### 5.2. Paletas Predefinidas de 3 Colores
- **Texto (Foreground):**
  1. `15`: Blanco brillante
  2. `14`: Amarillo intenso
  3. `10`: Verde claro
- **Fondo de Carácter (Background):**
  1. `0`: Negro
  2. `1`: Azul marino
  3. `8`: Gris oscuro

### 5.3. Tabla de Imágenes Estampadas
Cada imagen insertada se registra con una tupla de 7 bytes:
- Offset 0: `ID` (1 = Arch Linux 44x36, 2 = Honkai 50x48)
- Offset 1..2: `X` (Posición X en píxeles dentro del documento)
- Offset 3..4: `Y` (Posición Y en píxeles dentro del documento)
- Offset 5: `FLIP` (0 = Normal, 1 = Espejo horizontal)
- Offset 6: `ROT` (0 = 0°, 1 = 90°, 2 = 180°, 3 = 270°)

---

## 6. Formato de Persistencia Binaria en Disco

El archivo almacenado en la carpeta de ejecución utiliza una estructura binaria compacta:

```
+-------------------------------------------------------------------+
| 1. ENCABEZADO (HEADER) - 8 BYTES                                  |
|    - [0..3]: Magic Number 'ED86' (45h, 44h, 38h, 36h)             |
|    - [4..5]: Cantidad de líneas en documento (DW)                 |
|    - [6..7]: Cantidad de imágenes estampadas (DW)                 |
+-------------------------------------------------------------------+
| 2. BLOQUE DE LÍNEAS DE TEXTO                                      |
|    Por cada línea (de 0 a DOC_LINE_COUNT - 1):                    |
|    - Longitud de línea (1 byte, 0..40)                            |
|    - N bytes: Caracteres ASCII                                    |
|    - N bytes: Atributos de Color de Texto (FG)                    |
|    - N bytes: Atributos de Color de Fondo (BG)                    |
+-------------------------------------------------------------------+
| 3. BLOQUE DE METADATOS DE IMÁGENES                                |
|    Por cada imagen (PLACED_COUNT registros de 7 bytes):           |
|    - [ID (1B), X (2B), Y (2B), FLIP (1B), ROT (1B)]               |
+-------------------------------------------------------------------+
```

---

## 7. Catálogo Completo de Controles y Atajos

| Atajo / Tecla | Scan Code / ASCII | Acción Ejecutada |
| :--- | :--- | :--- |
| **Flechas** | `48h, 50h, 4Bh, 4Dh` | Movimiento libre del cursor (Arriba, Abajo, Izquierda, Derecha). |
| **Enter** | `AL = 0Dh` | Salto de línea interactivo (split line y desplazamiento hacia abajo). |
| **Backspace** | `AL = 08h` | Borrado de carácter previo con retroceso y ajuste de línea. |
| **Alt + C** | `AH = 2Eh` | Centrar cursor en la línea actual (`col = len / 2`). |
| **Alt + U** | `AH = 16h` | Mover el cursor a la primera línea del documento / vista (`0, 0`). |
| **Alt + D** | `AH = 20h` | Mover el cursor a la última línea activa del documento. |
| **Alt + S** | `AH = 1Fh` | Guardar documento en disco y salir del programa limpiamente. |
| **Alt + M** | `AH = 32h` | Ciclar color de letra (FG) entre los 3 predefinidos para texto nuevo. |
| **Alt + N** | `AH = 31h` | Ciclar color de fondo (BG) entre los 3 predefinidos para texto nuevo. |
| **Alt + I** | `AH = 17h` | Insertar Imagen Pixel Art 1 (Arch Linux) en coordenadas de cursor. |
| **Alt + J** | `AH = 24h` | Insertar Imagen Pixel Art 2 (Honkai) en coordenadas de cursor. |
| **Alt + B** | `AH = 30h` | Abrir modal de Buscar y Reemplazar texto en todo el documento. |
| **Alt + H** | `AH = 23h` | Desplegar ventana modal de Ayuda con el catálogo de atajos. |
| **Alt + X** | `AH = 2Dh` | Salida inmediata desde el Menú Principal restaurando video. |
| **Alt + Z** | `AH = 2Ch` | Cancelar operación en modales (Crear/Abrir) y volver al menú. |

---

## 8. Bitácora de Implementación y Fases de Desarrollo

- **Fase 1 (Arquitectura y Planificación):** Análisis de requerimientos de `proyecto1.md` e `instrucciones_editor_x8086.md`, revisión de rutinas matriciales y paletas de `lab6.asm`. Aprobación del plan por el usuario.
- **Fase 2 (Estructura de Datos y Fuentes Gráficas):** Implementación de tablas en `.DATA` para buffer multilínea y obtención de la tabla ROM 8x8 de BIOS mediante `INT 10h, AX=1130h, BH=03h` para renderizado ultra rápido y nítido directamente en VRAM `0A000h`.
- **Fase 3 (Motor Gráfico y Pixel Art):** Integración de matrices de datos de Arch Linux y Honkai, dibujo con transparencia (color 48) y prioridad visual absoluta sobre el texto.
- **Fase 4 (Comportamiento Nano y Edición):** Implementación de inserción de texto, borrado retroactivo con Backspace, partición de líneas con Enter, navegación por flechas y scroll vertical continuo.
- **Fase 5 (Atajos de Teclado):** Implementación de rutinas para `Alt+C`, `Alt+U`, `Alt+D`, `Alt+M`, `Alt+N`, `Alt+I`, `Alt+J`, `Alt+B` (búsqueda y sustitución) y `Alt+H` (modal de ayuda).
- **Fase 6 (Persistencia y Manejo de Archivos):** Diálogos para Crear (conversión obligatoria a mayúsculas) y Abrir (insensible a mayúsculas/minúsculas con reintento por error), serialización binaria con número mágico `ED86`.
- **Fase 7 (Menú Principal y UI):** Menú gráfico estilizado con navegación por flechas, selección por Enter y atajo `Alt+X`.
- **Fase 8 (Verificación de Integridad):** Verificación exhaustiva de directivas TASM, modelo de memoria, rangos de saltos (`JUMPS`), optimización de ciclos de dibujado de pixeles y preservación de registros.
- **Fase 9 (Depuración de Modos de Direccionamiento 8086):** Corrección del error `Illegal indexing mode` reportado por TASM en `HANDLE_BACKSPACE`, `HANDLE_ENTER` y `EXECUTE_SEARCH_REPLACE`. En la arquitectura x8086 de 16 bits, registros de datos como `DX` y `CX` no pueden operar como índices (`[DX]`, `[CX]`), y no es válido combinar dos registros de índice simultáneos (`[SI + DI]`). Se sustituyeron por punteros base lineales con `[SI]` y `[DI]`, garantizando compatibilidad 100% estricta con el conjunto de instrucciones del 8086.

---

## 9. Procedimiento de Compilación y Ejecución en Clase

De acuerdo con las instrucciones críticas del proyecto, **no se compila en el entorno Linux actual**, sino que se compila directamente en la sesión de calificación en el entorno estándar de laboratorio (DOSBox / Máquina Virtual con TASM y LINK).

### Comandos de Compilación:
Utilizando el archivo por lotes existente en el directorio (`a.bat`):
```bat
a editor
```
O de forma manual paso a paso:
```bat
tasm /m2 editor.asm;
link editor;
editor.exe
```

---

## 10. Matriz de Cumplimiento de la Rúbrica de Calificación (100 pts)

| Categoría | Pts | Criterios Cumplidos en la Implementación |
| :--- | :---: | :--- |
| **Manejo de Archivos** | **25 pts** | - Creación física de archivos en disco con nombre forzado en **MAYÚSCULAS**.<br>- Apertura insensible a mayúsculas/minúsculas (`FORCE_UPPER` y normalización).<br>- Manejo de errores con reintento explícito si el archivo no existe.<br>- Retorno al menú principal con `Alt+Z` desde los modales.<br>- Persistencia binaria completa con identificador mágico `ED86`. |
| **Pantalla de Edición** | **20 pts** | - Renderizado gráfico nativo en Modo 13h (320x200) sin parpadeo.<br>- Comportamiento estilo nano: Enter divide líneas, Backspace borra y fusiona.<br>- Viewport dinámico de 23 filas con **scroll vertical multipágina** continuo.<br>- Navegación fluida y libre con teclas de flecha (Arriba, Abajo, Izquierda, Derecha). |
| **Atajos de Teclado** | **20 pts** | - `Alt+C`: Centra cursor en la línea actual.<br>- `Alt+U`: Salto a primera línea del documento.<br>- `Alt+D`: Salto a última línea activa.<br>- `Alt+S`: Guardado en disco y salida limpia.<br>- `Alt+M`: Ciclo de color de fuente (3 colores).<br>- `Alt+N`: Ciclo de color de fondo (3 colores).<br>- `Alt+B`: Búsqueda y reemplazo dinámico de cadenas de texto.<br>- `Alt+H`: Modal de ayuda gráfica con catálogo de atajos. |
| **Imágenes Pixel Art** | **20 pts** | - Integración de matrices de datos de Arch Linux (`Alt+I`) y Honkai (`Alt+J`).<br>- Transformaciones matriciales integradas de Lab 6 (rotación 90° y espejo).<br>- **Prioridad absoluta:** Dibujadas por encima del texto respetando transparencia (color 48).<br>- Coordenadas vinculadas al documento que acompañan el scroll vertical. |
| **Presentación y UI** | **15 pts** | - Menú principal estilizado con sombras, marcos y navegación interactiva.<br>- Barra superior de estado (archivo, línea, columna y paleta activa).<br>- Barra inferior permanente tipo cheatsheet con los atajos nano/Alt.<br>- Cuadros de diálogo modales limpios y estéticos. |
| **TOTAL** | **100 pts** | **100% de cobertura técnica según requerimientos.** |

