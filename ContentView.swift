import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.055, green: 0.065, blue: 0.055).ignoresSafeArea()
                if library.documents.isEmpty { emptyState }
                else {
                    List {
                        ForEach(library.documents) { document in
                            NavigationLink {
                                ReaderView(document: document)
                            } label: {
                                DocumentRow(document: document)
                            }
                            .listRowBackground(Color.white.opacity(0.035))
                            .swipeActions {
                                Button(role: .destructive) { library.delete(document) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("ReadMeh")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import PDF")
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { library.importPDF(from: url) }
                case .failure(let error): library.errorMessage = error.localizedDescription
                }
            }
            .alert("ReadMeh", isPresented: Binding(
                get: { library.errorMessage != nil },
                set: { if !$0 { library.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(red: 0.77, green: 0.91, blue: 0.46))
            Text("Your library")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
            Text("Bring in a PDF and let ReadMeh read it aloud.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showingImporter = true } label: {
                Label("Import a PDF", systemImage: "plus")
                    .font(.headline).padding(.horizontal, 22).padding(.vertical, 13)
                    .background(Color(red: 0.77, green: 0.91, blue: 0.46))
                    .foregroundStyle(.black).clipShape(Capsule())
            }
            .padding(.top, 8)
        }
        .padding(32)
    }
}

private struct DocumentRow: View {
    let document: DocumentRecord
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Color(red: 0.77, green: 0.91, blue: 0.46))
                .frame(width: 42, height: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title).font(.system(size: 16, weight: .medium)).lineLimit(2)
                Text("\(document.pageCount) pages").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if document.lastPosition > 0 {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct ReaderView: View {
    let document: DocumentRecord
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var speech: SpeechPlayer
    @State private var extractedText = ""
    @State private var loadError: String?
    @State private var isLoading = true

    private var progress: Double {
        guard speech.totalCharacters > 0 else { return 0 }
        return min(1, Double(speech.currentCharacter) / Double(speech.totalCharacters))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.title).font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("\(document.pageCount) pages").font(.subheadline).foregroundStyle(.secondary)
                }
                if isLoading { ProgressView("Preparing document…").frame(maxWidth: .infinity) }
                else if let loadError {
                    ContentUnavailableView("Can't read this PDF", systemImage: "doc.questionmark", description: Text(loadError))
                } else {
                    playbackPanel
                    voicePanel
                    Text(extractedText).font(.system(size: 16)).lineSpacing(7)
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(22)
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.055))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: document.id) {
            do { extractedText = try library.text(for: document); isLoading = false }
            catch { loadError = error.localizedDescription; isLoading = false }
        }
        .onChange(of: speech.currentCharacter) { _, value in
            library.updatePosition(for: document.id, position: value)
        }
        .onDisappear { library.updatePosition(for: document.id, position: speech.currentCharacter, force: true) }
    }

    private var playbackPanel: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                ProgressView(value: progress).tint(Color(red: 0.77, green: 0.91, blue: 0.46))
                HStack {
                    Text("\(speech.currentCharacter.formatted()) characters")
                    Spacer()
                    Text("\(speech.totalCharacters.formatted())")
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 28) {
                Button { speech.stop() } label: { Image(systemName: "stop.fill").font(.title3) }
                Button {
                    if speech.isSpeaking { speech.pause() }
                    else if speech.isPaused { speech.resume() }
                    else { speech.play(text: extractedText, from: document.lastPosition) }
                } label: {
                    Image(systemName: speech.isSpeaking ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 68, height: 68)
                        .background(Color(red: 0.77, green: 0.91, blue: 0.46))
                        .foregroundStyle(.black).clipShape(Circle())
                }
                Button { speech.play(text: extractedText, from: 0) } label: {
                    Image(systemName: "backward.end.fill").font(.title3)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(20).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VOICE").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
            Picker("Narrator", selection: $speech.selectedVoiceIdentifier) {
                ForEach(speech.voices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                }
            }
            .pickerStyle(.menu)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(String(format: "%.2fx", Double(speech.rate / AVSpeechUtteranceDefaultSpeechRate))).monospacedDigit()
                }
                Slider(value: $speech.rate, in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                    .tint(Color(red: 0.77, green: 0.91, blue: 0.46))
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack { Text("Pitch"); Spacer(); Text(String(format: "%.1f", speech.pitch)).monospacedDigit() }
                Slider(value: $speech.pitch, in: 0.5...2.0).tint(Color(red: 0.77, green: 0.91, blue: 0.46))
            }
        }
        .padding(20).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
