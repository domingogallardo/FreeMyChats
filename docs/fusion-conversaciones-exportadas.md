# Fusión de conversaciones exportadas en FreeMyChats

## Estado

Implementación parcial de la funcionalidad completa, con la parte de API
publicada en SwiftWABackupAPI 5.0.0:

- implementados el diagnóstico y la materialización entre perspectivas;
- implementada la creación de staging desde Free My Chats;
- implementado el contrato `.fmcchat` v1 y su codec seguro en SwiftWABackupAPI;
- probados desde Free My Chats la creación, inspección, extracción y uso del
  paquete como entrada del mismo motor de composición;
- pendientes la persistencia reversible, la instalación definitiva y la interfaz.

Este documento sigue describiendo el flujo final esperado. La especificación
vinculante y su estado detallado están en
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).

La evaluación de este diseño frente a la implementación actual de Vistas
unificadas está en
[Evaluación para exportar e importar conversaciones entre propietarios](evaluacion-importacion-conversaciones.md).

La especificación vigente para SwiftWABackupAPI es
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).
Esta última sustituye las propuestas anteriores que exigían persistir una
identidad global del propietario: la perspectiva se infiere durante el análisis o
se aporta opcionalmente como parámetro.

La unificación incremental que ya realiza la aplicación con varias exportaciones
locales se mantiene como un perfil específico del mismo motor. El funcionamiento de
`Exports` y `MergedChats`, incluida su estrategia de mensajes y multimedia, se
explica en [Conversaciones materializadas](conversaciones-materializadas.md).

## Objetivo

Permitir que una persona incorpore a una conversación del catálogo de chats
exportados de FreeMyChats los mensajes presentes en otra exportación de la misma
conversación. Debe funcionar tanto con grupos como con conversaciones
individuales, conservar la multimedia y permitir deshacer posteriormente cada
importación.

La fusión afecta únicamente a la biblioteca local de FreeMyChats. No modifica una
copia de iPhone ni intenta reinsertar mensajes en WhatsApp.

## Decisiones de alcance

- Solo se aceptan archivos generados por FreeMyChats.
- No se importan los ZIP o TXT producidos por la función nativa de exportación de
  WhatsApp.
- La correspondencia de mensajes se obtiene alineando el contenido compartido de
  ambas exportaciones.
- La fusión no depende de `ZSTANZAID` ni de otros identificadores internos y no
  documentados de WhatsApp.
- Una operación ambigua se detiene: la aplicación no elimina ni combina mensajes
  basándose en una conjetura de baja confianza.
- Las aportaciones importadas se conservan como capas reversibles y sobreviven a
  una nueva exportación desde la copia fuente.

## Experiencia de usuario

### Crear un archivo para compartir

En el menú de una conversación del catálogo aparecerá:

> Crear archivo para compartir…

Esta operación no vuelve a extraer la conversación desde la copia de iPhone. Abre
la exportación existente, la valida y crea un paquete `.fmcchat` autocontenido.
Debe funcionar incluso cuando ya se haya eliminado la copia fuente.

### Añadir mensajes

En el mismo menú aparecerá:

> Añadir mensajes de otra exportación…

El flujo será:

1. Seleccionar o arrastrar un archivo `.fmcchat`.
2. Validar su formato e identidad de conversación.
3. Analizar el solapamiento sin modificar la biblioteca.
4. Mostrar mensajes emparejados y exclusivos, anclas, cobertura, orientación de
   perspectivas, confianza, razones y multimedia exclusiva según el plan
   aplicable.
5. Confirmar la importación.
6. Materializar la conversación combinada de forma atómica.
7. Volver a abrir el chat manteniendo en lo posible la posición de lectura.

Un resumen posible sería:

```text
Misma conversación · Chat familiar

1.842 mensajes coincidentes
  127 mensajes nuevos
      246 MB de multimedia exclusiva

Confianza de la fusión: alta
```

### Consultar y deshacer

La opción `Importaciones de esta conversación…` mostrará la fecha, procedencia y
resultado de cada importación. Desde ahí se podrá retirar una aportación y
reconstruir la conversación sin sus mensajes exclusivos.

