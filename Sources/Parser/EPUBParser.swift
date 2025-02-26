//
//  EPUBParser.swift
//  EPUBKit
//
//  Created by Witek on 09/06/2017.
//  Copyright © 2017 Witek Bobrowski. All rights reserved.
//

import Foundation
import AEXML

public final class EPUBParser: EPUBParserProtocol {

    public typealias XMLElement = AEXMLElement

    private let archiveService: EPUBArchiveService
    private let spineParser: EPUBSpineParser
    private let metadataParser: EPUBMetadataParser
    private let manifestParser: EPUBManifestParser
    private let tableOfContentsParser: EPUBTableOfContentsParser

    public weak var delegate: EPUBParserDelegate?

    public init() {
        archiveService = EPUBArchiveServiceImplementation()
        metadataParser = EPUBMetadataParserImplementation()
        manifestParser = EPUBManifestParserImplementation()
        spineParser = EPUBSpineParserImplementation()
        tableOfContentsParser = EPUBTableOfContentsParserImplementation()
    }

    public func parse(documentAt path: URL) throws -> EPUBDocument {
        var directory: URL
        var contentDirectory: URL
        var metadata: EPUBMetadata
        var manifest: EPUBManifest
        var spine: EPUBSpine
        var tableOfContents: EPUBTableOfContents?
        var isEncrypted = false

        delegate?.parser(self, didBeginParsingDocumentAt: path)
        do {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)

            directory = isDirectory.boolValue ? path : try unzip(archiveAt: path)
            delegate?.parser(self, didUnzipArchiveTo: directory)

            let contentService = try EPUBContentServiceImplementation(directory)
            contentDirectory = contentService.contentDirectory
            delegate?.parser(self, didLocateContentAt: contentDirectory)

            spine = getSpine(from: contentService.spine)
            delegate?.parser(self, didFinishParsing: spine)

            metadata = getMetadata(from: contentService.metadata)
            delegate?.parser(self, didFinishParsing: metadata)

            manifest = getManifest(from: contentService.manifest)
            delegate?.parser(self, didFinishParsing: manifest)

            if let toc = spine.toc, let fileName = manifest.items[toc]?.path {
                let tableOfContentsElement = try contentService.tableOfContents(fileName)
                let parsedTableOfContents = getTableOfContents(from: tableOfContentsElement)
                delegate?.parser(self, didFinishParsing: parsedTableOfContents)

                tableOfContents = parsedTableOfContents
            }

            isEncrypted = getIsEncrypted(from: contentService.drm)
            delegate?.parser(self, didFinishParsing: isEncrypted)
        } catch let error {
            delegate?.parser(self, didFailParsingDocumentAt: path, with: error)
            throw error
        }
        delegate?.parser(self, didFinishParsingDocumentAt: path)
        return EPUBDocument(directory: directory,
                            contentDirectory: contentDirectory,
                            metadata: metadata,
                            manifest: manifest,
                            spine: spine,
                            tableOfContents: tableOfContents,
                            isEncrypted: isEncrypted)
    }

}

extension EPUBParser: EPUBParsable {

    public func unzip(archiveAt path: URL) throws -> URL {
        try archiveService.unarchive(archive: path)
    }

    public func getSpine(from xmlElement: XMLElement) -> EPUBSpine {
        spineParser.parse(xmlElement)
    }

    public func getMetadata(from xmlElement: XMLElement) -> EPUBMetadata {
        metadataParser.parse(xmlElement)
    }

    public func getManifest(from xmlElement: XMLElement) -> EPUBManifest {
        manifestParser.parse(xmlElement)
    }

    public func getTableOfContents(from xmlElement: XMLElement) -> EPUBTableOfContents {
        tableOfContentsParser.parse(xmlElement)
    }

    public func getIsEncrypted(from xmlElement: XMLElement?) -> Bool {
        guard let drm = xmlElement else { return false }

        return !drm.children.filter { $0.all(containingAttributeKeys: ["fairplay:sinf"]) != nil }.isEmpty
    }
}
