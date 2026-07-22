# Especificación para SwiftWABackupAPI: motor general de fusión y conversaciones portables

## 1. Destinatario y propósito

Este documento es el contrato de trabajo para el agente que desarrolla
SwiftWABackupAPI. Define una ampliación general de la API para componer varias
exportaciones de una conversación y, sobre esa misma base, intercambiar
conversaciones mediante archivos `.fmcchat`.

El diseño debe servir para dos casos con un único motor:

1. **Vista unificada actual:** varias exportaciones de copias locales, normalmente
   desde la misma perspectiva, se deduplican y materializan como una conversación.
2. **Importación entre personas:** una exportación creada desde otra perspectiva
   se alinea con la conversación local, se reorienta y se incorpora sin duplicar
   el tramo común.

La especificación parte de SwiftWABackupAPI 4.5.0 y Free My Chats 1.3.10. El
agente debe trabajar en el repositorio real de SwiftWABackupAPI, no en
`.build/checkouts/SwiftWABackupAPI` de Free My Chats.

Documentos de contexto:

- `FreeMyChats/docs/fusion-conversaciones-exportadas.md`
- `FreeMyChats/docs/evaluacion-importacion-conversaciones.md`
- `FreeMyChats/docs/conversaciones-materializadas.md`
- `SwiftWABackupAPI/Docs/JSONContract.md`

Las decisiones de este documento sobre perspectiva e identidad sustituyen las
propuestas anteriores que exigían persistir una identidad global del propietario.

El primer incremento implementable, limitado a las Vistas unificadas locales de
la misma perspectiva, se especifica por separado en
[Composición de Vistas unificadas locales](especificacion-swiftwabackupapi-fusion-local-inicial.md).

## 2. Decisiones vinculantes

1. No se añade a la biblioteca ni al paquete una identidad global obligatoria del
   propietario.
2. Cada documento se trata como una **fuente con perspectiva**: `isFromMe`
   significa “usuario de esta fuente”, no una identidad absoluta universal.
3. El motor debe inferir durante el análisis la relación entre perspectivas.
4. Si la evidencia del contenido no basta, el llamante puede proporcionar una
   identidad o pista de perspectiva como parámetro.
5. La ausencia de una pista no autoriza una conjetura: si no puede orientarse con
   seguridad un mensaje nuevo, el plan no es aplicable.
6. Las funciones centrales deben aceptar N fuentes y ser reutilizables por la
   fusión local actual; `.fmcchat` es solo una forma adicional de obtener una
   fuente.
7. El motor no utiliza `ZSTANZAID` como identidad portable ni criterio principal.
8. El análisis es de solo lectura. La materialización escribe únicamente en un
   staging proporcionado por el cliente.
9. Free My Chats conserva la responsabilidad de instalar, retirar, reconstruir y
   hacer rollback de sus carpetas de biblioteca.
10. Un resultado ambiguo se explica y se rechaza; el MVP no permite forzarlo.

## 3. Objetivos funcionales

SwiftWABackupAPI debe poder:

- convertir `ExportedChatDocument` y `Media` en una fuente validada;
- analizar varias fuentes de la misma conversación;
- inferir si dos fuentes usan la misma perspectiva o perspectivas distintas;
- resolver autores a participantes canónicos cuando haya evidencia;
- detectar la misma conversación en grupos e individuales;
- alinear secuencias con solapamientos parciales;
- clasificar coincidencias, mensajes exclusivos, conflictos y ambigüedades;
- calcular una decisión y razones de confianza;
- materializar un único `ExportedChatDocument` desde la perspectiva de una fuente
  target elegida;
- reasignar IDs y respuestas;
- copiar y deduplicar multimedia por contenido;
- devolver IDs estables y procedencia suficiente para reconstrucción;
- crear, inspeccionar y extraer un `.fmcchat` seguro;
- emitir progreso y admitir cancelación cooperativa;
- ofrecer un diagnóstico CLI sin exponer contenido privado por defecto.

## 4. No objetivos del MVP

- Importar el ZIP/TXT nativo de WhatsApp.
- Escribir en WhatsApp, `ChatStorage.sqlite` o una copia de iPhone.
- Autenticar criptográficamente a quien entrega el archivo.
- Resolver manualmente conflictos mensaje a mensaje.
- Concatenar conversaciones sin solapamiento demostrado.
- Inferir teléfonos por sufijos, nombres de agenda o dígitos de un LID.
- Hacer que SwiftWABackupAPI conozca `library.json`, `Exports`, `Imports` o
  `MergedChats`.
- Mantener el proyecto Python legado.

## 5. Arquitectura general

La implementación se separa en cuatro capas:

```text
ExportedChatDocument / directorio portable
                    │
                    ▼
        ConversationSourceValidator
                    │
                    ▼
       CanonicalConversationBuilder
                    │
                    ▼
        ConversationCompositionEngine
          ├── inferencia de perspectiva
          ├── identidad de conversación
          ├── alineación y confianza
          └── plan/evidencia
                    │
                    ▼
       ConversationMaterializer
          ├── perspectiva target
          ├── IDs y respuestas
          └── multimedia y contactos

PortableConversationArchiveCodec
          ├── crea .fmcchat desde una fuente
          └── valida/extrae .fmcchat como una fuente
```

El codec portable no implementa un segundo alineador. Una vez abierto, un paquete
produce el mismo tipo de `ConversationSource` que una exportación local.

## 6. Superficie pública principal

Los nombres pueden refinarse siguiendo las Swift API Design Guidelines, pero las
capacidades y garantías son obligatorias.

Las conformidades `Sendable` mostradas se aplicarán únicamente cuando todos los
campos almacenados sean valores seguros. `ExportedChatDocument` no declara hoy esa
conformidad, por lo que `ConversationSource` no debe marcarse
`@unchecked Sendable` solo para satisfacer una firma. Se puede añadir `Sendable` a
tipos de valor existentes cuando sea correcto o dejar el wrapper sin conformidad.

```swift
public struct ConversationCompositionEngine {
    public init(policy: ConversationCompositionPolicy = .conservativeDefault)

    public func analyze(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint] = [],
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

El uso para la Vista unificada actual debe ser directo:

```swift
let sources = localExports.map {
    try ConversationSource(
        id: .init(rawValue: $0.contributionID),
        document: $0.exported.document,
        mediaDirectoryURL: $0.exported.mediaDirectoryURL,
        conversationIdentityHint: $0.conversationIdentity,
        perspectiveHint: nil,
        stableMessageIDs: $0.stableMessageIDs
    )
}

let prepared = try engine.analyze(
    sources: sources,
    targetSourceID: sources[0].id,
    perspectiveConstraints: [
        .samePerspective(sourceIDs: sources.map(\.id))
    ]
)

let result = try engine.materialize(
    prepared,
    targetChatID: localExports[0].exported.document.chat.id,
    destinationDirectory: stagingURL
)
```

El uso con un archivo recibido añade otra fuente, no otra lógica:

```swift
let importedDirectory = try archiveCodec.extractValidatedArchive(
    at: packageURL,
    to: importStagingURL
)

let importedSource = try importedDirectory.makeConversationSource(
    id: .init(rawValue: importID),
    perspectiveHint: suppliedHint
)

let prepared = try engine.analyze(
    sources: localSources + storedImportedSources + [importedSource],
    targetSourceID: localTarget.id
)
```

## 7. Fuente general de conversación

### 7.1 Modelo

```swift
public struct ConversationSourceID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
}

public enum ConversationSourceKind: String, Codable, Sendable {
    case exportedDocument
    case portableDocument
}

public struct ConversationSource {
    public let id: ConversationSourceID
    public let kind: ConversationSourceKind
    public let conversationIdentityHint: CanonicalParticipantIdentity?
    public let perspectiveHint: ConversationPerspectiveHint?
    public let sourceDate: Date

