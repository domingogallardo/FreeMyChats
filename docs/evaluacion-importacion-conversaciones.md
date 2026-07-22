# Evaluación para exportar e importar conversaciones entre propietarios

## Estado y alcance

Este documento contrasta el diseño inicial de
[fusión de conversaciones exportadas](fusion-conversaciones-exportadas.md) con la
implementación actual de Free My Chats 1.3.10 y SwiftWABackupAPI 4.5.0.

La especificación posterior y vinculante para SwiftWABackupAPI está en
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).
En ella la perspectiva de cada fuente se infiere durante la composición o se
proporciona opcionalmente como parámetro; no se exige persistir una identidad
global del propietario.

La primera entrega, limitada a trasladar a la API la Vista unificada local actual,
está en
[Composición de Vistas unificadas locales](especificacion-swiftwabackupapi-fusion-local-inicial.md).

No es una implementación. Su objetivo es fijar qué se puede reutilizar, qué debe
cambiar y cómo debería ser el recorrido de exportación e importación antes de
modificar el código.

El MVP contemplado aquí permite incorporar un archivo creado por Free My Chats a
una conversación que ya existe en la biblioteca receptora. No importa ZIP o TXT
generados directamente por WhatsApp y no escribe en WhatsApp ni en una copia de
iPhone.

## Conclusión

La funcionalidad es viable y una parte importante de la Vista unificada actual es
reutilizable, sobre todo:

- el catálogo que representa una conversación una sola vez;
- la conservación de aportaciones independientes;
- la materialización de un único `chat.json` y una única carpeta `Media`;
- el remapeo de identificadores y respuestas;
- la deduplicación de multimedia por SHA-256;
- la reconstrucción al retirar una aportación;
- la instalación temporal con rollback y la reparación desde las fuentes.

Sin embargo, el motor actual no puede recibir sin cambios una exportación de otra
persona. Está diseñado para varias copias del mismo propietario y considera
`isFromMe` parte de la huella. El mismo mensaje de la mujer aparecerá como
`isFromMe == true` en su archivo y como `isFromMe == false` en la biblioteca del
marido. Con la huella actual se tratarían como mensajes diferentes.

La dificultad principal no es comprimir o copiar archivos, sino demostrar que dos
documentos son de la misma conversación, expresar los autores con identidades
absolutas y alinear con suficiente confianza los mensajes compartidos.

La recomendación es implementar primero un diagnóstico de solo lectura con datos
reales. No conviene empezar por la escritura definitiva ni por la interfaz final.

## Qué hace hoy la Vista unificada

La implementación vigente está repartida principalmente entre
`ConversationArchiveService`, `ConversationIdentityResolver`,
`ConversationArchiveRecord` y `FreeMyChatsStore`.

Cuando varias copias locales contienen el mismo chat:

1. La conversación se identifica por tipo y JID normalizado, con algunos alias
   LID a JID telefónico.
2. Cada exportación local queda en `Exports` y se registra mediante un
   `VersionChatID`.
3. Los mensajes se ordenan y deduplican mediante una huella exacta.
4. Se reasignan `id`, `chatId` y `replyTo`.
5. La multimedia se copia y deduplica por SHA-256.
6. El resultado se instala en `MergedChats` mediante una carpeta temporal.
7. Si se retira una aportación, la conversación se reconstruye con las restantes.

Esta base es valiosa, pero contiene tres supuestos que dejan de cumplirse al
cambiar de propietario:

- `ConversationContribution` siempre apunta a una versión local mediante
  `VersionChatID`.
- La identidad de una conversación individual solo contiene el JID del otro
  participante, no el conjunto de ambos participantes.
- La huella incluye `isFromMe` y exige coincidencia exacta del timestamp y del
  resto del contenido central; no hace alineación secuencial ni clasifica
  ambigüedades.

## Reutilización propuesta

### Reutilizable casi directamente

- El catálogo y la apertura de una única conversación materializada.
- `MergedChats/<conversationId>` como resultado derivado.
- El esquema de construir en una carpeta temporal, validar y sustituir al final.
- El materializador de multimedia, sus nombres deterministas y SHA-256.
- La reasignación de IDs locales y el mapa para `replyTo`.
- La actualización del catálogo y de la conversación abierta en el store.
- La reconstrucción y degradación al retirar aportaciones.
- Buena parte de los fixtures de pruebas de solapamiento, multimedia, rollback y
  reparación.

