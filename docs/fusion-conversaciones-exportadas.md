# Fusión de conversaciones exportadas en FreeMyChats

## Estado

Diseño de una funcionalidad futura. No está implementada.

La evaluación de este diseño frente a la implementación actual de Vistas
unificadas está en
[Evaluación para exportar e importar conversaciones entre propietarios](evaluacion-importacion-conversaciones.md).

La especificación vigente para el agente de SwiftWABackupAPI es
[Motor general de fusión y conversaciones portables](especificacion-swiftwabackupapi-motor-fusion-portable.md).
Esta última sustituye las propuestas anteriores que exigían persistir una
identidad global del propietario: la perspectiva se infiere durante el análisis o
se aporta opcionalmente como parámetro.

Este documento no describe la unificación incremental que ya realiza la
aplicación con varias exportaciones locales. El funcionamiento vigente de
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
4. Mostrar mensajes coincidentes, nuevos, ambiguos y conflictos, además del
   espacio multimedia adicional.
5. Confirmar la importación.
6. Materializar la conversación combinada de forma atómica.
7. Volver a abrir el chat manteniendo en lo posible la posición de lectura.

Un resumen posible sería:

```text
Misma conversación entre Ana y Bruno

1.842 mensajes coincidentes
  127 mensajes nuevos
   18 archivos multimedia nuevos · 246 MB
    0 conflictos

Confianza de la fusión: alta
```

### Consultar y deshacer

La opción `Importaciones de esta conversación…` mostrará la fecha, procedencia y
resultado de cada importación. Desde ahí se podrá retirar una aportación y
reconstruir la conversación sin sus mensajes exclusivos.

## Formato de intercambio `.fmcchat`

Un `.fmcchat` será un ZIP con extensión propia y una raíz canónica:

```text
Conversacion.fmcchat
├── manifest.json
├── chat.json
└── Media/
    └── …
```

La creación del paquete debe:

- Incluir la conversación materializada visible, aunque contenga importaciones
  anteriores.
- Excluir las capas internas `Base` e `Imports` y su historial de procedencia.
- Incluir únicamente archivos multimedia referenciados por `chat.json`.
- Añadir tamaño y SHA-256 de cada archivo al manifiesto.
- Escribir en una ubicación temporal y mover el resultado al terminar.
- Producir un nombre legible sin utilizarlo como identidad de la conversación.

### Manifiesto propuesto

```swift
public struct PortableConversationManifest: Codable {
    public let schemaVersion: Int
    public let generator: String
    public let generatorVersion: String
    public let createdAt: Date
    public let sourceOwner: PortableParticipantIdentity
    public let conversationKey: PortableConversationKey
    public let messageCount: Int
    public let media: [PortableMediaEntry]
}
```

El manifiesto no certifica la autenticidad de quien lo entrega. Los hashes
garantizan integridad interna, no identidad criptográfica.

## Identidad de la conversación

El nombre visible no sirve para decidir si dos conversaciones son la misma.

```swift
public enum PortableConversationKey: Codable, Hashable {
    case group(groupJID: String)
    case individual(participants: Set<PortableParticipantIdentity>)
}
```

### Grupos

Se utiliza el JID canónico del grupo. Además se comprueba que ambos documentos
declaran `chatType == .group`.

### Conversaciones individuales

Desde cada teléfono, `contactJid` identifica a la otra persona. Por tanto, la
clave se forma con el conjunto no ordenado de las dos identidades absolutas:

```text
{ identidad del propietario, identidad del interlocutor }
```

Las identidades deben normalizar los alias telefónicos y LID conocidos por la
API. Si no se puede demostrar que ambas exportaciones contienen a las mismas dos
personas, la importación se rechaza o queda pendiente de confirmación explícita.

## Normalización de autores

`isFromMe` expresa la perspectiva del propietario de cada exportación y no puede
copiarse directamente.

Antes de alinear mensajes, la API convierte cada autor en una identidad absoluta:

- En la exportación local, el propietario se convierte en `localOwner`.
- En el archivo recibido, su `.me` se convierte en la identidad de quien lo
  compartió.
- En una conversación individual, los mensajes recibidos por quien comparte se
  atribuyen al otro participante.
- En un grupo se reconcilian JID telefónico, JID LID, teléfono normalizado y los
  alias resueltos por la API.

Después de fusionar se recalcula `isFromMe` respecto al propietario de la
biblioteca receptora.

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
    let author: CanonicalParticipantIdentity?
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

El texto se normaliza de manera conservadora: Unicode canónico y saltos o espacios
equivalentes, sin eliminar puntuación, emojis ni diferencias semánticas.

### Huellas fuertes y débiles

Una huella fuerte combina:

```text
autor canónico
+ instante del mensaje
+ tipo
+ hash del contenido textual o multimedia
```

Una huella débil puede carecer de autor, multimedia o contenido distintivo. Un
mensaje aislado como `Sí` o un emoji repetido nunca debe actuar por sí solo como
ancla definitiva.

