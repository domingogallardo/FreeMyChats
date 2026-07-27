# Free My Chats

**Free My Chats** es una aplicación nativa para macOS que extrae tu WhatsApp de tu copia de seguridad de iPhone y la convierte en una biblioteca local persistente en tu disco duro.

¿Tienes chats de WhatsApp que ocupan varios gigas y que no vas a volver a consultar, pero que no quieres eliminar por el miedo a necesitarlos en el futuro? Ahora con **Free My Chats** puedes guardarlos en el disco duro de tu Mac, con todas sus imágenes y audios, listos para ser explorados y consultados en cualquier momento y para incluirlos en tus copias de seguridad. Una vez copiados en tu biblioteca de Free My Chats, puedes usar la opción `Vaciar chat` en WhatsApp y recuperar esos gigas preciosos que necesitas urgentemente.

![Vista general de Free My Chats](docs/images/free-my-chats-overview.png)

La biblioteca mantiene dos niveles deliberadamente distintos:

- La columna izquierda organiza las distintas copias locales de WhatsApp y muestra claramente el espacio ocupado por cada una.
- Al seleccionar un chat se despliega su información; la copia física y autocontenida solo se crea al pulsar `Añadir a la biblioteca`.
- Cada copia guardada desde la columna izquierda se puede abrir en Finder o borrar de forma independiente.
- La columna derecha contiene el catálogo y muestra cada conversación una sola vez. Si procede de varias copias guardadas, al pulsarla abre su cronología combinada; una flecha permite volver al catálogo.
- La selección y navegación del catálogo no cambian al explorar chats o copias en el panel izquierdo.
- Una copia fuente se puede eliminar para liberar espacio sin perder los chats que ya estuvieran guardados en la biblioteca.

## Funcionalidades detalladas

- Descubrimiento e inspección de copias de iPhone en MobileSync o en otra carpeta.
- Creación y reapertura de bibliotecas locales con múltiples versiones de una copia.
- Incorporación y eliminación de copias desde el navegador lateral.
- Listado de los chats de cada copia con tamaño multimedia en GB, filtros por grupo, persona o archivado,
  y orden por fecha o por tamaño de mayor a menor.
- Vista previa de número de mensajes y fechas antes de añadir un chat a la biblioteca.
- Incorporación explícita a la biblioteca desde la fila desplegada del chat.
- Exportación de la conversación visible completa como archivo autocontenido
  `.fmcchat`, incluyendo todas las copias locales y chats importados de su Vista
  unificada.
- Importación de `.fmcchat` sobre una conversación existente: la aplicación
  localiza automáticamente una única coincidencia segura, crea la Vista unificada
  y conserva la aportación de forma reversible en `ImportedChats`.
- Grupo `Chats importados` en la parte superior de la columna izquierda, con
  nombre, fecha de importación y acciones para abrir o retirar cada aportación.
- Actualización incremental: si el mismo chat ya se guardó desde una copia anterior,
  `Añadir a la biblioteca` conserva la nueva copia por separado y reúne los
  mensajes de todas las copias guardadas en una sola cronología, sin crear un duplicado
  en el catálogo.
- Antes de añadir una copia, la confirmación indica cuántos mensajes contiene
  y cuántos puede añadir como máximo; al terminar muestra la cifra incorporada realmente.
  Antes de borrar, indica al instante cuántos mensajes exclusivos deja de aportar
  esa copia.
- Identificación por JID y tipo de chat, deduplicación de mensajes coincidentes y
  conservación de cada copia como aportación reconstruible.
- Indicador de actividad mientras se añade un chat a la biblioteca.
- Detección de copias guardadas vigentes, desactualizadas o inválidas.
- Visor de mensajes, autores, respuestas con vista previa, reacciones
  consultables por autor, ubicaciones y adjuntos, con reproductor integrado para
  los audios.
- Navegación entre los mensajes de respuesta y sus originales, con resaltado
  temporal y retorno al punto de partida.
