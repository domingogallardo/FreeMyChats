# Evaluación para exportar e importar conversaciones entre propietarios

## Estado y alcance

Este documento contrasta el diseño inicial de
[fusión de conversaciones portables](fusion-conversaciones-portables.md) con la
implementación de partida de Free My Chats 1.3.10 y SwiftWABackupAPI 4.5.0. El
resultado de la parte de API se publicó inicialmente en SwiftWABackupAPI 5.0.0;
Free My Chats 2.0.0 integra la API 6.0.0 y completa el flujo de aplicación.

La especificación posterior y vinculante para SwiftWABackupAPI está en
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).
En ella la perspectiva de cada fuente se infiere durante la composición o se
proporciona opcionalmente como parámetro; no se exige persistir una identidad
global del propietario.

La primera entrega, limitada a trasladar a la API la Vista unificada local actual,
está en
[Composición de Vistas unificadas locales](especificacion-swiftwabackupapi-fusion-local-inicial.md).

El documento nació como evaluación. SwiftWABackupAPI 5.0.0 implementa el
diagnóstico, la materialización respecto al target, el contrato `.fmcchat` v1 y
su codec seguro. Free My Chats implementa el ciclo completo
crear–inspeccionar–extraer–componer–instalar, la persistencia reversible de las
aportaciones importadas y su interfaz.

La aplicación actual permite incorporar un archivo creado por Free My Chats a
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

El perfil `currentUnifiedView` conserva deliberadamente la huella exacta de las
copias de una misma perspectiva. Para una exportación de otra persona, la API
5.0.0 usa el perfil `conservativeCrossPerspective`: trata `isFromMe` como un rol
relativo a cada fuente, infiere la relación entre perspectivas y reorienta la
salida respecto a `targetSourceID`. Así, el mismo mensaje puede aparecer como
propio en una fuente y recibido en otra sin duplicarse.

La dificultad principal no es comprimir o copiar archivos, sino demostrar que dos
documentos son de la misma conversación, relacionar sus autores relativos y
alinear con suficiente confianza los mensajes compartidos.

La recomendación de comenzar por un diagnóstico de solo lectura ya se ha
aplicado. También se han completado la materialización conservadora en staging,
el contrato portable y la instalación reversible dentro de la biblioteca.

## Qué hace hoy la Vista unificada

La implementación vigente está repartida principalmente entre
`ConversationArchiveService`, `ConversationIdentityResolver`,
`ConversationArchiveRecord` y `FreeMyChatsStore`.

Cuando varias copias locales contienen el mismo chat:

1. La conversación se identifica por tipo y JID normalizado, con algunos alias
   LID a JID telefónico.
2. Cada copia guardada local queda en `StoredChats` y se registra mediante un
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

## Reutilización aplicada

### Reutilizado casi directamente

- El catálogo y la apertura de una única conversación materializada.
- `MergedChats/<conversationId>` como resultado derivado.
- El esquema de construir en una carpeta temporal, validar y sustituir al final.
- La instalación atómica del staging materializado por la API.
- La reasignación de IDs, respuestas y multimedia, ahora implementada dentro de
  SwiftWABackupAPI.
- La actualización del catálogo y de la conversación abierta en el store.
- La reconstrucción y degradación al retirar aportaciones.
- Buena parte de los fixtures de pruebas de solapamiento, multimedia, rollback y
  reparación.

### Reutilizado después de generalizar

- `ConversationArchiveRecord` registra aportaciones importadas además de
  copias guardadas locales.
- La resolución de aportaciones abre fuentes de `StoredChats` y de
  `ImportedChats`.
- `ConversationCompositionEngine` entrega el documento con perspectiva y autores
  normalizados.
- Los contadores de aportaciones y mensajes exclusivos incluyen ambos tipos
  de fuente.
- El flujo de retirada distingue entre borrar una copia guardada local y
  retirar una importación.
- La posición de lectura sigue confiando en el `Int` materializado; no se
  traduce con el mapa estable al reconstruir.

