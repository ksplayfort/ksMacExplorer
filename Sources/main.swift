/*
 * KSMacExplorer
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import Combine
import AppKit
import ImageIO
@preconcurrency import AVFoundation
import QuickLook
@preconcurrency import QuickLookThumbnailing

// MARK: - 📣 Notifications for Menu & Ribbon Actions
extension Notification.Name {
    static let menuNewWindow = Notification.Name("menuNewWindow")
}

// MARK: - 🎯 Cross-App Drag & Drop Bridge
struct NativeDragDropHandler: NSViewRepresentable {
    var url: URL?
    var isDirectory: Bool
    var onSingleClick: () -> Void
    var onDoubleClick: () -> Void
    var onDropURLs: (([URL], NSDragOperation) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NativeDragDropNSView()
        view.url = url
        view.isDirectory = isDirectory
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onDropURLs = onDropURLs
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? NativeDragDropNSView else { return }
        view.url = url
        view.isDirectory = isDirectory
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        view.onDropURLs = onDropURLs
    }
}

class NativeDragDropNSView: NSView {
    var url: URL?
    var isDirectory: Bool = false
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDropURLs: (([URL], NSDragOperation) -> Void)?

    private var mouseDownLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 3.0
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
        onSingleClick?()

        if event.clickCount == 2 {
            onDoubleClick?()
        }
        super.mouseDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        guard !isDragging, let url = url else {
            super.mouseDragged(with: event)
            return
        }

        let currentLocation = event.locationInWindow
        let distance = hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y)

        guard distance > dragThreshold else {
            super.mouseDragged(with: event)
            return
        }
        isDragging = true

        let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let draggingFrame = self.bounds
        draggingItem.setDraggingFrame(draggingFrame, contents: icon)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        super.mouseUp(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

extension NativeDragDropNSView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            return .move
        } else {
            return .copy
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
    }
}

// MARK: - 🖱️ Native Click Handler
struct NativeClickHandler: NSViewRepresentable {
    var onSingleClick: () -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NativeClickNSView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? NativeClickNSView {
            view.onSingleClick = onSingleClick
            view.onDoubleClick = onDoubleClick
        }
    }
}

class NativeClickNSView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var mouseDownLocation: NSPoint = .zero
    private let dragThreshold: CGFloat = 3.0
    private var isDragging = false

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false

        if event.clickCount == 2 {
            onDoubleClick?()
            isDragging = true
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let currentLocation = event.locationInWindow
        let distance = hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y)
        if distance > dragThreshold {
            isDragging = true
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging {
            onSingleClick?()
        }
        super.mouseUp(with: event)
    }
}

extension NativeDragDropNSView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onDropURLs != nil else { return [] }
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) { return .move }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return onDropURLs != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let onDropURLs = onDropURLs else { return false }

        let pasteboard = sender.draggingPasteboard
        var urls: [URL] = []

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            urls = fileURLs
        }
        else if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for string in strings {
                if let url = URL(string: string), url.scheme != nil {
                    urls.append(url)
                } else if FileManager.default.fileExists(atPath: string) {
                    urls.append(URL(fileURLWithPath: string))
                }
            }
        }

        guard !urls.isEmpty else { return false }

        let modifiers = NSEvent.modifierFlags
        let operation: NSDragOperation = modifiers.contains(.shift) ? .move : .copy

        onDropURLs(urls, operation)
        return true
    }
}

// MARK: - 🪟 Window & Clipboard Management System
@MainActor
class WindowState {
    static let shared = WindowState()
    enum Action { case unspecified, forceWindow }
    var action: Action = .unspecified
    var pendingTabURL: URL? = nil
}

@MainActor
class SystemClipboard: ObservableObject {
    static let shared = SystemClipboard()

    @Published var clipboardURLs: [URL] = []
    @Published var isCutMode: Bool = false

    func copy(_ urls: Set<URL>) {
        clipboardURLs = Array(urls)
        isCutMode = false
        writeToPasteboard()
    }

    func cut(_ urls: Set<URL>) {
        clipboardURLs = Array(urls)
        isCutMode = true
        writeToPasteboard()
    }

    private func writeToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(clipboardURLs.map { $0 as NSURL })
    }

    func getURLsToPaste() -> (urls: [URL], isCut: Bool) {
        let pb = NSPasteboard.general
        guard let pbURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !pbURLs.isEmpty else {
            return ([], false)
        }

        let pbSet = Set(pbURLs.map { $0.standardizedFileURL })
        let internalSet = Set(clipboardURLs.map { $0.standardizedFileURL })

        if pbSet == internalSet {
            return (clipboardURLs, isCutMode)
        } else {
            return (pbURLs, false)
        }
    }

    func clear() {
        clipboardURLs = []
        isCutMode = false
        NSPasteboard.general.clearContents()
    }
}

class WindowAccessorView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var hasConfigured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window, !hasConfigured {
            self.hasConfigured = true
            onWindow?(window)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = WindowAccessorView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct WindowPayload: Codable, Hashable {
    var id = UUID()
    var url: URL
}

@main
struct KSMacExplorer: App {
    @Environment(\.openWindow) private var openWindow
    @FocusedObject private var focusedViewModel: ExplorerViewModel?

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup(id: "explorer") {
            MainExplorerView()
        }
        .commands {
            // แทนที่เมนู App Info เริ่มต้น เพื่อเปิดหน้าต่าง About ของเราเอง
            CommandGroup(replacing: .appInfo) {
                Button("About KSMacExplorer") {
                    openWindow(id: "about")
                }
            }
            
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    if NSApp.windows.contains(where: { $0.isKeyWindow || $0.isMainWindow }) {
                        NotificationCenter.default.post(name: .menuNewWindow, object: nil)
                    } else {
                        WindowState.shared.action = .forceWindow
                        openWindow(id: "explorer")
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    if focusedViewModel?.isEditingText == true { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                    else { focusedViewModel?.cutSelected() }
                }.keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    if focusedViewModel?.isEditingText == true { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    else { focusedViewModel?.copySelected() }
                }.keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    if focusedViewModel?.isEditingText == true { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    else { focusedViewModel?.paste() }
                }.keyboardShortcut("v", modifiers: .command)

                Divider()

                Button("Select All") {
                    if focusedViewModel?.isEditingText == true { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    else { focusedViewModel?.selectAll() }
                }.keyboardShortcut("a", modifiers: .command)
            }
        }
        
        // หน้าต่าง About Window
        WindowGroup("About KSMacExplorer", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Data Models & ViewModels

struct BookmarkItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let url: URL
}

class FileItem: NSObject, Identifiable, @unchecked Sendable {
    @objc let name: String
    let url: URL
    @objc let isDirectory: Bool
    @objc let fileSize: Int64
    @objc let modificationDate: Date?
    @objc let fileType: String
    var folderContentSize: Int64? = nil
    var dimensions: String?
    var thumbnail: NSImage?
    var children: [FileItem]? = nil

    init(name: String, url: URL, isDirectory: Bool, fileSize: Int64, modificationDate: Date?, fileType: String, folderContentSize: Int64? = nil, dimensions: String? = nil, thumbnail: NSImage? = nil, children: [FileItem]? = nil) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileType = fileType
        self.folderContentSize = folderContentSize
        self.dimensions = dimensions
        self.thumbnail = thumbnail
        self.children = children
    }

    var id: URL { url }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FileItem else { return false }
        return self.url.standardized == other.url.standardized &&
               self.folderContentSize == other.folderContentSize &&
               self.children == other.children
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(url)
        return hasher.finalize()
    }
}

enum ViewMode: String, CaseIterable {
    case icons
    case list
}

enum FileConflictAction {
    case keepBoth
    case replace
    case skip
}

@MainActor
class ExplorerViewModel: ObservableObject {
    @AppStorage("autoExpandSidebar") var autoExpandSidebar: Bool = true {
        willSet { objectWillChange.send() }
    }

    @AppStorage("showFolderSizes") var showFolderSizes: Bool = false {
        willSet { objectWillChange.send() }
        didSet {
            if showFolderSizes {
                for file in files where file.isDirectory && file.folderContentSize == nil {
                    Task { await loadFolderSize(for: file) }
                }
            }
        }
    }
    
    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = false {
        willSet { objectWillChange.send() }
        didSet {
            Task {
                await loadFiles(from: currentPathURL, isNavigating: true)
                await loadSidebarTree()
            }
        }
    }

    @Published var currentPathURL: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var files: [FileItem] = []
    @Published var searchText: String = ""
    @AppStorage("searchHistoryJSON") private var searchHistoryJSON: String = "[]"

    @Published var selectionTime: Date = .distantPast
    
    private var renameTask: Task<Void, Never>? = nil

    @Published var isDraggingFile: Bool = false

    @Published var selectedURLs: Set<URL> = [] {
        didSet {
            if selectedURLs.count != 1 {
                renamingURL = nil
                cancelRename()
            } else if selectedURLs != oldValue {
                selectionTime = Date()
            }
        }
    }
    
    // ✨ ฟังก์ชันสำหรับหาปลายทางที่แท้จริงของ Alias/Shortcut
    nonisolated static func resolveIfAlias(url: URL) -> URL {
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
            if values.isAliasFile == true || values.isSymbolicLink == true {
                return try URL(resolvingAliasFileAt: url)
            }
        } catch {}
        return url
    }

    func handleDoubleClick(for file: FileItem) {
        cancelRename()
        open(file: file)
    }

    func toggleSelection(for url: URL) {
        let modifiers = NSEvent.modifierFlags
        let isCommandPressed = modifiers.contains(.command)
        let isShiftPressed = modifiers.contains(.shift)

        if isShiftPressed, let anchor = lastSelectedURL {
            let allItems = filteredFiles
            if let startIndex = allItems.firstIndex(where: { $0.url == anchor }),
               let endIndex = allItems.firstIndex(where: { $0.url == url }) {
                let start = min(startIndex, endIndex)
                let end = max(startIndex, endIndex)
                let rangeURLs = allItems[start...end].map { $0.url }
                if isCommandPressed { selectedURLs.formUnion(rangeURLs) }
                else { selectedURLs = Set(rangeURLs) }
            }
        } else if isCommandPressed {
            if selectedURLs.contains(url) { selectedURLs.remove(url) }
            else { selectedURLs.insert(url) }
            lastSelectedURL = url
        } else {
            selectedURLs = [url]
            lastSelectedURL = url
        }
    }
    
    func triggerRename(for file: FileItem) {
        cancelRename()
        
        renameTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) 
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if !self.isDraggingFile && self.selectedURLs.count == 1 {
                    self.startRename()
                }
            }
        }
    }
    
    func cancelRename() {
        renameTask?.cancel()
        renameTask = nil
    }

    var searchHistory: [String] {
        get {
            guard let data = searchHistoryJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                searchHistoryJSON = str
            }
        }
    }

    @AppStorage("bookmarksJSON") private var bookmarksJSON: String = "[]"

    var bookmarks: [BookmarkItem] {
        get {
            guard let data = bookmarksJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([BookmarkItem].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let str = String(data: data, encoding: .utf8) {
                bookmarksJSON = str
            }
        }
    }

    func addCurrentToBookmarks() {
        let newBookmark = BookmarkItem(id: UUID(), name: currentPathURL.lastPathComponent.isEmpty ? "/" : currentPathURL.lastPathComponent, url: currentPathURL)
        var current = bookmarks
        if !current.contains(where: { $0.url.standardized == currentPathURL.standardized }) {
            current.append(newBookmark)
            bookmarks = current
        }
    }

    func removeBookmark(id: UUID) {
        bookmarks = bookmarks.filter { $0.id != id }
    }

    func handleDrop(urls: [URL], to targetURL: URL, operation: NSDragOperation) {
        let fileManager = FileManager.default
        let resolvedTargetURL = ExplorerViewModel.resolveIfAlias(url: targetURL)

        for sourceURL in urls {
            var destinationURL = resolvedTargetURL.appendingPathComponent(sourceURL.lastPathComponent)
            if sourceURL.standardized == destinationURL.standardized { continue }

            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    let action = self.promptFileExists(for: destinationURL)
                    if action == .skip { continue }
                    if action == .replace {
                        try? fileManager.removeItem(at: destinationURL)
                    } else if action == .keepBoth {
                        destinationURL = self.generateUniqueCopyURL(for: sourceURL, in: resolvedTargetURL)
                    }
                }

                if operation == .link {
                    try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
                } else if operation == .move {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                } else {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                }
            } catch {
                print("Drop Error: \(error.localizedDescription)")
            }
        }
        Task { await loadFiles(from: currentPathURL) }
    }

    @Published var folderTree: [FileItem] = []
    @Published var externalDrives: [FileItem] = []
    @Published var backStack: [URL] = []
    @Published var forwardStack: [URL] = []
    @AppStorage("viewMode") var viewMode: ViewMode = .icons { willSet { objectWillChange.send() } }

    @Published var sortDescriptors: [SortDescriptor<FileItem>] = [SortDescriptor(\FileItem.name, order: .forward)]
    @Published var lastSelectedURL: URL? = nil
    @Published var renamingURL: URL? = nil
    @Published var renameText: String = ""
    @Published var errorMessage: String? = nil
    @Published var isShowingError: Bool = false
    @Published var operationSummaryMessage: String = ""
    @Published var isShowingOperationSummary: Bool = false
    @Published var previewURL: URL? = nil

    @Published var isOperating: Bool = false
    @Published var operationTotalItems: Int = 0
    @Published var operationProcessedItems: Int = 0
    private var operationTask: Task<Void, Never>? = nil

    @Published var isEditingText: Bool = false

    private var folderMonitorSource: DispatchSourceFileSystemObject?

    @Published var clipboardURLs: [URL] = []
    @Published var isCutMode: Bool = false

    var canPaste: Bool {
        return NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    init(initialURL: URL? = nil) {
        let targetURL = WindowState.shared.pendingTabURL ?? initialURL ?? FileManager.default.homeDirectoryForCurrentUser
        WindowState.shared.pendingTabURL = nil

        self.currentPathURL = targetURL

        SystemClipboard.shared.$clipboardURLs.assign(to: &$clipboardURLs)
        SystemClipboard.shared.$isCutMode.assign(to: &$isCutMode)

        Task {
            await loadFiles(from: currentPathURL)
            await loadSidebarTree()
        }

        loadExternalDrives()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.loadExternalDrives() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.loadExternalDrives() }
        }
    }

    func loadExternalDrives() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey]
        let paths = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []

        var drives: [FileItem] = []
        for url in paths {
            if url.path == "/" || url.path == "/System/Volumes/Data" { continue }
            drives.append(FileItem(name: url.lastPathComponent, url: url, isDirectory: true, fileSize: 0, modificationDate: nil, fileType: "Drive"))
        }

        DispatchQueue.main.async {
            self.externalDrives = drives.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func eject(url: URL) {
        FileManager.default.unmountVolume(at: url, options: []) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot eject '\(url.lastPathComponent)': \(error.localizedDescription)"
                    self.isShowingError = true
                }
            } else {
                DispatchQueue.main.async {
                    self.loadExternalDrives()
                    if self.currentPathURL.standardized.path.hasPrefix(url.standardized.path) {
                        Task { await self.loadFiles(from: FileManager.default.homeDirectoryForCurrentUser) }
                    }
                }
            }
        }
    }

    var filteredFiles: [FileItem] {
        guard !searchText.isEmpty else { return files }

        var query = searchText
        while query.hasPrefix("*") { query.removeFirst() }
        while query.hasSuffix("*") { query.removeLast() }
        if query.isEmpty { return files }

        let shouldAppendStar = !query.hasSuffix("?")
        let finalQuery = "*" + query + (shouldAppendStar ? "*" : "")

        let predicate = NSPredicate(format: "self LIKE[cd] %@", finalQuery)
        return files.filter { file in predicate.evaluate(with: file.name) }
    }

    var freeDiskSpace: String {
        do {
            let values = try currentPathURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacity {
                return ByteCountFormatter.string(fromByteCount: Int64(capacity), countStyle: .file)
            }
        } catch { }
        return "--"
    }

    func commitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var history = searchHistory
        history.removeAll { $0.lowercased() == trimmed.lowercased() }
        history.insert(trimmed, at: 0)
        searchHistory = Array(history.prefix(5))
    }

    func copySelected() {
        guard !selectedURLs.isEmpty else { return }
        SystemClipboard.shared.copy(selectedURLs)
    }

    func cutSelected() {
        guard !selectedURLs.isEmpty else { return }
        SystemClipboard.shared.cut(selectedURLs)
    }

    @MainActor
    private func promptFileExists(for destination: URL) -> FileConflictAction {
        let alert = NSAlert()
        alert.messageText = "An item named \"\(destination.lastPathComponent)\" already exists in this location."
        alert.informativeText = "Do you want to replace it with the one you are moving or copying?"
        
        alert.addButton(withTitle: "Keep Both") 
        let replaceBtn = alert.addButton(withTitle: "Replace")
        replaceBtn.hasDestructiveAction = true
        alert.addButton(withTitle: "Skip")
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .keepBoth
        case .alertSecondButtonReturn:
            return .replace
        default:
            return .skip
        }
    }

    nonisolated private func generateUniqueCopyURL(for sourceURL: URL, in destinationFolder: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        let dotExt = ext.isEmpty ? "" : ".\(ext)"
        var newName = "\(baseName) copy\(dotExt)"
        var newURL = destinationFolder.appendingPathComponent(newName)
        var counter = 2
        while FileManager.default.fileExists(atPath: newURL.path) {
            newName = "\(baseName) copy \(counter)\(dotExt)"
            newURL = destinationFolder.appendingPathComponent(newName)
            counter += 1
        }
        return newURL
    }

    func paste() {
        let (sources, isCut) = SystemClipboard.shared.getURLsToPaste()
        guard !sources.isEmpty else { return }

        let destinationFolder = currentPathURL
        isOperating = true
        operationTotalItems = sources.count
        operationProcessedItems = 0

        operationTask = Task {
            var wasCancelled = false
            for sourceURL in sources {
                if Task.isCancelled { break }
                await Task.detached(priority: .userInitiated) {
                    var finalDestination = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
                    do {
                        if isCut {
                            if sourceURL.standardized == finalDestination.standardized { return }
                            if FileManager.default.fileExists(atPath: finalDestination.path) {
                                let action = await MainActor.run { self.promptFileExists(for: finalDestination) }
                                if action == .skip { return }
                                if action == .replace {
                                    try? FileManager.default.removeItem(at: finalDestination)
                                } else if action == .keepBoth {
                                    finalDestination = self.generateUniqueCopyURL(for: sourceURL, in: destinationFolder)
                                }
                            }
                            try FileManager.default.moveItem(at: sourceURL, to: finalDestination)
                        } else {
                            if FileManager.default.fileExists(atPath: finalDestination.path) {
                                let action = await MainActor.run { self.promptFileExists(for: finalDestination) }
                                if action == .skip { return }
                                if action == .replace {
                                    try? FileManager.default.removeItem(at: finalDestination)
                                } else if action == .keepBoth {
                                    finalDestination = self.generateUniqueCopyURL(for: sourceURL, in: destinationFolder)
                                }
                            }
                            try FileManager.default.copyItem(at: sourceURL, to: finalDestination)
                        }
                    } catch {
                        await MainActor.run {
                            self.errorMessage = error.localizedDescription
                            self.isShowingError = true
                        }
                    }
                }.value

                if Task.isCancelled { wasCancelled = true; break }
                self.operationProcessedItems += 1
            }

            if wasCancelled || Task.isCancelled {
                self.operationSummaryMessage = "Operation cancelled. Successfully processed \(self.operationProcessedItems) of \(self.operationTotalItems) items."
                self.isShowingOperationSummary = true
            }

            if isCut {
                await MainActor.run { SystemClipboard.shared.clear() }
            }
            self.isOperating = false
            self.operationTask = nil
            await loadFiles(from: destinationFolder)
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
        isOperating = false
    }

    func togglePreview() {
        guard selectedURLs.count == 1, let url = selectedURLs.first, !isDir(url) else { return }
        previewURL = url
    }

    private func isDir(_ url: URL) -> Bool {
        let resolvedURL = ExplorerViewModel.resolveIfAlias(url: url)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func selectAll() {
        selectedURLs = Set(filteredFiles.map { $0.url })
        lastSelectedURL = filteredFiles.last?.url
    }

    func compressSelected() {
        guard !selectedURLs.isEmpty else { return }
        let urls = Array(selectedURLs)
        let destFolder = currentPathURL

        isOperating = true
        operationTotalItems = 1
        operationProcessedItems = 0

        operationTask = Task {
            var zipName = "Archive.zip"
            if urls.count == 1 {
                zipName = "\(urls[0].deletingPathExtension().lastPathComponent).zip"
            }

            var finalZipURL = destFolder.appendingPathComponent(zipName)
            var counter = 2
            let baseName = finalZipURL.deletingPathExtension().lastPathComponent
            while FileManager.default.fileExists(atPath: finalZipURL.path) {
                finalZipURL = destFolder.appendingPathComponent("\(baseName) \(counter).zip")
                counter += 1
            }

            await Task.detached(priority: .userInitiated) {
                let process = Process()
                process.currentDirectoryURL = destFolder
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                var args = ["-r", "-q", finalZipURL.lastPathComponent]
                args.append(contentsOf: urls.map { $0.lastPathComponent })
                process.arguments = args
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    print("Compression error: \(error)")
                }
            }.value

            self.operationProcessedItems = 1
            self.isOperating = false
            self.operationTask = nil
            await loadFiles(from: destFolder)
        }
    }

    func uncompressSelected() {
        guard !selectedURLs.isEmpty else { return }
        let zipUrls = Array(selectedURLs).filter { $0.pathExtension.lowercased() == "zip" }
        guard !zipUrls.isEmpty else { return }

        let destFolder = currentPathURL
        isOperating = true
        operationTotalItems = zipUrls.count
        operationProcessedItems = 0

        operationTask = Task {
            for url in zipUrls {
                if Task.isCancelled { break }
                await Task.detached(priority: .userInitiated) {
                    let process = Process()
                    process.currentDirectoryURL = destFolder
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-n", "-q", url.lastPathComponent]
                    do {
                        try process.run()
                        process.waitUntilExit()
                    } catch {
                        print("Uncompression error: \(error)")
                    }
                }.value
                self.operationProcessedItems += 1
            }
            self.isOperating = false
            self.operationTask = nil
            await loadFiles(from: destFolder)
        }
    }

    func loadChildren(for item: FileItem) async {
        guard item.isDirectory, item.children == nil else { return }
        let currentShowHidden = self.showHiddenFiles 
        let subfolders = await Task.detached(priority: .userInitiated) { return ExplorerViewModel.fetchSubfolders(for: item.url, showHidden: currentShowHidden) }.value 
        self.folderTree = updateNode(in: self.folderTree, targetURL: item.url, with: subfolders)
        self.externalDrives = updateNode(in: self.externalDrives, targetURL: item.url, with: subfolders)
    }

    private func updateNode(in nodes: [FileItem], targetURL: URL, with children: [FileItem]) -> [FileItem] {
        let target = targetURL.standardizedFileURL.resolvingSymlinksInPath()
        return nodes.map { node in
            let currentNode = node.url.standardizedFileURL.resolvingSymlinksInPath()
            if currentNode == target {
                let newNode = node
                newNode.children = children
                return newNode
            } else if let nodeChildren = node.children {
                let newNode = node
                newNode.children = updateNode(in: nodeChildren, targetURL: targetURL, with: children)
                return newNode
            }
            return node
        }
    }

    func loadMetadata(for item: FileItem) async {
        guard !item.isDirectory, item.thumbnail == nil else { return }
        let resolvedURL = ExplorerViewModel.resolveIfAlias(url: item.url)
        let dims = await ExplorerViewModel.getMediaDimensions(for: resolvedURL)
        let thumb = await ExplorerViewModel.generateThumbnail(for: resolvedURL, size: CGSize(width: 64, height: 64))
        if let index = self.files.firstIndex(where: { $0.url == item.url }) {
            let updatedItem = self.files[index]
            updatedItem.dimensions = dims
            updatedItem.thumbnail = thumb
            self.files[index] = updatedItem
            self.objectWillChange.send()
        }
    }

    nonisolated static func getFileTypeString(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "Folder" }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return "Document" }
        guard let uti = UTType(filenameExtension: ext) else { return "Document-\(ext)" }

        var category = "Document"
        if uti.conforms(to: .image) { category = "Image" }
        else if uti.conforms(to: .audiovisualContent) {
            category = uti.conforms(to: .audio) ? "Audio" : "Video"
        }
        else if uti.conforms(to: .archive) { category = "Archive" }
        else if uti.conforms(to: .sourceCode) { category = "Code" }
        else if uti.conforms(to: .text) { category = "Text" }
        else if uti.conforms(to: .application) || uti.conforms(to: .executable) { category = "App" }

        return "\(category)-\(ext)"
    }

    func loadFolderSize(for item: FileItem) async {
        guard item.isDirectory, item.folderContentSize == nil else { return }
        let url = item.url
        let currentShowHidden = self.showHiddenFiles 
        let calculatedSize = await Task.detached(priority: .background) { return ExplorerViewModel.calculateDirectorySize(at: url, showHidden: currentShowHidden) }.value 
        if let index = self.files.firstIndex(where: { $0.url == url }) {
            let updatedItem = self.files[index]
            if updatedItem.folderContentSize == nil {
                updatedItem.folderContentSize = calculatedSize
                self.files[index] = updatedItem
                self.objectWillChange.send()
            }
        }
    }

    func startRename() {
        guard selectedURLs.count == 1, let url = selectedURLs.first else { return }
        renameText = url.lastPathComponent
        renamingURL = url
        isEditingText = true
    }

    func commitRename() {
        guard let oldURL = renamingURL else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !newName.isEmpty && newName != oldURL.lastPathComponent else {
            renamingURL = nil
            isEditingText = false
            return
        }

        let illegalCharacters = CharacterSet(charactersIn: "/:")
        if newName.rangeOfCharacter(from: illegalCharacters) != nil {
            self.errorMessage = "Names cannot contain characters such as ':' or '/'"
            self.isShowingError = true
            renamingURL = nil
            isEditingText = false
            return
        }

        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)

        if !FileManager.default.fileExists(atPath: newURL.path) {
            do {
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                Task { await loadFiles(from: currentPathURL) }
            } catch {
                self.errorMessage = error.localizedDescription
                self.isShowingError = true
            }
        } else {
            self.errorMessage = "A file or folder with this name already exists."
            self.isShowingError = true
        }
        renamingURL = nil
        isEditingText = false
    }

    func open(file: FileItem) {
        let targetURL = ExplorerViewModel.resolveIfAlias(url: file.url)
        var isDirPointer: ObjCBool = false
        
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirPointer), isDirPointer.boolValue {
            Task { await loadFiles(from: targetURL) }
        } else {
            NSWorkspace.shared.open(targetURL)
        }
    }

    func openSelected() {
        for url in selectedURLs {
            let targetURL = ExplorerViewModel.resolveIfAlias(url: url)
            var isDirPointer: ObjCBool = false
            
            if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirPointer), isDirPointer.boolValue {
                Task { await loadFiles(from: targetURL) }
            } else {
                NSWorkspace.shared.open(targetURL)
            }
        }
    }

    func openWith(file: FileItem) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application to open '\(file.name)'"
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            if response == .OK, let appURL = panel.url {
                let targetURL = ExplorerViewModel.resolveIfAlias(url: file.url)
                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: configuration)
            }
        }
    }

    func openInTerminal(url: URL) {
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            let targetURL = ExplorerViewModel.resolveIfAlias(url: url)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([targetURL], withApplicationAt: terminalURL, configuration: configuration)
        }
    }

    func showInFinder(url: URL) { 
        let targetURL = ExplorerViewModel.resolveIfAlias(url: url)
        NSWorkspace.shared.activateFileViewerSelecting([targetURL]) 
    }

    func showGetInfo(for url: URL) {
        let scriptSource = "tell application \"Finder\" to open information window of (POSIX file \"\(url.path)\" as alias)"
        if let script = NSAppleScript(source: scriptSource) { script.executeAndReturnError(nil) }
    }

    func deleteSelected() {
        guard !selectedURLs.isEmpty else { return }

        let alert = NSAlert()
        let itemCount = selectedURLs.count
        alert.messageText = "Delete \(itemCount) \(itemCount == 1 ? "item" : "items")?"
        alert.informativeText = "Are you sure you want to move the selected \(itemCount == 1 ? "item" : "items") to the Trash?"
        alert.alertStyle = .warning

        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            let urlsToDelete = Array(selectedURLs)
            NSWorkspace.shared.recycle(urlsToDelete) { _, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = error.localizedDescription
                        self.isShowingError = true
                    }
                }
                Task { await self.loadFiles(from: self.currentPathURL) }
            }
        }
    }

    func createNewFolder(named name: String) {
        let baseName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Folder" : name
        var newFolderURL = currentPathURL.appendingPathComponent(baseName)

        if FileManager.default.fileExists(atPath: newFolderURL.path) {
            var count = 1
            var tempURL = currentPathURL.appendingPathComponent("\(baseName) \(count)")
            while FileManager.default.fileExists(atPath: tempURL.path) {
                count += 1
                tempURL = currentPathURL.appendingPathComponent("\(baseName) \(count)")
            }
            newFolderURL = tempURL
        }

        do {
            try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: false, attributes: nil)
            Task { await loadFiles(from: currentPathURL) }
        } catch { print("ไม่สามารถสร้างโฟลเดอร์ได้: \(error.localizedDescription)") }
    }

    func applySort() {
        guard !sortDescriptors.isEmpty else {
            files.sort { item1, item2 in
                if item1.isDirectory != item2.isDirectory { return item1.isDirectory }
                return item1.name.localizedStandardCompare(item2.name) == .orderedAscending
            }
            return
        }

        files.sort { item1, item2 in
            if item1.isDirectory != item2.isDirectory { return item1.isDirectory }
            for descriptor in sortDescriptors {
                let result = descriptor.compare(item1, item2)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return false
        }
    }
    
    func refresh() {
        Task { await loadFiles(from: currentPathURL, isNavigating: true) }
    }

    func loadFiles(from targetURL: URL, isNavigating: Bool = false) async {
        let resolvedTargetURL = ExplorerViewModel.resolveIfAlias(url: targetURL) 

        if !isNavigating && resolvedTargetURL.standardized != currentPathURL.standardized {
            backStack.append(currentPathURL)
            forwardStack.removeAll()
        }

        self.selectedURLs.removeAll()
        self.lastSelectedURL = nil
        self.renamingURL = nil

        let currentShowHidden = self.showHiddenFiles 
        let result = await Task.detached(priority: .userInitiated) {
            return await ExplorerViewModel.performFileLoading(from: resolvedTargetURL, showHidden: currentShowHidden) 
        }.value

        await MainActor.run {
            self.currentPathURL = resolvedTargetURL
            self.files = result
            self.applySort()
            self.startMonitoringFolder(at: resolvedTargetURL)
        }
    }

    func goBack() {
        guard !backStack.isEmpty else { return }
        let previous = backStack.removeLast()
        forwardStack.append(currentPathURL)
        Task { await loadFiles(from: previous, isNavigating: true) }
    }

    func goForward() {
        guard !forwardStack.isEmpty else { return }
        let next = forwardStack.removeLast()
        backStack.append(currentPathURL)
        Task { await loadFiles(from: next, isNavigating: true) }
    }

    func jumpBack(to index: Int) {
        guard index < backStack.count else { return }
        let targetURL = backStack[index]
        let itemsToMove = backStack.suffix(from: index + 1)
        forwardStack = Array(itemsToMove.reversed()) + [currentPathURL] + forwardStack
        backStack.removeSubrange(index...)
        Task { await loadFiles(from: targetURL, isNavigating: true) }
    }

    func jumpForward(to index: Int) {
        guard index < forwardStack.count else { return }
        let targetURL = forwardStack[index]
        let itemsToMove = forwardStack.prefix(upTo: index)
        backStack = backStack + [currentPathURL] + Array(itemsToMove)
        forwardStack.removeSubrange(...index)
        Task { await loadFiles(from: targetURL, isNavigating: true) }
    }

    func loadSidebarTree() async {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let currentShowHidden = self.showHiddenFiles 
        let subfolders = await Task.detached(priority: .userInitiated) { return ExplorerViewModel.fetchSubfolders(for: homeURL, showHidden: currentShowHidden) }.value 
        self.folderTree = [ FileItem(name: "Home", url: homeURL, isDirectory: true, fileSize: 0, modificationDate: nil, fileType: "Folder", children: subfolders) ]
    }

    nonisolated static func calculateDirectorySize(at url: URL, showHidden: Bool) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHidden {
            options.insert(.skipsHiddenFiles)
        }
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: options) else { return 0 }
        for case let fileURL as URL in enumerator {
            do {
                let resources = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resources.fileSize { totalSize += Int64(fileSize) }
            } catch { }
        }
        return totalSize
    }

    static func getMediaDimensions(for url: URL) async -> String? {
        let uti = UTType(filenameExtension: url.pathExtension)
        if uti?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
            if let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
                return "\(width) × \(height)"
            }
        } else if uti?.conforms(to: .audiovisualContent) == true {
            let asset = AVURLAsset(url: url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first, let size = try? await track.load(.naturalSize) {
                return "\(Int(size.width)) × \(Int(size.height))"
            }
        }
        return nil
    }

    static func generateThumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 2.0, representationTypes: .thumbnail)
        do { return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage } catch { return nil }
    }

    nonisolated static func performFileLoading(from url: URL, showHidden: Bool) async -> [FileItem] {
        let fileManager = FileManager.default
        do {
            var options: FileManager.DirectoryEnumerationOptions = []
            if !showHidden {
                options.insert(.skipsHiddenFiles)
            }
            
            let items = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isAliasFileKey, .isSymbolicLinkKey], options: options)
            var newFiles: [FileItem] = []
            for item in items {
                let resources = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isAliasFileKey, .isSymbolicLinkKey])
                
                var isActuallyDir = resources?.isDirectory ?? false
                let isAlias = (resources?.isAliasFile == true || resources?.isSymbolicLink == true)
                
                if isAlias {
                    let resolvedURL = resolveIfAlias(url: item)
                    var isDirPointer: ObjCBool = false
                    if fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirPointer) {
                        isActuallyDir = isDirPointer.boolValue
                    }
                } else if !isActuallyDir {
                    var isDirPointer: ObjCBool = false
                    if fileManager.fileExists(atPath: item.path, isDirectory: &isDirPointer) {
                        isActuallyDir = isDirPointer.boolValue
                    }
                }
                
                let fileTypeStr = isAlias ? "Alias" : getFileTypeString(for: item, isDirectory: isActuallyDir)
                
                newFiles.append(FileItem(name: item.lastPathComponent, url: item, isDirectory: isActuallyDir, fileSize: Int64(resources?.fileSize ?? 0), modificationDate: resources?.contentModificationDate, fileType: fileTypeStr))
            }
            return newFiles.sorted {
                if $0.isDirectory == $1.isDirectory { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.isDirectory && !$1.isDirectory
            }
        } catch { return [] }
    }

    nonisolated static func fetchSubfolders(for url: URL, showHidden: Bool) -> [FileItem] {
        do {
            var options: FileManager.DirectoryEnumerationOptions = []
            if !showHidden {
                options.insert(.skipsHiddenFiles)
            }
            
            return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey], options: options).compactMap { item in
                guard let resources = try? item.resourceValues(forKeys: [.isDirectoryKey, .isAliasFileKey, .isSymbolicLinkKey]) else { return nil }
                
                var isDir = resources.isDirectory ?? false
                if resources.isAliasFile == true || resources.isSymbolicLink == true {
                    let resolved = resolveIfAlias(url: item)
                    var isDirPointer: ObjCBool = false
                    if FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirPointer) {
                        isDir = isDirPointer.boolValue
                    }
                }
                
                guard isDir else { return nil }
                return FileItem(name: item.lastPathComponent, url: item, isDirectory: true, fileSize: 0, modificationDate: nil, fileType: "Folder")
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { return [] }
    }

    // MARK: - Auto Update (Folder Monitoring)
    private var refreshTask: Task<Void, Never>? = nil

    private func startMonitoringFolder(at url: URL) {
        folderMonitorSource?.cancel()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .link, .revoke, .extend, .attrib],
            queue: .global(qos: .background)
        )
        let eventHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.triggerSafeRefresh() }
        }
        let cancelHandler: @Sendable () -> Void = { Darwin.close(fd) }
        source.setEventHandler(handler: eventHandler)
        source.setCancelHandler(handler: cancelHandler)
        folderMonitorSource = source
        source.resume()
    }

    private func triggerSafeRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await reloadFilesSafely()
        }
    }

    private func reloadFilesSafely() async {
        let targetURL = self.currentPathURL
        let currentShowHidden = self.showHiddenFiles
        
        let newFiles = await Task.detached(priority: .userInitiated) {
            return await ExplorerViewModel.performFileLoading(from: targetURL, showHidden: currentShowHidden)
        }.value

        await MainActor.run {
            guard self.renamingURL == nil else { return }
            guard self.currentPathURL == targetURL else { return }
            let existingSelection = self.selectedURLs
            self.files = newFiles
            self.applySort()
            let newURLs = Set(self.files.map { $0.url })
            self.selectedURLs = existingSelection.intersection(newURLs)
        }
    }
}

// MARK: - Views

struct StatusBarView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    private var statusText: String {
        let totalCount = viewModel.filteredFiles.count
        if viewModel.selectedURLs.isEmpty { return "\(totalCount) items matched" }
        else {
            let selectedItems = viewModel.files.filter { viewModel.selectedURLs.contains($0.url) }
            let totalSize = selectedItems.reduce(0 as Int64) { total, item in total + (item.isDirectory ? (item.folderContentSize ?? 0) : item.fileSize) }
            return "\(viewModel.selectedURLs.count) of \(totalCount) items selected (\(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)))"
        }
    }

    var body: some View {
        HStack {
            if viewModel.isOperating {
                HStack(spacing: 8) {
                    ProgressView(value: Double(viewModel.operationProcessedItems), total: Double(viewModel.operationTotalItems)).progressViewStyle(.linear).frame(width: 100)
                    Text("Processing \(viewModel.operationProcessedItems) of \(viewModel.operationTotalItems)...")
                    Button(action: viewModel.cancelOperation) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            } else { Text(statusText) }
            Spacer()
            Text("\(viewModel.freeDiskSpace) available").foregroundColor(.secondary)
        }
        .font(.caption).padding(.horizontal, 10).padding(.vertical, 4).background(Color(NSColor.windowBackgroundColor))
    }
}

struct MainExplorerView: View {
    @StateObject var viewModel: ExplorerViewModel
    @State private var showSidebar: Bool = true
    @State private var showInspector: Bool = true
    @FocusState private var focusedField: ExplorerFocusField?

    @State private var myWindow: NSWindow? = nil
    @Environment(\.openWindow) private var openWindow

    enum ExplorerFocusField: Hashable { case addressBar, renameField }

    init(initialURL: URL? = nil) { _viewModel = StateObject(wrappedValue: ExplorerViewModel(initialURL: initialURL)) }

    var body: some View {
        VStack(spacing: 0) {
            AddressBarView(viewModel: viewModel, focusedField: $focusedField)
            Divider()
            RibbonToolbarView(viewModel: viewModel, showSidebar: $showSidebar, showInspector: $showInspector)
            Divider()
            HSplitView {
                if showSidebar {
                    FileTreeView(viewModel: viewModel)
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 300)
                }

                FileGridView(viewModel: viewModel, focusedField: $focusedField)
                    .frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .contentShape(Rectangle())
                    .dropDestination(for: URL.self) { items, _ in
                        let modifiers = NSEvent.modifierFlags
                        let operation: NSDragOperation = modifiers.contains(.shift) ? .move : .copy
                        viewModel.handleDrop(urls: items, to: viewModel.currentPathURL, operation: operation)
                        return true
                    }

                if showInspector {
                    FileDetailView(viewModel: viewModel)
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 300)
                }
            }
            Divider()
            StatusBarView(viewModel: viewModel)
        }
        .navigationTitle(viewModel.currentPathURL.lastPathComponent.isEmpty ? "/" : viewModel.currentPathURL.lastPathComponent)
        .frame(minWidth: 900, idealHeight: 600)
        .focusedSceneObject(viewModel)
        .background(
            WindowAccessor { window in
                self.myWindow = window
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .menuNewWindow)) { _ in
            guard myWindow?.isKeyWindow == true || myWindow?.isMainWindow == true else { return }
            WindowState.shared.action = .forceWindow
            WindowState.shared.pendingTabURL = viewModel.currentPathURL
            openWindow(id: "explorer")
        }
        .background(
            ZStack {
                Button("") { viewModel.openSelected() }.keyboardShortcut(.return, modifiers: []).disabled(viewModel.isEditingText)
                Button("") { viewModel.startRename() }.keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!)), modifiers: []).disabled(viewModel.isEditingText)
                Button("") { viewModel.togglePreview() }.keyboardShortcut(.space, modifiers: []).disabled(viewModel.isEditingText)
                Button("") { viewModel.selectAll() }.keyboardShortcut("a", modifiers: .command).disabled(viewModel.isEditingText)
                Button("") { focusedField = .addressBar }.keyboardShortcut("l", modifiers: .command)
            }.buttonStyle(PlainButtonStyle()).frame(width: 0, height: 0).opacity(0)
        )
        .onChange(of: viewModel.currentPathURL) { newValue in
            myWindow?.title = newValue.lastPathComponent.isEmpty ? "/" : newValue.lastPathComponent
        }
        .onChange(of: focusedField) { newValue in
            if newValue != nil { viewModel.isEditingText = true }
            else if viewModel.renamingURL == nil { viewModel.isEditingText = false }
        }
        .onChange(of: viewModel.renamingURL) { newValue in
            if newValue != nil { viewModel.isEditingText = true }
            else if focusedField == nil { viewModel.isEditingText = false }
        }
        .alert("Operation Failed", isPresented: $viewModel.isShowingError) { Button("OK", role: .cancel) { } } message: { Text(viewModel.errorMessage ?? "Error") }
        .alert("Cancelled", isPresented: $viewModel.isShowingOperationSummary) { Button("OK", role: .cancel) { } } message: { Text(viewModel.operationSummaryMessage) }
        .quickLookPreview($viewModel.previewURL)
    }
}

// MARK: - Sub Views

struct SearchBarView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    var body: some View {
        HStack(spacing: 4) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search", text: $viewModel.searchText).textFieldStyle(.plain).onSubmit { viewModel.commitSearch() }
                if !viewModel.searchText.isEmpty { Button(action: { viewModel.searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(4).padding(.horizontal, 4).background(Color(NSColor.controlBackgroundColor)).cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1)).frame(width: 220)
            Menu { ForEach(viewModel.searchHistory, id: \.self) { term in Button(term) { viewModel.searchText = term } } } label: { Image(systemName: "clock.arrow.circlepath") }.menuStyle(.borderlessButton).fixedSize()
        }
    }
}

struct FolderSizeCalculatingView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    let file: FileItem
    var body: some View { Text("Calculating...").task { await viewModel.loadFolderSize(for: file) } }
}

struct AddressBarView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    var focusedField: FocusState<MainExplorerView.ExplorerFocusField?>.Binding
    @State private var textInput: String = ""
    var body: some View {
        HStack {
            Button(action: { viewModel.goBack() }) { Image(systemName: "arrow.backward") }.disabled(viewModel.backStack.isEmpty)
            Button(action: { viewModel.goForward() }) { Image(systemName: "arrow.forward") }.disabled(viewModel.forwardStack.isEmpty)
            Button(action: { Task { await viewModel.loadFiles(from: viewModel.currentPathURL.deletingLastPathComponent()) } }) { Image(systemName: "arrow.up") }
            TextField("Address", text: $textInput).textFieldStyle(RoundedBorderTextFieldStyle()).focused(focusedField, equals: .addressBar).onSubmit { Task { await viewModel.loadFiles(from: URL(fileURLWithPath: textInput)) } }.onChange(of: viewModel.currentPathURL) { textInput = $0.path }.onAppear { textInput = viewModel.currentPathURL.path }
            Button(action: { Task { await viewModel.loadFiles(from: viewModel.currentPathURL) } }) { Image(systemName: "arrow.clockwise") }
            Divider().frame(height: 20)
            SearchBarView(viewModel: viewModel)
        }.padding(8).background(Color(NSColor.controlBackgroundColor))
    }
}

struct RibbonToolbarView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    @Binding var showSidebar: Bool
    @Binding var showInspector: Bool
    @State private var isShowingNewFolderAlert = false
    @State private var newFolderName = ""

    var body: some View {
        HStack(spacing: 15) {
            Picker("", selection: $viewModel.viewMode) { Image(systemName: "square.grid.2x2").tag(ViewMode.icons); Image(systemName: "list.bullet").tag(ViewMode.list) }.pickerStyle(.segmented).frame(width: 70)
            Divider().frame(height: 20)
            RibbonButton(icon: "doc.on.clipboard", label: "Copy") { viewModel.copySelected() }
            RibbonButton(icon: "scissors", label: "Cut") { viewModel.cutSelected() }
            RibbonButton(icon: "doc.on.clipboard.fill", label: "Paste") { viewModel.paste() }.disabled(!viewModel.canPaste)
            Divider().frame(height: 20)
            RibbonButton(icon: "folder.badge.plus", label: "New Folder") { newFolderName = "New Folder"; isShowingNewFolderAlert = true }
            RibbonButton(icon: "trash", label: "Delete") { viewModel.deleteSelected() }
            Divider().frame(height: 20)
            Menu {
                Button(action: viewModel.addCurrentToBookmarks) { Label("Bookmark Current Folder", systemImage: "plus.square.on.square") }
                if !viewModel.bookmarks.isEmpty { Divider(); ForEach(viewModel.bookmarks) { bookmark in Menu(bookmark.name) { Button("Go to Folder") { Task { await viewModel.loadFiles(from: bookmark.url) } }; Button("Remove Bookmark", role: .destructive) { viewModel.removeBookmark(id: bookmark.id) } } } }
            } label: { RibbonButton(icon: "bookmark", label: "Bookmarks") { } }.menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Toggle("Auto Expand", isOn: $viewModel.autoExpandSidebar).toggleStyle(.checkbox)
            Toggle("Folder Sizes", isOn: $viewModel.showFolderSizes).toggleStyle(.checkbox)
            Toggle("Hidden Files", isOn: $viewModel.showHiddenFiles).toggleStyle(.checkbox)
            Divider().frame(height: 20)
            Toggle("Sidebar", isOn: $showSidebar).toggleStyle(.button)
            Toggle("Details", isOn: $showInspector).toggleStyle(.button)
            Divider().frame(height: 20)
            RibbonButton(icon: "macwindow.badge.plus", label: "New Window") {
                NotificationCenter.default.post(name: .menuNewWindow, object: nil)
            }
        }.padding(8).background(Color(NSColor.windowBackgroundColor))
        .alert("New Folder", isPresented: $isShowingNewFolderAlert) { TextField("Name", text: $newFolderName); Button("Create") { viewModel.createNewFolder(named: newFolderName) }; Button("Cancel", role: .cancel) { } }
    }
}

struct RibbonButton: View {
    let icon: String; let label: String; var action: () -> Void
    var body: some View { Button(action: action) { VStack { Image(systemName: icon).font(.system(size: 16)); Text(label).font(.caption2) } }.buttonStyle(PlainButtonStyle()) }
}

struct FileTreeView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    let homeURL = FileManager.default.homeDirectoryForCurrentUser

    var googleDriveURL: URL? {
        let fileManager = FileManager.default
        let myDriveURL = homeURL.appendingPathComponent("My Drive")
        if fileManager.fileExists(atPath: myDriveURL.path) { return myDriveURL }
        let volumeDriveURL = URL(fileURLWithPath: "/Volumes/GoogleDrive")
        if fileManager.fileExists(atPath: volumeDriveURL.path) { return volumeDriveURL }
        let cloudStorageURL = homeURL.appendingPathComponent("Library/CloudStorage")
        if let contents = try? fileManager.contentsOfDirectory(at: cloudStorageURL, includingPropertiesForKeys: nil),
           let driveURL = contents.first(where: { $0.lastPathComponent.hasPrefix("GoogleDrive") }) {
            return driveURL
        }
        return nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section(header: Text("Quick Access").font(.caption).foregroundColor(.secondary)) {
                    SidebarRow(title: "Home", icon: "house", url: homeURL, viewModel: viewModel)
                    SidebarRow(title: "Desktop", icon: "desktopcomputer", url: homeURL.appendingPathComponent("Desktop"), viewModel: viewModel)
                    SidebarRow(title: "Documents", icon: "doc.text", url: homeURL.appendingPathComponent("Documents"), viewModel: viewModel)
                    SidebarRow(title: "Downloads", icon: "arrow.down.circle", url: homeURL.appendingPathComponent("Downloads"), viewModel: viewModel)
                }
                Section(header: Text("Devices & Cloud").font(.caption).foregroundColor(.secondary)) {
                    SidebarRow(title: "Macintosh HD", icon: "internaldrive", url: URL(fileURLWithPath: "/"), viewModel: viewModel)
                    ForEach(viewModel.externalDrives, id: \.url) { drive in
                        FolderTreeRow(viewModel: viewModel, item: drive, isDrive: true)
                    }
                    if let driveURL = googleDriveURL {
                        SidebarRow(title: "Google Drive", icon: "externaldrive.badge.icloud", url: driveURL, viewModel: viewModel)
                    }
                }
                Section(header: Text("Folders").font(.caption).foregroundColor(.secondary)) {
                    ForEach(viewModel.folderTree) { item in
                        FolderTreeRow(viewModel: viewModel, item: item)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.currentPathURL) { newValue in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
            .onChange(of: viewModel.folderTree) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo(viewModel.currentPathURL, anchor: .center) }
                }
            }
            .onChange(of: viewModel.externalDrives) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation { proxy.scrollTo(viewModel.currentPathURL, anchor: .center) }
                }
            }
        }
    }
}

struct FolderTreeRow: View {
    @ObservedObject var viewModel: ExplorerViewModel
    let item: FileItem
    var isDrive: Bool = false
    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                if let children = item.children {
                    ForEach(children) { child in FolderTreeRow(viewModel: viewModel, item: child) }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading...").font(.caption).foregroundColor(.secondary)
                    }.padding(.leading)
                }
            }
        } label: {
            SidebarRow(title: item.name, icon: isDrive ? "externaldrive" : "folder", url: item.url, viewModel: viewModel, showEject: isDrive)
        }
        .onChange(of: isExpanded) { expanded in
            if expanded && item.children == nil { Task { await viewModel.loadChildren(for: item) } }
        }
        .onChange(of: viewModel.currentPathURL) { newValue in expandIfAncestor(of: newValue) }
        .onAppear { expandIfAncestor(of: viewModel.currentPathURL) }
    }

    private func expandIfAncestor(of targetURL: URL) {
        guard viewModel.autoExpandSidebar else { return }
        if targetURL.standardized.path.hasPrefix(item.url.standardized.path) && targetURL.standardized.path.count > item.url.standardized.path.count {
            withAnimation { isExpanded = true }
        }
    }
}

struct SidebarRow: View {
    let title: String
    let icon: String
    let url: URL
    @ObservedObject var viewModel: ExplorerViewModel
    var showEject: Bool = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(
                    NativeDragDropHandler(
                        url: url,
                        isDirectory: true,
                        onSingleClick: { Task { await viewModel.loadFiles(from: url) } },
                        onDoubleClick: {},
                        onDropURLs: { urls, operation in
                            viewModel.handleDrop(urls: urls, to: url, operation: operation)
                        }
                    )
                )
            if showEject {
                Button(action: { viewModel.eject(url: url) }) {
                    Image(systemName: "eject.fill").font(.system(size: 10)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1.0 : 0.0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(viewModel.currentPathURL.standardized == url.standardized ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in isHovering = hovering }
        .id(url)
    }
}

// MARK: - 🗂️ File Grid View (AppKit Native)

struct FileGridView: View {
    @ObservedObject var viewModel: ExplorerViewModel
    var focusedField: FocusState<MainExplorerView.ExplorerFocusField?>.Binding

    var body: some View {
        FileGridAppKitView(viewModel: viewModel, focusedField: focusedField)
            .background(Color(NSColor.textBackgroundColor))
    }
}

struct FileGridAppKitView: NSViewRepresentable {
    @ObservedObject var viewModel: ExplorerViewModel
    var focusedField: FocusState<MainExplorerView.ExplorerFocusField?>.Binding

    func makeNSView(context: Context) -> NSView {
        let container = FileGridContainerView()
        container.viewModel = viewModel
        container.focusedField = focusedField
        container.coordinator = context.coordinator
        context.coordinator.container = container
        container.updateViewMode()
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? FileGridContainerView else { return }
        let modeChanged = container.viewModel?.viewMode != viewModel.viewMode
        let renamingChanged = container.viewModel?.renamingURL != viewModel.renamingURL
        container.viewModel = viewModel
        container.focusedField = focusedField
        container.updateViewMode()
        if !modeChanged {
            if renamingChanged {
                container.iconView?.syncRenamingFromViewModel()
                container.listView?.syncRenamingFromViewModel()
            }
        }
    }

    func makeCoordinator() -> FileGridCoordinator { FileGridCoordinator() }
}

class FileGridCoordinator: NSObject {
    weak var container: FileGridContainerView?
}

class FileGridContainerView: NSView {
    weak var viewModel: ExplorerViewModel?
    var focusedField: FocusState<MainExplorerView.ExplorerFocusField?>.Binding?
    weak var coordinator: FileGridCoordinator?

    var iconView: IconCollectionView?
    var listView: ListTableView?
    private var currentMode: ViewMode?

    func updateViewMode() {
        guard let viewModel = viewModel else { return }
        let mode = viewModel.viewMode

        if currentMode == mode {
            iconView?.viewModel = viewModel
            listView?.viewModel = viewModel
            return
        }
        currentMode = mode

        iconView?.removeFromSuperview()
        listView?.removeFromSuperview()
        iconView = nil
        listView = nil

        if mode == .icons {
            let collection = IconCollectionView()
            collection.viewModel = viewModel
            collection.focusedField = focusedField
            collection.translatesAutoresizingMaskIntoConstraints = false
            addSubview(collection)
            NSLayoutConstraint.activate([
                collection.topAnchor.constraint(equalTo: topAnchor),
                collection.leadingAnchor.constraint(equalTo: leadingAnchor),
                collection.trailingAnchor.constraint(equalTo: trailingAnchor),
                collection.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            iconView = collection
            collection.reloadData()
        } else {
            let table = ListTableView()
            table.viewModel = viewModel
            table.focusedField = focusedField
            table.translatesAutoresizingMaskIntoConstraints = false
            addSubview(table)
            NSLayoutConstraint.activate([
                table.topAnchor.constraint(equalTo: topAnchor),
                table.leadingAnchor.constraint(equalTo: leadingAnchor),
                table.trailingAnchor.constraint(equalTo: trailingAnchor),
                table.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            listView = table
            table.reloadData()
        }
    }
}

// MARK: - Icon Mode: NSCollectionView

class ExplorerCollectionView: NSCollectionView {
    weak var explorerViewModel: ExplorerViewModel?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.indexPathForItem(at: point)?.item ?? -1
        guard let viewModel = explorerViewModel, row >= 0, row < viewModel.filteredFiles.count else {
            let menu = NSMenu()
            let newFolderItem = NSMenuItem(title: "New Folder", action: #selector(emptyNewFolderAction), keyEquivalent: "")
            newFolderItem.target = self
            menu.addItem(newFolderItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(emptyRefreshAction), keyEquivalent: "")
            refreshItem.target = self
            menu.addItem(refreshItem)
            
            return menu
        }

        return super.menu(for: event)
    }
    
    @objc private func emptyNewFolderAction() { explorerViewModel?.createNewFolder(named: "New Folder") }
    @objc private func emptyRefreshAction() { explorerViewModel?.refresh() }
}

class IconCollectionView: NSScrollView {
    private var cancellables = Set<AnyCancellable>()
    
    weak var viewModel: ExplorerViewModel? {
        didSet {
            if let cv = _collectionView { cv.explorerViewModel = viewModel }
            setupBindings()
        }
    }
    var focusedField: FocusState<MainExplorerView.ExplorerFocusField?>.Binding?

    private var _collectionView: ExplorerCollectionView!
    private var flowLayout: NSCollectionViewFlowLayout!
    private var isProgrammaticSelection = false

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NSSize(width: 90, height: 100)
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 15
        flowLayout.sectionInset = NSEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

        _collectionView = ExplorerCollectionView()
        _collectionView.collectionViewLayout = flowLayout
        _collectionView.isSelectable = true
        _collectionView.allowsMultipleSelection = true
        _collectionView.allowsEmptySelection = true
        _collectionView.register(IconCollectionItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("IconItem"))
        _collectionView.dataSource = self
        _collectionView.delegate = self
        _collectionView.registerForDraggedTypes([.fileURL, .URL, .string])

        _collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        _collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        
        let singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleSingleClick(_:)))
        singleClick.numberOfClicksRequired = 1
        singleClick.delaysPrimaryMouseButtonEvents = false
        _collectionView.addGestureRecognizer(singleClick)
        
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.delaysPrimaryMouseButtonEvents = false
        _collectionView.addGestureRecognizer(doubleClick)

        documentView = _collectionView
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
    }
    
    @objc private func handleSingleClick(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: _collectionView)
        guard let ip = _collectionView.indexPathForItem(at: point) else { return }
        guard let viewModel = viewModel, ip.item >= 0, ip.item < viewModel.filteredFiles.count else { return }
        
        let file = viewModel.filteredFiles[ip.item]
        
        if viewModel.selectedURLs.count == 1 && viewModel.selectedURLs.contains(file.url) {
            if let item = _collectionView.item(at: ip) as? IconCollectionItem {
                let pointInItem = item.view.convert(point, from: _collectionView)
                if item.nameTextFieldFrame.contains(pointInItem) {
                    let timeSinceSelection = Date().timeIntervalSince(viewModel.selectionTime)
                    if timeSinceSelection > 0.4 {
                        viewModel.triggerRename(for: file)
                    }
                }
            }
        }
    }
    
    @objc private func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: _collectionView)
        guard let ip = _collectionView.indexPathForItem(at: point) else { return }
        guard let viewModel = viewModel, ip.item >= 0, ip.item < viewModel.filteredFiles.count else { return }
        
        let file = viewModel.filteredFiles[ip.item]
        viewModel.handleDoubleClick(for: file)
    }
    
    private func setupBindings() {
        cancellables.removeAll()
        guard let vm = viewModel else { return }
        
        Publishers.CombineLatest(vm.$files, vm.$searchText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadData()
                self?.syncSelectionFromViewModel()
            }
            .store(in: &cancellables)
    }

    func reloadData() { _collectionView.reloadData() }

    func syncSelectionFromViewModel() {
        guard let viewModel = viewModel else { return }
        isProgrammaticSelection = true
        var indexPaths: Set<IndexPath> = []
        for (idx, file) in viewModel.filteredFiles.enumerated() {
            if viewModel.selectedURLs.contains(file.url) { indexPaths.insert(IndexPath(item: idx, section: 0)) }
        }
        _collectionView.selectionIndexPaths = indexPaths
        isProgrammaticSelection = false
    }

    func syncRenamingFromViewModel() {
        guard viewModel != nil else { return }
        reloadData()
    }
}

extension IconCollectionView: NSCollectionViewDataSource {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel?.filteredFiles.count ?? 0
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("IconItem"), for: indexPath) as! IconCollectionItem
        guard let files = viewModel?.filteredFiles, indexPath.item >= 0, indexPath.item < files.count else { return item }
        let file = files[indexPath.item]
        item.configure(with: file, viewModel: viewModel!)
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard let files = viewModel?.filteredFiles, indexPath.item >= 0, indexPath.item < files.count else { return nil }
        let file = files[indexPath.item]
        let pbItem = NSPasteboardItem()
        pbItem.setString(file.url.absoluteString, forType: .fileURL)
        pbItem.setString(file.url.absoluteString, forType: .URL)
        pbItem.setString(file.url.path, forType: .string)
        return pbItem
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard viewModel?.handleDrop != nil else { return [] }
        let modifiers = NSEvent.modifierFlags
        return modifiers.contains(.shift) ? .move : .copy
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let pasteboard = draggingInfo.draggingPasteboard
        var urls: [URL] = []
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            urls = fileURLs
        } else if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for string in strings {
                if let url = URL(string: string), url.scheme != nil { urls.append(url) }
                else if FileManager.default.fileExists(atPath: string) { urls.append(URL(fileURLWithPath: string)) }
            }
        }
        guard !urls.isEmpty else { return false }

        let modifiers = NSEvent.modifierFlags
        let operation: NSDragOperation = modifiers.contains(.shift) ? .move : .copy

        let targetURL: URL
        if dropOperation == .on, let files = viewModel?.filteredFiles, indexPath.item >= 0, indexPath.item < files.count {
            let file = files[indexPath.item]
            targetURL = file.isDirectory ? file.url : viewModel!.currentPathURL
        } else {
            targetURL = viewModel!.currentPathURL
        }

        viewModel?.handleDrop(urls: urls, to: targetURL, operation: operation)
        return true
    }
}

extension IconCollectionView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !isProgrammaticSelection else { return }
        guard let indexPath = indexPaths.first, let files = viewModel?.filteredFiles, indexPath.item >= 0, indexPath.item < files.count else { return }
        let file = files[indexPath.item]
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) || modifiers.contains(.shift) {
            viewModel?.toggleSelection(for: file.url)
        } else {
            viewModel?.selectedURLs = [file.url]
            viewModel?.lastSelectedURL = file.url
            viewModel?.selectionTime = Date()
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        guard !isProgrammaticSelection else { return }
        for indexPath in indexPaths {
            guard let files = viewModel?.filteredFiles, indexPath.item >= 0, indexPath.item < files.count else { continue }
            let file = files[indexPath.item]
            viewModel?.selectedURLs.remove(file.url)
        }
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        viewModel?.isDraggingFile = true
        viewModel?.cancelRename() // ยกเลิกหากกำลังลาก
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        viewModel?.isDraggingFile = false
    }
}

// MARK: - Context Menu Helper
@MainActor fileprivate class FileContextMenuController: NSObject {
    weak var viewModel: ExplorerViewModel?

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyAction), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let cutItem = NSMenuItem(title: "Cut", action: #selector(cutAction), keyEquivalent: "")
        cutItem.target = self
        menu.addItem(cutItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(pasteAction), keyEquivalent: "")
        pasteItem.target = self
        pasteItem.isEnabled = viewModel?.canPaste ?? false
        menu.addItem(pasteItem)

        menu.addItem(NSMenuItem.separator())

        let terminalItem = NSMenuItem(title: "Open in Terminal", action: #selector(openInTerminalAction), keyEquivalent: "")
        terminalItem.target = self
        menu.addItem(terminalItem)

        menu.addItem(NSMenuItem.separator())

        let selectedCount = viewModel?.selectedURLs.count ?? 0
        let zipFiles = viewModel?.selectedURLs.filter { $0.pathExtension.lowercased() == "zip" } ?? []

        if selectedCount > 0 {
            let compressTitle = selectedCount == 1 ? "Compress \"\(viewModel!.selectedURLs.first!.lastPathComponent)\"" : "Compress \(selectedCount) Items"
            let compressItem = NSMenuItem(title: compressTitle, action: #selector(compressAction), keyEquivalent: "")
            compressItem.target = self
            menu.addItem(compressItem)
        }

        if !zipFiles.isEmpty {
            let uncompressTitle = zipFiles.count == 1 ? "Uncompress \"\(zipFiles.first!.lastPathComponent)\"" : "Uncompress \(zipFiles.count) Items"
            let uncompressItem = NSMenuItem(title: uncompressTitle, action: #selector(uncompressAction), keyEquivalent: "")
            uncompressItem.target = self
            menu.addItem(uncompressItem)
        }

        if selectedCount > 0 || !zipFiles.isEmpty { menu.addItem(NSMenuItem.separator()) }

        let newFolderItem = NSMenuItem(title: "New Folder", action: #selector(newFolderAction), keyEquivalent: "")
        newFolderItem.target = self
        menu.addItem(newFolderItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteAction), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        let renameItem = NSMenuItem(title: "Rename", action: #selector(renameAction), keyEquivalent: "")
        renameItem.target = self
        renameItem.isEnabled = (viewModel?.selectedURLs.count == 1)
        menu.addItem(renameItem)
        
        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        return menu
    }

    @objc private func copyAction() { viewModel?.copySelected() }
    @objc private func cutAction() { viewModel?.cutSelected() }
    @objc private func pasteAction() { viewModel?.paste() }
    @objc private func newFolderAction() { viewModel?.createNewFolder(named: "New Folder") }
    @objc private func deleteAction() { viewModel?.deleteSelected() }
    @objc private func renameAction() { viewModel?.startRename() }
    @objc private func compressAction() { viewModel?.compressSelected() }
    @objc private func uncompressAction() { viewModel?.uncompressSelected() }
    @objc private func refreshAction() { viewModel?.refresh() }

    @objc private func openInTerminalAction() {
        guard let viewModel = viewModel else { return }
        if viewModel.selectedURLs.count == 1, let url = viewModel.selectedURLs.first {
            let targetURL = ExplorerViewModel.resolveIfAlias(url: url) // ✨
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) && isDir.boolValue {
                viewModel.openInTerminal(url: targetURL)
                return
            }
        }
        let targetCurrentURL = ExplorerViewModel.resolveIfAlias(url: viewModel.currentPathURL)
        viewModel.openInTerminal(url: targetCurrentURL)
    }
}

fileprivate class IconItemContainerView: NSView {
    weak var item: IconCollectionItem?
    override func rightMouseDown(with event: NSEvent) { item?.handleRightClick(event: event) }
}

class IconCollectionItem: NSCollectionViewItem {
    private var iconImageView: NSImageView!
    private var nameTextField: NSTextField!
    private var renameTextField: NSTextField!
    private var fileItem: FileItem?
    private weak var explorerViewModel: ExplorerViewModel?
    private var menuController: FileContextMenuController?

    var nameTextFieldFrame: NSRect { return nameTextField.frame }

    override func loadView() {
        let containerView = IconItemContainerView(frame: NSRect(x: 0, y: 0, width: 90, height: 100))
        containerView.item = self
        containerView.wantsLayer = true
        self.view = containerView

        iconImageView = NSImageView(frame: NSRect(x: 22.5, y: 50, width: 45, height: 45))
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        containerView.addSubview(iconImageView)

        nameTextField = NSTextField(labelWithString: "")
        nameTextField.frame = NSRect(x: 0, y: 5, width: 90, height: 40)
        nameTextField.alignment = .center
        nameTextField.font = NSFont.systemFont(ofSize: 11)
        nameTextField.lineBreakMode = .byTruncatingTail
        nameTextField.maximumNumberOfLines = 2
        containerView.addSubview(nameTextField)

        renameTextField = NSTextField(frame: NSRect(x: 2, y: 5, width: 86, height: 20))
        renameTextField.isEditable = true
        renameTextField.isBordered = true
        renameTextField.backgroundColor = .black
        renameTextField.textColor = .white
        renameTextField.font = NSFont.systemFont(ofSize: 11)
        renameTextField.isHidden = true
        renameTextField.delegate = self
        containerView.addSubview(renameTextField)
    }

    func configure(with file: FileItem, viewModel: ExplorerViewModel) {
        self.fileItem = file
        self.explorerViewModel = viewModel

        if let thumb = file.thumbnail {
            iconImageView.image = thumb
        } else {
            iconImageView.image = NSImage(systemSymbolName: file.isDirectory ? "folder.fill" : "doc.text.fill", accessibilityDescription: nil)
            iconImageView.contentTintColor = file.isDirectory ? .systemBlue : .secondaryLabelColor
        }

        nameTextField.stringValue = file.name

        if viewModel.renamingURL?.standardized == file.url.standardized {
            nameTextField.isHidden = true
            renameTextField.isHidden = false
            renameTextField.stringValue = viewModel.renameText
            renameTextField.becomeFirstResponder()
            renameTextField.selectText(nil)
        } else {
            nameTextField.isHidden = false
            renameTextField.isHidden = true
        }

        if viewModel.selectedURLs.contains(file.url) {
            view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            view.layer?.cornerRadius = 8
        } else {
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }

        view.alphaValue = (viewModel.clipboardURLs.contains(file.url) && viewModel.isCutMode) ? 0.5 : 1.0

        if menuController == nil { menuController = FileContextMenuController() }
        menuController?.viewModel = viewModel
    }

    func handleRightClick(event: NSEvent) {
        guard let viewModel = explorerViewModel, let file = fileItem else { return }
        if !viewModel.selectedURLs.contains(file.url) {
            viewModel.selectedURLs = [file.url]
            viewModel.lastSelectedURL = file.url
        }
        if menuController == nil { menuController = FileContextMenuController() }
        menuController?.viewModel = viewModel
        let menu = menuController?.buildMenu() ?? NSMenu()
        let location = self.view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: location, in: self.view)
    }

    override var isSelected: Bool {
        didSet {
            if isSelected {
                view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
                view.layer?.cornerRadius = 8
            } else {
                view.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }
}

extension IconCollectionItem: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField == renameTextField else { return }
        if let reason = obj.userInfo?["NSTextMovement"] as? Int {
            if reason == NSReturnTextMovement {
                explorerViewModel?.renameText = renameTextField.stringValue
                explorerViewModel?.commitRename()
            } else {
                explorerViewModel?.renamingURL = nil
                explorerViewModel?.isEditingText = false
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            explorerViewModel?.renameText = renameTextField.stringValue
            explorerViewModel?.commitRename()
            control.window?.makeFirstResponder(nil)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            explorerViewModel?.renamingURL = nil
            explorerViewModel?.isEditingText = false
            control.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}

// MARK: - Context Menu Table View
@MainActor fileprivate class ContextMenuTableView: NSTableView {
    weak var menuProvider: ListTableView?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)

        guard row >= 0, let provider = menuProvider, let viewModel = provider.viewModel, row < viewModel.filteredFiles.count else {
            let menu = NSMenu()
            let newFolderItem = NSMenuItem(title: "New Folder", action: #selector(emptyNewFolderAction), keyEquivalent: "")
            newFolderItem.target = self
            menu.addItem(newFolderItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(emptyRefreshAction), keyEquivalent: "")
            refreshItem.target = self
            menu.addItem(refreshItem)
            
            return menu
        }

        let file = viewModel.filteredFiles[row]
        if !viewModel.selectedURLs.contains(file.url) {
            viewModel.selectedURLs = [file.url]
            viewModel.lastSelectedURL = file.url
        }

        if provider.menuController == nil { provider.menuController = FileContextMenuController() }
        provider.menuController?.viewModel = viewModel
        return provider.menuController?.buildMenu()
    }

    @objc private func emptyNewFolderAction() { menuProvider?.viewModel?.createNewFolder(named: "New Folder") }
    @objc private func emptyRefreshAction() { menuProvider?.viewModel?.refresh() }
}

// MARK: - List Mode: NSTableView

class ListTableView: NSScrollView, NSTextFieldDelegate {
    private var cancellables = Set<AnyCancellable>()
    
    weak var viewModel: ExplorerViewModel? {
        didSet { setupBindings() }
    }
    var focusedField: FocusState<MainExplorerView.ExplorerFocusField?>.Binding?

    private var _tableView: ContextMenuTableView!
    private var nameColumn: NSTableColumn!
    private var dateColumn: NSTableColumn!
    private var sizeColumn: NSTableColumn!
    private var typeColumn: NSTableColumn!
    private var isProgrammaticSelection = false
    fileprivate var menuController: FileContextMenuController?

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        _tableView = ContextMenuTableView()
        _tableView.menuProvider = self
        _tableView.allowsMultipleSelection = true
        _tableView.allowsEmptySelection = true
        _tableView.usesAlternatingRowBackgroundColors = false
        _tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        _tableView.registerForDraggedTypes([.fileURL, .URL, .string])

        _tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        _tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameColumn.title = "Name"
        nameColumn.minWidth = 200
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        _tableView.addTableColumn(nameColumn)

        dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Date"))
        dateColumn.title = "Date Modified"
        dateColumn.width = 150
        dateColumn.minWidth = 100
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "modificationDate", ascending: true)
        _tableView.addTableColumn(dateColumn)

        sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 100
        sizeColumn.minWidth = 80
        sizeColumn.maxWidth = 150
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "fileSize", ascending: true)
        _tableView.addTableColumn(sizeColumn)

        typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Type"))
        typeColumn.title = "Kind"
        typeColumn.width = 120
        typeColumn.minWidth = 100
        typeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "fileType", ascending: true, selector: #selector(NSString.localizedStandardCompare(_:)))
        _tableView.addTableColumn(typeColumn)

        _tableView.dataSource = self
        _tableView.delegate = self
        
        _tableView.action = #selector(handleSingleClick)
        _tableView.doubleAction = #selector(handleDoubleClick)
        _tableView.target = self

        documentView = _tableView
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
    }
    
    @objc private func handleSingleClick() {
        let row = _tableView.clickedRow
        let col = _tableView.clickedColumn
        guard row >= 0, col >= 0, let viewModel = viewModel, row < viewModel.filteredFiles.count else { return }
        
        let colIdentifier = _tableView.tableColumns[col].identifier.rawValue
        
        if colIdentifier == "Name" && viewModel.selectedURLs.count == 1 {
            let file = viewModel.filteredFiles[row]
            if viewModel.selectedURLs.contains(file.url) {
                let timeSinceSelection = Date().timeIntervalSince(viewModel.selectionTime)
                if timeSinceSelection > 0.4 {
                    viewModel.triggerRename(for: file)
                }
            }
        }
    }
    
    @objc private func handleDoubleClick() {
        let row = _tableView.clickedRow
        guard let files = viewModel?.filteredFiles, row >= 0, row < files.count else { return }
        let file = files[row]
        viewModel?.handleDoubleClick(for: file)
    }
    
    private func setupBindings() {
        cancellables.removeAll()
        guard let vm = viewModel else { return }
        
        Publishers.CombineLatest(vm.$files, vm.$searchText)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reloadData()
                self?.syncSelectionFromViewModel()
            }
            .store(in: &cancellables)
    }

    func reloadData() { _tableView.reloadData() }

    func syncSelectionFromViewModel() {
        guard let viewModel = viewModel else { return }
        isProgrammaticSelection = true
        var indexes = IndexSet()
        for (idx, file) in viewModel.filteredFiles.enumerated() {
            if viewModel.selectedURLs.contains(file.url) { indexes.insert(idx) }
        }
        _tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        isProgrammaticSelection = false
    }

    func syncRenamingFromViewModel() {
        guard let viewModel = viewModel else { return }
        if let renamingURL = viewModel.renamingURL {
            if let index = viewModel.filteredFiles.firstIndex(where: { $0.url.standardized == renamingURL.standardized }) {
                _tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if let cellView = self._tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? NSTableCellView,
                       let textField = cellView.textField {
                        self.window?.makeFirstResponder(textField)
                        if let editor = textField.currentEditor() { editor.selectAll(nil) }
                    }
                }
            }
        } else {
            _tableView.reloadData()
        }
    }
}

extension ListTableView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { return viewModel?.filteredFiles.count ?? 0 }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let files = viewModel?.filteredFiles, row >= 0, row < files.count else { return nil }
        return files[row]
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let files = viewModel?.filteredFiles, row >= 0, row < files.count else { return nil }
        let file = files[row]
        let pbItem = NSPasteboardItem()
        pbItem.setString(file.url.absoluteString, forType: .fileURL)
        pbItem.setString(file.url.absoluteString, forType: .URL)
        pbItem.setString(file.url.path, forType: .string)
        return pbItem
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        let modifiers = NSEvent.modifierFlags
        return modifiers.contains(.shift) ? .move : .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard
        var urls: [URL] = []

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            urls = fileURLs
        } else if let strings = pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] {
            for string in strings {
                if let url = URL(string: string), url.scheme != nil { urls.append(url) }
                else if FileManager.default.fileExists(atPath: string) { urls.append(URL(fileURLWithPath: string)) }
            }
        }
        guard !urls.isEmpty else { return false }

        let modifiers = NSEvent.modifierFlags
        let operation: NSDragOperation = modifiers.contains(.shift) ? .move : .copy

        let targetURL: URL
        if dropOperation == .on && row >= 0 && row < (viewModel?.filteredFiles.count ?? 0) {
            let file = viewModel!.filteredFiles[row]
            targetURL = file.isDirectory ? file.url : viewModel!.currentPathURL
        } else {
            targetURL = viewModel!.currentPathURL
        }

        viewModel?.handleDrop(urls: urls, to: targetURL, operation: operation)
        return true
    }
}

extension ListTableView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnID = tableColumn?.identifier.rawValue else { return nil }
        guard let files = viewModel?.filteredFiles, row >= 0, row < files.count else { return nil }
        let file = files[row]
        let cellID = NSUserInterfaceItemIdentifier("ListCell_\(columnID)")

        var cellView = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView
        if cellView == nil {
            cellView = NSTableCellView()
            cellView?.identifier = cellID

            if columnID == "Name" {
                let imgView = NSImageView()
                imgView.imageScaling = .scaleProportionallyUpOrDown
                imgView.translatesAutoresizingMaskIntoConstraints = false
                cellView?.imageView = imgView
                cellView?.addSubview(imgView)

                let tf = makeListTextField(fontSize: 12, alignment: .left)
                tf.delegate = self
                cellView?.textField = tf
                cellView?.addSubview(tf)

                NSLayoutConstraint.activate([
                    imgView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 8),
                    imgView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imgView.widthAnchor.constraint(equalToConstant: 18),
                    imgView.heightAnchor.constraint(equalToConstant: 18),
                    tf.leadingAnchor.constraint(equalTo: imgView.trailingAnchor, constant: 6),
                    tf.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -8),
                    tf.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            } else {
                let tf = makeListTextField(fontSize: columnID == "Name" ? 12 : 11, alignment: columnID == "Size" ? .right : .left)
                cellView?.textField = tf
                cellView?.addSubview(tf)
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 8),
                    tf.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -8),
                    tf.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
        }

        if columnID == "Name" {
            let isRenaming = (viewModel?.renamingURL?.standardized == file.url.standardized)
            if let thumb = file.thumbnail {
                cellView?.imageView?.image = thumb
            } else {
                cellView?.imageView?.image = NSImage(systemSymbolName: file.isDirectory ? "folder.fill" : "doc.text.fill", accessibilityDescription: nil)
                cellView?.imageView?.contentTintColor = file.isDirectory ? .systemBlue : .secondaryLabelColor
            }
            cellView?.textField?.isEditable      = isRenaming
            cellView?.textField?.isBordered      = isRenaming
            cellView?.textField?.drawsBackground = isRenaming
            cellView?.textField?.backgroundColor = isRenaming ? .black : .clear
            cellView?.textField?.textColor       = isRenaming ? .white : .labelColor
            cellView?.textField?.stringValue     = isRenaming ? (viewModel?.renameText ?? file.name) : file.name
            if isRenaming {
                DispatchQueue.main.async { [weak self] in
                    self?.window?.makeFirstResponder(cellView?.textField)
                    cellView?.textField?.currentEditor()?.selectAll(nil)
                }
            }
        } else if columnID == "Date" {
            cellView?.textField?.stringValue = file.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
            cellView?.textField?.textColor = .secondaryLabelColor
        } else if columnID == "Type" {
            cellView?.textField?.stringValue = file.fileType
            cellView?.textField?.textColor = .secondaryLabelColor
        } else if columnID == "Size" {
            if file.isDirectory {
                if viewModel?.showFolderSizes == true {
                    if let size = file.folderContentSize {
                        cellView?.textField?.stringValue = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        cellView?.textField?.textColor = .secondaryLabelColor
                    } else {
                        cellView?.textField?.stringValue = "Calculating..."
                        cellView?.textField?.textColor = .tertiaryLabelColor
                        Task { [weak viewModel] in await viewModel?.loadFolderSize(for: file) }
                    }
                } else {
                    cellView?.textField?.stringValue = "--"
                    cellView?.textField?.textColor = .tertiaryLabelColor
                }
            } else {
                cellView?.textField?.stringValue = ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file)
                cellView?.textField?.textColor = .secondaryLabelColor
            }
        }

        cellView?.alphaValue = (viewModel?.clipboardURLs.contains(file.url) == true && viewModel?.isCutMode == true) ? 0.5 : 1.0
        return cellView
    }

    private func makeListTextField(fontSize: CGFloat, alignment: NSTextAlignment) -> NSTextField {
        let tf = NSTextField(labelWithString: "")
        tf.isEditable = false
        tf.isBordered = false
        tf.backgroundColor = .clear
        tf.font = NSFont.systemFont(ofSize: fontSize)
        tf.alignment = alignment
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 22 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isProgrammaticSelection else { return }
        guard let tableView = notification.object as? NSTableView else { return }
        var selected = Set<URL>()
        for row in tableView.selectedRowIndexes {
            if row < viewModel!.filteredFiles.count { selected.insert(viewModel!.filteredFiles[row].url) }
        }
        viewModel?.selectedURLs = selected
        viewModel?.lastSelectedURL = selected.first
        viewModel?.selectionTime = Date()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptors = tableView.sortDescriptors.first else { return }
        let key = descriptors.key ?? "name"
        let order: SortOrder = descriptors.ascending ? .forward : .reverse
        if key == "name" { viewModel?.sortDescriptors = [SortDescriptor(\FileItem.name, order: order)] }
        else if key == "modificationDate" { viewModel?.sortDescriptors = [SortDescriptor(\FileItem.modificationDate, order: order)] }
        else if key == "fileType" { viewModel?.sortDescriptors = [SortDescriptor(\FileItem.fileType, order: order)] }
        else if key == "fileSize" { viewModel?.sortDescriptors = [SortDescriptor(\FileItem.fileSize, order: order)] }
        viewModel?.applySort()
        tableView.reloadData()
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, rowIndexes: IndexSet) {
        viewModel?.isDraggingFile = true
        viewModel?.cancelRename() // ยกเลิกการเปลี่ยนชื่อเมื่อเริ่มลากไฟล์
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        viewModel?.isDraggingFile = false
    }
}

extension ListTableView {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        var view: NSView? = textField
        var foundRow: Int?
        while let superview = view?.superview {
            if let cellView = superview as? NSTableCellView {
                let row = _tableView.row(for: cellView)
                if row >= 0 { foundRow = row; break }
            }
            view = superview
        }
        guard let row = foundRow, row < viewModel!.filteredFiles.count else { return }
        let file = viewModel!.filteredFiles[row]
        guard viewModel?.renamingURL?.standardized == file.url.standardized else { return }

        if let reason = obj.userInfo?["NSTextMovement"] as? Int {
            if reason == NSReturnTextMovement {
                viewModel?.renameText = textField.stringValue
                viewModel?.commitRename()
            } else {
                viewModel?.renamingURL = nil
                viewModel?.isEditingText = false
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let textField = control as? NSTextField else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            viewModel?.renameText = textField.stringValue
            viewModel?.commitRename()
            control.window?.makeFirstResponder(nil)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            viewModel?.renamingURL = nil
            viewModel?.isEditingText = false
            control.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}

// MARK: - Details / Inspector View
struct FileDetailView: View {
    @ObservedObject var viewModel: ExplorerViewModel

    var body: some View {
        ZStack(alignment: .top) {
            if viewModel.selectedURLs.count > 1 {
                VStack(spacing: 20) {
                    Spacer().frame(height: 120)
                    Image(systemName: "docs.custom").resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 64).foregroundColor(.secondary)
                    Text("\(viewModel.selectedURLs.count) items selected").font(.headline).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let item = viewModel.files.first(where: { $0.url.standardized == viewModel.selectedURLs.first?.standardized }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 12) {
                            if let thumb = item.thumbnail {
                                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 64)
                            } else {
                                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                                    .resizable().aspectRatio(contentMode: .fit).frame(width: 64, height: 64)
                                    .foregroundColor(item.isDirectory ? .blue : .secondary)
                            }
                            Text(item.name).font(.headline).multilineTextAlignment(.center).lineLimit(5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            DetailItem(label: "Kind", value: item.fileType)
                            if let dims = item.dimensions { DetailItem(label: "Dimensions", value: dims) }
                            if item.isDirectory {
                                if viewModel.showFolderSizes {
                                    if let size = item.folderContentSize {
                                        DetailItem(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    } else {
                                        DetailItem(label: "Size", value: "Calculating...").task { await viewModel.loadFolderSize(for: item) }
                                    }
                                } else {
                                    DetailItem(label: "Size", value: "--")
                                }
                            } else {
                                DetailItem(label: "Size", value: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                            }
                            if let date = item.modificationDate { DetailItem(label: "Modified", value: date.formatted(date: .abbreviated, time: .shortened)) }
                            DetailItem(label: "Where", value: item.url.path)
                        }
                        Spacer()
                    }
                    .padding()
                    .task(id: item.url) { await viewModel.loadMetadata(for: item) }
                }
            } else {
                VStack {
                    Spacer().frame(height: 100)
                    Text("Select an item to view details").foregroundColor(.secondary).italic()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct DetailItem: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary).fontWeight(.semibold)
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}

// MARK: - About View
struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApplication.shared.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
            
            VStack(alignment: .leading, spacing: 16) {
                Text("About KSMacExplorer")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Version 1.0")
                    Text("Copyright © 2026 KS. All rights reserved.")
                }
                
                Text("This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.")
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("DISCLAIMER:")
                    Text("This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                
                HStack {
                    Spacer()
                    Button("View License") {
                        openURL(URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                    }
                    Button("OK") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
        }
        .padding(24)
        .frame(width: 500)
        .fixedSize(horizontal: true, vertical: true)
    }
}