- Búsqueda de texto dentro de la conversación guardada.
- Acciones para abrir la biblioteca, cada copia guardada y la carpeta de la conversación combinada en Finder.
- Borrado por copia guardada desde la columna izquierda: el catálogo reconstruye la conversación con las copias restantes y la retira si ya no queda ninguna.
- Limpieza automática de una copia sin fuente cuando se borra su último chat guardado.
- Guía para conceder acceso total al disco y volver a intentar la inspección cuando sea necesario.
- Opción de mover a la Papelera la copia original del iPhone después de extraer WhatsApp.
- Recordatorio de que, tras guardar un chat en la biblioteca, puedes usar `Vaciar chat` en WhatsApp para liberar espacio en el iPhone.

## Estructura de una biblioteca

```text
Mi biblioteca Free My Chats/
├── library.json
├── Sources/
│   └── <sourceId>/
│       ├── Backup/
│       │   ├── ChatStorage.sqlite
│       │   ├── .wa-backup/
│       │   └── …
│       └── Catalog/
│           └── ChatProfilePhotos/
├── StoredChats/
│   └── Copia 2026-04-03 21.26/
│       └── Chats/
│           └── <chatId>/
│               ├── archive.json  # Solo si es la única aportación
│               ├── chat.json
│               └── Media/
├── ImportedChats/
│   └── <conversationId>/
│       └── <importId>/
│           ├── manifest.json
│           ├── chat.json
│           └── Media/
└── MergedChats/
    └── <conversationId>/         # Varias copias locales o algún chat importado
        ├── archive.json
        ├── chat.json
        └── Media/
```

`StoredChats` conserva cada aportación ligada a la copia de la que procede.
`ImportedChats` conserva cada paquete recibido como una fuente independiente y
reversible.

Si una conversación solo tiene una aportación, su `archive.json` se guarda dentro
de la propia copia guardada y el panel derecho abre directamente ese `chat.json` y
su carpeta `Media`. No se crea una segunda carpeta para ella en `MergedChats`.

`MergedChats` contiene las conversaciones que reúnen varias copias locales o al
menos un chat importado. Cada una es una materialización completa: su `chat.json`
combina los mensajes, los ordena cronológicamente, elimina los coincidentes y
reconstruye sus identificadores y respuestas. La vista abre ese único documento
y su carpeta `Media`; no va saltando entre copias guardadas. Si varias
aportaciones contienen un archivo idéntico, la conversación combinada lo guarda
una sola vez.

La descripción técnica completa está en
[Conversaciones materializadas](docs/conversaciones-materializadas.md).

## Descargar el código fuente

