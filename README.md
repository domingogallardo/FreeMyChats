# Free My Chats

Free My Chats es una aplicación nativa para macOS que convierte los datos de WhatsApp de una copia de iPhone en una biblioteca local de conversaciones.

La biblioteca mantiene dos niveles deliberadamente distintos:

- La columna izquierda organiza las distintas copias locales de WhatsApp y muestra claramente el espacio ocupado por cada una.
- Al seleccionar un chat se despliega su información; la exportación física y autocontenida solo se crea al pulsar `Exportar`.
- La columna derecha mantiene un listado independiente de chats exportados. Al pulsar uno abre su `chat.json` y los archivos de `Media`; una flecha permite volver al listado.
- La selección y navegación del panel derecho no cambian al explorar chats o copias en el panel izquierdo.
- Una copia fuente se puede eliminar para liberar espacio sin perder los chats que ya estuvieran exportados.

## Funciones del MVP

- Descubrimiento e inspección de copias de iPhone en MobileSync o en otra carpeta.
- Creación y reapertura de bibliotecas locales con múltiples versiones de una copia.
- Incorporación y eliminación de copias desde el navegador lateral.
- Catálogo de chats con búsqueda y filtros por grupo, persona o archivado.
- Vista previa de número de mensajes y fechas antes de exportar.
- Exportación explícita desde la fila desplegada del chat.
- Detección de exportaciones vigentes, desactualizadas o inválidas.
- Visor de mensajes, autores, respuestas, reacciones, ubicaciones y adjuntos.
- Búsqueda de texto dentro del chat exportado.
- Acciones para abrir la biblioteca, la carpeta del chat y sus archivos en Finder, o borrar una exportación.
- Limpieza automática de una copia sin fuente cuando se borra su último chat exportado.

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
└── Exports/
    └── Copia 2026-04-03 21.26/
        └── Chats/
            └── <chatId>/
                ├── chat.json
                └── Media/
```

`Exports` permanece vacío hasta que el usuario exporta un chat. Los recursos
auxiliares del navegador, como las fotos de perfil, se guardan junto a su copia
fuente. Las bibliotecas anteriores se reorganizan automáticamente al abrirse:
se conservan sus exportaciones y los UUID visibles se sustituyen por nombres de
carpeta basados en la fecha de la copia.

## Relación con SwiftWABackupAPI

Este proyecto utiliza [SwiftWABackupAPI 4.2 o posterior](https://github.com/domingogallardo/SwiftWABackupAPI), el paquete Swift que implementa el acceso a las copias de iPhone, la extracción de WhatsApp y las exportaciones persistentes de chats.

## Requisitos

- macOS 14 o posterior.
- Swift 5.9 o posterior.
- Acceso a una carpeta de copias de seguridad de iPhone.
- Permiso de acceso total al disco para la aplicación o Terminal cuando macOS lo requiera.

La ubicación predeterminada de las copias es:

```text
~/Library/Application Support/MobileSync/Backup/
```

## Compilar y ejecutar

Desde la raíz del repositorio:

```bash
swift build
./script/build_and_run.sh
```

El script crea `dist/FreeMyChats.app` y abre la aplicación. Swift Package Manager descarga automáticamente SwiftWABackupAPI y sus dependencias.

## Privacidad

FreeMyChats está pensado para tareas legítimas de copia, recuperación y análisis personal. Utiliza únicamente copias sobre las que tengas derecho de acceso y respeta la privacidad de las personas participantes en las conversaciones.
