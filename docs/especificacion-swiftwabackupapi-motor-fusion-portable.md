# Especificación para SwiftWABackupAPI: motor general de fusión y conversaciones portables

## Estado de implementación — Free My Chats 2.1.1

SwiftWABackupAPI introdujo en la 5.0.0 los incrementos local, diagnóstico, de
materialización entre perspectivas y el contrato portable v1. Free My Chats
2.1.1 consume la API 6.0.1 y completa su integración:

- Free My Chats construye su Vista unificada actual mediante
  `ConversationCompositionEngine` y conserva instalación/rollback.
- La API implementa fuentes N-arias, restricciones y pistas de perspectiva,
  canonización relativa, anclas conservadoras, inferencia y diagnóstico.
- `analyze`/`materialize`/`compose` reorientan individuales y grupos respecto a
  `targetSourceID`, sin persistir una identidad global del propietario.
- Se materializan IDs, replies, reacciones, contactos y multimedia en staging;
  una decisión ambigua o rechazada no escribe.
- Free My Chats registra las aportaciones recibidas en `ImportedChats`, instala
  la materialización con rollback y permite consultarlas o retirarlas desde la
  interfaz.
- SwiftWABackupAPI implementa los modelos v1 y
  `PortableConversationArchiveCodec`: creación, inspección, extracción y apertura
  validada de `.fmcchat`, con hashes, límites configurables, rechazo de rutas
  peligrosas y limpieza transaccional.
- `PortableConversationDirectory.makeConversationSource` adapta el paquete
  validado al mismo `ConversationCompositionEngine`; Free My Chats ya expone esa
  frontera mediante un servicio interno probado de extremo a extremo.
- La autoría `sourceUser` no contiene identidad ni nombre del propietario; una
  identidad de perspectiva solo puede inferirse al componer o recibirse como
  parámetro operativo.
- Las fichas y fotos de contacto solo se incluyen para participantes que la
  fuente demuestra que no son su usuario; los contactos no demostrables se
  omiten para no filtrar indirectamente la identidad del propietario.
- La regresión publicada de la API pasa 149 pruebas y la aplicación contiene 64
  pruebas. Incluyen fixtures sintéticos para perspectivas iguales/opuestas,
  composición N-aria, mensajes
  débiles, offsets, multimedia, replies, reacciones, seguridad ZIP, privacidad y
  rechazo seguro. Dos pruebas opcionales validan en solo lectura tanto la Vista
  unificada como un ciclo portable real sobre la biblioteca de referencia.

La Fase 3 de integración persistente está incluida en Free My Chats 2.0.0:
registro reversible de aportaciones portables, instalación definitiva en la
biblioteca, reconstrucción al retirarlas e interfaz de usuario.

## 1. Destinatario y propósito

Este documento describe el contrato implementado por SwiftWABackupAPI 5.0.0 para
componer varias
copias guardadas de una conversación y, sobre esa misma base, intercambiar
conversaciones mediante archivos `.fmcchat`.

La implementación sirve a dos casos con un único motor:

1. **Vista unificada actual:** varias copias guardadas de copias locales, normalmente
   desde la misma perspectiva, se deduplican y materializan como una conversación.
2. **Importación entre personas:** una exportación creada desde otra perspectiva
   se alinea con la conversación local, se reorienta y se incorpora sin duplicar
   el tramo común.

La especificación nació sobre SwiftWABackupAPI 4.5.0 y Free My Chats 1.3.10. El
motor resultante se publicó inicialmente en SwiftWABackupAPI 5.0.0. Free My Chats
2.1.1 consume la versión exacta 6.0.1, compatible con la terminología definitiva de
chats guardados; los checkouts de `.build` no son fuente editable.

Documentos de contexto:

- `FreeMyChats/docs/fusion-conversaciones-portables.md`
- `FreeMyChats/docs/evaluacion-importacion-conversaciones.md`
- `FreeMyChats/docs/conversaciones-materializadas.md`
- `SwiftWABackupAPI/Docs/JSONContract.md`

Las decisiones de este documento sobre perspectiva e identidad sustituyen las
propuestas anteriores que exigían persistir una identidad global del propietario.

El primer incremento, limitado a las Vistas unificadas locales de la misma
perspectiva, se documenta por separado en
[Composición de Vistas unificadas locales](especificacion-swiftwabackupapi-fusion-local-inicial.md).

## 2. Decisiones vinculantes

1. No se añade a la biblioteca ni al paquete una identidad global obligatoria del
   propietario.
2. Cada documento se trata como una **fuente con perspectiva**: `isFromMe`
   significa “usuario de esta fuente”, no una identidad absoluta universal.
3. El motor infiere durante el análisis la relación entre perspectivas.
4. Si la evidencia del contenido no basta, el llamante puede proporcionar una
   identidad o pista de perspectiva como parámetro.
5. La ausencia de una pista no autoriza una conjetura: si no puede orientarse con
   seguridad un mensaje nuevo, el plan no es aplicable.
6. Las funciones centrales aceptan N fuentes y son reutilizables por la
   fusión local actual; `.fmcchat` es solo una forma adicional de obtener una
   fuente.
7. El motor no utiliza `ZSTANZAID` como identidad portable ni criterio principal.
8. El análisis es de solo lectura. La materialización escribe únicamente en un
   staging proporcionado por el cliente.