    public init(
        id: ConversationSourceID,
        document: ExportedChatDocument,
        mediaDirectoryURL: URL,
        conversationIdentityHint: CanonicalParticipantIdentity? = nil,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        stableMessageIDs: [Int: ArchiveMessageID] = [:]
    ) throws
}
```

El contenido concreto de una fuente es deliberadamente opaco después de
construirla:

- el inicializador público anterior envuelve un `ExportedChatDocument` v1;
- `PortableConversationDirectory.makeConversationSource(...)` crea el mismo tipo
  conservando internamente `PortableMessage.id` y `PortableMessageAuthor.role`;
- ambas variantes convergen en `CanonicalConversationBuilder`;
- no convertir el documento portable a v1 antes de analizar, porque se perderían
  UUID, roles relativos y evidencia;
- no es necesario exponer un enum público con todos los arrays del payload si eso
  permite fabricar una fuente no validada.

Requisitos:

- `id` lo asigna el cliente y es único dentro de la composición.
- No contiene rutas relativas a la biblioteca ni conocimiento de una copia.
- `sourceDate` representa la instantánea lógica para resolver metadatos mutables;
  normalmente `document.exportedAt`.
- `conversationIdentityHint` describe, solo en un chat individual, identidades
  equivalentes del interlocutor (`contactJid`, phoneJID, LID, teléfono) resueltas
  por el cliente; no describe al usuario de la fuente.
- Debe existir un inicializador desde `ExportedChat` y otro desde documento más
  directorio.
- El inicializador valida lo barato; `analyze` ejecuta la validación completa.
- El mapa de IDs estables puede estar vacío en exportaciones antiguas; una fuente
  portable conserva los suyos desde `chat.json`.

### 7.2 Pista opcional de perspectiva

```swift
public struct ConversationPerspectiveHint: Codable, Hashable, Sendable {
    public let participant: CanonicalParticipantIdentity
    public let confidence: HintConfidence
}

public enum HintConfidence: String, Codable, Sendable {
    case derived
    case asserted
}
```

Además de una identidad opcional por fuente, el llamante puede aportar relaciones
que ya conoce entre fuentes:

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
}
```

Constructores cómodos deben incluir:

```swift
.samePerspective(sourceIDs: [...])
.differentPerspectives(_ first: ConversationSourceID, _ second: ConversationSourceID)
.identity(_ participant: CanonicalParticipantIdentity, for sourceID: ConversationSourceID)
```

La Vista unificada actual usará una restricción `.samePerspective` para todas sus
copias locales. Esto expresa una relación conocida por el caso de uso sin
introducir una identidad global del propietario.

No se denomina ni se persiste como “propietario”. Significa únicamente: “el
usuario representado por `isFromMe` en esta fuente parece ser este participante”.

Reglas:

- Es opcional.
- Puede proporcionarse al construir la fuente o justo antes de analizar.
- Una pista contradicha por evidencia fuerte produce conflicto de perspectiva.
- Una pista no convierte dos conversaciones diferentes en la misma.
- La API no necesita hacer público `WhatsAppBackupReader.ownerJid`.
- El cliente puede obtener la pista por sus propios medios o pedirla al usuario.
- Las restricciones relacionales también se validan cuando existe solapamiento;
  una contradicción fuerte produce un error, no se ignora.

### 7.3 Validación de fuente

Antes de analizar:

- `chat.id` coherente con todos los `message.chatId`;
- IDs de mensaje únicos;
- orden cronológico o reordenación controlada con diagnóstico;
- `replyTo` interno o preview conservable;
- nombres multimedia seguros y archivos presentes;
- coordenadas y duraciones válidas;
- `isFromMe` coherente con `MessageAuthor.kind` cuando exista;
- hash de medios calculable;
- `stableMessageIDs` solo para IDs presentes y sin UUID duplicados incompatibles.

## 8. Identidad general de participante

### 8.1 Modelo

```swift
public struct CanonicalParticipantIdentity: Codable, Hashable, Sendable {
    public let addresses: [ParticipantAddress]
}

public struct ParticipantAddress: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case phone
        case phoneJID
        case lidJID
    }

    public let kind: Kind
    public let value: String
}
```

Los nombres visibles no forman parte de la identidad. Si hace falta presentación,
usar un tipo separado.

### 8.2 Normalización

- JID: trim, minúsculas y forma Unicode estable.
- `phoneJID`: `@s.whatsapp.net`, usuario reducido a dígitos.
- `lidJID`: `@lid`; sus dígitos no son un teléfono.
- `phone`: conservar dígitos sin inferir país.
- No comparar por sufijo de teléfono.
- Direcciones vacías o inválidas se descartan; una identidad sin direcciones no
  existe.
- Orden canónico y sin duplicados para JSON y hashing determinista.

### 8.3 Evidencia de equivalencia

Dos identidades pueden relacionarse como:

```swift
public enum ParticipantIdentityRelationship: String, Codable, Sendable {
    case sameExactAddress
    case sameResolvedAlias
    case unknown
    case conflicting
}
```

La relación LID ↔ teléfono solo se acepta si está presente en los datos de la
fuente o se proporciona como alias explícito. Un nombre, push name o foto nunca
basta.

## 9. Autoría relativa a una fuente

El motor canónico no debe convertir inmediatamente `isFromMe` a un propietario
global. Primero expresa la autoría de forma relativa:

```swift
enum SourceRelativeAuthor {
    case sourceUser(identityHint: CanonicalParticipantIdentity?)
    case participant(CanonicalParticipantIdentity)
    case unresolved
}
```

Conversión desde `MessageInfo`:

- `isFromMe == true` → `.sourceUser`; si `MessageAuthor` contiene teléfono/JID,
  usarlo solo como pista de identidad de esa perspectiva.
- `isFromMe == false` + autor resoluble → `.participant`.
- `isFromMe == false` sin autor → `.unresolved`, salvo conversación individual en
  la que `contactJid` resuelva de forma segura al interlocutor.
- Contradicción entre `isFromMe` y `author.kind` → fuente inválida o conflicto
  bloqueante; no elegir uno silenciosamente.
- Aplicar el mismo modelo a reacciones.

Esta representación permite comparar dos mensajes antes de saber quién es el
usuario de cada fuente.

## 10. Inferencia de perspectivas

### 10.1 Problema

En exportaciones de la misma persona, un mensaje propio suele aparecer como:

```text
Fuente A: sourceUser
Fuente B: sourceUser
```

En exportaciones de personas distintas:

```text
Fuente A: sourceUser
Fuente B: participant(A)
```

El motor debe inferir esta relación a partir de muchos mensajes fuertes
provisionalmente coincidentes, no de un único mensaje.

### 10.2 Dos pasadas

#### Pasada 1: candidatos sin identidad completa

Generar candidatos mediante:

- tipo;
- contenido textual/caption conservador;
- hash multimedia;
- timestamp dentro de tolerancia;
- duración/ubicación;
- orden y ventanas contextuales.

La dirección y autor se usan como evidencia, pero una etiqueta `.sourceUser` de
una fuente no se compara todavía como identidad absoluta.

#### Pasada 2: resolver el grafo de perspectivas

Cada candidato fuerte aporta restricciones:

- `sourceUser ↔ sourceUser`: ambas fuentes probablemente representan al mismo
  participante.
- `sourceUser ↔ participant(X)`: la perspectiva de la primera fuente es X.
- `participant(X) ↔ sourceUser`: la perspectiva de la segunda es X.
- `participant(X) ↔ participant(Y)`: X e Y deben ser equivalentes.

Agregar evidencia por fuente, descartar outliers y exigir consistencia. Incorporar
las pistas explícitas. El resultado debe ser un grafo versionado y diagnosticable,
no un conjunto de asignaciones implícitas.

#### Pasada 3: alineación definitiva

Con las relaciones resueltas, recalcular huellas de autor y validar las anclas.
Los candidatos que contradigan el grafo se convierten en conflictos o se eliminan.

### 10.3 Resultado

```swift
public struct SourcePerspectiveResolution: Codable, Sendable {
    public let sourceID: ConversationSourceID
    public let inferredParticipant: CanonicalParticipantIdentity?
    public let relationToTarget: PerspectiveRelationship
    public let evidenceCount: Int
    public let confidence: ConversationCompositionConfidence
    public let reasons: [CompositionReason]
}

public enum PerspectiveRelationship: String, Codable, Sendable {
    case sameAsTarget
    case differentFromTarget
    case unresolved
    case conflicting
}
```

