# Fusión de conversaciones portables en FreeMyChats

## Estado

Free My Chats 2.1.0 implementa el flujo completo sobre la API introducida en
SwiftWABackupAPI 5.0.0 y consumida con su terminología definitiva en la 6.0.0:

- implementados el diagnóstico y la materialización entre perspectivas;
- implementada la creación de staging desde Free My Chats;
- implementado el contrato `.fmcchat` v1 y su codec seguro en SwiftWABackupAPI;
- implementadas y probadas la exportación de conversaciones materializadas, la búsqueda
  automática de una única conversación receptora, la persistencia reversible en
  `ImportedChats`, la instalación definitiva y la interfaz.

Este documento describe el flujo implementado. La especificación vinculante y
su estado detallado están en
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).

La evaluación de este diseño frente a la implementación actual de Vistas
unificadas está en
[Evaluación para exportar e importar conversaciones entre propietarios](evaluacion-importacion-conversaciones.md).

La especificación vigente para SwiftWABackupAPI es
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).
Esta última sustituye las propuestas anteriores que exigían persistir una
identidad global del propietario: la perspectiva se infiere durante el análisis o
se aporta opcionalmente como parámetro.

La unificación incremental que ya realiza la aplicación con varias copias guardadas
locales se mantiene como un perfil específico del mismo motor. El funcionamiento de
`StoredChats` y `MergedChats`, incluida su estrategia de mensajes y multimedia, se
explica en [Conversaciones materializadas](conversaciones-materializadas.md).

## Funcionalidad

Una persona puede incorporar a una conversación del catálogo de FreeMyChats los
mensajes presentes en otra exportación portable de la misma conversación. El
flujo funciona con grupos y conversaciones individuales, conserva la multimedia
y permite deshacer cada importación.

La fusión afecta únicamente a la biblioteca local de FreeMyChats. No modifica una
copia de iPhone ni intenta reinsertar mensajes en WhatsApp.

## Decisiones de alcance

- Solo se aceptan archivos generados por FreeMyChats.
- No se importan los ZIP o TXT producidos por la función nativa de exportación de
  WhatsApp.
- La correspondencia de mensajes se obtiene alineando el contenido compartido de
  ambas fuentes.
- La fusión no depende de `ZSTANZAID` ni de otros identificadores internos y no
  documentados de WhatsApp.
- Una operación ambigua se detiene: la aplicación no elimina ni combina mensajes
  basándose en una conjetura de baja confianza.
- Las aportaciones importadas se conservan como capas reversibles y sobreviven a
  una nueva copia guardada desde la copia fuente.

## Experiencia de usuario

### Crear un archivo para compartir

En el menú del icono de carpeta del encabezado de una conversación aparece:

> Exportar conversación…

Esta operación no vuelve a extraer la conversación desde la copia de iPhone.
Abre la conversación materializada visible, que incluye todas sus copias locales
y chats importados, la valida y crea un paquete `.fmcchat` autocontenido. También
funciona cuando ya se ha eliminado una copia fuente.

### Añadir mensajes

En la cabecera del grupo `Chats importados` aparece:

> Importar chat…

El flujo implementado:

1. Seleccionar un archivo `.fmcchat`.
2. Validar su formato e identidad de conversación.
3. Analizar el solapamiento sin modificar la biblioteca.
4. Exigir una única conversación aplicable del catálogo; cero o varias
   coincidencias producen un error.
5. Materializar la conversación combinada de forma atómica.
6. Abrir la nueva Vista unificada.

El resultado informa de la conversación y de los mensajes incorporados. El
diagnóstico interno también calcula coincidencias, multimedia exclusiva y
confianza; estos datos no se muestran íntegramente en la interfaz 2.1.0:

```text
Misma conversación · Chat familiar

1.842 mensajes coincidentes
  127 mensajes nuevos
      246 MB de multimedia exclusiva

Confianza de la fusión: alta
```

### Consultar y deshacer

El grupo `Chats importados`, situado encima de las copias de backup, muestra el
nombre y la fecha de cada importación. Desde ahí se puede abrir, revelar en Finder
o retirar una aportación y reconstruir la conversación sin sus mensajes
exclusivos.

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
- Excluir las capas internas de la biblioteca y su historial de procedencia.
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
    public let storedAt: Date
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