## Formato de intercambio `.fmcchat`

Un `.fmcchat` es un ZIP con extensión propia y una raíz canónica:

```text
Conversacion.fmcchat
├── manifest.json
├── chat.json
└── Media/
    └── …
```

La creación del paquete:

- Archiva el `ConversationSource` que recibe. Free My Chats proporciona la
  conversación visible materializada cuando quiere compartir también mensajes
  incorporados anteriormente.
- Excluir las capas internas `Base` e `Imports` y su historial de procedencia.
- Incluir únicamente archivos multimedia referenciados por `chat.json`.
- Añadir tamaño y SHA-256 de cada archivo al manifiesto.
- Escribir en una ubicación temporal y mover el resultado al terminar.
- Producir un nombre legible sin utilizarlo como identidad de la conversación.

### Manifiesto implementado

```swift
public struct PortableConversationManifest: Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let formatIdentifier =
        "com.domingogallardo.freemychats.portable-conversation"

    public let schemaVersion: Int
    public let format: String
    public let packageID: UUID
    public let createdAt: Date
    public let producer: PortableArchiveProducer
    public let implementation: PortableArchiveImplementation
    public let conversation: PortableConversationDescriptor
    public let messageCount: Int
    public let firstMessageAt: Date?
    public let lastMessageAt: Date?
    public let document: PortableFileEntry
    public let media: [PortableMediaEntry]
    public let contentDigest: String
}
```

El manifiesto no certifica la autenticidad de quien lo entrega. Los hashes
garantizan integridad interna, no identidad criptográfica.

## Identidad de la conversación

El nombre visible no sirve para decidir si dos conversaciones son la misma.

```swift
public struct PortableConversationDescriptor: Codable, Hashable, Sendable {
    public let chatType: ChatInfo.ChatType
    public let groupJID: String?
    public let contactJID: String?
    public let contactIdentity: CanonicalParticipantIdentity?
    public let displayName: String
    public let isArchived: Bool
    public let exportedAt: Date
    public let photoPath: String?
}
```

### Grupos

Se utiliza el JID canónico del grupo. Además se comprueba que ambos documentos
declaran `chatType == .group`.

### Conversaciones individuales

Desde cada teléfono, `contactJID` y `contactIdentity` describen al interlocutor
desde la perspectiva de esa fuente. No se serializa una identidad del propietario
ni el conjunto absoluto de dos personas. El engine demuestra equivalencia por el
solapamiento y la relación inferida entre perspectivas; si la evidencia no basta,
devuelve `requiresReview` o `rejected`.

## Normalización de autores

`isFromMe` expresa la perspectiva del usuario de cada fuente y no se copia
directamente. El documento portable representa cada autor como `sourceUser`,
`participant(identityHint:)` o `unresolved`.

El engine infiere si el `sourceUser` de cada fuente es igual o distinto del
`sourceUser` del target. En individuales aplica la inversión binaria cuando las
perspectivas son opuestas; en grupos usa las identidades respaldadas por anclas,
aliases o pistas operativas. La salida recalcula `isFromMe` respecto a
`targetSourceID`, sin conocer ni persistir un propietario global.

## Correspondencia de mensajes por alineación

Cada exportación se trata como una secuencia cronológica. Si dos secuencias
comparten una zona suficientemente amplia:

```text
Local:     A B C D E F
Recibida:      C D E F G H
Resultado: A B C D E F G H
```

La correspondencia no se decide por un único campo, sino por huellas de contenido
y por la posición relativa dentro de la conversación.

### Representación canónica

Para analizar un mensaje se construye una representación independiente de la
perspectiva y de los identificadores SQLite:

```swift
struct CanonicalMessage {
    let relativeAuthor: SourceRelativeAuthor
    let resolvedAuthor: ResolvedCompositionAuthor?
    let date: Date
    let type: CanonicalMessageType
    let text: String?
    let caption: String?
    let mediaHash: SHA256Digest?
    let duration: Int?
    let location: CanonicalLocation?
}
```

No forman parte de la identidad central:

- `MessageInfo.id` y `chatId`, porque son locales a cada SQLite.
- `isFromMe`, porque depende del propietario.
- Reacciones, que pueden cambiar entre dos momentos.
- `replyToPreview`, que es una representación derivada.
- Advertencias o errores producidos durante la exportación.

El texto se normaliza de manera conservadora: Unicode NFC y saltos CRLF/CR
convertidos a LF. No se hace trim ni se colapsan espacios, puntuación, mayúsculas
o emojis.

### Huellas fuertes y débiles

Una firma central combina:

```text
autor canónico
+ instante del mensaje
+ tipo
+ hash del contenido textual o multimedia
```

La 5.0.0 considera fuerte un mensaje con multimedia o ubicación, o con
texto/caption normalizado de al menos cuatro caracteres fuera del conjunto débil
versionado (`ok`, `sí`, `si`, `no` y varios emojis frecuentes). Un mensaje como
`Sí` no actúa por sí solo como ancla.

### Construcción de anclas

1. Calcular las huellas de ambas secuencias.
2. Seleccionar huellas fuertes que aparezcan una sola vez en cada secuencia.
3. Emparejar sus posiciones.
4. Obtener la mayor cadena de pares que conserve el orden cronológico.
5. Descartar anclas que produzcan cruces o saltos incoherentes.

Esta cadena puede calcularse en `O(n log n)` mediante índices de hashes y una
subsecuencia creciente, evitando un LCS cuadrático sobre chats grandes.

### Mensajes débiles y contexto

La 5.0.0 no calcula hashes de ventanas ni hace desambiguación contextual de
secuencias repetitivas. Una firma débil puede agruparse si aparece como máximo una
vez por fuente y cae dentro de la tolerancia temporal; las repeticiones ambiguas
permanecen separadas.

### Expansión entre anclas

Una vez aceptada la relación entre fuentes, el engine une anclas fuertes, IDs
estables compatibles y firmas target-relative únicas por fuente dentro de la
tolerancia. El resto permanece como contenido exclusivo; no se intenta
reconciliar difusamente mensajes editados.

### Resultado público del análisis

```swift
public struct ConversationCompositionDiagnostic: Codable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: Int
    public let profile: ConversationCompositionPolicy.Profile
    public let targetSourceID: ConversationSourceID
    public let sourceDigests: [ConversationSourceDigest]
    public let equivalence: ConversationEquivalence
    public let perspectives: [SourcePerspectiveResolution]
    public let pairAlignments: [ConversationPairAlignmentStatistics]
    public let statistics: ConversationDiagnosticStatistics
    public let confidence: ConversationCompositionConfidence
    public let disposition: ConversationCompositionDisposition
    public let reasons: [CompositionReason]
}
```

La API expone conteos agregados de mensajes emparejados y exclusivos, cobertura,
orden, anclas, autores/perspectivas resueltos y mensajes exclusivos no
orientables. No publica arrays de contenido `matches`, `onlyInImport`,
`conflicts` o `ambiguousRegions`; la UI presenta estadísticas y razones sin
recibir texto privado ni muestras de mensajes.

## Confianza y política de seguridad

La fusión automática requiere una confianza alta. El diagnóstico tiene en cuenta:

- Número y densidad de anclas fuertes.
- Longitud y cobertura temporal del tramo compartido.
- Porcentaje de anclas que mantiene el mismo orden.
- Consistencia de las diferencias de fecha.
- Calidad de la resolución de autores.
- Autores exclusivos que no pueden orientarse.
- Perspectivas no resueltas o contradictorias.

`ConversationCompositionPolicy.conservativeDefault` fija los umbrales publicados.
La política resultante es:

- Confianza alta y disposición `applicable`: permitir la fusión.
- Confianza media: `requiresReview`, sin materialización.
- Confianza baja, secuencias disjuntas o identidad dudosa: rechazar.

Cuando dos exportaciones no tengan un solapamiento suficiente no se puede demostrar
que un mensaje no esté duplicado. La proximidad temporal por sí sola no basta.

## Respuestas

Cada documento mantiene sus propios `id` y `replyTo`. Durante la materialización se
construyen dos mapas:

```text
id de la exportación local    → id combinado
id de la exportación recibida → id combinado
```

Los mensajes alineados de ambos orígenes apuntan al mismo mensaje combinado. Las
referencias `replyTo` se reescriben mediante estos mapas. Si el mensaje citado no
está disponible, se conserva `replyToPreview` cuando exista.

No es necesario utilizar `stanzaId` para reconstruir respuestas presentes en los
documentos de origen.

## Multimedia

- Cada archivo se identifica por SHA-256 y tamaño.
- Dos nombres iguales con distinto contenido se renombran de forma determinista.
- Dos archivos iguales con nombres distintos se almacenan una sola vez en la vista
  materializada.
- Se actualizan `mediaFilename` y los nombres de fotos de chat o contactos.
- No se confía en rutas proporcionadas por el paquete; solo se aceptan nombres de
  archivo seguros dentro de `Media`.
- Un archivo declarado en el manifiesto debe existir y coincidir con su hash.

## Campos mutables

Reacciones, nombres resueltos, ediciones, eliminaciones y otros metadatos pueden
diferir porque las exportaciones se hicieron en momentos distintos.

Para un mensaje alineado, la 5.0.0 aplica esta política:

- La ocurrencia del target gana cuando existe.
- Si no existe en el target, gana la fuente con `sourceDate` más reciente y se
  aplican desempates estables.
- Contenido, reacciones, warning, autor visible y reply proceden del
  representante; el reply se remapea.
- Los metadatos del chat proceden del target y los contactos prefieren target,
  después la fuente más reciente.
- No se hace unión ciega de reacciones ni reconciliación difusa de ediciones.

Las reglas concretas deben documentarse y cubrirse con pruebas antes de ampliar el
conjunto de campos combinados.

## Identidad propia de FreeMyChats

Al materializar la primera fusión, cada mensaje recibe un identificador estable de
archivo, independiente de WhatsApp y de SQLite:

```swift
public struct ArchiveMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
}
```

Este identificador no resuelve la primera correspondencia entre dos exportaciones
independientes, pero simplifica las importaciones posteriores, las posiciones de
lectura, el historial de procedencia y las respuestas dentro de un paquete que ya
haya sido materializado por una versión compatible.

## Persistencia reversible

La carpeta de un chat evolucionará a una composición por capas:

```text
Chats/<chatId>/
├── chat.json                 # Vista combinada compatible
├── Media/                    # Multimedia materializada
├── Base/
│   ├── chat.json
│   └── Media/
├── Imports/
│   └── <importId>/
│       ├── manifest.json
│       ├── chat.json
│       └── Media/
└── merge-manifest.json
```

`chat.json` y `Media` continúan siendo la vista que abre FreeMyChats. `Base` e
`Imports` son las fuentes que permiten reconstruirla.

Al reemplazar la exportación base desde una copia de iPhone, Free My Chats
preserva `Imports`, vuelve a analizar todas las fuentes, instala la nueva vista y
ejecuta rollback si falla. SwiftWABackupAPI no conoce ni modifica `Imports`,
`MergedChats`, `archive.json` o `library.json`.

La semántica no dependerá de la estrategia física utilizada para materializar la
multimedia.

## Capacidades implementadas en SwiftWABackupAPI 5.0.0

La API es propietaria del formato, la validación, el diagnóstico, la alineación y
la materialización dentro de un staging proporcionado por el cliente.

```swift
let codec = PortableConversationArchiveCodec()
let info = try codec.createArchive(from: source, producer: producer, destinationURL: url)
let inspected = try codec.inspectArchive(at: url)
let directory = try codec.extractValidatedArchive(at: url, to: stagingURL)
let imported = try directory.makeConversationSource(id: importID, perspectiveHint: hint)

let engine = ConversationCompositionEngine(policy: .conservativeDefault)
let diagnostic = try engine.diagnose(
    sources: localSources + [imported],
    targetSourceID: localTarget.id
)
let result = try engine.compose(
    sources: localSources + [imported],
    targetSourceID: localTarget.id,
    perspectiveConstraints: [],
    targetChatID: targetChatID,
    destinationDirectory: compositionStagingURL
)
```