No es imprescindible conocer un teléfono para concluir `sameAsTarget` o
`differentFromTarget` en una conversación individual si el patrón de perspectivas
y el interlocutor son inequívocos.

### 10.4 Política de seguridad

- Una fuente importada con mensajes exclusivos `.sourceUser` necesita relación
  resuelta con la perspectiva target.
- Un mensaje exclusivo de grupo con autor `.unresolved` no puede marcarse
  correctamente como propio/ajeno; debe contabilizarse como bloqueo salvo que el
  tipo se clasifique de forma demostrable como evento sin autor.
- En individuales, la relación binaria entre las dos perspectivas puede orientar
  mensajes aunque no se conozca el teléfono absoluto.
- Una pista proporcionada puede desbloquear la orientación, pero no el requisito
  de solapamiento.

## 11. Identidad y equivalencia de conversación

### 11.1 Grupos

- `chatType == .group` en todas las fuentes.
- JID normalizado terminado en `@g.us`.
- El JID debe coincidir exactamente después de normalizar.
- Un nombre coincidente con JID distinto nunca es suficiente.
- La inferencia de perspectiva se usa para autores, no para sustituir el JID del
  grupo.

### 11.2 Individuales

Una conversación individual no puede identificarse únicamente por
`contactJid`, porque cada participante ve como contacto a la otra persona.

El motor debe aceptar dos casos:

1. **Misma perspectiva:** los `contactJid`/alias identifican al mismo interlocutor
   y los mensajes alineados mantienen el patrón propio/recibido.
2. **Perspectivas opuestas:** el interlocutor de A es compatible con la perspectiva
   inferida de B, el interlocutor de B es compatible con la perspectiva inferida
   de A y los mensajes alineados invierten el patrón.

Si faltan identidades absolutas, el patrón bidireccional puede demostrar una
relación entre las dos perspectivas, pero solo junto a un solapamiento de
contenido fuerte. Dos chats individuales no se consideran iguales solo por tener
dos direcciones complementarias.

### 11.3 Resultado público

```swift
public struct ConversationEquivalence: Codable, Sendable {
    public let chatType: ChatInfo.ChatType
    public let status: ConversationEquivalenceStatus
    public let normalizedGroupJID: String?
    public let perspectiveResolutions: [SourcePerspectiveResolution]
    public let reasons: [CompositionReason]
}

public enum ConversationEquivalenceStatus: String, Codable, Sendable {
    case same
    case different
    case ambiguous
}
```

El nombre visible, `chat.id`, las fechas de exportación y el nombre de archivo no
participan.

## 12. Representación canónica de mensajes

### 12.1 Modelo interno

```swift
struct CanonicalMessage {
    let sourceReference: SourceMessageReference
    let stableID: ArchiveMessageID?
    let dateMilliseconds: Int64
    let relativeAuthor: SourceRelativeAuthor
    let resolvedAuthor: ResolvedCompositionAuthor?
    let type: CanonicalMessageType
    let text: String?
    let caption: String?
    let media: CanonicalMediaIdentity?
    let seconds: Int?
    let location: CanonicalLocation?
}
```

No forman parte de la identidad central:

- PK `MessageInfo.id`;
- `chatId`;
- `isFromMe` en bruto;
- `replyTo` y `replyToPreview`;
- reacciones;
- nombres visibles y fotos;
- advertencias/errores de extracción;
- orden de las fuentes;
- fecha de creación del paquete.

### 12.2 Texto

Normalización fuerte y conservadora:

- Unicode NFC;
- CRLF y CR convertidos a LF;
- conservar mayúsculas, puntuación, emojis, espacios y saltos;
- no aplicar trim, plegado de acentos, stemming, traducción ni comparación
  localizada.

Puede existir una forma débil que normalice espacios para generar candidatos, pero
nunca decide por sí sola una coincidencia definitiva.

### 12.3 Timestamp

- Convertir a milisegundos desde Unix con comprobación de rango.
- No incrustar el timestamp en una huella que impida tolerancia.
- Indexar por contenido/autor y después filtrar por diferencia temporal.
- No aplicar zonas horarias a instantes absolutos.
- Un offset sistemático solo se admite si la política lo permite y muchas anclas
  coherentes lo demuestran.
- El plan debe registrar distribución de deltas y cualquier offset usado.

### 12.4 Multimedia

Identidad central:

```swift
struct CanonicalMediaIdentity: Hashable {
    let algorithm: String   // "sha256"
    let digest: String      // 64 hex minúsculas
    let byteCount: Int64
}
```

El nombre no forma parte. Calcular hashes en streaming y cachearlos dentro de la
operación por URL y firma de archivo. No confiar en una caché previa para validar
entrada externa.

### 12.5 Fuerza de una señal

Clasificar cada mensaje/candidato como:

- `strong`: medio por hash, texto distintivo o combinación rica y única;
- `weak`: texto muy corto/frecuente, emoji aislado, contenido vacío;
- `contextOnly`: autor o contenido insuficiente para ser ancla aislada.

La fuerza debe depender de frecuencia dentro de las secuencias, estructura y
cantidad de información, no de una lista lingüística localizada de palabras.

## 13. Algoritmo de alineación general

### 13.1 Objetivo

Para N fuentes, producir grupos de equivalencia de mensajes y preservar el orden
de una única cronología. Cada mensaje fuente pertenece como máximo a un grupo.

Un grupo de equivalencia representa una aparición lógica y puede contener
referencias de una o varias fuentes.

### 13.2 Alineación por pares y composición N-aria

1. Elegir como eje la fuente target.
2. Alinear cada fuente adicional contra la unión lógica acumulada.
3. Mantener IDs estables de los grupos ya creados.
4. Verificar que una nueva alineación no contradice equivalencias anteriores.
5. Registrar evidencia por par de fuentes.
6. El resultado no debe depender de un orden accidental: definir un orden estable
   de aplicación o comprobar con tests que permutaciones equivalentes producen la
   misma unión lógica.

Para reconstrucción, el cliente puede aportar evidencia persistida. Una evidencia
solo se reutiliza si los digests lógicos de las fuentes coinciden.

### 13.3 Anclas fuertes

1. Calcular firma central sin timestamp rígido.
2. Indexar apariciones por firma.
3. Generar candidatos compatibles dentro de la tolerancia temporal.
4. Seleccionar firmas fuertes únicas o de baja multiplicidad.
5. Ordenar pares por posición de la primera secuencia.
6. Obtener la mayor subsecuencia creciente por posición de la segunda en
   `O(n log n)`.
7. Eliminar cruces y saltos incompatibles.

No ejecutar un LCS `O(n*m)` sobre chats completos.

### 13.4 Ventanas de contexto

Para mensajes débiles usar ventanas de 3 a 5 mensajes. La firma de ventana incluye:

- tipos;
- contenido central;
- patrón de autoría relativa/resuelta;
- deltas temporales relativos;
- orden.

Una ventana puede dar contexto a `Sí` o un emoji, pero un elemento repetitivo no
se convierte por ello en ancla aislada.

### 13.5 Expansión e intervalos

Desde las anclas ordenadas:

- expandir coincidencias exactas a ambos lados;
- analizar intervalos entre anclas;
- permitir inserciones en cualquiera de las fuentes;
- conservar múltiples posibilidades como región ambigua;
- no emparejar solo por cercanía temporal;
- detectar probable mismo evento con contenido central diferente como conflicto.

### 13.6 Prefijos y sufijos

Caso principal:

```text
Target:                 C D E F
Import:     A B C D E F
Resultado: A B C D E F
```

El prefijo A B se acepta como exclusivo si C D E F constituye solapamiento
suficiente, ordenado y coherente. Lo mismo aplica a un sufijo. Dos secuencias
completamente disjuntas no se concatenan por JID y fecha.

### 13.7 IDs estables existentes

Si dos fuentes contienen el mismo `ArchiveMessageID`:

- es evidencia fuerte;
- se valida igualmente el contenido central;
- el mismo UUID con contenido incompatible es conflicto grave;
- no se confía en UUID de un paquete no validado.

### 13.8 Complejidad

Objetivos:

- tiempo `O(totalMessages log totalMessages + totalMediaBytes)` en el caso normal;
- memoria `O(totalMessages)` con estructuras compactas;
- hashing en streaming;
- muestras de conflicto acotadas, conteos exactos;
- sin copia repetida de textos o blobs grandes en todas las capas.

## 14. Plan de composición

### 14.1 Preparación opaca y resumen público

```swift
public struct PreparedConversationComposition {
    public let plan: ConversationCompositionPlan
    // Mapeos completos y firmas de entrada permanecen internos.
}

public struct ConversationCompositionPlan: Codable, Sendable {
    public let schemaVersion: Int
    public let algorithmVersion: Int
    public let targetSourceID: ConversationSourceID
    public let sourceDigests: [ConversationSourceDigest]
    public let equivalence: ConversationEquivalence
    public let perspectives: [SourcePerspectiveResolution]
    public let statistics: ConversationCompositionStatistics
    public let confidence: ConversationCompositionConfidence
    public let disposition: ConversationCompositionDisposition
    public let reasons: [CompositionReason]
    public let conflictSamples: [MessageConflictSummary]
    public let ambiguousRegionSamples: [AmbiguousRegionSummary]
    public let additionalMediaByteCount: Int64
}
```

El cliente no puede modificar los mapeos internos de una preparación y luego
pedir que se materialicen como si hubieran sido aprobados.

### 14.2 Estadísticas mínimas

Por fuente y globales:

- mensajes totales;
- grupos lógicos resultantes;
- mensajes compartidos;
- mensajes exclusivos;
- conflictos;
- mensajes/regiones ambiguas;
- anclas fuertes;
- ventanas coincidentes;
- cobertura de mensajes y cobertura temporal;
- consistencia de orden;
- autores resueltos y no resueltos;
- relaciones de perspectiva resueltas/no resueltas;
- delta temporal mínimo, máximo, mediano y percentil alto;
- medios compartidos/nuevos y bytes adicionales;
- mensajes que no se pueden orientar respecto al target.

### 14.3 Confianza y disposición

```swift
public enum ConversationCompositionConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public enum ConversationCompositionDisposition: String, Codable, Sendable {
    case applicable
    case needsReview
    case rejected
}
```

Política del MVP:

- alta, conversación demostrada, perspectivas necesarias resueltas, cero
  conflictos y cero ambigüedad bloqueante → `applicable`;
- media → `needsReview`, pero no aplicable en Free My Chats;
- baja, conversación distinta, secuencias disjuntas o perspectiva necesaria no
  resuelta → `rejected`;
- conflicto central → no aplicable.

Una puntuación numérica puede ayudar al diagnóstico, pero no sustituye reglas y
razones versionadas.

### 14.4 Política configurable

```swift
public struct ConversationCompositionPolicy: Codable, Sendable {
    public var maximumTimestampDifferenceMilliseconds: Int64
    public var minimumStrongAnchorCount: Int
    public var minimumMatchedWindowCount: Int
    public var minimumOverlapMessageCount: Int
    public var minimumOrderConsistency: Double
    public var maximumUnresolvedAuthorFraction: Double
    public var requireOrientableExclusiveMessages: Bool
    public var allowSystematicTimestampOffset: Bool
}
```

Debe existir `.conservativeDefault`. Los valores finales se calibran con la Fase
0. Los tests pequeños usan una política explícita en lugar de debilitar el default.

### 14.5 Privacidad del plan

Por defecto los diagnósticos contienen IDs, índices, fechas, tipos y hashes
truncados, no texto, nombres ni teléfonos completos. El contenido solo aparece con
una opción de depuración explícita y nunca en errores/CLI por defecto.

## 15. Huellas y deduplicación en la Vista unificada actual

El nuevo motor debe poder sustituir la lógica actual de
`ConversationArchiveService.messageFingerprint` sin perder comportamiento.

Para fuentes de la misma perspectiva:

- `sourceUser` de ambas fuentes se considera compatible;
- participantes se comparan por identidad normalizada;
- timestamp, tipo, texto/caption, medio, duración y ubicación forman la señal
  central;
- la alineación contextual complementa la huella exacta;
- se conservan contadores de mensajes exclusivos por `sourceID`;
- se devuelve un mapa de referencias para reescribir respuestas;
- la deduplicación de medios continúa siendo por SHA-256.

La migración debe incluir tests de paridad con todos los casos actuales de Free My
Chats: actualizaciones solapadas, LID/JID, tres aportaciones, retirada, respuesta,
medios con nombres iguales y reparación.

### 15.1 Operaciones que debe poder sustituir

El plan o resultado debe exponer helpers de dominio para que Free My Chats no
reimplemente cálculos:

```swift
public struct ConversationSourceImpact: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let sourceMessageCount: Int
    public let exclusiveMessageCount: Int
    public let sharedMessageCount: Int
    public let exclusiveMediaByteCount: Int64
}

public struct ConversationRemovalImpact: Codable, Equatable, Sendable {
    public let sourceID: ConversationSourceID
    public let currentMessageCount: Int
    public let resultingMessageCount: Int
    public let removedMessageCount: Int
    public let removedMediaByteCount: Int64
}
```

Capacidades requeridas:

- conteo materializado sin escribir;
- impacto de añadir una fuente;
- impacto de retirar una fuente;
- exclusividad por fuente;
- reanálisis cuando cambia el digest de una fuente;
- rematerialización desde evidencia válida;
- reparación de una salida derivada dañada a partir de las fuentes.

Correspondencia con la implementación actual:

| Free My Chats actual | Nueva capacidad de SwiftWABackupAPI |
| --- | --- |
| `messageFingerprint` | canonización y firma central del engine |
| `materializedMessageCount` | estadísticas del plan |
| `buildDocument` | `materialize` |
| `MediaMaterializer` | materializador de medios del engine |
| `removalMessageImpact` | helper de impacto del plan/evidencia |
| mapa `sourceToID` | `sourceMappings` + `ArchiveMessageID` |
| reconstrucción/reparación | rematerialización desde fuentes validadas |

Free My Chats seguirá gestionando manifiestos y movimientos atómicos, pero no
mantendrá una segunda definición de huella o de correspondencia de mensajes.

## 16. Conflictos y metadatos mutables

### 16.1 Conflicto central bloqueante

- autor resuelto incompatible;
- tipo incompatible en la misma posición lógica;
- texto/caption normalizado distinto;
- ambos medios presentes con hash distinto;
- ubicación incompatible;
- duración semánticamente incompatible;
- mismo ID estable con contenido central diferente;
- relación de perspectiva contradictoria.

### 16.2 Diferencia no central

- reacciones;
- nombre visible;
- foto;
- `replyToPreview`;
- warning/error de extracción;
- estado archivado;
- fecha de exportación.

Estas diferencias no crean otro mensaje por sí solas.

### 16.3 Política inicial

Para un mensaje coincidente:

- conservar contenido central validado;
- preferir fecha target si está dentro de tolerancia;
- para metadatos de mensaje, preferir la instantánea `sourceDate` más reciente;
- nombres/contactos target primero, importación completa ausencias;
- reacciones: preferir instantánea completa más reciente, no unión ciega;
- warnings solo si siguen siendo relevantes al medio materializado;
- toda regla debe ser determinista y estar cubierta por tests.

## 17. Respuestas

Construir mapas:

```text
(sourceID, sourceMessageID) → ArchiveMessageID → materialized Int
```

Reglas:

- mensajes alineados comparten `ArchiveMessageID`;
- mensajes exclusivos reutilizan ID estable o reciben uno;
- `replyTo` se traduce primero a ID estable y después a entero;
- respuestas incompatibles entre representantes generan diagnóstico/conflicto;
- original ausente → `replyTo == nil`, conservar mejor preview;
- no usar `stanzaId` para correspondencia entre fuentes.

## 18. Materialización general

### 18.1 Resultado

```swift
public struct ConversationMaterializationResult {
    public let document: ExportedChatDocument
    public let directoryURL: URL
    public let documentURL: URL
    public let mediaDirectoryURL: URL
    public let stableMessageIDsByMaterializedID: [Int: ArchiveMessageID]
    public let sourceMappings: [ConversationSourceMapping]
    public let exclusiveMessageCounts: [ConversationSourceID: Int]
    public let statistics: ConversationMaterializationStatistics
}
```

