# Conversaciones materializadas en Free My Chats

## Estado

Este documento describe la implementación de Free My Chats 2.1.1 con
SwiftWABackupAPI 6.0.1. La aplicación crea, valida, extrae e importa paquetes
`.fmcchat`; registra cada aportación en `ImportedChats`, instala la Vista
unificada con rollback y permite consultarla o retirarla desde la interfaz.

## Dos representaciones posibles

La ubicación física depende de los tipos y del número de aportaciones.

Una conversación con una sola copia guardada local y sin chats importados se
abre directamente desde ella:

```text
StoredChats/<copia>/Chats/<chatId>/
├── archive.json
├── chat.json
└── Media/
```

Una conversación con varias copias guardadas o con algún chat importado dispone
de una representación combinada:

```text
MergedChats/<conversationId>/
├── archive.json
├── chat.json
└── Media/
```

`StoredChats` conserva cada chat tal como fue extraído de una versión concreta de la
copia de WhatsApp. Cuando es la única aportación, su misma carpeta es la
representación que muestra el catálogo del panel derecho.

`ImportedChats/<conversationId>/<importId>/` conserva el `manifest.json`,
`chat.json` y `Media` extraídos y validados de cada paquete recibido. La
aportación permanece separada para poder reconstruir la conversación o retirarla.

`MergedChats` contiene representaciones materializadas de conversaciones con
varias copias locales o con al menos un chat importado. No contiene referencias
para que la interfaz alterne entre distintos `chat.json`: guarda un nuevo
`chat.json` completo y una carpeta `Media` directamente utilizable.

`archive.json` registra la identidad de la conversación, sus aportaciones y las
fechas de creación y actualización. La identidad se obtiene a partir del tipo de
chat y de su JID normalizado, no del nombre visible.

## Construcción de la cronología

Si solo existe una copia local y no hay chats importados, no se construye otra
cronología: la vista utiliza directamente el documento guardado.

Cuando existen varias copias locales o algún chat importado, Free My Chats
construye un `ConversationSource` por aportación y delega en
`ConversationCompositionEngine`:

1. Reúne todos sus mensajes.
2. Calcula una huella SHA-256 para cada mensaje.
3. Ordena los mensajes por fecha y, en caso de empate, por aportación y posición
   original.
4. Conserva un único representante por huella.
5. Asigna identificadores correlativos a la cronología resultante.
6. Reescribe `replyTo` para que las respuestas apunten a los nuevos
   identificadores.
7. Materializa un staging autocontenido con `chat.json` y `Media`.

Free My Chats elige como target la copia local más reciente. Las copias locales
se declaran de la misma perspectiva; si existen importaciones, el motor usa el
perfil conservador entre perspectivas. La aplicación añade `archive.json` al
staging y coordina su instalación o rollback en `MergedChats/<conversationId>`.
La API no conoce la estructura de la biblioteca.

La huella de un mensaje incluye:

- fecha con precisión de milisegundos;
- rol relativo de autor (`sourceUser` para `isFromMe`) y participante
  normalizado;
- texto y pie de foto;
- hash del archivo multimedia, cuando existe;
- duración y coordenadas, cuando existen.

El identificador original del mensaje no forma parte de la huella, porque puede
cambiar entre dos copias guardadas de la misma conversación. Dos mensajes con la
misma huella se consideran la misma aparición y se guardan una sola vez en la
cronología materializada.

Los contactos se agrupan por identidad telefónica normalizada y prefieren la
fuente target. Los datos generales y la fotografía del chat se toman de esa
aportación más reciente.

## Lectura y reparación

La vista de conversación recibe siempre un solo `chat.json` y una sola carpeta
`Media`. Con una única copia local, ambos pertenecen a esa copia; con varias
copias o alguna importación, pertenecen a la representación combinada. La
búsqueda, la paginación y la navegación de respuestas no necesitan conocer esa
diferencia.

La representación combinada se construye primero en una carpeta temporal y se
instala mediante movimientos atómicos. Si falta un archivo o el documento deja de
ser válido, la aplicación la reconstruye a partir de las aportaciones conservadas
en `StoredChats` e `ImportedChats`.

## Ciclo de incorporación y eliminación

La estructura física cambia automáticamente sin introducir ninguna distinción
adicional en la interfaz:

1. La primera copia guardada de un chat recibe su `archive.json` dentro de su propia
   carpeta. No se crea nada en `MergedChats`.
2. Al incorporar una segunda copia guardada de la misma conversación, se construye
   la cronología combinada y se instala en `MergedChats/<conversationId>/`.
   Los `archive.json` individuales dejan de ser necesarios y se retiran de las
   copias guardadas.
3. Al actualizar una copia guardada existente, la aplicación conserva previamente
   la identidad y las aportaciones registradas, sustituye la copia guardada y vuelve
   a instalar la representación que corresponda.
4. Si se elimina una aportación y todavía quedan varias, la conversación
   combinada se reconstruye con ellas.
5. Si al eliminar una aportación queda una sola, desaparece la carpeta combinada
   y su `archive.json` pasa a la copia guardada restante.
6. Si se elimina la última aportación, la conversación desaparece del catálogo.
7. Al importar un `.fmcchat`, la aplicación exige una única conversación local
   compatible, conserva el paquete validado en `ImportedChats` y materializa el
   resultado en `MergedChats`.
8. Al retirar un chat importado, reconstruye la conversación con las fuentes
   restantes y elimina la carpeta de esa importación solo después de instalar el
   resultado.
9. La última copia local no se puede borrar mientras la conversación conserve
   aportaciones importadas, porque la composición necesita una perspectiva local
   target.

Las promociones, reconstrucciones y degradaciones se preparan en carpetas
temporales. Un fallo recuperable durante la operación restaura la representación
anterior para no dejar el catálogo a medio actualizar.

## Multimedia

Una conversación con una única copia local utiliza directamente su carpeta
`Media`. En una conversación combinada, cada archivo multimedia referenciado por
la cronología se materializa dentro de `MergedChats`. Cuando varias aportaciones
contienen exactamente el mismo archivo, su SHA-256 permite almacenarlo una sola
vez en esa carpeta. Los archivos distintos que tengan el mismo nombre reciben
nombres separados y deterministas.

La vista trata su carpeta `Media` como parte de la conversación materializada y no
resuelve los adjuntos contra las carpetas de las aportaciones originales.

## Qué datos se materializan de nuevo

- Una conversación con una sola aportación no duplica sus mensajes ni su
  multimedia en `MergedChats`.
- En una conversación combinada, los mensajes permanecen en sus copias guardadas y
  también forman parte del nuevo documento unificado.
- Un mensaje repetido en varias aportaciones se conserva una sola vez en el
  `chat.json` combinado.
- La multimedia de una conversación combinada está presente en `StoredChats` y en
  `MergedChats`; dentro de esta última, los archivos idénticos de varias
  aportaciones se materializan una sola vez.
- La eliminación manual de `StoredChats` o `ImportedChats` impide reconstruir la
  conversación, aunque la materialización instalada pueda seguir abriéndose. Las
  aportaciones se eliminan desde la aplicación.