### Reutilizable después de generalizar

- `ConversationArchiveRecord`: debe registrar aportaciones importadas además de
  exportaciones locales.
- `ResolvedContribution`: debe poder abrir una fuente de `Exports` o de
  `Imports`.
- `buildDocument`: debe recibir el resultado de un alineador que ya haya
  normalizado perspectiva y autores.
- Los contadores de aportaciones y mensajes exclusivos deben incluir ambos tipos
  de fuente.
- El flujo de retirada debe distinguir entre borrar una exportación local y
  retirar una importación.
- La preservación de la posición de lectura debe usar un mapa entre el mensaje
  anterior y el nuevo resultado, no confiar solo en el `Int` materializado.

### No reutilizable como criterio de fusión entre propietarios

- La huella actual con `isFromMe`.
- La identidad individual basada únicamente en `contactJid`.
- La deduplicación como conjunto de hashes aislados. Los mensajes breves y
  repetidos necesitan contexto y orden.
- La elección implícita de un representante sin una política explícita para
  reacciones, ediciones, nombres y otros campos mutables.

## Estructura física recomendada

La propuesta inicial colocaba `Base` e `Imports` dentro de cada carpeta de chat.
Después de la implementación de las Vistas unificadas ya no es necesario hacer esa
reestructuración. `Exports` ya conserva las bases locales y `MergedChats` ya es el
resultado reconstruible.

Se recomienda añadir un tercer almacén de fuentes:

```text
Mi biblioteca Free My Chats/
├── library.json
├── Sources/
├── Exports/                         # Aportaciones de copias locales
├── Imports/                         # Aportaciones recibidas
│   └── <conversationId>/
│       └── <importId>/
│           ├── manifest.json
│           ├── chat.json
│           └── Media/
└── MergedChats/                     # Representación derivada
    └── <conversationId>/
        ├── archive.json
        ├── chat.json
        └── Media/
```

Reglas de materialización:

- Una aportación local y ninguna importación se abre directamente desde
  `Exports`, como ahora.
- Varias aportaciones locales se materializan en `MergedChats`, como ahora.
- Cualquier conversación con al menos una importación se materializa en
  `MergedChats`, aunque solo quede esa importación.
- `Imports` y `Exports` son fuentes; `MergedChats` se puede borrar y reconstruir.
- Retirar una importación borra únicamente su carpeta después de haber instalado
  correctamente el resultado reconstruido.
- Si se borra la última aportación local pero quedan importaciones, la conversación
  permanece en el catálogo.

Este diseño evita duplicar una `Base` y encaja con el sistema de reparación actual.

## Cambios de modelo necesarios

### Perspectiva de cada fuente

No se persistirá una identidad global obligatoria del propietario. Cada documento
mantiene su propia perspectiva: `isFromMe` significa “usuario de esta fuente”.
SwiftWABackupAPI inferirá durante la alineación si dos fuentes representan a la
misma persona o a personas distintas.

Si el contenido no aporta evidencia suficiente, Free My Chats podrá proporcionar
una identidad como pista opcional al construir la fuente o iniciar el análisis.
Una pista contradictoria se rechaza y su ausencia nunca autoriza una conjetura.
Las bibliotecas actuales continúan siendo legibles sin migración de propietario.

### Identidad de conversación

- Grupo: JID canónico del grupo más comprobación de `chatType == group`.
- Individual: equivalencia demostrada entre las perspectivas y sus interlocutores,
  apoyada por el solapamiento; `contactJid` por sí solo no basta.
- El nombre visible y el nombre del archivo nunca son identidad.

### Aportaciones importadas

Es menos invasivo conservar las aportaciones locales actuales y añadir al
manifiesto una colección separada:

```swift
struct ImportedConversationContribution: Codable, Identifiable {
    let id: UUID
    let importedAt: Date
    let packageCreatedAt: Date
    let perspectiveHint: CanonicalParticipantIdentity?
    let relativeDirectory: String
    let packageDigest: String
    let messageCount: Int
    let exclusiveMessageCount: Int
}
```

El resumen del catálogo expondrá por separado `localContributionCount` e
`importCount`; `contributionSources` seguirá conteniendo solo fuentes locales para
que el resaltado del panel izquierdo continúe funcionando.

