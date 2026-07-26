# Especificación inicial para SwiftWABackupAPI: composición de Vistas unificadas locales

## Estado de implementación — SwiftWABackupAPI 5.0.0

Este incremento está implementado, probado y publicado en SwiftWABackupAPI
5.0.0. Free My Chats 2.0.0 usa ya `ConversationCompositionEngine` para construir
la Vista unificada local y conserva la instalación, los manifiestos y el
rollback de su biblioteca.

El documento se mantiene como especificación de la semántica exacta del perfil
`currentUnifiedView`. Las ampliaciones que aquí figuraban como futuras
—diagnóstico y materialización entre perspectivas y `.fmcchat` v1— también están
implementadas en la API 5.0.0, pero pertenecen al perfil
`conservativeCrossPerspective` y al codec portable; no modifican las reglas
conservadoras de este perfil local.

## 1. Propósito

Este documento define el primer incremento del
[motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).

SwiftWABackupAPI implementa las funciones que Free My Chats utiliza para
construir una Vista unificada a
partir de varias copias guardadas locales de la misma conversación y de la misma
perspectiva.

La implementación reemplaza la parte de composición que vivía en
`FreeMyChats/Sources/FreeMyChats/Services/ConversationArchiveService.swift`:

- huella de mensajes;
- deduplicación;
- ordenación;
- conteos de exclusividad;
- remapeo de IDs y respuestas;
- selección de metadatos;
- unión de contactos;
- copia y deduplicación de multimedia;
- creación validada de `chat.json` y `Media`.

La persistencia de biblioteca, sus manifiestos y los reemplazos atómicos de
`MergedChats` permanecen en Free My Chats.

## 2. Relación con la especificación general

Esta fue la especificación de la primera entrega, no un diseño alternativo. Los
tipos y funciones son el subconjunto local de la API general y comparten el mismo
motor con la composición entre perspectivas.

Decisiones heredadas:

- `ConversationSource` es la entrada común.
- `ConversationCompositionEngine` analiza N fuentes.
- una fuente target define la perspectiva y presentación de salida;
- el análisis se separa de la materialización;
- `PreparedConversationComposition` conserva mapeos internos no manipulables;
- `ConversationCompositionPlan` expone estadísticas e impacto;
- `ConversationMaterializationResult` devuelve documento, medios y mappings;
- `ArchiveMessageID` proporciona identidad estable independiente de SQLite;
- la API no conoce `StoredChats`, `ImportedChats`, `MergedChats` ni `library.json`.

La API 5.0.0 añade sobre esta misma base:

- inferencia entre perspectivas diferentes;
- alineación conservadora por anclas y tolerancias temporales;
- paquetes `.fmcchat`;
- fuentes portables;
- evidencia entre propietarios.

Estas ampliaciones no se activan implícitamente: `currentUnifiedView` conserva la
huella exacta y exige una restricción explícita de misma perspectiva.

## 3. Caso de uso exacto

Free My Chats conserva copias guardadas autocontenidas:

```text
StoredChats/<version>/Chats/<chatId>/
├── chat.json
└── Media/
```

Dos o más copias guardadas de distintas copias locales pueden representar el mismo
chat y solaparse:

```text
Enero: A B C D
Julio:     C D E F
Vista: A B C D E F
```

Free My Chats selecciona las contribuciones, las abre con `StoredChatStore` y las
entrega a SwiftWABackupAPI como `ConversationSource`.

Para este incremento, Free My Chats afirma mediante una restricción explícita que
todas las fuentes usan la misma perspectiva. La API no persiste ni exige una
identidad de propietario.

## 4. Alcance incluido

- Una o más fuentes `StoredChatDocument` v2.
- Grupos e individuales.
- N fuentes, no solo dos.
- Misma perspectiva declarada mediante `ConversationPerspectiveConstraint`.
- Identidad de conversación por tipo/JID y alias de interlocutor aportados.
- Huella exacta compatible con la Vista unificada vigente.
- Deduplicación de mensajes y medios.
- Orden determinista.
- Respuestas y previews.
- Reacciones y demás metadatos conservados desde el representante elegido.
- Contactos y fotografías.
- Estadísticas por fuente.
- Impacto de retirar una fuente.
- Materialización en staging.
- Validación de entrada y salida.
- Progreso y cancelación cooperativa.
- IDs estables opcionales y mappings.
- Pruebas unitarias y de integración en SwiftWABackupAPI.

## 5. Fuera del perfil `currentUnifiedView`

- `.fmcchat` y cualquier ZIP, gestionados por
  `PortableConversationArchiveCodec`.
- Fuentes desde personas/perspectivas distintas, gestionadas por
  `.conservativeCrossPerspective`.
- Inferir una perspectiva sin restricción explícita, capacidad exclusiva del
  perfil conservador entre perspectivas.
- Identidad global o persistida del propietario.
- Alineación por ventanas, anclas o LIS.
- Tolerancia de timestamp.
- Clasificación contextual de conflictos.
- Secuencias que requieren deduplicación no exacta.
- Instalación o rollback en una biblioteca de Free My Chats.
- Escritura de `archive.json`.
- Eliminación física de una contribución.
- Interfaz de usuario.
- Cambios al proyecto Python legado.

## 6. Precondiciones

El perfil inicial acepta una composición si:

1. hay al menos una fuente;
2. todos los `ConversationSourceID` son únicos y no vacíos;
3. `targetSourceID` existe;
4. todas las fuentes son `StoredChatDocument` v2;
5. el llamante aporta una restricción `.samePerspective` que incluye todas las
   fuentes;
6. todas las fuentes pueden demostrarse como la misma conversación mediante las
   reglas de identidad de este documento;
7. todos los documentos y medios son válidos;
8. no hay colisiones incompatibles de IDs estables.

Si no se cumple una precondición, `analyze` falla con un error estructurado y no
escribe.

## 7. API pública mínima

### 7.1 IDs y fuente

```swift
public struct ConversationSourceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String)
}

public struct ArchiveMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID())
}
```

`ConversationSource` es opaco tras su construcción:

```swift
public struct ConversationSource {
    public let id: ConversationSourceID
    public let kind: ConversationSourceKind
    public let conversationIdentityHint: CanonicalParticipantIdentity?
    public let perspectiveHint: ConversationPerspectiveHint?
    public let sourceDate: Date

    public init(
        id: ConversationSourceID,
        document: StoredChatDocument,
        mediaDirectoryURL: URL,
        conversationIdentityHint: CanonicalParticipantIdentity? = nil,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        stableMessageIDs: [Int: ArchiveMessageID] = [:]
    ) throws
}
```

En este incremento:

- `kind == .storedDocument` siempre;
- `perspectiveHint` no es necesario cuando se proporciona la restricción de misma
  perspectiva;
- `conversationIdentityHint` se usa únicamente para resolver alias del
  interlocutor de un chat individual;
- el documento, directorio de medios y mapa estable permanecen internos para
  impedir una mutación posterior a la preparación.

### 7.2 Restricción de perspectiva

```swift
public struct ConversationPerspectiveConstraint: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case samePerspective
        case differentPerspectives
        case sourceIdentity
    }

    public let kind: Kind
    public let sourceIDs: [ConversationSourceID]
    public let participant: CanonicalParticipantIdentity?

    public static func samePerspective(
        sourceIDs: [ConversationSourceID]
    ) -> Self
}
```

El perfil `currentUnifiedView` ejecuta únicamente `.samePerspective`; exige una
restricción que cubra todas las fuentes. Las variantes
`.differentPerspectives` y `.sourceIdentity` se usan con el perfil
`conservativeCrossPerspective`.

La restricción expresa una relación entre fuentes, no una identidad personal.

### 7.3 Engine

```swift
public struct ConversationCompositionEngine {
    public init(policy: ConversationCompositionPolicy = .currentUnifiedView)

    public func analyze(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PreparedConversationComposition

    public func materialize(
        _ preparation: PreparedConversationComposition,
        targetChatID: Int,
        destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationMaterializationResult
}
```

### 7.4 Conveniencia implementada

La API expone una función que analiza y materializa en una llamada:

```swift
public func compose(
    sources: [ConversationSource],
    targetSourceID: ConversationSourceID,
    perspectiveConstraints: [ConversationPerspectiveConstraint],
    targetChatID: Int,
    destinationDirectory: URL,
    progress: WABackupProgressHandler? = nil,
    cancellation: WABackupCancellationHandler? = nil
) throws -> ConversationMaterializationResult
```

`compose` delega en la misma implementación que `analyze` + `materialize`.

## 8. Perfil de política inicial

```swift
public struct ConversationCompositionPolicy: Codable, Sendable {
    public enum Profile: String, Codable, Sendable {
        case currentUnifiedView
        case conservativeCrossPerspective
    }

    public let profile: Profile

    public static let currentUnifiedView: Self
}
```

En `.currentUnifiedView`:

- todas las fuentes deben declarar misma perspectiva;
- coincidencia de mensaje exacta según la sección 12;
- timestamp exacto a milisegundos;
- sin offset ni tolerancia;
- sin ventanas contextuales;
- sin concatenación basada en confianza;
- una conversación válida puede tener fuentes sin solapamiento, igual que hoy;
- los conflictos se limitan a invariantes estructurales e IDs estables
  incompatibles.

La policy entre perspectivas está disponible como `.conservativeDefault`; no se
utiliza para construir la Vista unificada local.

## 9. Preparación y plan

`PreparedConversationComposition` conserva internamente:

- fuentes validadas;
- firmas/digests de entrada;
- hashes multimedia;
- huella de cada mensaje;
- representante por huella;
- mapas de mensajes fuente a grupo lógico;
- traducción provisional de respuestas;
- IDs estables elegidos;
- nombres materiales previstos.

El cliente solo accede al plan:

```swift
public struct PreparedConversationComposition {
    public let plan: ConversationCompositionPlan
}
```

No debe ofrecer un inicializador público que permita fabricar una preparación.

### 9.1 Plan inicial

```swift
public struct ConversationCompositionPlan: Codable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: Int
    public let profile: ConversationCompositionPolicy.Profile
    public let targetSourceID: ConversationSourceID
    public let sourceDigests: [ConversationSourceDigest]
    public let statistics: ConversationCompositionStatistics
    public let sourceImpacts: [ConversationSourceImpact]
    public let confidence: ConversationCompositionConfidence
    public let disposition: ConversationCompositionDisposition
    public let reasons: [CompositionReason]
    public let crossPerspectiveDiagnostic: ConversationCompositionDiagnostic?
}
```

Para entradas válidas de este perfil:

- `confidence == .high`;
- `disposition == .applicable`;
- la razón indica `samePerspectiveConstraintAccepted`;
- `crossPerspectiveDiagnostic == nil`;
- no se pretende medir confianza de alineación contextual.

## 10. Validación de identidad de conversación

### 10.1 Reglas comunes

- Todos los `chatType` deben coincidir.
- El nombre visible no se usa.
- `chat.id` puede variar.
- Fechas, contadores y estado archivado pueden variar.

### 10.2 Grupos

- Normalizar `contactJid` con trim y minúsculas.
- Exigir sufijo `@g.us`.
- Todos los JID normalizados deben ser idénticos.
- Un nombre igual con JID diferente se rechaza.

### 10.3 Individuales

Cada fuente obtiene una identidad de interlocutor:

1. `conversationIdentityHint`, si existe;
2. `chat.contactJid` normalizado como phoneJID, lidJID o dirección genérica válida;
3. alias incluidos en la pista.

Todas deben tener una dirección común o una relación de alias explícita. No usar:

- nombre;
- foto;
- sufijo de teléfono;
- dígitos de LID como teléfono;
- solapamiento de mensajes para ignorar una identidad diferente en este perfil.

Free My Chats puede seguir usando `ConversationIdentityResolver` y pasar la
identidad resuelta como `conversationIdentityHint` hasta que una API genérica de
alias se comparta entre ambos proyectos.

## 11. Autoría en la misma perspectiva

Convertir `MessageInfo` a un autor relativo:

```swift
enum SamePerspectiveAuthor: Hashable {
    case sourceUser
    case participant(CanonicalParticipantIdentity)
    case unresolved
}
```

Reglas:

- `isFromMe == true` → `.sourceUser`.
- `isFromMe == false` + identidad de autor → `.participant`.
- `isFromMe == false` + mensaje de individual sin autor → interlocutor del chat.
- Autor ausente → `.unresolved`; el diagnóstico puede distinguir un evento del
  sistema cuando el tipo lo demuestre, pero la key inicial conserva la semántica
  de autor `nil` de la implementación vigente.
- `isFromMe == true` con `author.kind == .participant` → entrada inválida.
- `isFromMe == false` con `author.kind == .me` → entrada inválida.
- `displayName` y `MessageAuthor.source` no participan en identidad.

Como todas las fuentes son de la misma perspectiva, `.sourceUser` es equivalente
entre ellas sin conocer quién es esa persona.

### 11.1 Diferencias deliberadas respecto al código actual

Este traslado busca paridad funcional, no repetir defectos accidentales. Se
aceptan estas diferencias, que deben documentarse y probarse:

- los mensajes propios se identifican por el rol `.sourceUser`; no dejan de
  coincidir porque un `ownerJid` falte o cambie de representación;
- texto y caption se normalizan a NFC y saltos LF;
- la fuente target para presentación es explícita;
- la selección de contactos es determinista por target/fecha;
- se introducen mappings e IDs estables opcionales;
- la validación de rutas y symlinks es más estricta.

Cualquier otra diferencia en número, orden, replies o medios requiere consulta.

## 12. Huella exacta de mensaje

### 12.1 Campos

La clave lógica inicial contiene:

```swift
struct SamePerspectiveMessageKey: Encodable, Hashable {
    let timestampMilliseconds: Int64
    let author: SamePerspectiveAuthor
    let messageType: String
    let text: String?
    let caption: String?
    let media: CanonicalMediaIdentity?
    let seconds: Int?
    let latitude: Double?
    let longitude: Double?
}
```

No contiene:

- `MessageInfo.id`;
- `chatId`;
- `replyTo` o preview;
- reacciones;
- warning/error;
- nombres visuales;
- foto;
- fecha de copia guardada;
- `stanzaId`.

### 12.2 Normalización

- Timestamp redondeado a milisegundos, como la implementación actual.
- Texto/caption en Unicode NFC y saltos CRLF/CR convertidos a LF.
- No trim, no colapsar espacios, no cambiar puntuación o mayúsculas.
- `messageType` exacto del contrato v1.
- Teléfono: dígitos.
- phoneJID: usuario telefónico normalizado.
- LID: solo equivalente mediante alias/phone ya resuelto.
- Coordenadas y duración exactas en este perfil.
- Medio: tamaño + SHA-256, no nombre.

### 12.3 Digest de huella

Puede usarse la key directamente como `Hashable` dentro del proceso. Si se crea
un digest persistible:

- JSON/codificación canónica;
- claves ordenadas;
- SHA-256 hexadecimal en minúsculas;
- algoritmo/versionado registrado en el plan.

No usar `Hasher`, porque su semilla no es estable entre procesos.

## 13. Hashing y validación multimedia

### 13.1 Archivos referenciados

Validar y considerar:

- `chat.photoFilename`;
- `MessageInfo.mediaFilename`;
- `ContactInfo.photoFilename`.

Cada nombre debe ser un único componente seguro, sin `/`, `\\`, `..`, NUL ni
ruta absoluta. El archivo debe existir y no ser directorio ni enlace simbólico.

### 13.2 SHA-256

- Lectura por bloques, nunca `Data(contentsOf:)` para medios grandes.
- Comprobar cancelación entre bloques.
- Cachear dentro de la preparación por URL estandarizada y firma de archivo.
- No reutilizar una caché si tamaño/modificación cambian.
- Incluir byte count en `CanonicalMediaIdentity`.
- Propagar errores de lectura con URL y `sourceID`.