La versión estable más reciente está disponible en [GitHub Releases](https://github.com/domingogallardo/FreeMyChats/releases/latest). La publicación incluye únicamente el código fuente: cada persona compila la aplicación en su propio Mac siguiendo la guía inferior.

## Relación con SwiftWABackupAPI

Este proyecto integra [SwiftWABackupAPI 6.0.0](https://github.com/domingogallardo/SwiftWABackupAPI/releases/tag/6.0.0), el paquete Swift que implementa el acceso a las copias de iPhone, la extracción de WhatsApp, el guardado persistente de chats, la composición de conversaciones y el formato portable `.fmcchat` v1.

Free My Chats 2.1.0 usa la API de composición para
construir las Vistas unificadas y el formato `.fmcchat` v1. La API crea,
inspecciona, extrae, diagnostica, reorienta al target y materializa; Free My Chats
registra cada aportación en `ImportedChats`, instala el resultado o hace rollback
y permite retirarla posteriormente. La exportación, la búsqueda automática de
una única conversación receptora y la interfaz de importaciones están
implementadas y probadas. `Package.swift` fija la versión exacta `6.0.0` para
mantener sincronizados el contrato JSON, la terminología de chats guardados y el
motor de composición.

## Requisitos

- macOS Ventura 13 o posterior.
- Swift 5.9 o posterior.
- Acceso a una carpeta de copias de seguridad de iPhone.
- Permiso de acceso total al disco para la aplicación o Terminal cuando macOS lo requiera.

La ubicación predeterminada de las copias es:

```text
~/Library/Application Support/MobileSync/Backup/
```

## Guía para descargar, compilar y ejecutar

No hace falta saber programar, pero sí utilizar brevemente la aplicación Terminal. El proceso no modifica el sistema y se puede repetir cuando se publique una versión nueva.

### 1. Instalar las herramientas de Apple

Abre **Terminal** desde `Aplicaciones > Utilidades > Terminal`, copia este comando, pégalo y pulsa Intro:

```bash
xcode-select --install
```

macOS abre una ventana para instalar las herramientas de desarrollo. Si indica que ya están instaladas, continúa con el paso siguiente.

### 2. Descargar Free My Chats

En la página de la [versión más reciente](https://github.com/domingogallardo/FreeMyChats/releases/latest), abre el apartado **Assets** y descarga **Source code (zip)**. Descomprime el ZIP con doble clic y mueve la carpeta resultante a un lugar que recuerdes, por ejemplo `Documentos`.

### 3. Abrir la carpeta desde Terminal

Escribe `cd` seguido de un espacio en Terminal. Arrastra la carpeta descomprimida desde Finder hasta la ventana de Terminal y pulsa Intro. El comando tiene un aspecto parecido a este:

```bash
cd ~/Documents/FreeMyChats-1.3.8
```

### 4. Compilar y abrir la aplicación

Ejecuta:

```bash
./script/build_and_run.sh
```

La primera compilación puede tardar unos minutos porque Swift Package Manager descarga SwiftWABackupAPI y sus dependencias. Al terminar, el script crea `dist/FreeMyChats.app` y abre la aplicación automáticamente.

La primera vez, crea una biblioteca donde guardar los chats extraídos. Si la biblioteca está vacía, Free My Chats abre automáticamente la pantalla para localizar y analizar las copias del iPhone.

Puedes ejecutar esa copia directamente para comprobar que funciona o repetir el comando anterior cuando necesites volver a compilar.

### 5. Mover la aplicación a Aplicaciones

Una vez compilada, abre la carpeta `dist` y arrastra `FreeMyChats.app` a la carpeta `Aplicaciones` del Mac. A partir de ese momento se abre normalmente desde Finder, Launchpad o Spotlight sin conservar la aplicación dentro de la carpeta del código fuente.

Si vuelves a compilar una versión nueva, sustituye la copia de `Aplicaciones` por la nueva `dist/FreeMyChats.app`.

### 6. Conceder acceso a las copias del iPhone

Si macOS impide leer la copia, abre `Ajustes del Sistema > Privacidad y seguridad > Acceso total al disco`, añade o activa la copia de **Free My Chats** que has trasladado a `Aplicaciones` y reinicia la aplicación. Si la biblioteca está vacía, la comprobación continúa al arrancar; si ya contiene copias, pulsa `Añadir copia` para volver a intentarlo. Si sustituyes la aplicación después de recompilar, macOS puede pedir que retires la entrada anterior y vuelvas a añadir la copia nueva.

### Alternativa para personas familiarizadas con Git

```bash
git clone https://github.com/domingogallardo/FreeMyChats.git
cd FreeMyChats
./script/build_and_run.sh
```

## Privacidad

FreeMyChats está pensado para tareas legítimas de copia, recuperación y análisis personal. Utiliza únicamente copias sobre las que tengas derecho de acceso y respeta la privacidad de las personas participantes en las conversaciones.

## Licencia

Free My Chats se distribuye bajo la [PolyForm Noncommercial License 1.0.0](LICENSE.md). Puedes descargar, estudiar, modificar y redistribuir el código con fines no comerciales. No puedes vender la aplicación ni utilizar el código o sus modificaciones para crear un producto o servicio comercial.

Esta es una licencia de código fuente disponible, no una licencia _open source_ aprobada por la OSI, porque restringe expresamente el uso comercial.