9. Free My Chats conserva la responsabilidad de instalar, retirar, reconstruir y
   hacer rollback de sus carpetas de biblioteca.
10. Un resultado ambiguo se explica y se rechaza; la aplicación actual no permite
    forzarlo.

## 3. Objetivos funcionales

SwiftWABackupAPI 5.0.0:

- convertir `StoredChatDocument` y `Media` en una fuente validada;
- analizar varias fuentes de la misma conversación;
- inferir si dos fuentes usan la misma perspectiva o perspectivas distintas;
- resolver autores a participantes canónicos cuando haya evidencia;
- detectar la misma conversación en grupos e individuales;
- alinear secuencias con solapamientos parciales;
- clasificar coincidencias, mensajes exclusivos y relaciones de perspectiva
  resueltas, no resueltas o contradictorias;
- calcular una decisión y razones de confianza;
- materializar un único `StoredChatDocument` desde la perspectiva de una fuente
  target elegida;
- reasignar IDs y respuestas;
- copiar y deduplicar multimedia por contenido;
- devolver IDs estables y procedencia suficiente para reconstrucción;
- crear, inspeccionar y extraer un `.fmcchat` seguro;
- emitir progreso y admitir cancelación cooperativa;
- ofrecer un diagnóstico CLI sin exponer contenido privado por defecto.

## 4. Funcionalidades fuera del alcance de la aplicación actual

- Importar el ZIP/TXT nativo de WhatsApp.
- Escribir en WhatsApp, `ChatStorage.sqlite` o una copia de iPhone.
- Autenticar criptográficamente a quien entrega el archivo.
- Resolver manualmente conflictos mensaje a mensaje.
- Concatenar conversaciones sin solapamiento demostrado.
- Inferir teléfonos por sufijos, nombres de agenda o dígitos de un LID.
- Hacer que SwiftWABackupAPI conozca `library.json`, `StoredChats`, `ImportedChats` o
  `MergedChats`.
- Mantener el proyecto Python legado.

## 5. Arquitectura general

La implementación se separa en cuatro capas:

```text
StoredChatDocument / directorio portable
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
produce el mismo tipo de `ConversationSource` que una copia guardada local.

## 6. Superficie pública principal

Esta es la superficie publicada. Los tipos puramente de valor adoptan `Sendable`;
`ConversationSource`, `PreparedConversationComposition` y los resultados que
contienen documentos o URLs permanecen sin una conformidad insegura.

```swift
public struct ConversationCompositionEngine {
    public let policy: ConversationCompositionPolicy

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

    public func compose(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint],
        targetChatID: Int,
        destinationDirectory: URL,
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationMaterializationResult

