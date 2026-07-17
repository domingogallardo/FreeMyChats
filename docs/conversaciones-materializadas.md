# Conversaciones materializadas en Free My Chats

## Estado

Este documento describe la implementación actual. El diseño de importación de
paquetes `.fmcchat` está documentado por separado y todavía no está implementado.

## Dos representaciones posibles

La ubicación física depende del número de aportaciones.

Una conversación con una sola exportación se abre directamente desde ella:

```text
Exports/<copia>/Chats/<chatId>/
├── archive.json
├── chat.json
└── Media/
```

Una conversación con varias exportaciones dispone además de una representación
combinada:

```text
MergedChats/<conversationId>/
├── archive.json
├── chat.json
└── Media/
```

`Exports` conserva cada chat tal como fue extraído de una versión concreta de la
copia de WhatsApp. Cuando es la única aportación, su misma carpeta es la
representación que muestra el catálogo del panel derecho.

`MergedChats` solo contiene representaciones materializadas de conversaciones
con varias aportaciones. No contiene referencias para que la interfaz alterne
entre distintos `chat.json`: guarda un nuevo `chat.json` completo y una carpeta
`Media` directamente utilizable.

`archive.json` registra la identidad de la conversación, sus aportaciones y las
fechas de creación y actualización. La identidad se obtiene a partir del tipo de
chat y de su JID normalizado, no del nombre visible.

## Construcción de la cronología

Si solo existe una aportación, no se construye otra cronología: la vista utiliza
directamente el documento exportado.

Cuando existen varias aportaciones, Free My Chats:

1. Reúne todos sus mensajes.
2. Calcula una huella SHA-256 para cada mensaje.
3. Ordena los mensajes por fecha y, en caso de empate, por aportación y posición
   original.
4. Conserva un único representante por huella.
5. Asigna identificadores correlativos a la cronología resultante.
6. Reescribe `replyTo` para que las respuestas apunten a los nuevos
   identificadores.
7. Escribe el documento combinado en `MergedChats/<conversationId>/chat.json`.

La huella de un mensaje incluye:

- fecha con precisión de milisegundos;
- dirección (`isFromMe`), tipo y autor normalizado;
- texto y pie de foto;
- hash del archivo multimedia, cuando existe;
- duración y coordenadas, cuando existen.

El identificador original del mensaje no forma parte de la huella, porque puede
cambiar entre dos exportaciones de la misma conversación. Dos mensajes con la
misma huella se consideran la misma aparición y se guardan una sola vez en la
cronología materializada.

Los contactos se agrupan por teléfono. Los datos generales y la fotografía del
chat se toman de la aportación más reciente.

## Lectura y reparación

La vista de conversación recibe siempre un solo `chat.json` y una sola carpeta
`Media`. Si existe una aportación, ambos pertenecen a la exportación; si existen
varias, pertenecen a la representación combinada. La búsqueda, la paginación, la
navegación de respuestas y la posición de lectura no necesitan conocer esa
diferencia.

La representación combinada se construye primero en una carpeta temporal y se
instala mediante movimientos atómicos. Si falta un archivo o el documento deja de
ser válido, la aplicación puede reconstruirla a partir de las aportaciones
conservadas en `Exports`.

## Ciclo de incorporación y eliminación

La estructura física cambia automáticamente sin introducir ninguna distinción
adicional en la interfaz:

1. La primera exportación de un chat recibe su `archive.json` dentro de su propia
   carpeta. No se crea nada en `MergedChats`.
2. Al incorporar una segunda exportación de la misma conversación, se construye
   la cronología combinada y se instala en `MergedChats/<conversationId>/`.
   Los `archive.json` individuales dejan de ser necesarios y se retiran de las
   exportaciones.
3. Al actualizar una exportación existente, la aplicación conserva previamente
   la identidad y las aportaciones registradas, sustituye la exportación y vuelve
   a instalar la representación que corresponda.
4. Si se elimina una aportación y todavía quedan varias, la conversación
   combinada se reconstruye con ellas.
5. Si al eliminar una aportación queda una sola, desaparece la carpeta combinada
   y su `archive.json` pasa a la exportación restante.
6. Si se elimina la última aportación, la conversación desaparece del catálogo.

Las promociones, reconstrucciones y degradaciones se preparan en carpetas
temporales. Un fallo recuperable durante la operación restaura la representación
anterior para no dejar el catálogo a medio actualizar.

## Multimedia

Una conversación individual utiliza directamente la carpeta `Media` de su
exportación. En una conversación combinada, cada archivo multimedia referenciado
por la cronología se materializa dentro de `MergedChats`. Cuando varias
aportaciones contienen exactamente el mismo archivo, su SHA-256 permite
almacenarlo una sola vez en esa carpeta. Los archivos distintos que tengan el
mismo nombre reciben nombres separados y deterministas.

La vista trata su carpeta `Media` como parte de la conversación materializada y no
resuelve los adjuntos contra las carpetas de las aportaciones originales.

## Qué datos se materializan de nuevo

- Una conversación con una sola aportación no duplica sus mensajes ni su
  multimedia en `MergedChats`.
- En una conversación combinada, los mensajes permanecen en sus exportaciones y
  también forman parte del nuevo documento unificado.
- Un mensaje repetido en varias aportaciones se conserva una sola vez en el
  `chat.json` combinado.
- La multimedia de una conversación combinada está presente en `Exports` y en
  `MergedChats`; dentro de esta última, los archivos idénticos de varias
  aportaciones se materializan una sola vez.
- La eliminación manual de `Exports` impide reconstruir la conversación, aunque
  la materialización instalada todavía pudiera abrirse. Las aportaciones deben
  eliminarse desde la aplicación.