### Construcción de anclas

1. Calcular las huellas de ambas secuencias.
2. Seleccionar huellas fuertes que aparezcan una sola vez en cada secuencia.
3. Emparejar sus posiciones.
4. Obtener la mayor cadena de pares que conserve el orden cronológico.
5. Descartar anclas que produzcan cruces o saltos incoherentes.

Esta cadena puede calcularse en `O(n log n)` mediante índices de hashes y una
subsecuencia creciente, evitando un LCS cuadrático sobre chats grandes.

### Ventanas de contexto

Para mensajes repetitivos se calculan hashes de ventanas de tres a cinco mensajes
consecutivos. La secuencia completa proporciona una señal fuerte aunque alguno de
sus mensajes sea genérico:

```text
Ana: ¿Quedamos mañana?
Bruno: Sí
Ana: A las diez
```

### Expansión entre anclas

Una vez localizada una cadena de anclas, se comparan los intervalos situados entre
ellas. Las coincidencias exactas se expanden hacia ambos lados y las diferencias
se clasifican sin alterar todavía ningún archivo.

### Resultado del análisis

```swift
public struct ConversationMergePlan {
    public let conversationKey: PortableConversationKey
    public let matches: [MessageMatch]
    public let onlyInTarget: [SourceMessageReference]
    public let onlyInImport: [SourceMessageReference]
    public let conflicts: [MessageConflict]
    public let ambiguousRegions: [AmbiguousRegion]
    public let confidence: MergeConfidence
    public let additionalMediaBytes: Int64
}
```

Las categorías serán:

- `matched`: mismo mensaje en ambos documentos.
- `onlyInTarget`: solo existe en la exportación local.
- `onlyInImport`: mensaje que debe añadirse.
- `conflicting`: probablemente el mismo mensaje, pero con contenidos distintos.
- `ambiguous`: existen varias alineaciones plausibles.

## Confianza y política de seguridad

La fusión automática requiere una confianza alta. Se tendrán en cuenta:

- Número y densidad de anclas fuertes.
- Longitud y cobertura temporal del tramo compartido.
- Porcentaje de anclas que mantiene el mismo orden.
- Consistencia de las diferencias de fecha.
- Calidad de la resolución de autores.
- Número de ventanas contextuales coincidentes.
- Cantidad de regiones ambiguas o conflictos.

No se fijarán umbrales definitivos sin probar el algoritmo con conversaciones
reales. Como política inicial:

- Confianza alta y cero conflictos: permitir la fusión.
- Confianza media: mostrar diagnóstico y no fusionar automáticamente.
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

Para un mensaje alineado, la primera versión puede aplicar una política sencilla:

- Conservar el contenido central validado por la alineación.
- Preferir los metadatos de la exportación más reciente cuando no entren en
  conflicto.
- Unir contactos e identidades por clave canónica.
- Informar de diferencias que no tengan todavía una política explícita.

Las reglas concretas deben documentarse y cubrirse con pruebas antes de ampliar el
conjunto de campos combinados.

## Identidad propia de FreeMyChats

Al materializar la primera fusión, cada mensaje recibe un identificador estable de
archivo, independiente de WhatsApp y de SQLite:

```swift
public struct ArchiveMessageID: Codable, Hashable {
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

Al reemplazar la exportación base desde una copia de iPhone, SwiftWABackupAPI debe
preservar `Imports`, instalar la nueva base y volver a materializar la unión. Nunca
debe reemplazar toda la carpeta descartando silenciosamente las aportaciones.

La semántica no dependerá de la estrategia física utilizada para materializar la
multimedia.

## Ampliaciones propuestas en SwiftWABackupAPI

La API debe ser propietaria del formato, la validación, la alineación y las
operaciones atómicas.

```swift
public extension ChatExportStore {
    func createPortableArchive(
        chatId: Int,
        destination: URL,
        progress: WABackupProgressHandler? = nil
    ) throws -> URL

    func inspectImport(
        packageURL: URL,
        intoChat chatId: Int,
        progress: WABackupProgressHandler? = nil
    ) throws -> ConversationMergePlan

    func applyImport(
        _ plan: ConversationMergePlan,
        progress: WABackupProgressHandler? = nil
    ) throws -> ImportedConversationContribution

    func listImports(chatId: Int) throws -> [ImportedConversationContribution]

