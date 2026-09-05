Universidad Francisco Marroquín

Arquitectura y Diseño de Computadoras

Ing. Gustavo Sánchez

Proyecto 1:

Editor de texto

Objetivos:

El estudiante debe de demostrar la capacidad de aplicar el conocimiento sobre los siguientes temas:

●  Lenguaje de programación x8086
●  Manejo de cadenas
●  Colores y páginas
●  Manejo de archivos
●
●  Entradas de teclado

Imágenes

Descripción general:

Junto a sus parejas de laboratorio deben de diseñar y programar una aplicación en assembler x8086 que
emule  las  capacidades  básicas  de  un  editor  de  texto,  por  ejemplo,  Microsoft  Word.  Este  debe  de  ser
capaz de crear, editar y guardar archivos de textos que el estudiante debe de definir. Cada archivo debe
de  guardar  el  color de fondo deseado por el usuario, el texto ingresado, el color para cada carácter de
texto y las imágenes que el usuario ya haya ingresado.

Al iniciar el programa debe mostrar un menú al usuario el cual navegará utilizando las flechas del teclado
y podrá seleccionar una opción presionando Enter.

Entre las opciones debe de mostrar:

●  Crear un archivo nuevo
●  Abrir un archivo existente
●  Salir

También se puede salir presionando alt+x mientras esté en esta pantalla de menú.

Todas las pantallas del programa deben de ser atractivas para el usuario, incorporando colores, ascii art o
imágenes Pixel art.

Crear un archivo nuevo

Debe  de  solicitarle  al  usuario  el  nombre  de  un  archivo,  este  debe  de  guardarse  en  mayúsculas
únicamente. De no poder crear el archivo deberá indicarlo al usuario. Después de crear el archivo debe
de proceder a la pantalla de edición. Si el usuario presiona ALT+Z este deberá regresar al menú principal.
El  estudiante  debe  de  decidir  la  terminación  del  archivo  y  todos  los  archivos  deben  de  crearse  en  la
misma carpeta donde el programa se está ejecutando.

Abrir un archivo nuevo

Al  igual  que  en  el  inciso  anterior  se  le  debe  de solicitar el nombre del archivo al usuario. El programa
debe de ser capaz de abrirlo sin importar si el usuario ingresó el nombre en mayúsculas o minúsculas. De
no  poder  abrir  el  archivo  el  programa  debe  de  indicarle  al  usuario  que  hubo  un  error  y  pedirle  que
ingrese otro nombre. Si el usuario presiona ALT+Z este deberá regresar al menú principal. Puede asumir
que  todos  los  archivos  a  abrir  estarán  en  la  misma  carpeta  donde  el  programa  se  estará  ejecutando.
Después de abrir un archivo debe de proceder a la pantalla de edición.

Pantalla de edición

En  esta  pantalla  el  usuario  es  libre  de  escribir  lo  que  quiera  utilizando  caracteres  alfanuméricos  y los
siguientes  signos de puntuación “,”, “.”, y “:”. El usuario puede mover el cursor utilizando las flechas del
teclado y al empezar a escribir el texto debe mostrarse en pantalla.

Esta pantalla debe de soportar varios atajos con el teclado:

●  Alt+C: Centrar el cursor en la línea actual
●  Alt+U: Mover el cursor al primer renglón de la página
●  Alt+D: Mover el cursor al último renglón de la página
●  Alt+S: Guardar y salir del programa
●  Alt+M: Cambiar el color de letra para lo que se va a escribir, no cambia el texto ya escrito.

o  Para  esto  puede  tener  una  lista  predefinida  de  3  colores  y  solo  alternar entre estos 3

cada vez que el usuario presiona el atajo.

●  Alt+N: Cambiar el color de fondo para lo que se va a escribir, no cambia el texto ya escrito.

o  Para  esto  puede  tener  una  lista  predefinida  de  3  colores  y  solo  alternar entre estos 3

cada vez que el usuario presiona el atajo.

●  Alt+I: Agregar imagen 1, usted debe de tener 2 opciones de imágenes en píxel art que el usuario
puede utilizar cuantas veces quiera en su archivo. Al seleccionar este atajo se debe de agregar la

la imagen 1 a la pantalla, en donde esté el cursor del usuario. Esta imagen debe de estar siempre
por encima del texto.

●  Alt+J:  Al  seleccionar  este  atajo  se  debe  de  agregar  la  imagen 2 a la pantalla, en donde este el

cursor del usuario. Esta imagen debe de estar siempre por encima del texto.

●  Alt+B: Buscar y reemplazar, debe de solicitarle al usuario dos palabras de este largo, y realizar el

reemplazo.

●  Alt+H: Mostrarle al usuario los atajos que tiene disponible y una breve descripción de cada uno.

Rúbrica:

Manejo de archivos: 25

Pantalla de edición: 20

Atajos: 20

Imágenes: 20

Presentación: 15

Puntos  Extras:  Pueden  haber  puntos  extras  por  funcionalidad  extra,  consultar  con  el  catedrático  para
confirmar que algo adicional va a tener puntos extras.