### 18.2 Perspectiva de salida

La salida se orienta respecto a `targetSourceID`, no a una identidad global:

- mensaje perteneciente a la perspectiva target → `isFromMe = true`;
- participante diferente → `false`;
- en individual con perspectivas opuestas, transformar roles de forma binaria;
- en grupo, usar el grafo de identidades/perspectivas;
- autor no resoluble que podría ser target bloquea si el mensaje es exclusivo;
- `MessageAuthor.kind` debe concordar con `isFromMe`;
- los mensajes ya presentes en target conservan su orientación.

### 18.3 Orden e IDs

- cronología ascendente;
- empates resueltos por orden lógico de alineación y después criterio estable;
- IDs enteros correlativos compatibles con `ExportedChatDocument`;
- mapa completo entero ↔ `ArchiveMessageID`;
- estabilidad lógica entre reconstrucciones mediante IDs estables, no mediante el
  entero materializado.

### 18.4 Metadatos de chat

- `chat.id`: parámetro `targetChatID`;
- `contactJid`, nombre, archivado y avatar: fuente target;
- `numberMessages`, `lastMessageDate` y `mediaByteCount`: recalculados;
- no copiar el `contactJid` del remitente en individuales;
- contactos agrupados por identidad, con presentación target preferida.

### 18.5 Multimedia

- copiar solo referencias resultantes;
- hash y copia en streaming;
- una copia por contenido idéntico;
- nombres diferentes/datos iguales → una copia;
- nombre igual/datos diferentes → nombres deterministas distintos;
- verificar tamaño/hash durante o después de copiar;
- salida completa validada antes de éxito.

### 18.6 Staging

- El destino debe no existir o estar vacío según contrato explícito.
- La API no reemplaza `MergedChats` ni borra fuentes.
- Escribe solo dentro del staging.
- Limpia únicamente staging creado por la propia llamada al fallar/cancelar.
- Valida `chat.json` y `Media` antes de devolver resultado.

## 19. Evidencia persistible y reconstrucción

Free My Chats debe poder retirar una aportación y reconstruir. La API devolverá
modelos `Codable` versionados con:

- digest lógico de cada fuente;
- versión de algoritmo y política;
- `ArchiveMessageID` por referencia fuente;
- grupos de equivalencia aprobados;
- relación de perspectiva entre fuentes;
- procedencia y exclusividad;
- hashes de medios usados.

No incluir URLs absolutas. Si cambia el digest de una fuente, su evidencia se
invalida y debe realinearse.

La API debe aceptar evidencia previa como optimización/estabilidad, pero volver a
validar contenido central. Nunca usar evidencia de otro digest.

## 20. Formato `.fmcchat` v1

### 20.1 Principio

El paquete conserva la perspectiva de su documento. No contiene un campo
obligatorio `sourceOwner` ni una identidad global del propietario.

La autoría portable se expresa como:

```swift
public struct PortableMessageAuthor: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case sourceUser
        case participant
        case unresolved
    }

    public let role: Role
    public let identityHint: CanonicalParticipantIdentity?
    public let displayName: String?
}
```

Durante la importación el motor resuelve esta perspectiva contra el target. El
llamante puede aportar `ConversationPerspectiveHint` si hace falta.

### 20.2 Contenedor

```text
Conversacion.fmcchat
├── manifest.json
├── chat.json
└── Media/
    └── <nombre-seguro>
```

ZIP sin carpeta envolvente. Archivos permitidos únicamente en esas rutas; no hay
subdirectorios bajo `Media` en v1.

### 20.3 Manifiesto

```swift
public struct PortableConversationManifest: Codable, Sendable {
    public static let currentSchemaVersion = 1

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

Tipos auxiliares mínimos:

```swift
public struct PortableArchiveProducer: Codable, Hashable, Sendable {
    public let name: String
    public let version: String
}

public struct PortableArchiveImplementation: Codable, Hashable, Sendable {
    public let name: String                 // "SwiftWABackupAPI"
    public let formatVersion: Int           // 1
    public let algorithmVersion: Int
}

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

Invariantes de `PortableConversationDescriptor`:

- grupo: `groupJID` obligatorio y `contactJID/contactIdentity` ausentes;
- individual: `groupJID` ausente y al menos `contactJID` o `contactIdentity`;
- `displayName`, `isArchived`, `exportedAt` y `photoPath` son presentación;
- el descriptor representa la vista de la fuente y no pretende contener el par
  absoluto de participantes antes de inferir perspectivas.

Ejemplo abreviado de manifiesto sin propietario global:

```json
{
  "schemaVersion": 1,
  "format": "com.domingogallardo.freemychats.portable-conversation",
  "packageID": "5c7fa727-91c4-4ed1-8cc2-1a5e37286426",
  "createdAt": "2026-07-22T10:15:30.000Z",
  "producer": {
    "name": "Free My Chats",
    "version": "1.4.0"
  },
  "implementation": {
    "name": "SwiftWABackupAPI",
    "formatVersion": 1,
    "algorithmVersion": 1
  },
  "conversation": {
    "chatType": "group",
    "groupJID": "1234567890-123456789@g.us",
    "displayName": "Familia",
    "isArchived": false,
    "exportedAt": "2026-07-22T10:14:00.000Z"
  },
  "messageCount": 1842,
  "firstMessageAt": "2017-02-03T08:00:00.000Z",
  "lastMessageAt": "2026-07-20T22:11:10.000Z",
  "document": {
    "path": "chat.json",
    "byteCount": 1248302,
    "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  },
  "media": [],
  "contentDigest": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
}
```

No incluir `sourceOwner`. `PortableConversationDescriptor` contiene:

- tipo;
- JID de grupo normalizado si es grupo;
- `contactJid`/identidad del interlocutor desde la perspectiva fuente si es
  individual;
- nombre visible solo como presentación.

### 20.4 Documento portable

```swift
public struct PortableConversationDocument: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let conversation: PortableConversationDescriptor
    public let messages: [PortableMessage]
    public let contacts: [PortableContact]
}

public struct PortableMessage: Codable, Sendable {
    public let id: ArchiveMessageID
    public let date: Date
    public let author: PortableMessageAuthor
    public let messageType: String
    public let text: String?
    public let caption: String?
    public let mediaPath: String?
    public let replyTo: ArchiveMessageID?
    public let replyToPreview: String?
    public let reactions: [PortableReaction]?
    public let warning: String?
    public let seconds: Int?
    public let latitude: Double?
    public let longitude: Double?
}
```

Modelos auxiliares:

```swift
public struct PortableContact: Codable, Sendable {
    public let identity: CanonicalParticipantIdentity
    public let displayName: String
    public let photoPath: String?
}

public struct PortableReaction: Codable, Sendable {
    public let emoji: String
    public let author: PortableMessageAuthor
}

public struct PortableMediaEntry: Codable, Hashable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String
}
```

`PortableConversationArchiveInfo` es el resumen seguro devuelto tras validar:

```swift
public struct PortableConversationArchiveInfo: Codable, Sendable {
    public let archiveURL: URL
    public let manifest: PortableConversationManifest
    public let archiveByteCount: Int64
    public let uncompressedByteCount: Int64
    public let archiveSHA256: String
}
```

La URL puede excluirse de la codificación persistente o representarse por separado
si se quiere que el resumen JSON sea portable; no debe entrar en digests.

No exportar PK SQLite, `chatId` ni `stanzaId`. La perspectiva relativa se conserva
mediante `author.role`, no mediante una identidad global.

### 20.5 IDs portables

```swift
public struct ArchiveMessageID: Codable, Hashable, Sendable {
    public let rawValue: UUID
}
```

- Reutilizar ID estable proporcionado por el cliente.
- Si no existe, generar uno al crear el paquete.
- Dos paquetes independientes no tienen por qué usar el mismo UUID.
- `replyTo` solo referencia IDs del documento.

### 20.6 Fechas y JSON

- UTC RFC 3339 con milisegundos fijos.
- JSON UTF-8.
- Claves ordenadas para fixtures/digests reproducibles.
- Arrays con orden canónico donde el orden no sea semántico.
- Mensajes en orden cronológico y estable.

## 21. Digest e integridad del paquete

