/// A SwiftUI demo that exercises every feature of the Localaze Swift SDK.
///
/// Point it at the stub server in `../stub-server` (`dart run serve.dart`),
/// then use the Server section to put a patch, a major, or a retyped catalog on
/// offer and watch the SDK accept or refuse it.
///
/// What each section is for is written on the screen, so the app doubles as the
/// documentation for what the SDK does.

import Localaze
import SwiftUI

@main
struct DemoApp: App {
    @StateObject private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            DemoView().environmentObject(model)
        }
    }
}

struct DemoView: View {
    @EnvironmentObject private var model: DemoModel

    var body: some View {
        NavigationStack {
            Form {
                renderedSection
                localeSection
                serverSection
                policySection
                updateSection
                diagnosticsSection
                notesSection
            }
            .navigationTitle("Localaze SDK")
        }
    }

    // MARK: - Sections

    private var renderedSection: some View {
        Section {
            row("authSignOut", model.translations.authSignOut)
            row("authWelcome(name:)", model.translations.authWelcome(name: "Ayan"))
            row("billingDue(when:)",
                model.translations.billingDue(when: demoDate))
            row("inboxUnread(count:)",
                model.translations.inboxUnread(count: model.count))

            Stepper("count — \(model.count)", value: $model.count, in: 0...200)

            // The rows worth trying: in Russian, 11 and 111 select `many`
            // despite ending in 1.
            HStack {
                ForEach([0, 1, 2, 5, 11, 21, 101, 111], id: \.self) { value in
                    Button("\(value)") { model.count = value }
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Rendered strings")
        } footer: {
            Text("""
                Every accessor is typed. inboxUnread(count:) cannot be called \
                without a number — that is a compile error, not a runtime one. \
                The Russian plural rule is compiled into Localaze.g.swift, so \
                no plural data ships and no MessageFormat is parsed on device.
                """)
        }
    }

    private var localeSection: some View {
        Section {
            Picker("Locale", selection: Binding(
                get: { model.locale },
                set: { model.setLocale($0) }
            )) {
                Text("Azərbaycan").tag("az")
                Text("Русский").tag("ru")
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Locale")
        } footer: {
            Text("Switches at runtime, with no restart.")
        }
    }

    private var serverSection: some View {
        Section {
            Picker("Serving", selection: Binding(
                get: { model.scenario },
                set: { next in Task { await model.serve(next) } }
            )) {
                ForEach(Scenario.allCases) { scenario in
                    Text(scenario.rawValue).tag(scenario)
                }
            }
            Text(model.scenario.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Server")
        } footer: {
            Text("""
                Puts a release on offer. The stub server serves the same \
                fixtures the conformance suites assert on.
                """)
        }
    }

    private var policySection: some View {
        Section {
            Picker("Policy", selection: $model.policy) {
                Text("none").tag(LocalazeUpdatePolicy.none)
                Text("patchOnly").tag(LocalazeUpdatePolicy.patchOnly)
                Text("minorAndPatch").tag(LocalazeUpdatePolicy.minorAndPatch)
            }
            Toggle("applyImmediately", isOn: $model.applyImmediately)
        } header: {
            Text("Update policy")
        } footer: {
            Text("""
                Policy is about intent. The signature check is about \
                possibility, and it runs regardless — a major is refused under \
                every policy, including a range. applyImmediately is off by \
                default in the SDK: text changing under a user mid-session is \
                worse than being one launch out of date.
                """)
        }
    }

    private var updateSection: some View {
        Section {
            Button {
                Task { await model.update() }
            } label: {
                HStack {
                    if model.busy { ProgressView() }
                    Text("Check for update")
                }
            }
            .disabled(model.busy)

            Button("Apply pending") { _ = model.applyPending() }

            if let status = model.lastStatus {
                StatusRow(status: status)
            }
        } header: {
            Text("Update — v\(model.version)")
        } footer: {
            Text("Never throws, and never blocks a screen.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            if model.diagnostics.isEmpty {
                Text("Nothing reported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.diagnostics.prefix(12).enumerated()), id: \.offset) {
                    Text($0.element)
                        .font(.system(.caption, design: .monospaced))
                }
                Button("Clear") { model.clearDiagnostics() }
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("""
                Nothing in the SDK throws, so a wrong key and a quiet network \
                look identical from outside. This callback is how anyone finds \
                out an integration never worked.
                """)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            Text("""
                This demo configures no storage, so an applied update lasts for \
                the session only — the documented default when none is given.

                Server: \(baseUrl)
                """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bits

    private var demoDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
    }

    private func row(_ call: String, _ rendered: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(call)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(rendered).font(.body)
        }
    }
}

struct StatusRow: View {
    let status: LocalazeFetchStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(headline, systemImage: icon).foregroundStyle(colour)
            if let detail = status.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        switch status.outcome {
        case .applied: return "Applied\(status.version.map { " \($0)" } ?? "")"
        case .upToDate: return "Already up to date"
        case .refusedByPolicy: return "Refused by policy"
        case .refusedBySignature: return "Refused by signature"
        case .failed: return "Failed"
        case .none: return "—"
        }
    }

    private var icon: String {
        switch status.outcome {
        case .applied: return "checkmark.circle"
        case .upToDate: return "checkmark.circle.badge.questionmark"
        case .refusedByPolicy: return "hand.raised"
        case .refusedBySignature: return "exclamationmark.shield"
        case .failed: return "wifi.slash"
        case .none: return "circle"
        }
    }

    private var colour: Color {
        switch status.outcome {
        case .applied: return .green
        case .upToDate: return .secondary
        case .refusedByPolicy: return .orange
        case .refusedBySignature, .failed: return .red
        case .none: return .secondary
        }
    }
}