### 13.3 Cambio de entrada

El plan registra digest lógico de cada fuente. Antes de materializar:

- volver a comprobar documento y firma de medios;
- si cambió cualquier entrada, lanzar `inputChanged`;
- no materializar con los mapeos antiguos.

## 14. Construcción de grupos lógicos

### 14.1 Reunión

Por cada fuente y mensaje, crear:

```swift
struct SourceMessageReference: Codable, Hashable, Sendable {
    let sourceID: ConversationSourceID
    let messageID: Int
}
```

Agrupar todas las referencias con la misma `SamePerspectiveMessageKey`.

### 14.2 Exclusividad

Para cada grupo lógico:

- una fuente presente → un mensaje exclusivo de esa fuente;
- dos o más fuentes presentes → compartido;
- varias apariciones con la misma key dentro de una única fuente requieren una
  política explícita.

La implementación actual colapsa dos apariciones idénticas incluso dentro de una
misma fuente. Para paridad inicial se conserva ese comportamiento, pero el plan
cuenta y emite la razón diagnóstica `duplicateFingerprintWithinSource`. El perfil
contextual permanece separado y no cambia silenciosamente esta semántica.

### 14.3 Representante

Ordenar primero todas las referencias:

1. fecha ascendente;
2. posición de la fuente en el array de entrada;
3. posición original dentro de la fuente.

El primer elemento de un grupo es el representante central, igual que en la
implementación vigente. Las decisiones de metadatos se aplican después.

### 14.4 Orden de grupos

El orden de la conversación es el de los representantes según el criterio
anterior. Asignar enteros `1...n`.

El array de fuentes forma parte de la entrada semántica de esta policy. El perfil
`conservativeCrossPerspective` usa alineación y dispone de cobertura específica
de determinismo N-ario ante cambios de orden de entrada.

## 15. IDs estables y mappings

### 15.1 Elección de `ArchiveMessageID`

Para cada grupo:

1. si la referencia target aporta ID estable, usarlo;
2. si no, usar el ID estable de la primera referencia ordenada;
3. si no existe ninguno, derivar un UUID determinista de la huella lógica;
4. si el mismo ID estable aparece en keys incompatibles, error;
5. si referencias equivalentes traen IDs estables diferentes, elegir según 1/2 y
   devolver los demás como aliases de evidencia.

### 15.2 Mapa de resultado

```swift
public struct ConversationSourceMapping: Codable, Sendable {
    public let sourceID: ConversationSourceID
    public let sourceMessageIDs: [Int: ArchiveMessageID]
}
```

Además, el resultado devuelve:

```swift
public let stableMessageIDsByMaterializedID: [Int: ArchiveMessageID]
```

Free My Chats podrá persistir estos mapas en una fase posterior. Si no los
persiste, la siguiente reconstrucción puede generar nuevos UUID; eso no afecta a
la deduplicación inicial, pero sí limita la estabilidad de lectura futura.

## 16. Remapeo de respuestas

Construir:

```text
(sourceID, source message Int) → ArchiveMessageID → materialized Int
```

Para el representante:

- buscar su `replyTo` dentro de la misma fuente;
- traducir al grupo lógico citado;
- escribir el nuevo entero;
- si no se encuentra, dejar `replyTo == nil` y conservar `replyToPreview`;
- si otras referencias del mismo grupo apuntan a un grupo diferente, registrar
  diagnóstico `inconsistentReplyMetadata`; en esta fase gana el representante;
- no usar `stanzaId`.

La inconsistencia de respuesta no cambia la huella central ni duplica mensajes en
este perfil.

## 17. Política de metadatos

### 17.1 Mensaje

El contenido base procede del representante. Para mantener paridad:

- texto, caption, tipo, fecha, duración, ubicación y warning: representante;
- reacciones: representante;
- autor visible: representante;
- reply: remapeado desde el representante;
- medio: contenido del grupo materializado y nombre reescrito.

No implementar todavía “la fuente más reciente gana” para cada metadato si cambia
la salida vigente. El plan puede registrar diferencias para una política futura.

### 17.2 Chat

Usar la fuente target para:

- `contactJid`;
- nombre;
- `isArchived`;
- avatar si existe.

Usar `targetChatID` para `chat.id`.

Recalcular:

- `numberMessages`;
- `lastMessageDate`;
- `mediaByteCount`.

Free My Chats elige como target la copia guardada local más reciente para mantener
nombre/avatar actualizados y conserva el ID de chat materializado mediante el
parámetro `targetChatID`.

### 17.3 Contactos

Agrupar por identidad telefónica normalizada, compatible con el comportamiento
actual por `phone`.

Orden de preferencia:

1. contacto de la fuente target;
2. contacto de la fuente con `sourceDate` más reciente;
3. primer contacto ordenado.

Materializar la foto del contacto elegido. El orden final de contactos debe ser
determinista por identidad canónica.

## 18. Materialización de multimedia

### 18.1 Directorio de salida

```text
<destinationDirectory>/
├── chat.json
└── Media/
```

El destino debe no existir o estar vacío según el contrato definitivo. La API no
escribe `archive.json`.

### 18.2 Deduplicación

Mantener mapas:

```text
(sourceID, sourceFilename) → destinationFilename
SHA-256 + byteCount         → destinationFilename
```

Reglas:

- mismo contenido/nombres distintos → un archivo;
- mismo nombre/contenidos distintos → nombres distintos;
- nombre destino determinista:
  `<12-hex-hash>-<safe-original-name>`;