    public func diagnose(
        sources: [ConversationSource],
        targetSourceID: ConversationSourceID,
        perspectiveConstraints: [ConversationPerspectiveConstraint] = [],
        progress: WABackupProgressHandler? = nil,
        cancellation: WABackupCancellationHandler? = nil
    ) throws -> ConversationCompositionDiagnostic
}
```

El inicializador por defecto conserva la semántica local
`currentUnifiedView`. Para fuentes de perspectivas distintas el cliente crea el
engine con `.conservativeDefault`.

El uso para la Vista unificada actual debe ser directo:

```swift
let sources = localStoredChats.map {
    try ConversationSource(
        id: .init(rawValue: $0.contributionID),
        document: $0.stored.document,
        mediaDirectoryURL: $0.stored.mediaDirectoryURL,
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
    targetChatID: localStoredChats[0].stored.document.chat.id,
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
    case storedDocument
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
        document: StoredChatDocument,
        mediaDirectoryURL: URL,
        conversationIdentityHint: CanonicalParticipantIdentity? = nil,
        perspectiveHint: ConversationPerspectiveHint? = nil,
        stableMessageIDs: [Int: ArchiveMessageID] = [:]
    ) throws
}
```

El contenido concreto de una fuente es deliberadamente opaco después de
construirla:

- el inicializador público anterior envuelve un `StoredChatDocument` v2;
- `PortableConversationDirectory.makeConversationSource(...)` adapta de forma
  controlada el documento portable al mismo tipo, conserva
  `PortableMessage.id` como ID estable y traduce `PortableMessageAuthor.role` a
  autoría relativa;
- ambas variantes convergen en `ConversationCompositionEngine`;
- el cliente no hace esa conversión manual ni puede fabricar un
  `PortableConversationDirectory` supuestamente validado.

Requisitos:

- `id` lo asigna el cliente y es único dentro de la composición.
- No contiene rutas relativas a la biblioteca ni conocimiento de una copia.
- `sourceDate` representa la instantánea lógica para resolver metadatos mutables;
  normalmente `document.storedAt`.
- `conversationIdentityHint` describe, solo en un chat individual, identidades
  equivalentes del interlocutor (`contactJid`, phoneJID, LID, teléfono) resueltas
  por el cliente; no describe al usuario de la fuente.
- Existen inicializadores desde `StoredChat` y desde documento más directorio.
- El inicializador valida lo barato; `analyze` ejecuta la validación completa.
- El mapa de IDs estables puede estar vacío en copias guardadas anteriores; una fuente
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

Los constructores públicos son:

```swift
.samePerspective(sourceIDs: [...])
.differentPerspectives(_ first: ConversationSourceID, _ second: ConversationSourceID)
.identity(_ participant: CanonicalParticipantIdentity, for sourceID: ConversationSourceID)
```

La Vista unificada actual usa una restricción `.samePerspective` para todas sus
copias locales. Esto expresa una relación conocida por el caso de uso sin
introducir una identidad global del propietario.

No se denomina ni se persiste como “propietario”. Significa únicamente: “el
usuario representado por `isFromMe` en esta fuente parece ser este participante”.

Reglas:

- Es opcional.
- La pista se proporciona al construir la fuente; una identidad operativa
  equivalente puede aportarse a `analyze` mediante la restricción
  `.identity(_:for:)`.
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

La API no publica un enum `ParticipantIdentityRelationship`. Dos identidades
comparten participante cuando sus direcciones canónicas producen al menos una
clave de comparación común. `phone` y `phoneJID` del mismo número comparten
clave; un LID solo se relaciona con teléfono cuando ambos aparecen en una misma
`CanonicalParticipantIdentity` aportada como alias/hint. Un nombre, push name o
foto nunca basta.

## 9. Autoría relativa a una fuente

El motor canónico no convierte `isFromMe` a un propietario global. Primero
expresa la autoría de forma relativa:

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
- Contradicción entre `isFromMe` y `author.kind` → fuente inválida.
- Aplicar el mismo modelo a reacciones.

Esta representación permite comparar dos mensajes antes de saber quién es el
usuario de cada fuente.

## 10. Inferencia de perspectivas

### 10.1 Problema

En copias guardadas de la misma persona, un mensaje propio suele aparecer como:

```text
Fuente A: sourceUser
Fuente B: sourceUser
```

En exportaciones de personas distintas:

```text
Fuente A: sourceUser
Fuente B: participant(A)
```

El motor infiere esta relación a partir de varios mensajes fuertes
provisionalmente coincidentes, no de un único mensaje.

### 10.2 Análisis por pares respecto al target

#### Pasada 1: candidatos sin identidad completa

Para cada fuente adicional, generar candidatos contra el target mediante:

- tipo;
- contenido textual/caption conservador;
- hash multimedia;
- timestamp dentro de tolerancia;
- duración/ubicación;
- orden relativo.

La dirección y autor se usan como evidencia, pero una etiqueta `.sourceUser` de
una fuente no representa una identidad absoluta.

Solo pasan a ancla las firmas fuertes únicas en ambas secuencias o los IDs
estables compatibles, dentro de la tolerancia temporal. El engine obtiene la
subsecuencia creciente de anclas para preservar el orden.

#### Pasada 2: resolver la relación con el target

Cada candidato fuerte aporta restricciones:

- `sourceUser ↔ sourceUser`: ambas fuentes probablemente representan al mismo
  participante.
- `sourceUser ↔ participant(X)`: la perspectiva de la primera fuente es X.
- `participant(X) ↔ sourceUser`: la perspectiva de la segunda es X.
- `participant(X) ↔ participant(Y)`: X e Y deben ser equivalentes.

El motor cuenta evidencia `sameAsTarget` y `differentFromTarget`, detecta una
mezcla contradictoria e incorpora hints y constraints explícitos. Cada fuente
obtiene un `SourcePerspectiveResolution` respecto al target; la 5.0.0 no propaga
un grafo independiente entre pares de fuentes no target.

#### Pasada 3: alineación definitiva

Con las relaciones resueltas, el engine reorienta los mensajes respecto al
target, une las anclas aceptadas y agrupa firmas target-relative compatibles.

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
  correctamente como propio/ajeno; se contabiliza como bloqueo salvo que el
  tipo se clasifique de forma demostrable como evento sin autor.
- En individuales, la relación binaria entre las dos perspectivas puede orientar
  mensajes aunque no se conozca el teléfono absoluto.
- Una pista proporcionada puede desbloquear la orientación, pero no el requisito
  de solapamiento.

## 11. Identidad y equivalencia de conversación

### 11.1 Grupos

- `chatType == .group` en todas las fuentes.
- JID normalizado terminado en `@g.us`.
- El JID coincide exactamente después de normalizar.
- Un nombre coincidente con JID distinto nunca es suficiente.
- La inferencia de perspectiva se usa para autores, no para sustituir el JID del
  grupo.

### 11.2 Individuales

Una conversación individual no puede identificarse únicamente por
`contactJid`, porque cada participante ve como contacto a la otra persona.

El motor acepta dos casos:

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

El nombre visible, `chat.id`, las fechas de guardado y el nombre de archivo no
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
- El diagnóstico registra la distribución de deltas; el plan añade la razón
  `systematicTimestampOffsetApplied` cuando aplica un offset.

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

La 5.0.0 considera fuerte un mensaje con medio o ubicación, o un contenido
textual/caption normalizado de al menos cuatro caracteres que no pertenezca al
conjunto conservador `ok`, `sí`, `si`, `no`, `👍`, `❤️`, `😂`, `🙏`. Para ser
ancla, su firma debe aparecer una sola vez en cada secuencia, salvo coincidencia
de `ArchiveMessageID`.

Este conjunto débil forma parte de la versión actual del algoritmo. No se usa
para deduplicar por sí solo: evita que respuestas breves o emojis frecuentes
decidan una perspectiva.

## 13. Algoritmo de alineación general

### 13.1 Objetivo

Para N fuentes, producir grupos de equivalencia de mensajes y preservar el orden
de una única cronología. Cada mensaje fuente pertenece como máximo a un grupo.

Un grupo de equivalencia representa una aparición lógica y puede contener
referencias de una o varias fuentes.

### 13.2 Alineación por pares y composición N-aria

1. Elegir como eje la fuente target.
2. Diagnosticar cada fuente adicional contra el target.
3. Unir las anclas aceptadas y los IDs estables compatibles.
4. Agrupar además firmas de contenido ya orientado que aparezcan como máximo una
   vez por fuente y estén dentro de la tolerancia temporal.
5. Registrar estadísticas por cada par target–fuente.
6. El resultado usa un orden estable y los tests comprueban que permutaciones
   equivalentes producen la misma unión lógica.

En la 5.0.0 el cliente no aporta evidencia persistida al engine. Conserva el plan
o diagnóstico para auditoría y presentación, pero reconstruye mediante un nuevo
análisis de las fuentes.

### 13.3 Anclas fuertes

1. Calcular firma central sin timestamp rígido.
2. Indexar apariciones por firma.
3. Generar candidatos compatibles dentro de la tolerancia temporal.
4. Seleccionar firmas fuertes que aparezcan exactamente una vez en cada
   secuencia, o IDs estables compatibles.
5. Ordenar pares por posición de la primera secuencia.
6. Obtener la mayor subsecuencia creciente por posición de la segunda en
   `O(n log n)`.
7. Eliminar cruces y saltos incompatibles.

No ejecutar un LCS `O(n*m)` sobre chats completos.

### 13.4 Mensajes débiles y repetitivos

La 5.0.0 no implementa hashes de ventanas ni desambiguación contextual de
secuencias repetitivas. Un mensaje débil puede agruparse cuando su firma
target-relative es única por fuente y cae dentro de la tolerancia temporal. Si
se repite dentro de una fuente, se mantiene separado salvo que un ID estable o
un ancla fuerte demuestre la equivalencia.

### 13.5 Agrupación y límites deliberados

Las anclas ordenadas, los IDs estables y las firmas target-relative compatibles
forman los grupos lógicos. Las inserciones exclusivas se conservan como mensajes
separados. La versión actual no hace reconciliación difusa de ediciones, no
publica regiones ambiguas por mensaje y no intenta detectar que dos contenidos
centrales diferentes sean “probablemente” el mismo evento.

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
- diagnósticos agregados y conteos exactos sin muestras de contenido;
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
    public let profile: ConversationCompositionPolicy.Profile
    public let targetSourceID: ConversationSourceID
    public let sourceDigests: [ConversationSourceDigest]
    public let statistics: ConversationCompositionStatistics
    public let sourceImpacts: [ConversationSourceImpact]
    public let confidence: ConversationCompositionConfidence
    public let disposition: ConversationCompositionDisposition
    public let reasons: [CompositionReason]
    public let crossPerspectiveDiagnostic: ConversationCompositionDiagnostic?

    public func removalImpact(
        of sourceID: ConversationSourceID
    ) throws -> ConversationRemovalImpact
}
```

