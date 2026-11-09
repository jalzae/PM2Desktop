import SwiftUI
import AppKit

struct AddProcessSheet: View {
    @EnvironmentObject var store: PM2Store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var scriptPath = ""
    @State private var cwd = ""
    @State private var args = ""
    @State private var interpreter = "auto"
    @State private var customInterpreter = ""
    @State private var buildCommand = ""
    @State private var autoRestart = true
    @State private var errorText: String?
    @State private var isSubmitting = false

    private let interpreterChoices = ["auto", "node", "ts-node", "bun", "deno", "python3", "custom"]

    private var resolvedInterpreter: String {
        interpreter == "custom" ? customInterpreter : interpreter
    }

    private var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Name is required."
        }
        if scriptPath.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Start target is required (a script file or an executable such as npm)."
        }
        if interpreter == "custom" && customInterpreter.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter a custom interpreter."
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New PM2 Process")
                    .font(.headline)
                Text("PM2 keeps it running and restarts it if it crashes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            Divider()

            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("my-app"))
                        .onChange(of: scriptPath) { newValue in
                            if name.isEmpty, let last = newValue.split(separator: "/").last {
                                name = last.replacingOccurrences(of: ".", with: " ")
                                    .split(separator: " ").first.map(String.init) ?? name
                            }
                        }

                    HStack(spacing: 8) {
                        TextField("Start target", text: $scriptPath, prompt: Text("/path/to/app.js — or npm"))
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { pickScript() }
                    }

                    HStack(spacing: 8) {
                        TextField("Working directory", text: $cwd, prompt: Text("Defaults to the script folder"))
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") { pickDirectory() }
                    }

                    TextField("Arguments", text: $args, prompt: Text("e.g. --port 3000 (space separated)"))
                }

                Section("Build (optional)") {
                    TextField("Build command", text: $buildCommand, prompt: Text("e.g. npm run build — runs before start"))
                }

                Section("Options") {
                    Picker("Interpreter", selection: $interpreter) {
                        ForEach(interpreterChoices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                    }
                    if interpreter == "custom" {
                        TextField("Custom interpreter", text: $customInterpreter, prompt: Text("e.g. tsx"))
                    }
                    Toggle("Restart automatically on crash", isOn: $autoRestart)
                }
            }
            .formStyle(.grouped)
            .padding(.top, -14)

            Divider()

            VStack(spacing: 8) {
                if let error = errorText {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let validation = validationMessage {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(isSubmitting ? "Starting…" : "Create & Start") {
                        Task { await submit() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil || isSubmitting)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 520)
    }

    private func pickScript() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = cwd.isEmpty ? nil : URL(fileURLWithPath: cwd)
        if panel.runModal() == .OK, let url = panel.url {
            scriptPath = url.path
            if cwd.isEmpty {
                cwd = url.deletingLastPathComponent().path
            }
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            cwd = url.path
        }
    }

    private func submit() async {
        errorText = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let config = NewProcessConfig(
            name: name.trimmingCharacters(in: .whitespaces),
            scriptPath: scriptPath.trimmingCharacters(in: .whitespaces),
            cwd: cwd.trimmingCharacters(in: .whitespaces),
            args: args,
            interpreter: resolvedInterpreter,
            buildCommand: buildCommand.trimmingCharacters(in: .whitespaces),
            autoRestart: autoRestart
        )

        do {
            try await store.addProcess(config)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