La API incluye `ArchiveMessageID`, modelos portables separados de
`ExportedChatDocument` v1, progreso, cancelación y errores estructurados. No
incluye identidad del propietario ni operaciones para aplicar, listar o retirar
importaciones: esas operaciones pertenecen a Free My Chats.

FreeMyChats no debe implementar un segundo motor de fusión manipulando JSON.

## Ampliaciones propuestas en FreeMyChats

### Estado y servicios

- Añadir operaciones `creatingSharePackage`, `inspectingImport`, `importingMessages`
  y `removingImport` a `FreeMyChatsStore`.
- Incorporar un servicio delgado para elegir destinos y archivos mediante paneles
  de macOS.
- Refrescar el catálogo de chats exportados, la conversación abierta y la posición
  de lectura tras materializar.
- Persistir únicamente la aportación, el paquete validado y cualquier pista
  operativa necesaria; no persistir un propietario global.

### Interfaz

- Añadir las acciones al menú del encabezado del chat exportado.
- Mostrar el análisis en una hoja modal antes de aplicar cambios.
- Exponer el historial en un inspector o una hoja secundaria, sin cargar cada
  burbuja con información de procedencia.
- Ofrecer `Mostrar en Finder` para el `.fmcchat` recién creado.
- Aceptar arrastrar un `.fmcchat` sobre una conversación como acceso directo al
  mismo flujo validado.

### Posición de lectura

La primera versión puede traducir la posición existente mediante el mapa de
mensajes alineados. A medio plazo conviene que `ChatReadingPositionStore` utilice
`ArchiveMessageID` en lugar del `Int` local.

## Compatibilidad

- FreeMyChats sigue abriendo `ExportedChatDocument` v1.
- El codec crea el contrato portable separado sin migrar el documento persistente.
- Un grupo requiere JID `@g.us`; un individual requiere una identidad canónica
  utilizable del interlocutor, derivada de `contactJid` y aliases opcionales.
- El paquete no requiere identidad del propietario. Si falta la identidad del
  interlocutor, `createArchive` devuelve `invalidSource` y Free My Chats puede
  solicitar una pista de conversación explícita.
- No se aplicará una migración destructiva al abrir una biblioteca.

## Seguridad y atomicidad

Los paquetes se consideran entrada no confiable aunque provengan de FreeMyChats.
SwiftWABackupAPI ya:

- limita tamaño total, número de entradas, ratio, JSON, ruta y tamaño individual;
- rechaza rutas absolutas, `..`, entradas no regulares y nombres inseguros;
- valida schema, manifiesto, hashes, conteos y referencias multimedia;
- extrae únicamente en el staging proporcionado;
- elimina temporales propios si se cancela o falla.

Free My Chats todavía debe coordinar la instalación del paquete, `archive.json` y
la nueva vista para conservar intacta la biblioteca ante un fallo.

## Rendimiento

- La API calcula hashes multimedia en streaming.
- Indexa firmas de mensajes en diccionarios.
- Construye la cadena de anclas mediante una subsecuencia creciente.
- Evita LCS cuadrático y no implementa comparación contextual exhaustiva.
- Publica progreso y admite cancelación.
- Cachea hashes dentro de la preparación y revalida las entradas antes de
  materializar; no confía en una caché externa para validar paquetes.

## Cobertura de pruebas

Las pruebas de correspondencia, identidad, contenido y seguridad de la API están
implementadas en SwiftWABackupAPI 5.0.0. Las pruebas de persistencia enumeradas
más abajo siguen pendientes en Free My Chats.

### Correspondencia

- Dos exportaciones idénticas con identificadores SQLite diferentes.
- Solapamiento al principio, al final y en la zona intermedia.
- Conversaciones con miles de `Sí`, emojis y mensajes repetidos.
- Mensajes con pequeñas diferencias de fecha entre exportaciones.
- Regiones compartidas cortas o completamente disjuntas.
- Orden inconsistente y conflictos deliberados.

### Identidad

- Grupo con JID estable.
- Conversación individual vista desde ambos propietarios.
- Participante representado como JID telefónico en una exportación y LID en otra.
- Autor no resoluble y nombres de agenda distintos.