El cliente no puede modificar los mapeos internos de una preparación y luego
pedir que se materialicen como si hubieran sido aprobados.

La equivalencia, las perspectivas resueltas y las medidas de alineación viven en
`ConversationCompositionDiagnostic`, devuelto por `diagnose` y adjunto en
`crossPerspectiveDiagnostic` cuando el plan procede del perfil conservador. El
perfil local deja ese campo a `nil`.

### 14.2 Estadísticas mínimas

El plan expone conteos globales de fuentes, ocurrencias, mensajes materializados,
deduplicados, compartidos y exclusivos, además de bytes multimedia de entrada,
salida y duplicados. `sourceImpacts` aporta por fuente mensajes totales,
compartidos, exclusivos y bytes exclusivos.

El diagnóstico entre perspectivas expone, sin contenido, anclas fuertes,
candidatos y mensajes emparejados; cobertura target/fuente; consistencia de
orden; diferencias temporales mínima, máxima, mediana y percentil 95; autores y
perspectivas resueltos/no resueltos; conflictos de perspectiva y mensajes
exclusivos no orientables.

### 14.3 Confianza y disposición

```swift
public enum ConversationCompositionConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

public enum ConversationCompositionDisposition: String, Codable, Sendable {
    case applicable
    case requiresReview
    case rejected
}
```

Política de la aplicación actual:

- alta, conversación demostrada y perspectivas necesarias resueltas →
  `applicable`;
- media → `requiresReview`, pero no materializable;
- baja, conversación distinta, secuencias disjuntas o perspectiva necesaria no
  resuelta → `rejected`;
- perspectiva contradictoria o ID estable incompatible → no aplicable.

Una puntuación numérica puede ayudar al diagnóstico, pero no sustituye reglas y
razones versionadas.

### 14.4 Política configurable

```swift
public struct ConversationCompositionPolicy: Codable, Sendable {
    public let profile: Profile
    public let maximumTimestampDifferenceMilliseconds: Int64
    public let minimumStrongAnchorCount: Int
    public let minimumMatchedWindowCount: Int
    public let minimumOverlapMessageCount: Int
    public let minimumOrderConsistency: Double
    public let maximumUnresolvedAuthorFraction: Double
    public let requireOrientableExclusiveMessages: Bool
    public let allowSystematicTimestampOffset: Bool

    public static let currentUnifiedView: Self
    public static let conservativeDefault: Self
}
```

