# FreeMyChats

FreeMyChats es una aplicación nativa para macOS que localiza las copias de seguridad de iPhone disponibles y muestra cuáles contienen datos de WhatsApp. La interfaz permite analizar la carpeta estándar de MobileSync o seleccionar otra ubicación, e indica de forma clara si cada copia está lista, cifrada o no contiene la base de datos esperada.

## Relación con SwiftWABackupAPI

Este proyecto utiliza [SwiftWABackupAPI](https://github.com/domingogallardo/SwiftWABackupAPI), el paquete Swift que implementa el acceso a las copias de iPhone y la detección, extracción y lectura de los datos de WhatsApp. FreeMyChats proporciona una interfaz gráfica sobre esa API: en su estado actual se centra en descubrir e inspeccionar copias, mientras que SwiftWABackupAPI contiene la lógica reutilizable y también ofrece una herramienta de línea de comandos.

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