### 21.1 Entradas

```swift
public struct PortableFileEntry: Codable, Hashable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String
}
```

`PortableMediaEntry` puede reutilizar esta forma o añadir el tipo lógico. Todos
los hashes son SHA-256 hexadecimal en minúsculas.

### 21.2 Digest lógico

No usar el hash de bytes ZIP como identidad lógica, porque compresión y metadatos
pueden cambiar. `contentDigest` se calcula a partir de:

1. versión de formato;
2. descriptor canónico de conversación;
3. tamaño y SHA-256 de `chat.json`;
4. por cada medio ordenado por ruta: ruta UTF-8 NFC, tamaño y SHA-256.

Documentar exactamente la serialización binaria o textual y sus separadores. El
manifiesto no entra completo en su propio digest. La API puede devolver además el
SHA-256 del ZIP final para detectar repetición byte a byte.

Los hashes certifican integridad interna, no autenticidad de la persona que creó
el archivo.

## 22. Codec portable público

```swift
public struct PortableConversationArchiveCodec {
    public init(limits: PortableArchiveLimits = .default)

    public func createArchive(
        from source: ConversationSource,
        producer: PortableArchiveProducer,
        destinationURL: URL,
        overwriteExisting: Bool = false,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo

    public func inspectArchive(
        at archiveURL: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationArchiveInfo

    public func extractValidatedArchive(
        at archiveURL: URL,
        to destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> PortableConversationDirectory

    public func openValidatedDirectory(
        at directoryURL: URL
    ) throws -> PortableConversationDirectory
}
```

`PortableConversationDirectory` tendrá inicializador no público y expondrá un
método para crear `ConversationSource`. Así el cliente no puede declarar validado
un directorio arbitrario.

### 22.1 Creación

1. Validar fuente.
2. Convertir autoría a roles portables.
3. Copiar solo medios referenciados.
4. Calcular hashes en streaming y deduplicar por contenido.
5. Escribir directorio canónico temporal.
6. Validarlo con el mismo validador de importación.
7. Crear ZIP temporal junto al destino.
8. Cerrar y volver a inspeccionar el ZIP.
9. Instalar/mover al destino únicamente al final.
10. Limpiar temporales propios.

No requiere copia de iPhone ni `WhatsAppBackupReader` abierto.

### 22.2 Conversación ya materializada

Free My Chats puede pasar un `ExportedChatDocument` de `MergedChats` y su `Media`.
El paquete representa esa conversación visible como una fuente única. No incluye
las capas internas ni el historial de aportaciones.

### 22.3 Nombres de medios

Usar nombres seguros y deterministas, por ejemplo
`<12-hex-hash>-<nombre-saneado>`. Contenido idéntico usa una entrada; contenido
distinto nunca comparte ruta aunque el nombre original coincida.

## 23. Seguridad ZIP

### 23.1 Dependencia y plataforma

La solución debe inspeccionar el directorio central y extraer en streaming. La
biblioteca no debe invocar `ditto`, `zip` o `unzip` como procesos.

Si se añade una dependencia:

- encapsularla tras el codec;
- fijar versión compatible con Swift 5.8;
- actualizar `Package.swift` y `Package.resolved`;
- conservar la matriz de plataformas actual o documentar la decisión antes de
  romperla;
- cubrir sus casos límites con tests propios.

### 23.2 Límites

```swift
public struct PortableArchiveLimits: Sendable {
    public var maximumArchiveByteCount: Int64
    public var maximumUncompressedByteCount: Int64
    public var maximumEntryByteCount: Int64
    public var maximumJSONByteCount: Int64
    public var maximumEntryCount: Int
    public var maximumCompressionRatio: Double
    public var maximumPathUTF8ByteCount: Int
}
```

Defaults orientativos, que deben mantenerse configurables:

- ZIP: 100 GB;
- total descomprimido: 250 GB;
- entrada: 50 GB;
- JSON: 2 GB;
- entradas: 200.000;
- ratio: 200:1;
- ruta UTF-8: 512 bytes.

Comprobar overflow al sumar tamaños. Prever capacidad libre antes de extraer y
devolver requisito estimado cuando sea posible.

### 23.3 Rechazos estructurales

- ZIP corrupto, truncado, cifrado o multidisco.
- Ruta absoluta, `..`, `.`, componente vacío, NUL, barra invertida, letra de
  unidad o escape tras estandarizar.
- Symlink, hard link, dispositivo u otro tipo especial.
- Duplicados exactos, tras Unicode NFC o sin distinguir mayúsculas/minúsculas.
- `__MACOSX`, archivos ocultos o cualquier entrada extra no definida por v1.
- Subdirectorios dentro de `Media`.
- Número/tamaño/ratio fuera de límite.
- Nombre de medio no seguro.

### 23.4 Validación de contenido

- Leer y limitar `manifest.json` primero.
- Formato/schema soportado.
- `chat.json` declarado, tamaño y hash reales.
- Cada medio declarado existe y coincide.
- Ningún medio extra.
- Referencias del documento declaradas.
- Conteos, fechas y descriptor coherentes.
- IDs portables únicos y replies internos.
- Coordenadas finitas y dentro de rango.
- Duración/tamaño no negativos.
- JSON UTF-8, sin profundidad patológica.
- `contentDigest` correcto.

### 23.5 Extracción

- Destino vacío o inexistente según contrato.
- Creación exclusiva de archivos.
- Cada URL estandarizada permanece bajo staging.
- No seguir enlaces.
- Hash/tamaño comprobados mientras se escribe.
- Cancelación elimina únicamente staging creado por la llamada.
- No considerar válida una extracción parcial.

## 24. Consistencia de entradas y atomicidad

El análisis debe capturar para cada fuente:

- digest lógico de documento y medios;
- tamaño/fecha de modificación como optimización;
- versión de schema;
- IDs estables suministrados.

Antes de materializar, volver a comprobar las firmas. Si cambia una entrada,
lanzar `inputChanged` y exigir nuevo análisis.

Garantías:

- `analyze` no escribe;
- `materialize` no modifica fuentes;
- el codec crea temporales y mueve el archivo final al terminar;
- la materialización escribe solo staging;
- ninguna API borra exportaciones/importaciones del cliente;
- `.completed` se emite después de validar salida;
- la transacción entre carpetas de Free My Chats queda fuera de la API.

## 25. Progreso y cancelación

### 25.1 Cancelación

```swift
public typealias WABackupCancellationHandler = @Sendable () -> Bool
```

Comprobar:

- antes de cada fase;
- por bloques durante hashing/copia;
- por lotes durante canonización/alineación;
- antes de escribir resultados;
- antes de devolver éxito.

Lanzar un error público reconocible y limpiar temporales propios.

### 25.2 Fases nuevas

Ampliar `WABackupProgress.Phase` con equivalentes estables a:

- `validatingConversationSources`
- `hashingConversationMedia`
- `canonicalizingConversationMessages`
- `inferringConversationPerspectives`
- `aligningConversationMessages`
- `classifyingConversationComposition`
- `materializingConversation`
- `copyingConversationMedia`
- `validatingPortableArchive`
- `writingPortableArchive`
- `extractingPortableArchive`

Unidades nuevas si hacen falta:

- `bytes`
- `anchors`
- `archiveEntries`
- `sources`

Reglas:

- contadores monotónicos;
- total `nil` si se desconoce;
- no incluir texto/nombres/teléfonos en `currentItem`;
- un `.completed` por operación pública superior;
- no emitir `.completed` en error/cancelación.

## 26. Errores públicos

Crear un dominio estructurado, por ejemplo:

```swift
public enum ConversationCompositionError: Error, LocalizedError {
    case invalidSource(sourceID: ConversationSourceID, reason: String)
    case duplicateSourceID(ConversationSourceID)
    case targetSourceNotFound(ConversationSourceID)
    case differentConversations(ConversationCompositionPlan)
    case unresolvedPerspective(ConversationCompositionPlan)
    case conflictingPerspective(ConversationCompositionPlan)
    case insufficientOverlap(ConversationCompositionPlan)
    case conflictsDetected(ConversationCompositionPlan)
    case ambiguousAlignment(ConversationCompositionPlan)
    case invalidPreparation(reason: String)
    case inputChanged(URL)
    case destinationNotEmpty(URL)
    case cancelled
    case fileOperation(url: URL, underlying: Error)
}

public enum PortableConversationArchiveError: Error, LocalizedError {
    case unsupportedSchema(found: Int, supported: ClosedRange<Int>)
    case invalidFormat(String)
    case unsafeEntry(path: String, reason: String)
    case duplicateEntry(path: String)
    case missingEntry(path: String)
    case resourceLimitExceeded(limit: PortableArchiveLimit, actual: Int64)
    case hashMismatch(path: String)
    case contentDigestMismatch
    case inputChanged(URL)
    case destinationNotEmpty(URL)
    case cancelled
    case fileOperation(url: URL, underlying: Error)
}
```

Requisitos:

- `LocalizedError` en inglés, coherente con el paquete;
- casos estructurados para UI, no parsear strings;
- no incluir contenido privado por defecto;
- distinguir conversación diferente, perspectiva no resuelta, falta de
  solapamiento, conflicto y archivo inválido;
- conservar error subyacente en I/O.

## 27. Herramienta diagnóstica de Fase 0

Antes de fijar schema ZIP y umbrales, añadir una orden CLI de solo lectura:

```text
swift run SwiftWABackupCLI diagnose-conversation-composition \
  --target-chat-dir /ruta/A/Chats/44 \
  --source-chat-dir /ruta/B/Chats/90 \
  --target-perspective-jid 34600000000@s.whatsapp.net \
  --source-perspective-jid 34611111111@s.whatsapp.net \
  --output-json /tmp/composition-diagnostic.json \
  --pretty
```

Las pistas de perspectiva son opcionales. El comando debe poder ejecutarse sin
ellas para evaluar la inferencia.

Requisitos:

- aceptar `chat.json` + `Media` v1;
- ninguna escritura en entradas;
- salida sin texto por defecto;
- incluir autores resolubles, relaciones de perspectiva, timestamps, anclas,
  ventanas, orden, cobertura, ambigüedad y conflictos;
- un plan no aplicable es salida diagnóstica válida, no fallo técnico;
- ayuda y tests de parser siguiendo el CLI actual;
- permitir más de `--source-chat-dir` para probar N fuentes.

Ejecutar localmente con:

1. dos copias locales de la misma perspectiva;
2. dos propietarios del mismo grupo;
3. dos perspectivas de un individual;
4. chats distintos con igual nombre.

El informe anonimizado debe responder:

- distribución de diferencias temporales;
- porcentaje de autores resolubles;
- calidad de inferencia con/sin pistas;
- frecuencia de LID no resolubles;
- densidad de anclas;
- comportamiento de mensajes repetitivos;
- cobertura temporal;
- tipos de contenido que difieren.

No añadir chats privados al repositorio.

## 28. Plan de implementación

### Incremento inicial — composición local y paridad con FreeMyChats

Este es el primer incremento que debe implementarse. Su contrato detallado está
en
[`especificacion-swiftwabackupapi-fusion-local-inicial.md`](especificacion-swiftwabackupapi-fusion-local-inicial.md).

- Extraer a SwiftWABackupAPI la composición N-aria que hoy construye la Vista
  unificada de FreeMyChats.
- Trabajar con `ExportedChatDocument` v1 y fuentes de la misma perspectiva,
  declaradas mediante una restricción relacional explícita.
- Incluir validación, canonización, deduplicación exacta, orden, atribución por
  fuente, impacto de retirada, reconstrucción de IDs/replies, contactos,
  multimedia, materialización en staging, progreso y cancelación.
- Integrar FreeMyChats como cliente: la aplicación conserva instalación,
  persistencia de su biblioteca y transacción/rollback.
- Alcanzar paridad funcional y determinismo mediante fixtures extraídos de la
  suite actual.

Este incremento no infiere todavía perspectivas, no crea `.fmcchat` y no
introduce identidad global del propietario. La relación `samePerspective` es
un dato de la operación, no una identidad persistida.

### Fase 0 de la evolución portable — núcleo diagnóstico

- `ConversationSource`.
- Canonización relativa.
- Firmas de contenido y hash de medios.
- Inferencia de perspectivas.
- Alineación inicial y plan diagnóstico.
- CLI y fixtures sintéticos.
- Informe real anonimizado y propuesta de policy.

No diseñar todavía el ZIP definitivo si la evidencia contradice el enfoque.

### Fase 1 — ampliación del motor general

- Ampliar la API pública N-aria ya validada en el incremento inicial.
- Añadir plan, evidencia y confianza para relaciones no declaradas.
- Generalizar canonización, alineación y materialización entre perspectivas.
- Conservar compatibilidad con los casos de Vista unificada y sus fixtures.
- Añadir los nuevos errores y resultados diagnósticos sin duplicar motores.

### Fase 2 — contrato portable

- Modelos JSON v1.
- Directorio canónico.
- Codec ZIP seguro.
- Creación/inspección/extracción.
- Fixtures maliciosos y documentación.

### Fase 3 — integración entre perspectivas

- Importación como fuente portable.
- Pistas opcionales.
- Orientación target completa.
- Varias importaciones y reconstrucción.
- Evidencia persistible.

### Fase 4 — endurecimiento y release

- Rendimiento/memoria.
- Cancelación/progreso.
- Matriz de plataformas.
- README, contrato JSON, seguridad y release notes.
- `swift build` y `swift test`.
- tag consumible por Free My Chats.

## 29. Pruebas obligatorias

### 29.1 Paridad con fusión local actual

- Una única fuente produce conversación equivalente.
- Dos exportaciones sucesivas de la misma perspectiva.
- Solapamiento sin duplicados.
- Tres aportaciones y conteos exclusivos.
- LID/JID de un participante cambian entre copias.
- Distintos JID/nombre igual permanecen separados.
- Respuestas remapeadas.
- Mismo nombre de medio con datos distintos.
- Mismo medio con nombres distintos.
- Reconstrucción sin una fuente.
- Orden determinista en empates.
- Resultado abrible por `ExportedChatDocument`.

### 29.2 Inferencia de perspectiva

- `sourceUser ↔ sourceUser` infiere misma perspectiva.
- `sourceUser ↔ participant(X)` infiere perspectiva distinta.
- Inferencia de grupo con muchos autores.
- Individual opuesto sin pista pero con solapamiento fuerte.
- Individual opuesto con pista.
- Fuente sin mensajes propios.
- Fuente con mensajes propios pero sin identidad en `MessageAuthor`.
- Pista correcta refuerza evidencia.
- Pista incorrecta produce conflicto.
- Un único candidato no decide perspectiva.
- Evidencia contradictoria rechaza.
- Mensajes exclusivos importados quedan orientados respecto al target.
- Autor de grupo no resoluble y potencialmente target bloquea.

### 29.3 Identidad de conversación

- Grupo mismo JID.
- Grupo JID diferente/nombre igual.
- Individual misma perspectiva.
- Individual perspectivas opuestas.
- ContactJid LID frente a phoneJID con alias demostrado.
- LID sin alias no se convierte en teléfono.
- Teléfonos no coinciden por sufijo.
- Conversaciones distintas con timestamps cercanos.
- `chatType` incoherente.

### 29.4 Alineación

- Documentos idénticos con PK distintas.
- `isFromMe` opuesto para el mismo mensaje.
- Solapamiento al inicio, medio y final.
- Gran prefijo histórico en una fuente.
- Gran sufijo nuevo.
- Inserciones entre anclas.
- Miles de `Sí`, `OK` y emojis.
- Mensajes idénticos del mismo autor en segundos próximos.
- Ventanas desambiguan señales débiles.
- Cruces de orden producen ambigüedad.
- Secuencias disjuntas se rechazan.
- Timestamp dentro/fuera de policy.
- Offset sistemático permitido/no permitido.
- Autor ausente no es ancla fuerte.
- Mismo ID estable/contenido diferente bloquea.
- Permutación de fuentes conserva unión lógica.
- Cientos de miles de mensajes sin LCS cuadrático.

### 29.5 Contenido