`.conservativeDefault` usa el perfil `.conservativeCrossPerspective`; sus
umbrales están fijados y los tests pequeños pueden construir una política
explícita sin debilitar el valor por defecto.

### 14.5 Privacidad del plan

`ConversationCompositionDiagnostic.privacySafeReport`, usado por el CLI, conserva
IDs de fuente, digests, conteos y medidas, pero elimina participantes y JID de
grupo. No incluye texto, nombres, teléfonos ni contenido de mensajes. La API no
expone una opción de CLI que revele ese contenido.

## 15. Huellas y deduplicación en la Vista unificada actual

El perfil `currentUnifiedView` sustituye la lógica anterior de
`ConversationArchiveService.messageFingerprint` sin mantener una segunda
implementación en Free My Chats.

Para fuentes de la misma perspectiva:

- `sourceUser` de ambas fuentes se considera compatible;
- participantes se comparan por identidad normalizada;
- timestamp, tipo, texto/caption, medio, duración y ubicación forman la señal
  central;
- la coincidencia es exacta a milisegundos y no usa alineación contextual;
- se conservan contadores de mensajes exclusivos por `sourceID`;
- se devuelve un mapa de referencias para reescribir respuestas;
- la deduplicación de medios continúa siendo por SHA-256.

Los tests de paridad cubren actualizaciones solapadas, LID/JID, tres
aportaciones, retirada, respuestas, medios con nombres iguales y reparación.

### 15.1 Operaciones sustituidas

