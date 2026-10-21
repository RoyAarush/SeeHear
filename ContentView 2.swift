import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var settings = SpeechSettings()
    @StateObject private var voice = VoiceListener()
    @State private var description = ""
    @State private var isWorking = false
    @State private var showSettings = false
    private let speaker = Speaker()

    private let accent = Color(red: 0.0, green: 0.8, blue: 0.6)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Text("SeeHear")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(accent)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                    }
                    .accessibilityLabel("Settings")
                }

                if camera.permissionDenied {
                    Text("Camera access is required. Please enable it in Settings > SeeHear > Camera.")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(20)
                } else {
                    CameraView(session: camera.session)
                        .cornerRadius(20)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent, lineWidth: 3))
                        .accessibilityHidden(true)
                }

                ScrollView {
                    Text(description)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(description.isEmpty ? "No description yet" : description)
                }
                .frame(height: 90)

                bigButton(isWorking ? "Looking..." : "Describe Surroundings", fill: accent, text: .black) {
                    describeSurroundings()
                }
                .disabled(isWorking || camera.permissionDenied)
                .accessibilityHint("Takes a picture and says what is in front of you")

                bigButton("Read Text Aloud", fill: .orange, text: .black) { readText() }
                    .disabled(isWorking || camera.permissionDenied)
                    .accessibilityHint("Reads signs, menus, or documents in front of the camera")

                HStack(spacing: 10) {
                    smallButton(voice.isListening ? "Listening..." : "Voice Command", fill: .purple) {
                        speaker.stop()
                        voice.listen(onCommand: handle)
                    }
                    .accessibilityHint("Say describe, read, repeat, stop, faster, or slower")

                    smallButton("Repeat", fill: .blue) { say(description) }
                        .disabled(description.isEmpty)
                        .opacity(description.isEmpty ? 0.4 : 1)

                    smallButton("Stop", fill: .red) { speaker.stop() }
                }
            }
            .padding()
        }
        .onAppear { camera.start() }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, test: { say("This is how fast I will speak.") }) }
    }

    // MARK: Buttons
    private func bigButton(_ title: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2.bold())
                .foregroundColor(text)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(fill)
                .cornerRadius(20)
        }
        .accessibilityLabel(title == "Looking..." ? "Describe Surroundings" : title)
    }

    private func smallButton(_ title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(fill)
                .cornerRadius(16)
        }
    }

    // MARK: Actions
    private func say(_ text: String) { speaker.speak(text, rate: settings.rate) }

    private func describeSurroundings() {
        isWorking = true
        VisionDetector.describe(frame: camera.currentFrame(), detailed: settings.detailed) { text in
            description = text
            isWorking = false
            say(text)
        }
    }

    private func readText() {
        isWorking = true
        VisionDetector.readText(frame: camera.currentFrame()) { text in
            description = text
            isWorking = false
            say(text)
        }
    }

    private func handle(_ command: VoiceCommand) {
        switch command {
        case .describe:   describeSurroundings()
        case .read:       readText()
        case .repeatLast: say(description)
        case .stop:       speaker.stop()
        case .faster:
            settings.rate = min(0.6, settings.rate + 0.05)
            say("Faster")
        case .slower:
            settings.rate = max(0.3, settings.rate - 0.05)
            say("Slower")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SpeechSettings
    let test: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Speech speed") {
                    Slider(value: $settings.rate, in: 0.3...0.6, step: 0.02)
                        .accessibilityLabel("Speech speed")
                        .accessibilityValue("\(Int((settings.rate - 0.3) / 0.3 * 100)) percent")
                    Button("Test voice", action: test)
                }
                Section("Description length") {
                    Toggle("Detailed descriptions", isOn: $settings.detailed)
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
