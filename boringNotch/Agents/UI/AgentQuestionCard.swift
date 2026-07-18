//
//  AgentQuestionCard.swift
//  boringNotch
//

import SwiftUI

struct AgentQuestionCard: View {
    let sessionID: String
    let prompt: QuestionPrompt

    @ObservedObject private var manager = AgentActivityManager.shared
    @State private var selectedOptionIDs: Set<String> = []
    @State private var freeformText: String = ""

    private var canSubmit: Bool {
        !selectedOptionIDs.isEmpty || !freeformText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(prompt.title, systemImage: "questionmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)

            Text(prompt.question)
                .font(.caption)
                .foregroundStyle(.white)

            ForEach(prompt.options) { option in
                Button {
                    toggle(option)
                } label: {
                    HStack {
                        Image(systemName: optionIcon(for: option))
                        Text(option.label)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white)
            }

            if prompt.allowsFreeform {
                TextField("Type an answer…", text: $freeformText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Submit") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSubmit)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.blue.opacity(0.1)))
    }

    private func optionIcon(for option: QuestionOption) -> String {
        let selected = selectedOptionIDs.contains(option.id)
        return prompt.multiSelect
            ? (selected ? "checkmark.square.fill" : "square")
            : (selected ? "largecircle.fill.circle" : "circle")
    }

    private func toggle(_ option: QuestionOption) {
        if prompt.multiSelect {
            if selectedOptionIDs.contains(option.id) {
                selectedOptionIDs.remove(option.id)
            } else {
                selectedOptionIDs.insert(option.id)
            }
        } else {
            selectedOptionIDs = [option.id]
        }
    }

    private func submit() {
        let trimmed = freeformText.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = QuestionPromptResponse(
            selectedOptionIDs: Array(selectedOptionIDs),
            freeformText: trimmed.isEmpty ? nil : trimmed
        )
        manager.answerQuestion(sessionID: sessionID, response: response)
    }
}