El plan y el resultado exponen helpers de dominio para que Free My Chats no
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
    public let sourceMessageCount: Int
    public let resultingMessageCount: Int
    public let removedMessageCount: Int
    public let removedMediaByteCount: Int64
}
```

Capacidades requeridas:

- conteo materializado sin escribir;
- impacto de retirar una fuente;
- exclusividad por fuente;
- reanálisis cuando cambia el digest de una fuente;
- rematerialización después de volver a analizar fuentes válidas;
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

Free My Chats gestiona manifiestos y movimientos atómicos, pero no mantiene una
segunda definición de huella o de correspondencia de mensajes.

## 16. Conflictos y metadatos mutables

### 16.1 Condiciones bloqueantes implementadas

- autor resuelto incompatible;
- mismo ID estable con contenido central diferente;
- relación de perspectiva contradictoria.

La versión 5.0.0 no hace reconciliación difusa de ediciones. Dos contenidos
centrales diferentes no se fuerzan a representar el mismo mensaje; permanecen
separados salvo que un ID estable incompatible obligue a rechazar.

### 16.2 Diferencia no central

- reacciones;
- nombre visible;
- foto;
- `replyToPreview`;
- warning/error de extracción;
- estado archivado;
- fecha de guardado.

Estas diferencias no crean otro mensaje por sí solas.

### 16.3 Política de representante implementada

Para un mensaje coincidente:

- una ocurrencia del target gana cuando existe;
- si el target no contiene el mensaje, gana la instantánea de fuente más reciente,
  con desempates estables;
- contenido, reacciones, warning, autor visible y metadatos de respuesta proceden
  del representante;
- la respuesta se remapea al ID materializado;
- nombre, `contactJid`, archivado y avatar del chat proceden del target;
- contactos prefieren target y después la fuente más reciente.

## 17. Respuestas

Construir mapas:

```text
(sourceID, sourceMessageID) → ArchiveMessageID → materialized Int
```

Reglas:

- mensajes alineados comparten `ArchiveMessageID`;
- mensajes exclusivos reutilizan ID estable o reciben uno;
- `replyTo` se traduce primero a ID estable y después a entero;
- respuestas incompatibles entre representantes añaden
  `inconsistentReplyMetadata`; gana el representante;
- original ausente → `replyTo == nil`, conservar mejor preview;
- no usar `stanzaId` para correspondencia entre fuentes.

## 18. Materialización general

### 18.1 Resultado

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

### 18.2 Perspectiva de salida

La salida se orienta respecto a `targetSourceID`, no a una identidad global:

- mensaje perteneciente a la perspectiva target → `isFromMe = true`;
- participante diferente → `false`;
- en individual con perspectivas opuestas, transformar roles de forma binaria;
- en grupo, usar el grafo de identidades/perspectivas;
- autor no resoluble que podría ser target bloquea si el mensaje es exclusivo;
- `MessageAuthor.kind` concuerda con `isFromMe`;
- los mensajes ya presentes en target conservan su orientación.

### 18.3 Orden e IDs

- cronología ascendente;
- empates resueltos por orden lógico de alineación y después criterio estable;
- IDs enteros correlativos compatibles con `StoredChatDocument`;
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

- El destino no existe o está vacío según el contrato.
- La API no reemplaza `MergedChats` ni borra fuentes.
- Escribe solo dentro del staging.
- Limpia únicamente staging creado por la propia llamada al fallar/cancelar.
- Valida `chat.json` y `Media` antes de devolver resultado.

## 19. Evidencia persistible y reconstrucción

Free My Chats puede retirar una aportación y reconstruir con las fuentes
restantes. `ConversationCompositionPlan` y
`ConversationCompositionDiagnostic` son `Codable`, versionados y contienen
digests de fuente, versión de algoritmo, perfil, target, decisión, razones,
estadísticas e impactos; el diagnóstico añade equivalencia, perspectivas y
medidas de alineación.

`PreparedConversationComposition` es deliberadamente opaco y no es `Codable`.
La versión 5.0.0 tampoco acepta un plan anterior como atajo para materializar.
Después de reabrir la aplicación o cambiar fuentes, el cliente abre y valida las
fuentes, ejecuta de nuevo `analyze` y materializa la nueva preparación. Esto
evita aplicar mapeos obsoletos. Los mappings de IDs estables se devuelven en
`ConversationMaterializationResult`, pero su persistencia en la biblioteca sigue
siendo responsabilidad de Free My Chats.

## 20. Formato `.fmcchat` v1

### 20.1 Principio

El paquete conserva la perspectiva de su documento. No contiene un campo
obligatorio `sourceOwner` ni una identidad global del propietario.

La autoría portable se expresa como:

```swift
public struct PortableMessageAuthor: Codable, Hashable, Sendable {
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
    public let storedAt: Date
    public let photoPath: String?
}
```

Invariantes de `PortableConversationDescriptor`:

- grupo: `groupJID` obligatorio y `contactJID/contactIdentity` ausentes;
- individual: `groupJID` ausente y al menos `contactJID` o `contactIdentity`;
- `displayName`, `isArchived`, `storedAt` y `photoPath` son presentación;
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
    "version": "2.1.1"
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
    "storedAt": "2026-07-22T10:14:00.000Z"
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
public struct PortableConversationDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let conversation: PortableConversationDescriptor
    public let messages: [PortableMessage]
    public let contacts: [PortableContact]
}

public struct PortableMessage: Codable, Equatable, Sendable {
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
public struct PortableContact: Codable, Hashable, Sendable {
    public let identity: CanonicalParticipantIdentity
    public let displayName: String
    public let photoPath: String?
}

public struct PortableReaction: Codable, Hashable, Sendable {
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

`archiveURL` forma parte del `Codable` de este resumen operativo, pero no entra en
`contentDigest` ni en `archiveSHA256`.

No exportar PK SQLite, `chatId` ni `stanzaId`. La perspectiva relativa se conserva
mediante `author.role`, no mediante una identidad global.

### 20.5 IDs portables

```swift
public struct ArchiveMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID
}
```

- En JSON se codifica como una cadena UUID, no como un objeto con `rawValue`.
- Reutilizar ID estable proporcionado por el cliente.
- Si no existe, el codec deriva uno determinista del contenido y la posición
  canónica al crear el paquete.
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

`PortableConversationDirectory` tiene inicializador no público y expone
`makeConversationSource(id:perspectiveHint:)`. Así el cliente no puede declarar
validado un directorio arbitrario.

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

Free My Chats puede pasar un `StoredChatDocument` de `MergedChats` y su `Media`.
El paquete representa esa conversación visible como una fuente única. No incluye
las capas internas ni el historial de aportaciones.

### 22.3 Nombres de medios

Usar nombres seguros y deterministas, por ejemplo
`<12-hex-hash>-<nombre-saneado>`. Contenido idéntico usa una entrada; contenido
distinto nunca comparte ruta aunque el nombre original coincida.

## 23. Seguridad ZIP

### 23.1 Dependencia y plataforma

La implementación usa ZIPFoundation 0.9.20, fijada exactamente en
`Package.swift` y encapsulada tras el codec. Inspecciona las entradas antes de
extraer y procesa su contenido por bloques; no invoca `ditto`, `zip` ni `unzip`
como procesos. El paquete mantiene Swift tools 5.8 y se ha compilado con target
macOS 13 Ventura.

### 23.2 Límites

```swift
public struct PortableArchiveLimits: Codable, Equatable, Sendable {
    public var maximumArchiveByteCount: Int64
    public var maximumUncompressedByteCount: Int64
    public var maximumEntryByteCount: Int64
    public var maximumJSONByteCount: Int64
    public var maximumEntryCount: Int
    public var maximumCompressionRatio: Double
    public var maximumPathUTF8ByteCount: Int
}
```

Valores por defecto publicados, configurables al construir el codec:

- ZIP: 100 GB;
- total descomprimido: 250 GB;
- entrada: 50 GB;
- JSON: 2 GB;
- entradas: 200.000;
- ratio: 200:1;
- ruta UTF-8: 512 bytes.

El codec comprueba overflow al sumar tamaños. No reserva ni garantiza previamente
el espacio libre del volumen; un fallo real de escritura se devuelve como
`fileOperation` y se limpia únicamente el staging creado por la llamada.

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

El análisis captura para cada fuente:

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
- ninguna API borra copias guardadas ni importaciones del cliente;
- `.completed` se emite después de validar salida;
- la transacción entre carpetas de Free My Chats queda fuera de la API.

## 25. Progreso y cancelación

### 25.1 Cancelación

```swift
public typealias WABackupCancellationHandler = @Sendable () -> Bool
```

La implementación comprueba:

- antes de cada fase;
- por bloques durante hashing/copia;
- por lotes durante canonización/alineación;
- antes de escribir resultados;
- antes de devolver éxito.

Lanzar un error público reconocible y limpiar temporales propios.

### 25.2 Fases nuevas

`WABackupProgress.Phase` contiene:

- `validatingConversationSources`
- `hashingConversationMedia`
- `canonicalizingConversationMessages`
- `inferringConversationPerspectives`
- `aligningConversationMessages`
- `classifyingConversationComposition`
- `materializingConversation`
- `copyingConversationMedia`
- `creatingPortableConversationArchive`
- `inspectingPortableConversationArchive`
- `extractingPortableConversationArchive`

Las unidades añadidas son:

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

La API publica estos dominios estructurados:

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

public enum PortableConversationArchiveError: Error, LocalizedError {
    case invalidSource(reason: String)
    case archiveAlreadyExists(URL)
    case invalidArchive(URL, reason: String)
    case unsupportedSchema(Int)
    case limitExceeded(reason: String)
    case unsafePath(String)
    case integrityMismatch(path: String)
    case invalidDirectory(URL, reason: String)
    case destinationNotEmpty(URL)
    case cancelled
    case fileOperation(URL, underlying: Error)
}
```