    func removeImport(
        id: UUID,
        fromChat chatId: Int,
        progress: WABackupProgressHandler? = nil
    ) throws -> ExportedChat
}
```

También será necesario:

- Un schema nuevo de exportación que incluya identidad del propietario,
  `ConversationKey` y `ArchiveMessageID` opcional.
- Construcción pública o interna controlada de documentos materializados.
- Nuevas fases de progreso: validación, hashing, alineación, copia multimedia y
  materialización.
- Errores específicos para conversación distinta, paquete incompatible,
  identidad ambigua, conflicto y confianza insuficiente.
- Lectura compatible de los documentos actuales.

FreeMyChats no debe implementar un segundo motor de fusión manipulando JSON.

## Ampliaciones propuestas en FreeMyChats

### Estado y servicios

- Añadir operaciones `creatingSharePackage`, `inspectingImport`, `importingMessages`
  y `removingImport` a `FreeMyChatsStore`.
- Incorporar un servicio delgado para elegir destinos y archivos mediante paneles
  de macOS.
- Refrescar el catálogo de chats exportados, la conversación abierta y la posición
  de lectura tras materializar.
- Persistir el propietario canónico de la biblioteca o versión cuando sea
  necesario para recalcular `isFromMe`.

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

- FreeMyChats seguirá abriendo las exportaciones actuales.
- Crear un `.fmcchat` fusionable requerirá que el documento tenga la identidad y
  metadatos exigidos por el nuevo schema.
- Si la copia fuente existe, una exportación antigua puede actualizarse antes de
  compartirla.
- Si la fuente fue eliminada y no se puede obtener la identidad necesaria, la
  aplicación podrá solicitar datos explícitos o explicar que esa exportación no se
  puede convertir de forma segura.
- No se aplicará una migración destructiva al abrir una biblioteca.

## Seguridad y atomicidad

Los paquetes se consideran entrada no confiable aunque provengan de FreeMyChats:

- Limitar tamaño total, número de entradas y tamaño individual antes de extraer.
- Rechazar rutas absolutas, `..`, enlaces simbólicos y nombres inseguros.
- Validar schema, manifiesto, hashes y referencias multimedia.
- No sobrescribir archivos fuera del chat objetivo.
- Preparar toda la vista combinada en un hermano temporal.
- Validar el documento y sus medios antes de reemplazar la vista vigente.
- Conservar intacta la conversación anterior si se cancela o falla la operación.

## Rendimiento

- Calcular hashes multimedia en streaming.
- Indexar huellas de mensajes en diccionarios.
- Construir la cadena de anclas en `O(n log n)`.
- Limitar la comparación contextual a intervalos entre anclas.
- Publicar progreso y admitir cancelación.
- Cachear hashes multimedia por tamaño y fecha de modificación dentro de la
  biblioteca, sin confiar en esa caché para validar paquetes externos.

## Pruebas necesarias

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

### Fase 0: validación del enfoque

Conseguir dos exportaciones FreeMyChats de un mismo grupo y dos de una conversación
individual. Crear una herramienta de diagnóstico que calcule huellas, anclas,
alineación, ambigüedades y cobertura sin modificar archivos.

### Fase 1: contrato portable

Definir el nuevo schema, identidad canónica, manifiesto, hashes y creación validada
de `.fmcchat`.

### Fase 2: motor de análisis

Implementar representación canónica, huellas, ventanas, anclas ordenadas,
clasificación y confianza. Validarlo con fixtures sintéticos y exportaciones reales.

### Fase 3: materialización reversible

Introducir `Base`, `Imports`, `merge-manifest.json`, reasignación de IDs, respuestas,
multimedia y rollback atómico.

### Fase 4: experiencia en FreeMyChats

Añadir crear archivo, inspeccionar, confirmar, importar, consultar procedencia y
deshacer.

### Fase 5: endurecimiento

Calibrar umbrales, rendimiento, cancelación, paquetes maliciosos, migraciones y
reexportación de la base.

## Criterios de aceptación del MVP

- Fusiona grupos y conversaciones individuales generados por FreeMyChats.
- No utiliza `stanzaId` para identificar mensajes.
- Rechaza automáticamente conversaciones distintas y alineaciones ambiguas.
- No duplica los mensajes compartidos ni la multimedia idéntica.
- Normaliza correctamente `isFromMe` desde la perspectiva local.
- Conserva y remapea respuestas dentro de los datos disponibles.
- Permite deshacer una importación.
- Una reexportación de la base no elimina aportaciones importadas.
- Cualquier fallo deja intacta la exportación anterior.
- Las exportaciones existentes continúan siendo legibles.

## Riesgos y preguntas abiertas

- Cuánto varían realmente los timestamps entre dos copias del mismo mensaje.
- Qué porcentaje de mensajes carece de autor absoluto resoluble.
- Qué tipos producen huellas débiles o contenido diferente según el dispositivo.
- Qué umbral de solapamiento permite afirmar una fusión inequívoca.
- Cómo resolver metadatos mutables cuando las exportaciones tienen edades distintas.
- Qué estrategia física evita duplicar medios sin complicar la portabilidad y el
  rollback.
- Cómo convertir exportaciones antiguas cuando la copia fuente ya no existe.

Estas cuestiones deben resolverse mediante el diagnóstico de la fase 0 antes de
fijar el contrato definitivo.

## Siguiente gesto al retomar

Preparar cuatro exportaciones reales —dos participantes de un grupo y las dos
perspectivas de una conversación individual— y construir en SwiftWABackupAPI un
prototipo de solo lectura que produzca `ConversationMergePlan`. No diseñar todavía
la escritura definitiva hasta medir la calidad real de la alineación.