- si los 12 caracteres colisionan, ampliar el prefijo o añadir sufijo derivado
  hasta lograr unicidad;
- copia física independiente, no hard link, para que la salida sea autocontenida;
- copiar por streaming y validar byte count/hash;
- comprobar cancelación.

### 18.3 Qué se copia

- medio de cada mensaje representante;
- avatar target elegido;
- foto de cada contacto elegido.

No copiar archivos no referenciados.

### 18.4 `mediaByteCount`

Sumar una vez cada contenido multimedia único referenciado por mensajes. No sumar
avatar de chat ni fotos de contacto, manteniendo la semántica actual de
`ChatInfo.mediaByteCount`.

## 19. Escritura de `chat.json`

- Usar `StoredChatDocument` actual.
- `JSONEncoder.dateEncodingStrategy = .iso8601` mientras sea el contrato v1.
- `.prettyPrinted` y `.sortedKeys` para salida estable.
- Escribir de forma atómica dentro del staging.
- Abrir/decodificar el documento escrito.
- Validar todos sus medios.
- Emitir éxito solo después de esa validación.

SwiftWABackupAPI puede construir `MessageInfo`, `ChatInfo` y `ContactInfo`
directamente dentro del módulo. No debe usar round trip mediante
`JSONSerialization` solo para cambiar campos, como hace hoy Free My Chats por las
restricciones de acceso público.

## 20. Resultado público

```swift
public struct ConversationMaterializationResult {
    public let document: StoredChatDocument
    public let directoryURL: URL
    public let documentURL: URL
    public let mediaDirectoryURL: URL
    public let stableMessageIDsByMaterializedID: [Int: ArchiveMessageID]
    public let sourceMappings: [ConversationSourceMapping]
    public let sourceImpacts: [ConversationSourceImpact]
    public let statistics: ConversationMaterializationStatistics
}
```

La API no debe devolver una salida si el staging no pasa validación completa.

## 21. Estadísticas e impacto

### 21.1 Por fuente

```swift
public struct ConversationSourceImpact: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let sourceMessageCount: Int
    public let exclusiveMessageCount: Int
    public let sharedMessageCount: Int
    public let exclusiveMediaByteCount: Int64
}
```

`sharedMessageCount` cuenta grupos lógicos de esa fuente presentes también en otra.

### 21.2 Globales

```swift
public struct ConversationCompositionStatistics: Codable, Equatable, Sendable {
    public let sourceCount: Int
    public let inputMessageCount: Int
    public let materializedMessageCount: Int
    public let deduplicatedOccurrenceCount: Int
    public let sharedLogicalMessageCount: Int
    public let exclusiveLogicalMessageCount: Int
    public let inputMediaByteCount: Int64
    public let materializedMediaByteCount: Int64
    public let duplicateMediaByteCount: Int64
}
```

Definir con precisión occurrence frente a mensaje lógico en doc comments.

### 21.3 Impacto de retirada

El plan debe calcular sin escribir:

```swift
public func removalImpact(
    of sourceID: ConversationSourceID
) throws -> ConversationRemovalImpact
```

```swift
public struct ConversationRemovalImpact: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let currentMessageCount: Int
    public let sourceMessageCount: Int
    public let removedMessageCount: Int
    public let resultingMessageCount: Int
    public let removedMediaByteCount: Int64
}
```

`removedMessageCount` equivale a los grupos exclusivos de esa fuente. Para obtener
el resultado físico, Free My Chats volverá a analizar/materializar las fuentes
restantes.

## 22. Una sola fuente

El engine debe aceptar una fuente para mantener una semántica completa:

- todos sus mensajes son exclusivos;
- materialized count == source count salvo duplicados internos por huella;
- puede materializar un staging autocontenido;
- target obligatorio es esa fuente;
- no se requiere solapamiento.

Free My Chats seguirá abriendo directamente una única copia guardada y no necesita
crear `MergedChats`; esta capacidad sirve para tests y futuras fuentes portables.

## 23. Determinismo

Con las mismas fuentes, orden, target, policy e IDs estables:

- mismas keys lógicas;
- mismo representante;
- mismo orden de mensajes;
- mismos enteros materializados;
- mismos nombres de medios;
- mismo `chat.json` salvo fecha de materialización si forma parte del contrato;
- mismas estadísticas.

La fecha de salida debe proceder de una entrada/parámetro determinista. No llamar a
`Date()` dentro de `materialize` para un campo que entre en la salida reproducible.
Puede usarse `max(sourceDate)` o un `materializedAt` proporcionado por el cliente.

## 24. Progreso

Añadir fases de `WABackupProgress.Phase` necesarias para este incremento:

- `validatingConversationSources`
- `hashingConversationMedia`
- `canonicalizingConversationMessages`
- `classifyingConversationComposition`
- `materializingConversation`
- `copyingConversationMedia`

Unidades:

- `sources`
- `messages`
- `mediaFiles`
- `bytes` cuando sea viable.

Reglas:

- monotónico por fase;
- no incluir contenido privado en `currentItem`;
- un `.completed` por `analyze`, `materialize` o `compose` superior;
- no `.completed` en error/cancelación;
- `materialize` puede reutilizar hashes de la preparación, pero informa copia y
  validación.

## 25. Cancelación

```swift
public typealias WABackupCancellationHandler = @Sendable () -> Bool
```