Ambos enums implementan `LocalizedError` en inglés y conservan el error
subyacente en I/O. Las causas semánticas de perspectiva no resuelta, solapamiento
insuficiente o conflicto se expresan en el
`ConversationCompositionDiagnostic` asociado a los casos
`crossPerspectiveCompositionRejected` y
`crossPerspectiveCompositionRequiresReview`; el cliente no necesita parsear
strings ni recibe contenido de chat.

## 27. Herramienta diagnóstica de Fase 0

SwiftWABackupCLI incluye la orden de solo lectura:

```text
swift run SwiftWABackupCLI diagnose-conversation-composition \
  --target-chat-dir /ruta/A/Chats/44 \
  --source-chat-dir /ruta/B/Chats/90 \
  --target-perspective-jid 34600000000@s.whatsapp.net \
  --source-perspective-jid 34611111111@s.whatsapp.net \
  --output-json /tmp/composition-diagnostic.json \
  --pretty
```

Las pistas de perspectiva son opcionales y el comando puede ejecutarse sin ellas
para evaluar la inferencia.

Comportamiento implementado:

- aceptar `chat.json` + `Media` v1;
- ninguna escritura en entradas;
- salida sin texto por defecto;
- incluir equivalencia, autores resolubles, relaciones de perspectiva, anclas,
  orden, coberturas, diferencias temporales, disposición y razones;
- un plan no aplicable es salida diagnóstica válida, no fallo técnico;
- ayuda y tests de parser siguiendo el CLI actual;
- permitir más de `--source-chat-dir` para probar N fuentes.

La suite cubre fuentes sintéticas locales, perspectivas de grupo e individual y
chats distintos con igual nombre. Los tests de biblioteca real permanecen
opt-in para no incorporar chats privados al repositorio.

El informe anonimizado expone:

- distribución de diferencias temporales;
- porcentaje de autores resolubles;
- calidad de inferencia con/sin pistas;
- densidad de anclas;
- comportamiento conservador ante mensajes repetitivos;
- coberturas target y fuente.

## 28. Implementación por fases

### Incremento inicial — composición local y paridad con FreeMyChats — IMPLEMENTADO

Su contrato detallado está en
[`especificacion-swiftwabackupapi-fusion-local-inicial.md`](especificacion-swiftwabackupapi-fusion-local-inicial.md).

- SwiftWABackupAPI contiene la composición N-aria que construye la Vista
  unificada de FreeMyChats.
- Trabaja con `StoredChatDocument` v2 y fuentes de la misma perspectiva,
  declaradas mediante una restricción relacional explícita.
- Incluye validación, canonización, deduplicación exacta, orden, atribución por
  fuente, impacto de retirada, reconstrucción de IDs/replies, contactos,
  multimedia, materialización en staging, progreso y cancelación.
- FreeMyChats lo integra como cliente y conserva instalación,
  persistencia de su biblioteca y transacción/rollback.
- La paridad funcional y el determinismo se validan con fixtures sintéticos y la
  biblioteca real en modo de solo lectura.

El perfil local no infiere perspectivas ni procesa `.fmcchat`; el perfil
conservador y el codec portable proporcionan esas capacidades sin introducir
identidad global del propietario. La relación `samePerspective` es un dato de la
operación, no una identidad persistida.

### Fase 0 de la evolución portable — núcleo diagnóstico — IMPLEMENTADA

- `ConversationSource`.
- Canonización relativa.
- Firmas de contenido y hash de medios.
- Inferencia de perspectivas.
- Alineación inicial y plan diagnóstico.
- CLI y fixtures sintéticos.
- Informe real anonimizado y propuesta de policy.

### Fase 1 — ampliación del motor general — IMPLEMENTADA

- La API pública N-aria amplía el incremento inicial.
- Plan, diagnóstico y confianza cubren relaciones no declaradas.
- La canonización, alineación y materialización funcionan entre perspectivas.
- Se conserva compatibilidad con los casos de Vista unificada y sus fixtures.
- Los errores y resultados diagnósticos reutilizan el mismo motor.

### Fase 2 — contrato portable — IMPLEMENTADA

- Modelos JSON v1.
- Directorio canónico.
- Codec ZIP seguro.
- Creación/inspección/extracción.
- Fixtures maliciosos y documentación.