### Versionado

Añadir importaciones cambia la semántica del manifiesto. Debe incrementarse el
schema de `ConversationArchiveRecord` y, preferiblemente, el de la biblioteca o
añadir una capacidad mínima requerida. Una versión antigua debe rechazar una
biblioteca nueva antes que ignorar `Imports` y reconstruir perdiendo datos.

### Identidad estable de mensaje

Para el MVP, el análisis puede devolver un mapa del mensaje materializado anterior
al nuevo. A medio plazo se debe incorporar un `ArchiveMessageID` estable. Así las
posiciones de lectura, respuestas y futuras importaciones no dependen del entero
correlativo que cambia al reconstruir.

## División de responsabilidades

### SwiftWABackupAPI

Debería ser propietario de lo que define la interoperabilidad:

- modelos y schema portable;
- inferencia de perspectivas y pistas opcionales de participantes;
- creación y validación segura del `.fmcchat`;
- normalización de autores independiente de `isFromMe`;
- huellas canónicas, ventanas de contexto, anclas y alineación;
- clasificación de coincidencias, nuevos, conflictos y regiones ambiguas;
- cálculo de confianza y mapas de mensajes/respuestas;
- transformación final de `MessageInfo` a la perspectiva receptora.

Esto también evita que Free My Chats tenga que reconstruir tipos de la API
mediante conversiones JSON para modificar campos inmutables.

### Free My Chats

Debe ser propietario de la biblioteca y de la experiencia:

- paneles de abrir y guardar;
- `Imports` y su integración con `ConversationArchiveRecord`;
- preparación, confirmación, progreso y cancelación;
- instalación y rollback de la conversación materializada;
- actualización del catálogo, selección y posición de lectura;
- historial y retirada de importaciones.

La materialización de archivos puede seguir reutilizando el servicio actual,
alimentado por un resultado de fusión producido por la API.

### Inventario probable de cambios

En SwiftWABackupAPI harán falta nuevos modelos portables, un codec seguro para el
paquete, el resolvedor de identidad absoluta, el alineador y sus pruebas. También
habrá que resolver la relación entre perspectivas y transformar el plan aprobado
respecto a la fuente target.

En Free My Chats, el impacto principal será:

- `LibraryModels.swift`: ruta `Imports`, schema nuevo, aportación importada,
  contadores y nuevas clases de operación;
- `ConversationArchiveService.swift`: resolver ambos tipos de fuente,
  materializar con el plan de la API, instalar y retirar importaciones;
- `FreeMyChatsStore.swift`: estado de análisis, confirmación, progreso, aplicación,
  historial y refresco de selección;
- `ConversationView.swift`: menú de acciones y acceso al historial;
- vistas nuevas y pequeñas para la previsualización y la lista de importaciones;
- pruebas de modelos, servicios y compatibilidad de biblioteca.

Como Free My Chats fija una versión exacta de SwiftWABackupAPI en `Package.swift`,
el trabajo deberá completarse y versionarse primero en ese paquete; después se
actualizará la dependencia y se integrará la interfaz. No deben editarse como
solución permanente los archivos del checkout de `.build`.

## Formato `.fmcchat`

El archivo será autocontenido y tratado siempre como entrada no confiable:

```text
Conversacion.fmcchat
├── manifest.json
├── chat.json
└── Media/
```

El manifiesto debe incluir al menos:

- versión del schema y versión del generador;
- identificador aleatorio del paquete;
- fecha de creación;
- descriptor de la conversación desde la perspectiva de la fuente;
- número de mensajes;
- tamaño, SHA-256 y nombre seguro de cada archivo;
- digest del documento o del contenido lógico del paquete.

Conviene que `chat.json` portable sea un contrato separado de
`ExportedChatDocument` v1. De esa manera el formato interno vigente continúa
leyéndose sin una migración masiva y el documento portable puede representar
roles de autor relativos a la fuente e IDs de archivo explícitamente.

La creación incluye la conversación visible materializada, pero no el historial
interno de sus fuentes. Si una conversación ya incorpora datos recibidos, estos se
pueden volver a compartir como parte del resultado; en el receptor constituyen una
única aportación atribuida a quien creó el nuevo paquete.

Antes de extraer se deben limitar número de entradas, tamaño declarado y real,
ratio de compresión y tamaño individual. Se rechazan rutas absolutas, `..`, enlaces
simbólicos, duplicados de nombre, referencias ausentes y hashes incorrectos.

