#!/usr/bin/env swift

import Foundation

private let currentLibrarySchemaVersion = 2
private let currentStoredChatSchemaVersion = 2
private let currentArchiveSchemaVersion = 2

private enum MigrationError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

private struct Options {
    let libraryURL: URL
    let apply: Bool

    static func parse(_ arguments: [String]) throws -> Self? {
        if arguments.contains("--help") || arguments.contains("-h") {
            return nil
        }

        var apply = false
        var paths: [String] = []

        for argument in arguments {
            switch argument {
            case "--apply":
                apply = true
            default:
                if argument.hasPrefix("-") {
                    throw MigrationError.message("Opción desconocida: \(argument)")
                }
                paths.append(argument)
            }
        }

        guard paths.count == 1 else {
            throw MigrationError.message("Debe indicarse exactamente una biblioteca.")
        }

        let expandedPath = (paths[0] as NSString).expandingTildeInPath
        return Self(
            libraryURL: URL(fileURLWithPath: expandedPath, isDirectory: true)
                .standardizedFileURL,
            apply: apply
        )
    }
}

private enum DocumentKind: String {
    case storedChat = "chat.json"
    case conversationArchive = "archive.json"
}

private struct VersionDirectoryPlan {
    let id: String
    let oldName: String
    let newName: String
}

private struct DocumentPlan {
    let originalURL: URL
    let targetURL: URL
    let kind: DocumentKind
    let needsChange: Bool
}

private struct ManifestPlan {
    let updatedData: Data?
    let versions: [VersionDirectoryPlan]
    let sourceSchemaVersion: Int
}

private struct MigrationPlan {
    let libraryURL: URL
    let manifestURL: URL
    let legacyStorageURL: URL
    let storageURL: URL
    let sourceStorageURL: URL?
    let manifest: ManifestPlan
    let documents: [DocumentPlan]
    let shouldMoveStorageRoot: Bool
    let shouldCreateStorageRoot: Bool
    let versionMoves: [VersionDirectoryPlan]

    var changedDocuments: [DocumentPlan] {
        documents.filter(\.needsChange)
    }

    var hasChanges: Bool {
        manifest.updatedData != nil
            || shouldMoveStorageRoot
            || shouldCreateStorageRoot
            || !versionMoves.isEmpty
            || !changedDocuments.isEmpty
    }
}

private final class LibraryMigrator {
    private let fileManager = FileManager.default

    func makePlan(libraryURL: URL) throws -> MigrationPlan {
        try requireDirectory(libraryURL, description: "La biblioteca")

        let manifestURL = libraryURL.appendingPathComponent("library.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw MigrationError.message(
                "No se ha encontrado library.json en \(libraryURL.path)."
            )
        }

        let manifest = try planManifest(at: manifestURL)
        let legacyStorageURL = libraryURL.appendingPathComponent("Exports", isDirectory: true)
        let storageURL = libraryURL.appendingPathComponent("StoredChats", isDirectory: true)
        let legacyStorageKind = try itemKind(at: legacyStorageURL)
        let storageKind = try itemKind(at: storageURL)
        guard legacyStorageKind != .file else {
            throw MigrationError.message(
                "\(legacyStorageURL.path) existe, pero no es una carpeta."
            )
        }
        guard storageKind != .file else {
            throw MigrationError.message(
                "\(storageURL.path) existe, pero no es una carpeta."
            )
        }
        let legacyStorageExists = legacyStorageKind == .directory
        let storageExists = storageKind == .directory

        if legacyStorageExists && storageExists {
            throw MigrationError.message(
                "Existen a la vez Exports y StoredChats. Resuelve ese estado parcial antes de migrar."
            )
        }

        let sourceStorageURL: URL?
        if legacyStorageExists {
            sourceStorageURL = legacyStorageURL
        } else if storageExists {
            sourceStorageURL = storageURL
        } else {
            sourceStorageURL = nil
        }

        let versionMoves = try planVersionMoves(
            manifest.versions,
            in: sourceStorageURL
        )
        let mergedChatsURL = libraryURL.appendingPathComponent("MergedChats", isDirectory: true)
        var documents: [DocumentPlan] = []

        if let sourceStorageURL {
            documents += try planDocuments(
                below: sourceStorageURL,
                finalRoot: storageURL,
                versions: manifest.versions
            )
        }
        documents += try planDocuments(
            below: mergedChatsURL,
            finalRoot: mergedChatsURL,
            versions: []
        )

