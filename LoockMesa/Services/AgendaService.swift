import Foundation
import AppKit
import EventKit

final class AgendaService: ObservableObject {
    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var connected = false
    @Published private(set) var status = "Conecte sua agenda para ver eventos"
    @Published private(set) var reminders: [String] = []
    @Published private(set) var remindersConnected = false
    @Published private(set) var remindersStatus = "Conecte os Lembretes"
    private var reminderFetch: Any?
    private var reminderGeneration = 0
    func connectReminders() {
        store.requestAccess(to: .reminder) { [weak self] _, _ in DispatchQueue.main.async { self?.refreshReminders() } }
    }
    func refreshReminders() {
        guard !paused else { return }
        reminderGeneration += 1
        let generation = reminderGeneration
        if let reminderFetch { store.cancelFetchRequest(reminderFetch) }
        reminderFetch = nil
        let authorization = EKEventStore.authorizationStatus(for: .reminder)
        remindersConnected = authorization == .authorized
        guard remindersConnected else {
            reminders = []
            remindersStatus = authorization == .notDetermined ? "Conecte os Lembretes" : "Acesso não permitido"
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        reminderFetch = store.fetchReminders(matching: predicate) { [weak self] values in
            // Extract value types before publishing on the main thread.
            let titles = (values ?? []).sorted { ($0.title ?? "") < ($1.title ?? "") }.map { $0.title ?? "Lembrete" }
            DispatchQueue.main.async {
                guard let self, generation == self.reminderGeneration else { return }
                self.reminderFetch = nil
                self.reminders = titles
                self.remindersStatus = titles.isEmpty ? "Nenhum Lembrete" : "Lembretes do Mac"
            }
        }
    }
    @Published private(set) var notesConnected = false
    @Published private(set) var noteTitle = ""
    @Published private(set) var noteText = ""
    @Published private(set) var notesStatus = "Nota local · conexão com Notas da Apple opcional"
    private var notesLoading = false
    private var notesGeneration = 0
    func disconnectNotes() {
        notesGeneration += 1; notesConnected = false
        notesStatus = "Nota local do Loock"
    }
    func connectNotes() {
        guard !notesLoading else { return }
        notesLoading = true
        let generation = notesGeneration
        notesStatus = "Consultando Notas…"
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let script = NSAppleScript(source: """
            tell application "Notes"
                if (count of notes) is 0 then return {"Nenhuma nota", ""}
                set currentNote to first note
                return {name of currentNote, plaintext of currentNote}
            end tell
            """)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            let title = result?.atIndex(1)?.stringValue ?? ""
            let body = String((result?.atIndex(2)?.stringValue ?? "").prefix(12000))
            let succeeded = error == nil && result?.numberOfItems == 2
            DispatchQueue.main.async {
                guard let self else { return }
                self.notesLoading = false
                guard generation == self.notesGeneration else { return }
                self.notesConnected = succeeded
                if succeeded { self.noteTitle = title; self.noteText = body }
                self.notesStatus = succeeded ? "Notas da Apple · primeira nota da lista" : "Não foi possível ler Notas. Autorize em Privacidade → Automação."
            }
        }
    }
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var paused = false
    func setPaused(_ value: Bool) { guard paused != value else { return }; paused = value; if !value { refresh() } }
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 30
        refresh()
    }
    deinit { timer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) } }
    func connect() {
        store.requestAccess(to: .event) { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
    }
    func refresh() {
        guard !paused else { return }
        refreshReminders()
        if notesConnected { connectNotes() }
        let authorization = EKEventStore.authorizationStatus(for: .event)
        guard authorization == .authorized else {
            entries = []; connected = false
            status = authorization == .notDetermined ? "Conecte sua agenda para ver eventos" : "Acesso à agenda não permitido"
            return
        }
        connected = true
        let now = Date(); let end = Calendar.current.date(byAdding: .day, value: 7, to: now)!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        entries = store.events(matching: predicate).filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }.prefix(8).enumerated().map { index, event in
            CalendarEntry(id: (event.eventIdentifier ?? "event") + "-\(index)", title: event.title?.isEmpty == false ? event.title! : "Evento sem título", start: event.startDate, end: event.endDate, allDay: event.isAllDay)
        }
        status = entries.isEmpty ? "Nenhum evento nos próximos 7 dias" : "Agenda do Mac · próximos 7 dias"
    }
}

/// Launches installed system apps; never reads their databases directly.
func openWidgetApp(_ kind: WidgetKind) {
    let identifier: String
    switch kind {
    case .screenTime: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension")!); return
    case .music: MusicService.shared.openSource(); return
    case .calendar: identifier = "com.apple.iCal"
    case .reminders: identifier = "com.apple.reminders"
    case .notes: identifier = "com.apple.Notes"
    case .weather: identifier = "com.apple.weather"
    case .clock: identifier = "com.apple.clock"
    case .headphones, .macBattery: identifier = "com.apple.systempreferences"
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
}
