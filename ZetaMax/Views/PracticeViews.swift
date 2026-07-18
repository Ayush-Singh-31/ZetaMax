import SwiftUI

struct PracticeSetupView: View {
    @Bindable var engine: SessionEngine

    var body: some View {
        ZetaScreen(maxWidth: 960) {
            VStack(alignment: .leading, spacing: 24) {
                ZetaPageHeader(
                    title: "Practice",
                    systemImage: "bolt.fill"
                )

                Picker("Mode", selection: $engine.configuration.mode) {
                    ForEach(PracticeMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: engine.configuration.mode) { _, mode in
                    if mode == .benchmark {
                        engine.applyBenchmark(BenchmarkProfile.builtIns.first { $0.durationSeconds == 120 }!)
                    } else {
                        engine.configuration.benchmarkID = nil
                        engine.configuration.benchmarkVersion = nil
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 18) {
                        modeConfiguration
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .groupBoxStyle(ZetaGroupBoxStyle())

            }
        }
        .accessibilityIdentifier("practiceScreen")
        .safeAreaInset(edge: .bottom) {
            HStack {
                storageLabel
                Spacer()
                startButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
        }
        .navigationTitle("Practice")
    }

    private var storageLabel: some View {
        Label("Stored only on this Mac", systemImage: "lock.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var startButton: some View {
        Button("Start session") { engine.start() }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityIdentifier("startSessionButton")
    }

    @ViewBuilder
    private var modeConfiguration: some View {
        switch engine.configuration.mode {
        case .classic, .adaptive:
            operations
            Divider()
            rangeEditors
            Divider()
            durationEditor
            if engine.configuration.mode == .adaptive {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Weakness focus")
                        Spacer()
                        Text(focusLabel).foregroundStyle(.secondary)
                    }
                    Slider(value: $engine.configuration.adaptiveFocus, in: 0...1)
                    Text("Lower values preserve variety; higher values concentrate on categories that take longer or have recently slowed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .targeted:
            Picker("Target", selection: $engine.configuration.targetedPreset) {
                ForEach(TargetedPreset.allCases) { preset in Text(preset.title).tag(preset) }
            }
            Text(engine.configuration.targetedPreset.detail)
                .foregroundStyle(.secondary)
            RangeEditor(title: "Practice range", range: $engine.configuration.targetedRange)
            durationEditor
        case .benchmark:
            Picker("Profile", selection: benchmarkSelection) {
                ForEach(BenchmarkProfile.builtIns) { profile in Text(profile.name).tag(profile.id) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 10) {
                Label("All four operations", systemImage: "checkmark.seal.fill")
                Label("Addition 2–100", systemImage: "plus")
                Label("Multiplication 2–12 × 2–100", systemImage: "multiply")
            }
            .foregroundStyle(.secondary)
            Text("Benchmark settings are locked and versioned, so scores remain comparable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var operations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Operations").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 10) {
                ForEach(ArithmeticOperation.allCases.filter { [.addition, .subtraction, .multiplication, .division].contains($0) }) { operation in
                    Toggle(isOn: operationBinding(operation)) {
                        Text("\(operation.symbol)  \(operation.title)")
                    }
                    .toggleStyle(.button)
                }
            }
        }
    }

    private var rangeEditors: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operand ranges").font(.headline)
            RangeEditor(title: "Addition · left", range: $engine.configuration.additionLeft)
            RangeEditor(title: "Addition · right", range: $engine.configuration.additionRight)
            RangeEditor(title: "Multiplication · left", range: $engine.configuration.multiplicationLeft)
            RangeEditor(title: "Multiplication · right", range: $engine.configuration.multiplicationRight)
            Text("Subtraction reverses generated addition questions; division reverses multiplication for exact integer answers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var durationEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Duration").font(.headline)
                Spacer()
                Text(DurationText.compact(engine.configuration.durationSeconds)).monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68, maximum: 100))], alignment: .leading, spacing: 8) {
                ForEach([30, 45, 60, 120, 300, 600], id: \.self) { seconds in
                    Button(DurationText.compact(seconds)) { engine.configuration.durationSeconds = seconds }
                        .buttonStyle(.bordered)
                        .tint(engine.configuration.durationSeconds == seconds ? .accentColor : .secondary)
                }
            }
            Stepper("Custom duration: \(engine.configuration.durationSeconds) seconds", value: $engine.configuration.durationSeconds, in: 15...3_600, step: 15)
                .frame(maxWidth: 280, alignment: .leading)
        }
    }

    private var focusLabel: String {
        switch engine.configuration.adaptiveFocus {
        case ..<0.34: "Varied"
        case ..<0.67: "Balanced"
        default: "Concentrated"
        }
    }

    private func operationBinding(_ operation: ArithmeticOperation) -> Binding<Bool> {
        Binding(
            get: { engine.configuration.operations.contains(operation) },
            set: { enabled in
                if enabled {
                    if !engine.configuration.operations.contains(operation) { engine.configuration.operations.append(operation) }
                } else if engine.configuration.operations.count > 1 {
                    engine.configuration.operations.removeAll { $0 == operation }
                }
            }
        )
    }