Comprobar:

- antes de cada fase;
- durante hashing/copia por bloques;
- por lotes al recorrer mensajes;
- antes de crear/escribir salida;
- antes de devolver éxito.

Lanzar un error reconocible y limpiar solo el staging creado por la llamada. El
análisis cancelado no deja archivos.

## 26. Errores

```swift
public enum ConversationCompositionError: Error, LocalizedError {
    case noSources
    case duplicateSourceID(ConversationSourceID)
    case targetSourceNotFound(ConversationSourceID)
    case invalidSource(sourceID: ConversationSourceID, reason: String)
    case unsupportedCompositionProfile
    case missingSamePerspectiveConstraint([ConversationSourceID])
    case invalidPerspectiveConstraint(reason: String)
    case differentConversations(reason: String)
    case ambiguousConversationIdentity(reason: String)
    case crossPerspectiveCompositionRejected(ConversationCompositionDiagnostic)
    case crossPerspectiveCompositionRequiresReview(ConversationCompositionDiagnostic)
    case incompatibleStableMessageID(ArchiveMessageID)
    case inputChanged(sourceID: ConversationSourceID)
    case destinationNotEmpty(URL)
    case cancelled
    case fileOperation(url: URL, underlying: Error)
    case invalidMaterializedOutput(url: URL, reason: String)
}
```

Requisitos:

- `LocalizedError` en inglés;
- el cliente decide por casos, no parseando strings;
- no incluir textos de chat en errores;
- incluir `sourceID` y URL cuando ayuden;
- conservar error subyacente en I/O;
- distinguir identidad distinta, fuente inválida y cambio posterior al análisis.

## 27. Seguridad de archivos locales

Aunque las fuentes pertenezcan a la biblioteca local, validar:

- nombres de archivo como componente simple;
- ausencia de traversal;
- archivo regular y no symlink;
- URL estandarizada bajo el directorio `Media` de la fuente;
- destino bajo el staging;
- destino vacío;
- tamaños sin overflow;
- no seguir enlaces al copiar;
- no sobrescribir un archivo ya creado con contenido diferente;
- no borrar una ruta que la operación no haya creado.

El perfil inicial no necesita límites ZIP, pero sí debe evitar que un documento
manipulado haga leer o escribir fuera de sus directorios.

## 28. Límite de responsabilidad con Free My Chats

### SwiftWABackupAPI implementa

- validación de fuentes;
- identidad lógica entre documentos aportados;
- huellas, hashes y agrupación;
- plan/estadísticas/impactos;
- documento combinado;
- mappings e IDs estables;
- multimedia combinada;
- validación del staging.

### Free My Chats conserva

- localizar contribuciones en `StoredChats`;
- resolver alias LID del interlocutor y pasarlos como hint cuando sea necesario;
- construir `ConversationSourceID` desde sus contribuciones;
- declarar `.samePerspective`;
- elegir target y `targetChatID`;
- almacenar `ConversationArchiveRecord`;
- escribir `archive.json`;
- decidir cuándo usar directamente una copia guardada única;
- mover/reemplazar `MergedChats` de forma atómica;
- rollback entre manifiestos y carpetas;
- eliminar aportaciones;
- catálogo, UI y posición de lectura.

La API no acepta `LibrarySession`, `VersionChatID` ni tipos de Free My Chats.

## 29. Integración vigente en Free My Chats

Free My Chats 2.0.0 utiliza la API con esta correspondencia:

| Implementación anterior | Uso vigente |
| --- | --- |
| `ResolvedContribution` | construir `[ConversationSource]` |
| `materializedMessageCount` | `plan.statistics.materializedMessageCount` |
| `messageFingerprint` | eliminado; pertenece al engine |
| `authorFingerprintIdentity` | eliminado; pertenece al builder canónico |
| `buildDocument` | `engine.materialize(...)` |
| `MediaMaterializer` | eliminado; pertenece a SwiftWABackupAPI |
| `exclusiveMessageCounts` | `result.sourceImpacts` |
| `removalMessageImpact` | `plan.removalImpact(of:)` |
| `sourceToID` | `result.sourceMappings` |

Flujo implementado:

```swift
let sources = resolvedContributions.map { resolved in
    try ConversationSource(
        id: ConversationSourceID(rawValue: resolved.contribution.id),
        document: resolved.stored.document,
        mediaDirectoryURL: resolved.stored.mediaDirectoryURL,
        conversationIdentityHint: resolved.identityHint,
        stableMessageIDs: resolved.stableMessageIDs
    )
}

let target = sourcesForNewestMetadata.first!
let prepared = try engine.analyze(
    sources: sources,
    targetSourceID: target.id,
    perspectiveConstraints: [
        .samePerspective(sourceIDs: sources.map(\.id))
    ]
)

let result = try engine.materialize(
    prepared,
    targetChatID: existingAggregateChatID,
    destinationDirectory: temporaryMergedURL
)
```

Free My Chats añade su `archive.json` al staging y realiza el movimiento final.

## 30. Archivos implementados en SwiftWABackupAPI

La versión 5.0.0 separa las responsabilidades así:

```text
Sources/SwiftWABackupAPI/
├── ConversationCompositionModels.swift
├── ConversationCompositionDiagnostics.swift
├── ConversationCompositionEngine.swift
├── ConversationSHA256.swift
├── PortableConversationModels.swift
├── PortableConversationArchiveCodec.swift
└── WABackupProgress.swift

Tests/SwiftWABackupAPITests/
├── ConversationCompositionTests.swift
├── CrossPerspectiveConversationDiagnosticsTests.swift
├── CrossPerspectiveConversationMaterializationTests.swift
├── PortableConversationArchiveCodecTests.swift
└── RealLibraryConversationCompositionTests.swift
```

Los modelos, el motor, el diagnóstico, el hashing y el codec portable no se
añaden al archivo monolítico histórico `SwiftWABackupAPI.swift`.

## 31. Implementación realizada

### Paso 1 — modelos y validación — completado

- IDs.
- `ConversationSource` opaco.
- restricciones de perspectiva.
- identidad de grupo/individual.
- validación de documentos y medios.
- errores.

Resultado: fuentes validadas y errores públicos estructurados.

### Paso 2 — análisis puro — completado

- autoría misma perspectiva.
- key exacta.
- hashing streaming.
- agrupación N-aria.
- representantes y orden.
- estadísticas e impactos.
- preparación opaca.

Resultado: plan reproducible y `PreparedConversationComposition` opaco, sin
escritura durante el análisis.

### Paso 3 — documento — completado

- IDs estables.
- enteros materializados.
- replies.
- chat/contactos.
- policy de metadatos.

Resultado: `StoredChatDocument` materializado y mappings públicos.

### Paso 4 — medios y staging — completado

- nombres deterministas.
- copia/deduplicación.
- `chat.json`.
- validación de salida.
- resultado público.

### Paso 5 — progreso, cancelación y documentación — completado

- eventos.
- cancelación y limpieza.
- README/doc comments.
- suite completa.

## 32. Cobertura de pruebas

La suite publicada incluye los casos sintéticos siguientes y una validación
opcional de solo lectura contra la biblioteca real de Free My Chats. En el cierre
de la 5.0.0 se ejecutaron 149 pruebas, sin fallos ni omisiones al habilitar los
fixtures completos y la biblioteca real.

### 32.1 Fuente e identidad

- Fuente válida desde `StoredChat`.
- ID vacío/duplicado.
- Target ausente.
- Restricción que no cubre todas las fuentes.
- Variante de restricción aún no soportada.
- Grupo mismo JID.
- Grupo distinto/nombre igual.
- Individual mismo phoneJID.
- Individual phoneJID/LID con hint común.
- Individual con el mismo LID exacto aceptado.
- Individual phoneJID/LID distintos sin alias común rechazado.
- Tipo grupo/individual mezclado.
- `chat.id` diferentes permitidos.
- contradicción `isFromMe`/author.

### 32.2 Composición de mensajes

- Una fuente.
- Dos fuentes sin solapamiento.
- Dos fuentes idénticas con PK diferentes.
- Solapamiento A B C / B C D.
- Tres fuentes A B / B C / C D.
- Mismo timestamp/texto pero distinta dirección no coincide.
- Mismo contenido con autor participante distinto no coincide.
- LID/phone del mismo autor coincide cuando `phone` está resuelto.
- Texto NFC/NFD coincide según policy.
- CRLF/LF coincide.
- Diferencia de un espacio no coincide.
- Timestamp con un milisegundo de diferencia no coincide.
- Reacciones diferentes no duplican.
- Warning diferente no duplica.
- Caption diferente no coincide.
- Duración/ubicación diferente no coincide.
- Duplicado exacto dentro de una fuente sigue paridad y emite diagnóstico.

### 32.3 Estadísticas

- input occurrence count.
- logical/materialized count.
- shared/exclusive por fuente.
- tres fuentes comparten el mismo mensaje.
- fuente redundante con cero exclusivos.
- removal impact para única, primera, intermedia y última fuente.
- bytes multimedia exclusivos/compartidos.

### 32.4 Orden y determinismo

- Cronología ascendente.
- Empate por orden de fuente.
- Empate por posición original.
- Mismas entradas producen mismo documento lógico.
- `materializedAt`/fecha determinista.
- Cambiar orden de fuentes cambia solo los desempates documentados.

### 32.5 IDs y respuestas

- IDs correlativos.
- Reply de cada fuente remapeado.
- Original deduplicado.
- Original ausente conserva preview.
- Target stable ID preferido.
- Stable ID de otra fuente usado si target no tiene.
- UUID determinista si ninguna fuente aporta uno.
- UUID incompatible en dos keys falla.
- IDs diferentes equivalentes producen alias.
- mappings completos por fuente.

### 32.6 Metadatos y contactos

- Target proporciona nombre/contactJid/archivado/avatar.
- `targetChatID` se aplica.
- Conteo/última fecha/media bytes recalculados.
- Contacto target preferido.
- Fuente reciente completa contacto ausente.
- Foto de contacto reescrita.
- Reacciones/warning del representante según policy.

### 32.7 Multimedia

- Texto sin medios.
- Mismo archivo/nombre igual.
- Mismo archivo/nombres distintos.
- Nombre igual/contenidos distintos.
- Hashing de archivo mayor que un bloque.
- Medio ausente.
- Nombre traversal.
- Symlink rechazado.
- Colisión de prefijo hash gestionada mediante seam/test double si no es viable
  producir SHA-256 real.
- Solo se copian archivos referenciados.
- `mediaByteCount` no suma avatares.
- Copia materializada físicamente independiente.

### 32.8 Staging y consistencia