## Proceso de exportación para compartir

1. El usuario abre una conversación del catálogo y elige
   `Crear archivo para compartir…` en un menú de acciones del encabezado.
2. La aplicación comprueba que la conversación es válida y dispone de identidad
   portable suficiente.
3. Se abre el panel de guardado con un nombre legible y extensión `.fmcchat`.
4. En segundo plano se crea una carpeta temporal, se genera el documento portable,
   se copian solo los medios referenciados y se calculan hashes y tamaños.
5. Se valida el conjunto completo antes de comprimirlo.
6. El paquete se escribe en un archivo temporal situado junto al destino y se
   mueve al nombre definitivo al terminar.
7. Se informa de mensajes, archivos y tamaño; se ofrecen `Mostrar en Finder` y
   `Aceptar`.

Cancelar o fallar no modifica la biblioteca y elimina los temporales propios.

## Proceso de importación

1. El usuario abre la conversación receptora y elige
   `Añadir mensajes de otra exportación…`.
2. Selecciona o arrastra un `.fmcchat`.
3. La aplicación hace una validación estructural y de seguridad sin escribir en la
   conversación: schema, límites, rutas, hashes y referencias.
4. Comprueba que la identidad portable corresponde a la conversación receptora.
5. Infiere la relación entre perspectivas a partir del solapamiento y las
   identidades disponibles; si no basta, usa una pista opcional proporcionada por
   el llamante. Después recalcula `isFromMe` respecto de la fuente local target.
6. Calcula huellas fuertes y débiles, ventanas contextuales y la cadena ordenada de
   anclas. Analiza el solapamiento y clasifica cada diferencia.
7. Muestra una hoja de previsualización con:

   - conversación e identidad de quien compartió el archivo;
   - mensajes coincidentes, nuevos, ambiguos y conflictivos;
   - nuevos archivos y bytes adicionales;
   - tramo temporal cubierto y nivel de confianza;
   - causa concreta si no es seguro continuar.

8. Solo con confianza alta, identidad demostrada y cero conflictos se habilita
   `Añadir mensajes`.
9. Al confirmar, se copia primero el paquete validado a un `Imports` temporal, se
   construye una nueva materialización y se valida.
10. Se instalan de forma coordinada la fuente importada, `archive.json` y
    `MergedChats`. Si cualquier paso falla, se restaura el estado anterior.
11. Se refrescan catálogo y conversación abierta. La posición de lectura se
    traduce mediante el mapa de mensajes; si no es posible, se usa el mensaje
    temporalmente más cercano.
12. El resultado indica cuántos mensajes y archivos se han incorporado realmente.

El archivo recibido nunca se importa automáticamente solo porque el nombre del
chat coincida.

## Historial y retirada

El menú de la conversación incluirá `Importaciones de esta conversación…`. Una
hoja mostrará fecha de importación, productor del paquete, fecha del paquete,
mensajes totales y mensajes actualmente exclusivos.

Al retirar una importación:

1. se calcula cuántos mensajes y bytes dejarían de estar disponibles;
2. se pide confirmación con esas cifras;
3. se reconstruye la conversación sin la aportación en una ubicación temporal;
4. se instala el resultado;
5. solo entonces se elimina la carpeta de la importación retirada.

Si otra fuente contiene el mismo mensaje o medio, no desaparece del resultado.

## Interfaz propuesta

Las acciones principales deben estar en un menú `…` del encabezado de la
conversación, junto a búsqueda y Finder:

- `Crear archivo para compartir…`
- `Añadir mensajes de otra exportación…`
- `Importaciones de esta conversación…` cuando existan

También pueden exponerse en un menú de aplicación contextual cuando haya una
conversación seleccionada. El arrastre de `.fmcchat` es un acceso directo
posterior, no una ruta distinta de validación.

El análisis y la confirmación encajan mejor en una hoja que en una alerta: hay
varias cifras, estados, progreso y posibles diagnósticos. Las operaciones largas
deben mostrar fases comprensibles y permitir cancelar antes de la instalación.

## Plan de implementación recomendado

### Fase 0 — diagnóstico real, sin escrituras