- Unicode NFC/NFD.
- CRLF/LF.
- Mayúsculas, espacios, puntuación y emojis conservados.
- Texto y caption.
- Imagen, vídeo, audio, documento, GIF y sticker.
- Contacto, enlace y ubicación.
- Duración y coordenadas.
- Medio igual/nombre diferente.
- Nombre igual/medio diferente.
- Medio ausente o corrupto.
- Reacciones distintas no duplican.
- Edición central produce conflicto.
- Warning distinto no duplica.

### 29.6 Respuestas e IDs

- Reply presente en ambas fuentes.
- Original solo en target.
- Original solo en import.
- Original ausente con preview.
- IDs fuente distintos para mensajes equivalentes.
- Reply incompatible.
- IDs materializados correlativos.
- Mapa estable completo.
- Reconstrucción conserva `ArchiveMessageID`.

### 29.7 Materialización

- Orientación correcta con misma perspectiva.
- Orientación invertida con perspectiva distinta.
- Target conserva `chat.id`, `contactJid`, nombre y archivado.
- Conteos/fechas/tamaño recalculados.
- Contactos target preferidos.
- Reacciones de snapshot más reciente.
- Multimedia deduplicada.
- Varias fuentes locales más varias portables.
- Eliminar lógicamente una aportación y reconstruir.
- Cambio de digest invalida evidencia.
- Salida lógica determinista.
- Staging inválido no se devuelve como éxito.

### 29.8 Contrato JSON portable

- Snapshot de cada tipo público.
- Orden estable de arrays no semánticos.
- Fechas UTC con milisegundos.
- Round trip.
- Schema desconocido.
- Campos opcionales ausentes.
- No existe `sourceOwner` obligatorio.
- No aparecen PK SQLite, `chatId` ni `stanzaId`.
- Roles `sourceUser`, `participant`, `unresolved`.
- Replies solo a IDs portables.

### 29.9 Seguridad ZIP

- Crear, inspeccionar y extraer paquete válido.
- ZIP vacío, truncado y corrupto.
- Cifrado y multidisco.
- Path traversal Unix/Windows.
- Ruta absoluta, NUL y letra de unidad.
- Symlink, hard link y tipo especial.
- Duplicados exactos, case-fold y Unicode.
- `__MACOSX` y archivos extra.
- Subdirectorio en `Media`.
- Bomba por ratio/tamaño/entradas.
- Overflow de tamaños.
- JSON excesivo/profundo/inválido.
- Hash/tamaño/contentDigest incorrecto.
- Medio declarado ausente/no declarado.
- Referencia insegura desde JSON.
- Archivo cambia entre inspección y extracción.
- Destino no vacío.
- Cancelación sin residuos.

### 29.10 Progreso y cancelación

- Fases esperadas.
- Contadores monotónicos.
- `currentItem` sin contenido privado.
- `.completed` solo en éxito.
- Cancelación en hashing, alineación, ZIP y copia.

## 30. Fixtures

Crear fixtures sintéticos pequeños:

- dos copias de grupo desde misma perspectiva;
- dos perspectivas de grupo;
- dos perspectivas de individual;
- mensajes repetitivos;
- LID/JID/phone aliases;
- cada tipo de medio con bytes diminutos;
- respuestas cruzadas;
- conflicto de perspectiva y contenido;
- paquete portable válido mínimo.

Generar ZIP maliciosos durante tests cuando sea posible. Los chats reales se usan
solo localmente; informes anonimizan nombres, teléfonos, texto y hashes completos.

## 31. Documentación requerida en SwiftWABackupAPI

Actualizar o añadir:

- README con composición local N-aria y paquete portable;
- contrato JSON `.fmcchat` v1;
- especificación exacta de `contentDigest`;
- seguridad y límites ZIP;
- normalización de participantes/texto/fechas;
- inferencia de perspectivas y uso de pistas opcionales;
- policy por defecto y razones;
- metadatos mutables;
- progreso/cancelación;
- complejidad y límites de memoria;
- ayuda del CLI;
- release notes y versión/tag.

Documentar expresamente:

- no se persiste una identidad global obligatoria del propietario;
- el paquete conserva perspectiva relativa;
- una pista de perspectiva es opcional y validada;
- hashes no autentican remitente;
- la API no modifica WhatsApp ni bibliotecas de Free My Chats.

## 32. Criterios de aceptación

El trabajo se considera completo cuando:

1. La misma API compone exportaciones locales e importadas.
2. Acepta N fuentes y una fuente target.
3. Reproduce o mejora todos los casos de Vista unificada actuales.
4. No requiere identidad global persistida del propietario.
5. Infiere misma/distinta perspectiva con evidencia y permite pista opcional.
6. Rechaza perspectiva necesaria no resuelta.
7. Identifica grupos por JID y resuelve individuales desde ambas perspectivas.
8. `isFromMe` opuesto no duplica un mensaje compartido.
9. Mensajes repetitivos no se alinean por señal aislada.
10. Un tramo histórico más solapamiento moderno se incorpora correctamente.
11. Secuencias disjuntas no se concatenan.
12. Conflictos y ambigüedades no son aplicables.
13. El análisis no escribe.
14. La materialización reorienta respecto al target.
15. IDs y replies se remapean y se devuelven IDs estables.
16. Multimedia se deduplica por SHA-256.
17. Evidencia persistible permite reconstrucción y se invalida por digest.
18. Crea `.fmcchat` desde exportación o materialización sin copia fuente.
19. El paquete no incluye `sourceOwner` obligatorio ni IDs SQLite.
20. El codec resiste traversal, links, duplicados, corrupción y bombas.
21. Entradas modificadas entre análisis/aplicación se rechazan.
22. Progreso/cancelación funcionan.
23. Salida y planes son deterministas para las mismas entradas/policy.
24. Todos los tipos públicos tienen doc comments y contrato JSON.
25. `swift build` y `swift test` pasan en la matriz mantenida.
26. Existe tag/release consumible por Free My Chats.

## 33. Decisiones que no deben tomarse silenciosamente

El agente debe presentar evidencia y pedir decisión antes de:

- introducir una identidad global obligatoria del propietario;
- exigirla en `manifest.json`;
- separar el motor portable del motor de fusión local;
- limitar composición a exactamente dos fuentes;
- concatenar sin solapamiento;
- aceptar nombre o proximidad temporal como identidad suficiente;
- permitir forzar confianza media/baja;
- usar `stanzaId` como identidad portable;
- romper lectura de `ExportedChatDocument` v1;
- sustituir ZIP por otro contenedor;
- invocar herramientas ZIP del sistema desde la biblioteca;
- añadir dependencia que cambie plataformas soportadas;
- filtrar contenido real en logs/fixtures;
- fijar la policy entre perspectivas sin la Fase 0 diagnóstica;
- hacer que la API instale o borre estructura de Free My Chats.

## 34. Primera tarea concreta para el agente

Implementar primero, y solo, el incremento descrito en
[`especificacion-swiftwabackupapi-fusion-local-inicial.md`](especificacion-swiftwabackupapi-fusion-local-inicial.md):

1. Crear los modelos públicos de fuente, restricciones, policy, plan e impacto.
2. Convertir `ExportedChatDocument` v1 a la representación canónica relativa.
3. Validar que todas las fuentes pertenecen a la misma conversación y declarar
   `samePerspective` sin identidad global del propietario.
4. Reproducir la deduplicación exacta, el orden y la atribución N-aria actuales.
5. Reconstruir IDs, replies, metadatos, contactos y multimedia.
6. Materializar una salida validada en staging, sin instalarla en la biblioteca.
7. Añadir progreso, cancelación, comprobación de cambios de entrada y errores
   estructurados.
8. Portar y ampliar los fixtures de `ConversationArchiveServiceTests` indicados
   por la especificación inicial.
9. Demostrar determinismo y paridad semántica con la Vista unificada actual.
10. Entregar la versión de SwiftWABackupAPI consumible por FreeMyChats y un
    informe breve de cualquier diferencia deliberada.

Después de completar e integrar este incremento se retomará la Fase 0
diagnóstica para composición entre perspectivas. El incremento inicial no debe
crear aún el formato ZIP, inferir propietarios o perspectivas, modificar
`ExportedChatDocument` ni escribir dentro de una biblioteca de FreeMyChats.