    private var benchmarkSelection: Binding<String> {
        Binding(
            get: { engine.configuration.benchmarkID ?? "zetamac-standard-120" },
            set: { id in
                if let profile = BenchmarkProfile.builtIns.first(where: { $0.id == id }) { engine.applyBenchmark(profile) }
            }
        )
    }
}

private struct RangeEditor: View {
    let title: String
    @Binding var range: OperandRange

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).frame(minWidth: 130, idealWidth: 170, maxWidth: 190, alignment: .leading)
                fields
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.callout.weight(.medium))
                fields
            }
        }
    }

    private var fields: some View {
        HStack {
            TextField("Minimum", value: $range.minimum, format: .number)
                .frame(minWidth: 68, idealWidth: 90, maxWidth: 100)
                .multilineTextAlignment(.trailing)
            Text("to").foregroundStyle(.secondary)
            TextField("Maximum", value: $range.maximum, format: .number)
                .frame(minWidth: 68, idealWidth: 90, maxWidth: 100)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ActivePracticeView: View {
    @Bindable var engine: SessionEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.zetaReduceMotionOverride) private var reduceMotionOverride

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                metric("Time", DurationText.clock(engine.remainingSeconds))
                Spacer()
                Button("End", role: .cancel) { engine.endEarly() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                metric("Score", String(engine.score))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) { Divider() }

            Spacer()

            VStack(spacing: 34) {
                Text(engine.currentQuestion?.prompt ?? "")
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("questionPrompt")
                    .accessibilityLabel(engine.currentQuestion?.prompt ?? "Question")

                FocusedAnswerField(
                    text: $engine.answerText,
                    onTextChange: engine.answerDidChange,
                    onSubmit: engine.submitCurrentAnswer
                )
                .frame(width: 320, height: 58)
                .accessibilityIdentifier("answerField")

                Label("Correct answers auto-submit · Return records an incorrect answer", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .animation(reduceMotion || reduceMotionOverride ? nil : .snappy(duration: 0.18), value: engine.currentQuestion?.prompt)

            Spacer()
            ZetaStatusChip(title: engine.configuration.mode.title, color: ZetaTheme.brand, systemImage: engine.configuration.mode.systemImage)
                .padding(22)
        }
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    colors: [engine.remainingSeconds <= 10 ? ZetaTheme.caution.opacity(0.13) : ZetaTheme.brand.opacity(0.10), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 500
                )
            }.ignoresSafeArea()
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: label == "Time" ? .leading : .trailing, spacing: 3) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(label == "Time" && engine.remainingSeconds <= 10 ? ZetaTheme.caution : Color.primary)
                .accessibilityIdentifier(label == "Score" ? "practiceScore" : "practiceTime")
        }
        .frame(width: 130, alignment: label == "Time" ? .leading : .trailing)
    }
}

struct SessionResultsView: View {
    @Bindable var engine: SessionEngine

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: session?.status == .completed ? "checkmark.circle.fill" : "pause.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(session?.status == .completed ? ZetaTheme.positive : ZetaTheme.caution)
            VStack(spacing: 6) {
                Text(session?.status == .completed ? "Session complete" : "Session interrupted")
                    .font(.largeTitle.bold())
                Text(session?.status == .completed ? "Your question-level data is ready to explore." : "The work was saved but excluded from benchmark trends.")
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190))], spacing: 12) {
                ZetaMetricTile(title: "Completed", value: String(session?.correctCount ?? 0), tint: ZetaTheme.brand)
                ZetaMetricTile(title: "Questions/min", value: String(format: "%.1f", questionsPerMinute), tint: ZetaTheme.cyan)
                ZetaMetricTile(title: "Median", value: milliseconds(median), tint: ZetaTheme.caution)
                ZetaMetricTile(title: "P90", value: p90Text, tint: Color(red: 0.62, green: 0.34, blue: 0.92))
            }
            .frame(maxWidth: 760)
            HStack {
                Button("Back to setup") { engine.dismissResults() }
                Button("Practice again") {
                    engine.dismissResults()
                    engine.start()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            Spacer()
        }
        .padding(32)
        .background(ZetaBackground())
    }

    private var session: PracticeSession? { engine.completedSession }
    private var median: Double {
        Statistics.median(session?.completedAttempts.compactMap(\.responseTimeMilliseconds).map(Double.init) ?? []) ?? 0
    }
    private var p90: Double {
        Statistics.percentile(session?.completedAttempts.compactMap(\.responseTimeMilliseconds).map(Double.init) ?? [], 0.9) ?? 0
    }
    private var p90Text: String {
        guard (session?.completedAttempts.count ?? 0) >= Statistics.reliableTailSampleCount else { return "—" }
        return milliseconds(p90)
    }
    private var questionsPerMinute: Double {
        guard let session else { return 0 }
        let elapsed = Double(session.activeElapsedMilliseconds ?? 0) / 1_000
        return elapsed > 0 ? Double(session.correctCount) / (elapsed / 60) : 0
    }
    private func milliseconds(_ value: Double) -> String { value > 0 ? String(format: "%.2fs", value / 1_000) : "—" }
}