- Destino no vacío.
- Fallo de escritura no devuelve resultado.
- Salida decodificable.
- Medio de salida ausente detectado.
- Fuente cambia entre analyze/materialize.
- Cancelación en hash, recorrido y copia.
- Limpieza limitada a temporales propios.

### 32.9 Progreso

- Fases esperadas.
- Contadores monotónicos.
- `currentItem` sin contenido.
- `.completed` solo en éxito.

## 33. Traslado de casos desde Free My Chats

Recrear en la suite de SwiftWABackupAPI, sin depender del módulo de la app, los
casos equivalentes a:

- `testCatalogOpensCombinedConversationFromMergedChatsDirectory` en su parte de
  documento combinado;
- `testSuccessiveStoredChatsFromSameOwnerBecomeOneConversation`;
- `testOverlappingMessagesAreNotDuplicatedDuringUpdate`;
- `testStoredContributionCountsReflectCurrentThreeStoredChatConfiguration`;
- `testAuthorLIDChangeDoesNotDuplicateMessages`;
- `testRemovingOlderContributionKeepsTheNewerCompleteConversation`;
- `testRemovingNewerContributionRestoresTheOlderConversation`;
- `testRemovingOneOfThreeContributionsKeepsACombinedConversation`;
- `testIncorporatingASecondBackupReplacesTheMaterializedArchiveAtomically`, solo
  staging/resultado; la instalación sigue en la app;
- `testUpdatingAContributionRebuildsTheExistingCombinedConversation`;
- `testDifferentJIDsRemainSeparateEvenWhenNamesMatch`;
- `testMediaWithSameFilenameAndDifferentContentsRemainDistinct`;
- `testOpenRepairingRebuildsMissingMediaFromContributions`, en cuanto a volver a
  materializar desde las fuentes.

No copiar dependencias de `LibrarySession` ni rutas de biblioteca a la API.

## 34. Documentación publicada

- Doc comments para todos los tipos públicos.
- README con ejemplo de N fuentes de misma perspectiva.
- Documento breve de semántica de `currentUnifiedView`.
- Campos exactos de la huella.
- Diferencia entre ocurrencia y mensaje lógico.
- Política de representante y desempate.
- Semántica de `ConversationSourceImpact` y `ConversationRemovalImpact`.
- Responsabilidad de staging frente a instalación del cliente.
- Limitación explícita: no usar este perfil para fuentes de personas distintas.
- Ruta de evolución al motor general.

## 35. Criterios de aceptación verificados

La versión 5.0.0 cumple:

1. Existe `ConversationSource` público desde `StoredChatDocument` v2.
2. `analyze` acepta N fuentes y exige target.
3. La misma perspectiva se declara sin identidad global de propietario.
4. Grupos/individuales distintos se rechazan por identidad, no por nombre.
5. Hints permiten unir phoneJID/LID del mismo interlocutor.
6. La huella reproduce la semántica lógica actual.
7. Solapamientos exactos no duplican mensajes.
8. Fuentes sin solapamiento se reúnen en este perfil, como hoy.
9. Se calculan estadísticas y exclusividad por fuente.
10. Se calcula impacto de retirada sin escribir.
11. IDs enteros y replies son correctos.
12. Se devuelven UUID estables/mappings.
13. Metadatos target y contactos siguen policy documentada.
14. Multimedia idéntica se almacena una vez.
15. Contenido distinto con igual nombre permanece separado.
16. La salida contiene `chat.json` y `Media` autocontenidos y válidos.
17. La API no escribe `archive.json` ni conoce la biblioteca.
18. Fuentes no cambian durante la operación.
19. Progreso y cancelación están cubiertos.
20. Los casos trasladados de Free My Chats pasan.
21. Una fuente portable validada se adapta al mismo engine mediante
    `PortableConversationDirectory.makeConversationSource`.
22. `swift build` y `swift test` pasan.
23. README y doc comments describen limitaciones.
24. El cambio está publicado en el tag y release `5.0.0`, consumible por Free My
    Chats.

## 36. Decisiones que requieren consulta

El agente no debe decidir silenciosamente:

- usar este perfil para perspectivas diferentes;
- eliminar la restricción explícita de misma perspectiva;
- introducir identidad global del propietario;
- aceptar JID individual distinto sin alias común;
- añadir tolerancia temporal;
- deduplicar con texto relajado;
- usar un LCS o algoritmo cuadrático;
- cambiar qué metadato gana sin pruebas de paridad;
- instalar directamente en `MergedChats`;
- escribir manifiestos de Free My Chats;
- añadir ZIP/dependencias portables en esta entrega;
- cambiar `StoredChatDocument` v2 sin incrementar explícitamente su esquema;
- usar `stanzaId` en la huella.

## 37. Entrega realizada

1. Los pasos 1–5 de la sección 31 están implementados.
2. `swift build` y `swift test` pasan, incluida una compilación de distribución
   con deployment target macOS 13 Ventura.
3. La superficie pública y sus responsabilidades están documentadas.
4. Existe cobertura sintética de rendimiento y casos límite.
5. La paridad se valida en solo lectura contra Vistas unificadas reales.
6. Las ampliaciones `.fmcchat` y entre perspectivas se implementan sobre el mismo
   motor, sin identidad global del propietario.
7. Free My Chats integra ya el perfil local y mantiene la instalación y el
   rollback.
8. SwiftWABackupAPI 5.0.0 está publicada en GitHub.