### No reutilizable como criterio de fusión entre propietarios

- La huella actual con `isFromMe`.
- La identidad individual basada únicamente en `contactJid`.
- La deduplicación como conjunto de hashes aislados. Los mensajes breves y
  repetidos necesitan contexto y orden.
- La elección implícita de un representante sin una política explícita para
  reacciones, ediciones, nombres y otros campos mutables.

## Estructura física implementada

La propuesta inicial colocaba `Base` e `Imports` dentro de cada carpeta de chat.
Después de la implementación de las Vistas unificadas ya no es necesario hacer esa
reestructuración. `StoredChats` ya conserva las bases locales y `MergedChats` ya es el
resultado reconstruible.

Free My Chats 2.0.0 añade un tercer almacén de fuentes:

```text
Mi biblioteca Free My Chats/
├── library.json
├── Sources/
├── StoredChats/                         # Aportaciones de copias locales
├── ImportedChats/                   # Aportaciones recibidas
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
  `StoredChats`, como ahora.
- Varias aportaciones locales se materializan en `MergedChats`, como ahora.
- Cualquier conversación con al menos una importación se materializa en
  `MergedChats`, aunque solo tenga una copia local.
- `ImportedChats` y `StoredChats` son fuentes; `MergedChats` se puede borrar y
  reconstruir.
- Retirar una importación borra únicamente su carpeta después de haber instalado
  correctamente el resultado reconstruido.
- La última aportación local no se puede borrar mientras haya importaciones: se
  conserva así el target local que orienta la Vista unificada.

Este diseño evita duplicar una `Base` y encaja con el sistema de reparación actual.

## Cambios de modelo realizados

### Perspectiva de cada fuente

No se persiste una identidad global obligatoria del propietario. Cada documento
mantiene su propia perspectiva: `isFromMe` significa “usuario de esta fuente”.
SwiftWABackupAPI infiere durante la alineación si dos fuentes representan a la
misma persona o a personas distintas.

Si el contenido no aporta evidencia suficiente, Free My Chats puede proporcionar
una identidad como pista opcional al construir la fuente o iniciar el análisis.
Una pista contradictoria se rechaza y su ausencia nunca autoriza una conjetura.
Las bibliotecas actuales continúan siendo legibles sin migración de propietario.

### Identidad de conversación

- Grupo: JID canónico del grupo más comprobación de `chatType == group`.
- Individual: equivalencia demostrada entre las perspectivas y sus interlocutores,
  apoyada por el solapamiento; `contactJid` por sí solo no basta.
- El nombre visible y el nombre del archivo nunca son identidad.

### Aportaciones importadas

Free My Chats conserva las aportaciones locales y registra las importadas en una
colección separada del manifiesto:

```swift
struct ImportedConversationContribution: Codable, Identifiable {
    let id: String
    let importedAt: Date
    let packageID: UUID
    let packageCreatedAt: Date
    let producerName: String
    let producerVersion: String
    let perspectiveHint: ConversationPerspectiveHint?
    let relativeDirectory: String
    let archiveSHA256: String
    let contentDigest: String
    let displayName: String
    let messageCount: Int?
    let exclusiveMessageCount: Int?
    let exclusiveMediaByteCount: Int64?
}
```

El resumen del catálogo expone por separado `localContributionCount` e
`importedContributionCount`; `contributionSources` contiene solo fuentes locales
para que el resaltado del panel izquierdo continúe funcionando.

### Versionado

La versión 2.0.0 usa el schema 3 tanto en `LibraryManifest` como en
`ConversationArchiveRecord`. Lee el schema 2 y lo actualiza al registrar la
primera importación; los demás schemas se rechazan para evitar ignorar
`ImportedChats` y reconstruir perdiendo datos.

### Identidad estable de mensaje

La API devuelve `ArchiveMessageID`, el mapa estable por ID materializado y los
mappings por fuente. Free My Chats no persiste esos mappings: las respuestas se
remapean correctamente dentro de cada materialización y cada reconstrucción
vuelve a analizar las fuentes. La posición de lectura se conserva por identidad
de conversación, pero el mensaje se guarda como un `Int` materializado y no se
traduce mediante `ArchiveMessageID` al reconstruir.

## División de responsabilidades

### SwiftWABackupAPI

Es propietaria de lo que define la interoperabilidad:

- modelos y schema portable;
- inferencia de perspectivas y pistas opcionales de participantes;
- creación y validación segura del `.fmcchat`;
- autoría relativa a cada fuente y orientación respecto al target;
- firmas canónicas, anclas únicas y alineación ordenada;
- equivalencia, disposición, razones y estadísticas de alineación;
- cálculo de confianza y mapas de mensajes/respuestas;
- transformación final de `MessageInfo` a la perspectiva target.

Esto también evita que Free My Chats tenga que reconstruir tipos de la API
mediante conversiones JSON para modificar campos inmutables.

### Free My Chats

Es propietario de la biblioteca y de la experiencia:

- paneles de abrir y guardar;
- `ImportedChats` y su integración con `ConversationArchiveRecord`;
- preparación, confirmación, progreso y cancelación;
- instalación y rollback de la conversación materializada;
- actualización del catálogo, selección y posición de lectura;
- historial y retirada de importaciones.

La API materializa `chat.json` y `Media` en staging. Free My Chats añade
`archive.json`, instala el directorio y ejecuta el rollback si falla la
transacción de biblioteca.

### Integración realizada

SwiftWABackupAPI 5.0.0 contiene los modelos portables, el codec seguro, las
identidades canónicas, la inferencia de perspectivas, el alineador, la
materialización target-relative y sus pruebas.

Free My Chats 2.0.0 incorpora:

- `LibraryModels.swift`: ruta `ImportedChats`, schema nuevo, aportación importada,
  contadores y nuevas clases de operación;
- `ConversationArchiveService.swift`: resolver ambos tipos de fuente,
  materializar con el plan de la API, instalar y retirar importaciones;
- `FreeMyChatsStore.swift`: estado de análisis, confirmación, progreso, aplicación,
  historial y refresco de selección;
- `ConversationView.swift`: menú de acciones y acceso al historial;
- ampliaciones de `ChatSidebarView` y `ConversationView` para exportar, importar,
  listar y retirar;
- pruebas de modelos, servicios y compatibilidad de biblioteca.

SwiftWABackupAPI introdujo el motor portable en 5.0.0. Free My Chats 2.0.0 fija
la versión exacta 6.0.0, que incorpora la terminología definitiva de chats
guardados y elimina las conversiones antiguas. Los archivos de
`.build/checkouts` no se editan.

## Formato `.fmcchat`

El archivo es autocontenido y se trata siempre como entrada no confiable:

```text
Conversacion.fmcchat
├── manifest.json
├── chat.json
└── Media/
```

El manifiesto v1 incluye:

- `schemaVersion`, identificador de formato, productor e implementación;
- identificador aleatorio del paquete;
- fecha de creación;
- descriptor de la conversación desde la perspectiva de la fuente;
- número de mensajes;
- tamaño, SHA-256 y ruta segura de `chat.json` y cada medio;
- `contentDigest` lógico del paquete.

`chat.json` portable es un contrato separado de `StoredChatDocument` v2. La
herramienta `Scripts/migrate-library-v1-to-v2.swift` realiza la migración manual
del formato interno anterior; el documento portable representa roles de autor
relativos a la fuente e IDs de archivo explícitos.

La creación incluye la conversación visible materializada, pero no el historial
interno de sus fuentes. Si una conversación ya incorpora datos recibidos, estos se
pueden volver a compartir como parte del resultado; en el receptor constituyen una
única aportación atribuida a quien creó el nuevo paquete.

Antes de extraer, el codec limita número de entradas, tamaño declarado y real,
ratio de compresión, tamaño individual, tamaño JSON y longitud de ruta. Rechaza
rutas absolutas, `..`, entradas que no sean ficheros regulares, duplicados de
nombre, referencias ausentes y hashes incorrectos.

## Proceso de exportación para compartir

1. El usuario abre una conversación del catálogo y, en el menú del icono de
   carpeta de su encabezado, pulsa `Exportar conversación…`.
2. La aplicación reutiliza la conversación materializada ya abierta, que reúne
   todas sus copias locales y chats importados; no vuelve a decodificarla.
3. Se abre el panel de guardado con un nombre legible y extensión `.fmcchat`.
4. En segundo plano se genera `chat.json` mensaje a mensaje y se calculan hashes
   y tamaños de los medios referenciados por bloques.
5. Los medios se escriben directamente desde su ubicación validada al ZIP
   temporal, sin duplicarlos primero en staging.
6. El ZIP terminado se comprueba por estructura, tamaños y hashes y se mueve al
   nombre definitivo únicamente si todo coincide.
7. Se informa de mensajes, archivos y tamaño; se ofrecen `Mostrar en Finder` y
   `Aceptar`.

Cancelar o fallar no modifica la biblioteca y elimina los temporales propios.

## Proceso de importación

1. El usuario pulsa `Importar chat…` en el grupo `Chats importados` o en el menú
   de la aplicación.
2. Selecciona un `.fmcchat`.
3. La aplicación hace una validación estructural y de seguridad sin escribir en la
   conversación: schema, límites, rutas, hashes y referencias.
4. Recorre el catálogo y exige que exista exactamente una conversación receptora
   con diagnóstico seguro. Si no hay ninguna o hay varias, muestra un error sin
   modificar la biblioteca.
5. Infiere la relación entre perspectivas a partir del solapamiento y las
   identidades disponibles; si no basta, usa una pista opcional proporcionada por
   el llamante. Después recalcula `isFromMe` respecto de la fuente local target.
6. Calcula firmas centrales, selecciona anclas fuertes únicas y obtiene su cadena
   ordenada. Los mensajes débiles repetidos no actúan como anclas ni se
   desambiguan mediante ventanas en la 5.0.0.
7. Solo con `disposition == .applicable` continúa automáticamente la importación.
8. Se copia primero el paquete validado a un staging temporal, se construye una
   nueva materialización y se valida.
9. Se instalan de forma coordinada la fuente importada en `ImportedChats`,
   `archive.json` y `MergedChats`. Si cualquier paso falla, se restaura el estado
   anterior.
10. Se refrescan catálogo y conversación abierta.
11. El resultado indica cuántos mensajes se han incorporado realmente.

El archivo recibido nunca se importa automáticamente solo porque el nombre del
chat coincida.

## Historial y retirada

El grupo `Chats importados`, situado encima de las copias de backup en el panel
izquierdo, muestra el nombre y la fecha de cada importación. Cada fila permite
abrir la conversación, mostrar su carpeta o retirar la aportación.

Al retirar una importación:

1. se calcula cuántos mensajes y bytes dejarían de estar disponibles;
2. se pide confirmación con esas cifras;
3. se reconstruye la conversación sin la aportación en una ubicación temporal;
4. se instala el resultado;
5. solo entonces se elimina la carpeta de la importación retirada.

Si otra fuente contiene el mismo mensaje o medio, no desaparece del resultado.

## Interfaz implementada

La exportación aparece en el menú del icono de carpeta del encabezado de la
conversación, junto a `Abrir en Finder`. La importación aparece en el encabezado
de `Chats importados` y en el menú de aplicación. Las operaciones largas muestran
su progreso y todos los errores de identidad o ambigüedad se presentan antes de
instalar nada.

## Implementación por fases

### Fase 0 — diagnóstico real, sin escrituras — IMPLEMENTADA

- SwiftWABackupCLI incluye `diagnose-conversation-composition`.
- La suite cubre grupos, individuales, perspectivas iguales y opuestas,
  mensajes repetitivos, anclas, coberturas, diferencias temporales y
  disposiciones no aplicables.
- El diagnóstico no escribe y ofrece `privacySafeReport`.

Resultado: `ConversationCompositionDiagnostic` reproducible; ninguna biblioteca
se modifica.

### Fase 1 — contrato e identidad portable — IMPLEMENTADA

- Modelos portables y versionados.
- Roles de autor relativos e inferencia de perspectiva.
- Identidad individual target-relative demostrada por solapamiento e hints, no
  un conjunto persistido de propietarios.
- Creación, inspección, extracción y apertura segura de `.fmcchat`.
- Fixtures de paquetes válidos y maliciosos.

Resultado: la API y los wrappers de la aplicación crean y validan paquetes; las
fases 3 y 4 completan su incorporación a la biblioteca y su interfaz.

### Fase 2 — alineación y política de contenido — IMPLEMENTADA

- Representación canónica independiente de perspectiva.
- Anclas únicas, agrupación target-relative y confianza.
- Política explícita para timestamps, reacciones y metadatos mutables.
- Mapas de IDs y respuestas.

Resultado: diagnóstico y materialización deterministas en staging.

### Fase 3 — persistencia reversible — IMPLEMENTADA

- `ImportedChats` y schema nuevo de la biblioteca.
- Generalización de aportaciones resueltas.
- Materialización atómica y rollback.
- Retirada, reparación y actualización de una copia guardada local sin perder
  importaciones.

Resultado: operaciones completas mediante servicios y tests.

### Fase 4 — experiencia macOS — IMPLEMENTADA

- Exportación de la conversación completa desde su menú de carpeta.
- Importación global con coincidencia única, resultado y progreso.
- Lista de chats importados con fecha, Finder y retirada.
- Mensajes de error accionables para ausencia, duplicado o ambigüedad.

### Validación adicional

- Pruebas de gran volumen, memoria y cancelación.
- Paquetes hostiles y límites de descompresión.
- Compatibilidad entre versiones y rechazo seguro por aplicaciones antiguas.
- Calibración final de confianza con conversaciones reales variadas.

## Cobertura crítica

- El mismo mensaje cambia de `isFromMe` entre dos propietarios y se deduplica.
- Los mensajes de ambos propietarios quedan orientados correctamente en la vista
  receptora.
- Grupo con autores LID/teléfono distintos entre dispositivos.
- Conversación individual identificada desde las dos perspectivas.
- Mensajes repetidos (`Sí`, emojis) no producen anclas falsas.
- Diferencias pequeñas de timestamp no crean duplicados ni coincidencias falsas.
- Importación idéntica repetida y paquete regenerado con el mismo contenido.
- Respuesta cuyo original solo existe en la importación.
- Una nueva copia guardada local después de importar no elimina `ImportedChats`.
- Eliminar la última fuente local se bloquea mientras existan importaciones.
- Retirar una importación mantiene mensajes y medios compartidos por otra fuente.
- Fallo o cancelación en cada fase deja bit a bit intacta la conversación previa.
- Una versión antigua de la aplicación rechaza de forma segura el schema nuevo.

## Decisiones ya fijadas por SwiftWABackupAPI 5.0.0

1. El flujo de Free My Chats importa inicialmente sobre una conversación local
   existente; la API puede materializar una sola fuente, pero no crea entradas de
   biblioteca.
2. `requiresReview` y `rejected` no se materializan; no existe una opción para
   forzar una alineación dudosa.
3. Las pistas de perspectiva son opcionales, operativas y se validan contra la
   evidencia.
4. El contenedor es ZIP mediante ZIPFoundation 0.9.20 y
   `PortableArchiveLimits.default` fija límites configurables.
5. El paquete no contiene identidad del propietario. Solo conserva identidades
   técnicas de participantes cuando la fuente demuestra que no son su usuario;
   `sourceUser` permanece relativo.

## Límite de validación actual

La suite cubre el flujo sintético y una biblioteca local de referencia. No
constituye una calibración representativa entre propietarios: los casos de
identidad o alineación ausentes de esos fixtures requieren validación adicional
antes de modificar los umbrales conservadores.