La implementación usa ZIPFoundation 0.9.20 encapsulada dentro del codec. El ZIP
se inspecciona antes de extraer, solo admite los ficheros canónicos declarados y
el directorio extraído vuelve a validarse. Free My Chats usa wrappers internos
para crear, inspeccionar y extraer, y registra el resultado validado como
aportación de biblioteca.

### Fase 3 — integración persistente entre perspectivas — IMPLEMENTADA

- Free My Chats persiste cada importación como fuente portable en
  `ImportedChats`.
- La instalación en `MergedChats` dispone de rollback.
- Varias importaciones y la retirada reconstruyen desde las fuentes conservadas.
- `ConversationArchiveRecord` registra procedencia, digests e impacto por
  aportación.
- La interfaz permite seleccionar, importar, listar, abrir en Finder y retirar.

La orientación target, las pistas opcionales y el staging previo a instalación
proceden de la Fase 1.

Esta fase no añade operaciones de biblioteca a SwiftWABackupAPI. Free My Chats
abre de nuevo cada fuente persistida,
ejecuta `analyze` y materializa una preparación recién validada. El contrato
actual no reutiliza evidencia entre ejecuciones y recalcula la composición para
evitar mapeos obsoletos.

### Fase 4 — endurecimiento y release — IMPLEMENTADA

- Rendimiento/memoria.
- Cancelación/progreso.
- Matriz de plataformas.
- README, contrato JSON, seguridad y release notes.
- `swift build` y `swift test`.
- tag `5.0.0` consumible por Free My Chats.

## 29. Pruebas obligatorias

### 29.1 Paridad con fusión local actual

- Una única fuente produce conversación equivalente.
- Dos copias guardadas sucesivas de la misma perspectiva.
- Solapamiento sin duplicados.
- Tres aportaciones y conteos exclusivos.
- LID/JID de un participante cambian entre copias.
- Distintos JID/nombre igual permanecen separados.
- Respuestas remapeadas.
- Mismo nombre de medio con datos distintos.
- Mismo medio con nombres distintos.
- Reconstrucción sin una fuente.
- Orden determinista en empates.
- Resultado abrible por `StoredChatDocument`.

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
- Señales débiles repetidas no se convierten en anclas ni se agrupan
  accidentalmente.
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
- Contenido central diferente permanece como mensaje separado; un mismo ID
  estable con contenido incompatible produce error.
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
- conflicto de perspectiva o ID estable incompatible;
- paquete portable válido mínimo.

Generar ZIP maliciosos durante tests cuando sea posible. Los chats reales se usan
solo localmente; informes anonimizan nombres, teléfonos, texto y hashes completos.

## 31. Documentación publicada en SwiftWABackupAPI

SwiftWABackupAPI 5.0.0 incluye:

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

La documentación establece expresamente:

- no se persiste una identidad global obligatoria del propietario;
- el paquete conserva perspectiva relativa;
- una pista de perspectiva es opcional y validada;
- hashes no autentican remitente;
- la API no modifica WhatsApp ni bibliotecas de Free My Chats.

## 32. Criterios de aceptación verificados

La versión 5.0.0 cumple:

1. La misma API compone copias guardadas locales y fuentes importadas.
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
12. Perspectivas contradictorias o no resueltas no son aplicables.
13. El análisis no escribe.
14. La materialización reorienta respecto al target.
15. IDs y replies se remapean y se devuelven IDs estables.
16. Multimedia se deduplica por SHA-256.
17. Plan y diagnóstico son persistibles y versionados; la reconstrucción vuelve a
    analizar las fuentes y valida sus digests antes de materializar.
18. Crea `.fmcchat` desde una copia guardada o materialización sin copia fuente.
19. El paquete no incluye `sourceOwner` obligatorio ni IDs SQLite.
20. El codec resiste traversal, links, duplicados, corrupción y bombas.
21. Entradas modificadas entre análisis/aplicación se rechazan.
22. Progreso/cancelación funcionan.
23. Salida y planes son deterministas para las mismas entradas/policy.
24. La superficie pública, los perfiles y el contrato portable están documentados
    en README y en los documentos de SwiftWABackupAPI.
25. `swift build` y 149 pruebas pasan, incluida la validación de solo lectura de la
    biblioteca real; la compilación de distribución usa target macOS 13 Ventura.
26. El tag y release `5.0.0` están publicados y son consumibles por Free My Chats.

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
- cambiar `StoredChatDocument` v2 sin incrementar explícitamente su esquema;
- sustituir ZIP por otro contenedor;
- invocar herramientas ZIP del sistema desde la biblioteca;
- añadir dependencia que cambie plataformas soportadas;
- filtrar contenido real en logs/fixtures;
- fijar la policy entre perspectivas sin la Fase 0 diagnóstica;
- hacer que la API instale o borre estructura de Free My Chats.

## 34. Entrega realizada

El incremento local, el diagnóstico, la composición entre perspectivas y el
codec `.fmcchat` v1 se introdujeron en SwiftWABackupAPI 5.0.0 y se consumen con
la terminología pública de SwiftWABackupAPI 6.0.0. Free My Chats 2.0.0 completa
la exportación, el registro de aportaciones portables, su instalación reversible
y la reconstrucción al retirarlas. SwiftWABackupAPI continúa sin escribir
`library.json`, `archive.json`, `ImportedChats` ni `MergedChats`.