        return MigrationPlan(
            libraryURL: libraryURL,
            manifestURL: manifestURL,
            legacyStorageURL: legacyStorageURL,
            storageURL: storageURL,
            sourceStorageURL: sourceStorageURL,
            manifest: manifest,
            documents: documents.sorted { $0.originalURL.path < $1.originalURL.path },
            shouldMoveStorageRoot: legacyStorageExists,
            shouldCreateStorageRoot: !legacyStorageExists && !storageExists,
            versionMoves: versionMoves
        )
    }

    func apply(_ plan: MigrationPlan) throws -> URL? {
        guard plan.hasChanges else { return nil }

        let backupURL = try makeBackup(for: plan)
        var rootWasMoved = false
        var storageRootWasCreated = false
        var completedVersionMoves: [(from: URL, to: URL)] = []

        do {
            if plan.shouldMoveStorageRoot {
                try fileManager.moveItem(
                    at: plan.legacyStorageURL,
                    to: plan.storageURL
                )
                rootWasMoved = true
            } else if plan.shouldCreateStorageRoot {
                try fileManager.createDirectory(
                    at: plan.storageURL,
                    withIntermediateDirectories: false
                )
                storageRootWasCreated = true
            }

            for version in plan.versionMoves {
                let oldURL = plan.storageURL.appendingPathComponent(
                    version.oldName,
                    isDirectory: true
                )
                let newURL = plan.storageURL.appendingPathComponent(
                    version.newName,
                    isDirectory: true
                )
                try fileManager.moveItem(at: oldURL, to: newURL)
                completedVersionMoves.append((from: newURL, to: oldURL))
            }

            for document in plan.changedDocuments {
                guard let data = try transformedDocument(
                    at: document.targetURL,
                    kind: document.kind
                ) else {
                    continue
                }
                try data.write(to: document.targetURL, options: .atomic)
            }

            if let updatedManifest = plan.manifest.updatedData {
                try updatedManifest.write(to: plan.manifestURL, options: .atomic)
            }

            let verification = try makePlan(libraryURL: plan.libraryURL)
            guard !verification.hasChanges else {
                throw MigrationError.message(
                    "La verificación final ha detectado cambios pendientes."
                )
            }

            return backupURL
        } catch {
            let rollbackError = rollback(
                plan: plan,
                backupURL: backupURL,
                completedVersionMoves: completedVersionMoves,
                rootWasMoved: rootWasMoved,
                storageRootWasCreated: storageRootWasCreated
            )
            if let rollbackError {
                throw MigrationError.message(
                    "\(error.localizedDescription)\n"
                        + "Además, el rollback automático ha fallado: "
                        + "\(rollbackError.localizedDescription)\n"
                        + "La copia de los JSON originales está en \(backupURL.path)."
                )
            }
            throw error
        }
    }

    private func planManifest(at url: URL) throws -> ManifestPlan {
        var object = try jsonObject(at: url)
        guard let schemaVersion = integer(object["schemaVersion"]) else {
            throw MigrationError.message("library.json no contiene un schemaVersion válido.")
        }
        guard schemaVersion == 1 || schemaVersion == currentLibrarySchemaVersion else {
            throw MigrationError.message(
                "La versión \(schemaVersion) de library.json no puede migrarse con esta herramienta."
            )
        }
        guard var versions = object["versions"] as? [[String: Any]] else {
            throw MigrationError.message("library.json no contiene una lista versions válida.")
        }

        var directoryPlans: [VersionDirectoryPlan] = []
        var usedNames = Set(
            versions.compactMap { record -> String? in
                nonEmptyString(record["storageDirectoryName"])
                    ?? nonEmptyString(record["exportDirectoryName"])
            }
        )

        for index in versions.indices {
            var record = versions[index]
            guard let id = nonEmptyString(record["id"]) else {
                throw MigrationError.message("La versión \(index) de library.json no tiene id.")
            }

            let currentName = nonEmptyString(record["storageDirectoryName"])
            let legacyName = nonEmptyString(record["exportDirectoryName"])
            let oldName = legacyName ?? currentName ?? id
            let newName: String

            if let currentName {
                newName = currentName
            } else if let legacyName {
                newName = legacyName
            } else {
                guard let encodedDate = nonEmptyString(record["sourceBackupCreationDate"]),
                      let date = parseISO8601(encodedDate) else {
                    throw MigrationError.message(
                        "La versión \(id) no tiene una fecha de copia válida para calcular su carpeta."
                    )
                }
                newName = makeStorageDirectoryName(for: date, excluding: usedNames)
            }

            guard isSafeDirectoryName(newName) else {
                throw MigrationError.message(
                    "La versión \(id) contiene un nombre de carpeta no seguro: \(newName)"
                )
            }
            usedNames.insert(newName)

            if schemaVersion == 1 {
                record.removeValue(forKey: "exportDirectoryName")
                record["storageDirectoryName"] = newName
                versions[index] = record
            } else {
                guard currentName != nil else {
                    throw MigrationError.message(
                        "La versión \(id) del manifiesto v2 no contiene storageDirectoryName."
                    )
                }
            }

            directoryPlans.append(
                VersionDirectoryPlan(id: id, oldName: oldName, newName: newName)
            )
        }

        let duplicateNames = Dictionary(grouping: directoryPlans, by: \.newName)
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        guard duplicateNames.isEmpty else {
            throw MigrationError.message(
                "Varias versiones usarían la misma carpeta: \(duplicateNames.joined(separator: ", "))."
            )
        }

        let updatedData: Data?
        if schemaVersion == 1 {
            object["schemaVersion"] = currentLibrarySchemaVersion
            object["versions"] = versions
            updatedData = try encodedJSON(object)
        } else {
            updatedData = nil
        }

        return ManifestPlan(
            updatedData: updatedData,
            versions: directoryPlans,
            sourceSchemaVersion: schemaVersion
        )
    }

    private func planVersionMoves(
        _ versions: [VersionDirectoryPlan],
        in sourceStorageURL: URL?
    ) throws -> [VersionDirectoryPlan] {
        guard let sourceStorageURL else { return [] }
        var moves: [VersionDirectoryPlan] = []

        for version in versions where version.oldName != version.newName {
            let oldURL = sourceStorageURL.appendingPathComponent(
                version.oldName,
                isDirectory: true
            )
            let newURL = sourceStorageURL.appendingPathComponent(
                version.newName,
                isDirectory: true
            )
            let oldKind = try itemKind(at: oldURL)
            let newKind = try itemKind(at: newURL)

            if oldKind == .directory && newKind == .missing {
                moves.append(version)
            } else if oldKind == .missing && newKind == .directory {
                continue
            } else if oldKind == .missing && newKind == .missing {
                continue
            } else {
                throw MigrationError.message(
                    "No se puede renombrar \(oldURL.path) como \(newURL.lastPathComponent): "
                        + "el origen o el destino está en conflicto."
                )
            }
        }

        return moves
    }

    private func planDocuments(
        below sourceRoot: URL,
        finalRoot: URL,
        versions: [VersionDirectoryPlan]
    ) throws -> [DocumentPlan] {
        guard try itemKind(at: sourceRoot) == .directory else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw MigrationError.message("No se puede recorrer \(sourceRoot.path).")
        }

        var plans: [DocumentPlan] = []
        for case let url as URL in enumerator {
            let kind: DocumentKind
            switch url.lastPathComponent {
            case DocumentKind.storedChat.rawValue:
                kind = .storedChat
            case DocumentKind.conversationArchive.rawValue:
                kind = .conversationArchive
            default:
                continue
            }

            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw MigrationError.message(
                    "Se esperaba un archivo JSON normal en \(url.path)."
                )
            }

            var relativeComponents = try relativePathComponents(of: url, below: sourceRoot)
            if let first = relativeComponents.first,
               let version = versions.first(where: { $0.oldName == first }) {
                relativeComponents[0] = version.newName
            }
            let targetURL = relativeComponents.reduce(finalRoot) {
                $0.appendingPathComponent($1)
            }
            let needsChange = try transformedDocument(at: url, kind: kind) != nil
            plans.append(
                DocumentPlan(
                    originalURL: url,
                    targetURL: targetURL,
                    kind: kind,
                    needsChange: needsChange
                )
            )
        }
        return plans
    }

    private func transformedDocument(at url: URL, kind: DocumentKind) throws -> Data? {
        var object = try jsonObject(at: url)
        guard let schemaVersion = integer(object["schemaVersion"]) else {
            throw MigrationError.message("\(url.path) no contiene un schemaVersion válido.")
        }

        switch kind {
        case .storedChat:
            if schemaVersion == currentStoredChatSchemaVersion {
                guard object["storedAt"] != nil, object["exportedAt"] == nil else {
                    throw MigrationError.message(
                        "\(url.path) mezcla campos de chat guardado v1 y v2."
                    )
                }
                return nil
            }
            guard schemaVersion == 1, let legacyDate = object["exportedAt"] else {
                throw MigrationError.message(
                    "\(url.path) usa una versión de chat que no puede migrarse."
                )
            }
            guard object["storedAt"] == nil else {
                throw MigrationError.message(
                    "\(url.path) ya contiene storedAt pero declara schemaVersion 1."
                )
            }
            object["schemaVersion"] = currentStoredChatSchemaVersion
            object["storedAt"] = legacyDate
            object.removeValue(forKey: "exportedAt")

        case .conversationArchive:
            if schemaVersion == currentArchiveSchemaVersion {
                try validateCurrentContributions(in: object, at: url)
                return nil
            }
            guard schemaVersion == 1,
                  var contributions = object["contributions"] as? [[String: Any]] else {
                throw MigrationError.message(
                    "\(url.path) usa una versión de archivo de conversación que no puede migrarse."
                )
            }
            for index in contributions.indices {
                guard let legacyDate = contributions[index]["exportedAt"],
                      contributions[index]["storedAt"] == nil else {
                    throw MigrationError.message(
                        "\(url.path) contiene una aportación v1 inválida."
                    )
                }
                contributions[index]["storedAt"] = legacyDate
                contributions[index].removeValue(forKey: "exportedAt")
            }
            object["schemaVersion"] = currentArchiveSchemaVersion
            object["contributions"] = contributions
        }

        return try encodedJSON(object)
    }

    private func validateCurrentContributions(
        in object: [String: Any],
        at url: URL
    ) throws {
        guard let contributions = object["contributions"] as? [[String: Any]] else {
            throw MigrationError.message("\(url.path) no contiene contributions.")
        }
        guard contributions.allSatisfy({
            $0["storedAt"] != nil && $0["exportedAt"] == nil
        }) else {
            throw MigrationError.message(
                "\(url.path) mezcla aportaciones de conversación v1 y v2."
            )
        }
    }

    private func makeBackup(for plan: MigrationPlan) throws -> URL {
        let timestamp = backupDateFormatter.string(from: Date())
        var backupURL = plan.libraryURL.appendingPathComponent(
            ".migration-backup-v1-to-v2-\(timestamp)",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: backupURL.path) {
            backupURL = plan.libraryURL.appendingPathComponent(
                ".migration-backup-v1-to-v2-\(timestamp)-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        }
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: false)

        let files = [plan.manifestURL] + plan.changedDocuments.map(\.originalURL)
        for sourceURL in files {
            let relativeComponents = try relativePathComponents(
                of: sourceURL,
                below: plan.libraryURL
            )
            let destinationURL = relativeComponents.reduce(backupURL) {
                $0.appendingPathComponent($1)
            }
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        let note = """
        Copia de seguridad de los JSON originales de la migración FreeMyChats v1 -> v2.
        Biblioteca: \(plan.libraryURL.path)
        Creada: \(ISO8601DateFormatter().string(from: Date()))
        No contiene archivos multimedia; la migración no los modifica.
        """
        try Data(note.utf8).write(
            to: backupURL.appendingPathComponent("README.txt"),
            options: .atomic
        )
        return backupURL
    }

    private func rollback(
        plan: MigrationPlan,
        backupURL: URL,
        completedVersionMoves: [(from: URL, to: URL)],
        rootWasMoved: Bool,
        storageRootWasCreated: Bool
    ) -> Error? {
        do {
            for move in completedVersionMoves.reversed() {
                if fileManager.fileExists(atPath: move.from.path) {
                    try fileManager.moveItem(at: move.from, to: move.to)
                }
            }

            if rootWasMoved, fileManager.fileExists(atPath: plan.storageURL.path) {
                try fileManager.moveItem(at: plan.storageURL, to: plan.legacyStorageURL)
            } else if storageRootWasCreated,
                      fileManager.fileExists(atPath: plan.storageURL.path) {
                let contents = try fileManager.contentsOfDirectory(
                    atPath: plan.storageURL.path
                )
                if contents.isEmpty {
                    try fileManager.removeItem(at: plan.storageURL)
                }
            }

            let originalFiles = [plan.manifestURL] + plan.changedDocuments.map(\.originalURL)
            for originalURL in originalFiles {
                let relativeComponents = try relativePathComponents(
                    of: originalURL,
                    below: plan.libraryURL
                )
                let backupFileURL = relativeComponents.reduce(backupURL) {
                    $0.appendingPathComponent($1)
                }
                guard fileManager.fileExists(atPath: backupFileURL.path) else { continue }
                try Data(contentsOf: backupFileURL).write(to: originalURL, options: .atomic)
            }
            return nil
        } catch {
            return error
        }
    }

    private enum ItemKind {
        case missing
        case file
        case directory
    }

    private func itemKind(at url: URL) throws -> ItemKind {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        return isDirectory.boolValue ? .directory : .file
    }

    private func requireDirectory(_ url: URL, description: String) throws {
        guard try itemKind(at: url) == .directory else {
            throw MigrationError.message("\(description) no es una carpeta: \(url.path)")
        }
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        do {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let object = value as? [String: Any] else {
                throw MigrationError.message("\(url.path) no contiene un objeto JSON.")
            }
            return object
        } catch let error as MigrationError {
            throw error
        } catch {
            throw MigrationError.message(
                "No se puede leer \(url.path): \(error.localizedDescription)"
            )
        }
    }

    private func encodedJSON(_ object: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(0x0A)
        return data
    }

    private func relativePathComponents(of url: URL, below root: URL) throws -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.starts(with: rootComponents),
              urlComponents.count > rootComponents.count else {
            throw MigrationError.message(
                "\(url.path) no está contenido en \(root.path)."
            )
        }
        return Array(urlComponents.dropFirst(rootComponents.count))
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == Double(number.intValue) else {
            return nil
        }
        return number.intValue
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    private func makeStorageDirectoryName(
        for date: Date,
        excluding existingNames: Set<String>
    ) -> String {
        let baseName = "Copia \(storageDirectoryDateFormatter.string(from: date))"
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) (\(suffix))") {
            suffix += 1
        }
        return "\(baseName) (\(suffix))"
    }

    private func isSafeDirectoryName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && name == URL(fileURLWithPath: name).lastPathComponent
            && !name.contains("/")
            && !name.contains("\\")
    }

    private let storageDirectoryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

    private let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private func printUsage() {
    print(
        """
        Migra una biblioteca de FreeMyChats del formato v1 al v2.

        Uso:
          swift Scripts/migrate-library-v1-to-v2.swift [--apply] <biblioteca>

        Sin --apply, solo valida la biblioteca y muestra el plan.
        Con --apply, crea una copia de los JSON originales y ejecuta la migración.

        Cierra FreeMyChats antes de usar esta herramienta.
        """
    )
}