- Preparar dos exportaciones del mismo grupo desde dos propietarios.
- Preparar dos perspectivas de una conversación individual.
- Crear en SwiftWABackupAPI un analizador de línea de comandos o tests que
  produzca autores canónicos, anclas, cobertura, diferencias de timestamps,
  ambigüedades y conflictos.
- Medir la calidad real antes de fijar tolerancias y umbrales.

Entregable: informe reproducible de `ConversationMergePlan`; ninguna biblioteca se
modifica.

### Fase 1 — contrato e identidad portable

- Modelos portables y versionados.
- Roles de autor relativos e inferencia de perspectiva.
- Conversación individual como conjunto de dos identidades.
- Escritura y lectura segura de `.fmcchat`.
- Fixtures de paquetes válidos y maliciosos.

Entregable: crear y validar paquetes, todavía sin incorporarlos.

### Fase 2 — alineación y política de contenido

- Representación canónica independiente de perspectiva.
- Anclas únicas, ventanas, expansión entre anclas y confianza.
- Política explícita para timestamps, reacciones y metadatos mutables.
- Mapas de IDs y respuestas.

Entregable: previsualización exacta y determinista de una importación.

### Fase 3 — persistencia reversible

- `Imports` y schema nuevo de la biblioteca.
- Generalización de aportaciones resueltas.
- Materialización atómica y rollback.
- Retirada, reparación y actualización de una exportación local sin perder
  importaciones.
- Traducción de la posición de lectura.

Entregable: operaciones completas mediante servicios y tests, aún sin pulir UI.

### Fase 4 — experiencia macOS

- Menú de acciones, paneles, hoja de análisis y progreso.
- Resultado, Finder, historial y retirada.
- Arrastre opcional del paquete.
- Accesibilidad, cancelación y mensajes de error accionables.

### Fase 5 — endurecimiento

- Pruebas de gran volumen, memoria y cancelación.
- Paquetes hostiles y límites de descompresión.
- Compatibilidad entre versiones y rechazo seguro por aplicaciones antiguas.
- Calibración final de confianza con conversaciones reales variadas.

## Pruebas críticas adicionales a las existentes

- El mismo mensaje cambia de `isFromMe` entre dos propietarios y se deduplica.
- Los mensajes de ambos propietarios quedan orientados correctamente en la vista
  receptora.
- Grupo con autores LID/teléfono distintos entre dispositivos.
- Conversación individual identificada desde las dos perspectivas.
- Mensajes repetidos (`Sí`, emojis) no producen anclas falsas.
- Diferencias pequeñas de timestamp no crean duplicados ni coincidencias falsas.
- Importación idéntica repetida y paquete regenerado con el mismo contenido.
- Respuesta cuyo original solo existe en la importación.
- Nueva exportación local después de importar no elimina `Imports`.
- Eliminar la última fuente local conserva una conversación respaldada por
  importaciones.
- Retirar una importación mantiene mensajes y medios compartidos por otra fuente.
- Fallo o cancelación en cada fase deja bit a bit intacta la conversación previa.
- Una versión antigua de la aplicación rechaza de forma segura el schema nuevo.

## Decisiones que conviene fijar antes de la Fase 1

1. El MVP importa únicamente sobre una conversación local existente. Se recomienda
   mantener este límite; crear una conversación solo desde un paquete puede venir
   después.
2. Ante confianza media o conflicto, el MVP informa y no permite forzar la unión.
   No se recomienda una confirmación manual de identidad que también autorice una
   alineación dudosa.
3. Las pistas de perspectiva son opcionales; se proporcionan como parámetro solo
   cuando la inferencia no es suficiente y siempre se validan contra el contenido.
4. Debe decidirse el contenedor ZIP concreto y sus límites antes de publicar el
   formato, porque forma parte de la superficie de seguridad y compatibilidad.
5. Debe decidirse si el número de teléfono completo se muestra en la interfaz o se
   enmascara; el paquete necesariamente contiene identidad técnica suficiente para
   realizar la fusión.

## Primer paso concreto

Crear el prototipo de solo lectura de la Fase 0 en SwiftWABackupAPI y ejecutarlo
contra el caso real del grupo familiar. Ese prototipo determinará si la fecha de
los mensajes coincide entre teléfonos, cuánto autor queda sin resolver y qué
cobertura de anclas se obtiene. Con esas medidas se podrá cerrar el contrato y la
política de confianza sin arriesgar bibliotecas reales.