### Contenido

- Texto, enlaces, ubicaciones, contactos, imágenes, vídeos, documentos y audios.
- Mismo medio con nombres distintos.
- Mismo nombre con medios diferentes.
- Respuestas cuyo original está en ambas exportaciones, en una sola o ausente.
- Reacciones y metadatos mutables diferentes.

### Persistencia

- Aplicar, listar y retirar una importación.
- Aplicar varias importaciones solapadas.
- Volver a exportar la base sin perder importaciones.
- Cancelar o provocar un fallo en cada fase y comprobar rollback.
- Abrir bibliotecas antiguas sin migración destructiva.

### Seguridad

- ZIP con path traversal, enlaces simbólicos o bomba de compresión.
- Hash multimedia incorrecto.
- Documento que referencia archivos ausentes o nombres inseguros.
- Paquete de otra conversación con el mismo nombre visible.

## Fases de implementación

### Fase 0: validación del enfoque — IMPLEMENTADA

La API incluye diagnóstico de solo lectura, anclas, alineación, cobertura,
perspectivas y disposición, con CLI y fixtures.

### Fase 1: contrato portable — IMPLEMENTADA

La API publica schema v1, identidad canónica, manifiesto, hashes y codec validado
de `.fmcchat`.

### Fase 2: motor de análisis — IMPLEMENTADA

La API implementa representación canónica, firmas, anclas ordenadas, disposición
y confianza. No implementa ventanas contextuales; los mensajes débiles repetidos
se mantienen separados. Los fixtures sintéticos y la biblioteca real validan el
resultado.

### Fase 3: persistencia reversible en Free My Chats — PENDIENTE

Introducir `Imports`, versionar `ConversationArchiveRecord`, registrar
aportaciones portables y coordinar instalación/rollback. La API ya reasigna IDs,
respuestas y multimedia en el staging.

### Fase 4: experiencia en FreeMyChats

Añadir crear archivo, inspeccionar, confirmar, importar, consultar procedencia y
deshacer.

### Fase 5: endurecimiento

Calibrar umbrales, rendimiento, cancelación, paquetes maliciosos, migraciones y
reexportación de la base.

## Criterios de aceptación

Cumplidos por SwiftWABackupAPI 5.0.0:

- Fusiona grupos y conversaciones individuales generados por FreeMyChats.
- No utiliza `stanzaId` para identificar mensajes.
- Rechaza automáticamente conversaciones distintas y alineaciones ambiguas.
- No duplica los mensajes compartidos ni la multimedia idéntica.
- Normaliza correctamente `isFromMe` desde la perspectiva local.
- Conserva y remapea respuestas dentro de los datos disponibles.
- Las exportaciones existentes continúan siendo legibles.

Pendientes de la Fase 3 de Free My Chats:

- Permite deshacer una importación.
- Una reexportación de la base no elimina aportaciones importadas.
- Cualquier fallo deja intacta la exportación anterior.

## Riesgos y preguntas abiertas

- La policy publicada admite 2 segundos de diferencia por defecto y exige tres
  anclas/mensajes de solapamiento con consistencia de orden mínima de 0,9; puede
  necesitar calibración con más conversaciones reales.
- Un autor exclusivo no orientable bloquea la composición conservadora.
- No hay desambiguación contextual de mensajes débiles repetidos ni
  reconciliación difusa de ediciones.
- La política de representante está fijada, pero una futura reconciliación de
  metadatos podría requerir un nuevo algoritmo versionado.
- Qué estrategia física evita duplicar medios sin complicar la portabilidad y el
  rollback.
- Cómo convertir exportaciones antiguas cuando la copia fuente ya no existe.

El contrato v1 ya está fijado; cualquier ampliación debe conservar el versionado
y el rechazo seguro.

## Siguiente paso

Implementar en Free My Chats el registro de una aportación extraída y validada,
su reapertura mediante `openValidatedDirectory`, el nuevo análisis de todas las
fuentes, la instalación atómica del staging materializado y la reconstrucción al
retirar la importación.