Cada fuente se trata como una secuencia cronológica. Si dos secuencias
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

Cuando dos fuentes no tengan un solapamiento suficiente no se puede demostrar
que un mensaje no esté duplicado. La proximidad temporal por sí sola no basta.

## Respuestas

Cada documento mantiene sus propios `id` y `replyTo`. Durante la materialización se
construyen dos mapas:

```text
id de la copia guardada local → id combinado
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
diferir porque las fuentes se capturaron en momentos distintos.

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

Este identificador no resuelve la primera correspondencia entre dos fuentes
independientes, pero simplifica las importaciones posteriores, las posiciones de
lectura, el historial de procedencia y las respuestas dentro de un paquete que ya
haya sido materializado por una versión compatible.

## Persistencia reversible

Free My Chats 2.1.0 separa las fuentes locales, las importadas y la
materialización:

```text
StoredChats/<copia>/Chats/<chatId>/
├── chat.json
└── Media/

ImportedChats/<conversationId>/<importId>/
├── manifest.json
├── chat.json
└── Media/

MergedChats/<conversationId>/
├── archive.json
├── chat.json
└── Media/
```

La aplicación abre directamente `StoredChats` solo cuando hay una copia local y
ninguna importación. En los demás casos abre `MergedChats`; `StoredChats` e
`ImportedChats` conservan las fuentes que permiten reconstruirla.

Al reemplazar la copia guardada base desde una copia de iPhone, Free My Chats
preserva `ImportedChats`, vuelve a analizar todas las fuentes, instala la nueva
vista y ejecuta rollback si falla. SwiftWABackupAPI no conoce ni modifica
`ImportedChats`,
`MergedChats`, `archive.json` o `library.json`.

La semántica es independiente de la estrategia física utilizada para
materializar la multimedia.

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
`StoredChatDocument` v2, progreso, cancelación y errores estructurados. No
incluye identidad del propietario ni operaciones para aplicar, listar o retirar
importaciones: esas operaciones pertenecen a Free My Chats.

FreeMyChats no debe implementar un segundo motor de fusión manipulando JSON.

## Integración implementada en FreeMyChats

### Estado y servicios

- `FreeMyChatsStore` publica las operaciones de exportación, importación y
  retirada con progreso.
- Los paneles nativos de macOS seleccionan destinos y archivos `.fmcchat`.
- Tras materializar se refrescan el catálogo y la conversación abierta.
- Solo se persisten la aportación, el paquete validado y la pista operativa
  necesaria; no se persiste un propietario global.

### Interfaz

- El menú de carpeta de cada conversación expone `Exportar conversación…`
  junto a `Abrir en Finder`.
- `Chats importados` aparece encima de las copias de backup y ofrece la
  importación global.
- La lista muestra nombre y fecha, y permite abrir, revelar en Finder o retirar
  cada aportación.
- La importación solo continúa si el análisis encuentra exactamente una
  conversación aplicable.

### Posición de lectura

`ChatReadingPositionStore` conserva la posición bajo la identidad estable de la
conversación, pero guarda el mensaje como `Int` materializado. La versión 2.1.0
no persiste el mapa de `ArchiveMessageID` ni traduce la posición cuando una
reconstrucción cambia los enteros.

## Formatos actuales

- FreeMyChats abre `StoredChatDocument` v2 para las copias guardadas locales.
- No existen aliases ni migraciones automáticas para el documento v1.
- El codec crea el contrato portable separado `.fmcchat` v1.
- Un grupo requiere JID `@g.us`; un individual requiere una identidad canónica
  utilizable del interlocutor, derivada de `contactJid` y aliases opcionales.
- El paquete no requiere identidad del propietario. Si falta la identidad del
  interlocutor, `createArchive` devuelve `invalidSource` y Free My Chats puede
  solicitar una pista de conversación explícita.
- La aplicación no aplica una migración destructiva al abrir una biblioteca. La
  migración v1 a v2 se ejecuta manualmente con
  `Scripts/migrate-library-v1-to-v2.swift`.

## Seguridad y atomicidad

Los paquetes se consideran entrada no confiable aunque provengan de FreeMyChats.
SwiftWABackupAPI ya:

- limita tamaño total, número de entradas, ratio, JSON, ruta y tamaño individual;
- rechaza rutas absolutas, `..`, entradas no regulares y nombres inseguros;
- valida schema, manifiesto, hashes, conteos y referencias multimedia;
- extrae únicamente en el staging proporcionado;
- elimina temporales propios si se cancela o falla.

Free My Chats coordina la instalación del paquete, `archive.json` y la nueva
vista, con staging y rollback para conservar intacta la biblioteca ante un fallo.

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
implementadas en SwiftWABackupAPI 5.0.0. Free My Chats añade cobertura de
persistencia, reapertura, duplicados, ausencia de coincidencia, retirada y
actualización de la copia local tras importar.

### Correspondencia

- Dos fuentes idénticas con identificadores SQLite diferentes.
- Solapamiento al principio, al final y en la zona intermedia.
- Conversaciones con miles de `Sí`, emojis y mensajes repetidos.
- Mensajes con pequeñas diferencias de fecha entre fuentes.
- Regiones compartidas cortas o completamente disjuntas.
- Orden inconsistente y conflictos deliberados.

### Identidad

- Grupo con JID estable.
- Conversación individual vista desde ambos propietarios.
- Participante representado como JID telefónico en una fuente y LID en otra.
- Autor no resoluble y nombres de agenda distintos.

### Contenido

- Texto, enlaces, ubicaciones, contactos, imágenes, vídeos, documentos y audios.
- Mismo medio con nombres distintos.
- Mismo nombre con medios diferentes.
- Respuestas cuyo original está en ambas fuentes, en una sola o ausente.
- Reacciones y metadatos mutables diferentes.

### Persistencia

- Aplicar, listar y retirar una importación.
- Aplicar varias importaciones solapadas.
- Actualizar la copia guardada base sin perder importaciones.
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

### Fase 3: persistencia reversible en Free My Chats — IMPLEMENTADA

Se ha introducido `ImportedChats`, versionado `ConversationArchiveRecord`,
registrado las aportaciones portables y coordinado instalación/rollback.

### Fase 4: experiencia en FreeMyChats — IMPLEMENTADA

Incluye exportar, importar sobre una coincidencia única, consultar procedencia y
deshacer.

### Validación adicional

Los umbrales conservadores necesitan más muestras de conversaciones reales. La
API ya cubre cancelación, paquetes maliciosos y límites de extracción; la
aplicación cubre migración manual y actualización de la copia guardada base.

## Criterios de aceptación

Cumplidos por SwiftWABackupAPI 5.0.0:

- Fusiona grupos y conversaciones individuales generados por FreeMyChats.
- No utiliza `stanzaId` para identificar mensajes.
- Rechaza automáticamente conversaciones distintas y alineaciones ambiguas.
- No duplica los mensajes compartidos ni la multimedia idéntica.
- Normaliza correctamente `isFromMe` desde la perspectiva local.
- Conserva y remapea respuestas dentro de los datos disponibles.
- Las copias guardadas con el formato actual continúan siendo legibles.

Cumplidos por la Fase 3 de Free My Chats:

- Permite deshacer una importación.
- Una actualización de la copia guardada base no elimina aportaciones importadas.
- Cualquier fallo deja intacta la copia guardada anterior.

## Riesgos y preguntas abiertas

- La policy publicada admite 2 segundos de diferencia por defecto y exige tres
  anclas/mensajes de solapamiento con consistencia de orden mínima de 0,9; puede
  necesitar calibración con más conversaciones reales.
- Un autor exclusivo no orientable bloquea la composición conservadora.
- No hay desambiguación contextual de mensajes débiles repetidos ni
  reconciliación difusa de ediciones.
- La política de representante está fijada y no reconcilia de forma difusa
  ediciones ni metadatos divergentes.
- `StoredChats`, `ImportedChats` y `MergedChats` priorizan reconstrucción y
  rollback sobre evitar toda duplicación física de medios.
- La migración de bibliotecas anteriores se realiza manualmente fuera de la
  aplicación con `Scripts/migrate-library-v1-to-v2.swift`.

El contrato v1 ya está fijado; cualquier ampliación debe conservar el versionado
y el rechazo seguro.

## Resultado en Free My Chats 2.0.0

Free My Chats registra la aportación extraída y validada, la reabre mediante
`openValidatedDirectory`, analiza de nuevo todas las fuentes, instala
atómicamente el staging materializado y reconstruye la conversación al retirar
la importación.