private func printPlan(_ plan: MigrationPlan, apply: Bool) {
    print("Biblioteca: \(plan.libraryURL.path)")
    print("Formato de library.json: v\(plan.manifest.sourceSchemaVersion)")

    if !plan.hasChanges {
        print("La biblioteca ya está en el formato v2.")
        return
    }

    if plan.shouldMoveStorageRoot {
        print("- Renombrar Exports como StoredChats.")
    } else if plan.shouldCreateStorageRoot {
        print("- Crear StoredChats.")
    }
    if plan.manifest.updatedData != nil {
        print("- Actualizar library.json a schemaVersion 2.")
    }
    if !plan.versionMoves.isEmpty {
        print("- Renombrar \(plan.versionMoves.count) carpeta(s) de copia.")
    }
    let changedChats = plan.changedDocuments.filter { $0.kind == .storedChat }.count
    let changedArchives = plan.changedDocuments.filter {
        $0.kind == .conversationArchive
    }.count
    print("- Actualizar \(changedChats) chat.json y \(changedArchives) archive.json.")

    if !apply {
        print("\nSimulación completada: no se ha modificado ningún archivo.")
        print("Repite el comando con --apply para ejecutar la migración.")
    }
}

do {
    guard let options = try Options.parse(Array(CommandLine.arguments.dropFirst())) else {
        printUsage()
        exit(EXIT_SUCCESS)
    }

    let migrator = LibraryMigrator()
    let plan = try migrator.makePlan(libraryURL: options.libraryURL)
    printPlan(plan, apply: options.apply)

    if options.apply, plan.hasChanges {
        let backupURL = try migrator.apply(plan)
        print("\nMigración completada y verificada.")
        if let backupURL {
            print("Copia de los JSON originales: \(backupURL.path)")
        }
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    fputs("Usa --help para ver la sintaxis.\n", stderr)
    exit(EXIT_FAILURE)
}
