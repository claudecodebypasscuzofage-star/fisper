import SwiftUI

// MARK: - Dictionary

struct DictionaryView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: DictEntry?
    @State private var adding = false
    @State private var query = ""

    var body: some View {
        PageScroll {
            PageHeader(title: "Dictionary", subtitle: "Names, jargon and spellings Fisper should always get right.") {
                Button("Add new") { adding = true }.buttonStyle(PrimaryButton())
            }
            if state.dictionary.items.count > 8 { SearchField(text: $query) }
            let items = state.dictionary.items.filter {
                query.isEmpty || $0.word.localizedCaseInsensitiveContains(query) || ($0.replacement ?? "").localizedCaseInsensitiveContains(query)
            }
            if items.isEmpty {
                EmptyState(icon: "character.book.closed", title: "No words yet",
                           detail: "Add names (“Siobhan”), product terms (“Kubernetes”) or fixes (“chat GPT → ChatGPT”).")
            } else {
                ListContainer {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, e in
                        ListRow(onEdit: { editing = e }, onDelete: { state.dictionary.items.removeAll { $0.id == e.id } }) {
                            HStack(spacing: 8) {
                                if e.isCorrection {
                                    HStack(spacing: 6) {
                                        Text(e.word).foregroundStyle(Theme.text2)
                                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3)
                                        Text(e.replacement!)
                                    }
                                } else {
                                    Text(e.word)
                                }
                                if e.learned == true {
                                    Label("Learned", systemImage: "sparkles").font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(Theme.forest)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.forestSoft))
                                        .help("Fisper learned this when you corrected a dictation")
                                }
                            }
                        }
                        if idx < items.count - 1 { Divider().overlay(Theme.hairline) }
                    }
                }
            }
            Text("Words here are also fed to Whisper as hints, so they're recognized more often in the first place. When you fix a word right after dictating, Fisper adds it here automatically ✨.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
            let picked = state.personal.profile.learnedWords
            if !picked.isEmpty && state.prefs.learnVocabulary {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PICKED UP FROM YOUR DICTATIONS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                    Chips(items: Array(picked.prefix(24)))
                    Text("Fisper hints these names and terms to the speech model automatically.").font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                }
            }
        }
        .sheet(isPresented: $adding) { DictEditor(entry: nil) }
        .sheet(item: $editing) { e in DictEditor(entry: e) }
    }
}

struct DictEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let entry: DictEntry?
    @State private var word = ""
    @State private var replacement = ""
    @State private var isCorrection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry == nil ? "Add a new word" : "Edit word").font(Theme.serif(24))
            Toggle("Correct a misspelling", isOn: $isCorrection).toggleStyle(.switch).font(.system(size: 13))
            if isCorrection {
                LabeledField(label: "When Fisper hears", placeholder: "chat GPT", text: $word)
                LabeledField(label: "Always write", placeholder: "ChatGPT", text: $replacement)
            } else {
                LabeledField(label: "Word or phrase", placeholder: "Kubernetes", text: $word)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add word" : "Save") { save() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
                    .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty || (isCorrection && replacement.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(26)
        .frame(width: 420)
        .background(Theme.canvas)
        .onAppear {
            if let e = entry { word = e.word; replacement = e.replacement ?? ""; isCorrection = e.isCorrection }
        }
    }

    private func save() {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        var e = entry ?? DictEntry(word: w)
        e.word = w
        e.replacement = isCorrection && !r.isEmpty ? r : nil
        if let i = state.dictionary.items.firstIndex(where: { $0.id == e.id }) { state.dictionary.items[i] = e }
        else { state.dictionary.items.insert(e, at: 0) }
        dismiss()
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: Snippet?
    @State private var adding = false

    var body: some View {
        PageScroll {
            PageHeader(title: "Snippets", subtitle: "Say a cue, get the full text — emails, links, addresses, sign-offs.") {
                Button("Add new") { adding = true }.buttonStyle(PrimaryButton())
            }
            SnippetDemo()
            if state.snippets.items.isEmpty {
                EmptyState(icon: "scissors", title: "No snippets yet", detail: "Try “my email”, “my calendar link” or “my address”.")
            } else {
                ListContainer {
                    ForEach(Array(state.snippets.items.enumerated()), id: \.element.id) { idx, s in
                        ListRow(onEdit: { editing = s }, onDelete: { state.snippets.items.removeAll { $0.id == s.id } }) {
                            HStack(alignment: .top, spacing: 10) {
                                Text("“\(s.trigger)”").fontWeight(.medium).frame(minWidth: 120, alignment: .leading)
                                Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3).padding(.top, 4)
                                Text(s.expansion).foregroundStyle(Theme.text2).lineLimit(3)
                            }
                        }
                        if idx < state.snippets.items.count - 1 { Divider().overlay(Theme.hairline) }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { SnippetEditor(snippet: nil) }
        .sheet(item: $editing) { s in SnippetEditor(snippet: s) }
    }
}

struct SnippetDemo: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("If you go to").foregroundStyle(Theme.text2)
            Text("“my LinkedIn”").fontWeight(.semibold)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border))
            Image(systemName: "arrow.right").foregroundStyle(Theme.text3).font(.system(size: 11, weight: .semibold))
            Text("linkedin.com/in/you").foregroundStyle(Theme.forest).fontWeight(.medium)
            Text("you'll see what…").foregroundStyle(Theme.text2)
        }
        .font(.system(size: 13.5))
        .padding(.vertical, 22).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardAlt))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
    }
}

struct SnippetEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let snippet: Snippet?
    @State private var trigger = ""
    @State private var expansion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(snippet == nil ? "New snippet" : "Edit snippet").font(Theme.serif(24))
            LabeledField(label: "When you say", placeholder: "my email", text: $trigger)
            VStack(alignment: .leading, spacing: 6) {
                Text("Fisper types").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                TextEditor(text: $expansion)
                    .font(.system(size: 13.5)).scrollContentBackground(.hidden)
                    .frame(height: 110).padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(PrimaryButton())
                    .disabled(trigger.trimmingCharacters(in: .whitespaces).isEmpty || expansion.isEmpty)
            }
        }
        .padding(26).frame(width: 460).background(Theme.canvas)
        .onAppear { if let s = snippet { trigger = s.trigger; expansion = s.expansion } }
    }

    private func save() {
        var s = snippet ?? Snippet(trigger: "", expansion: "")
        s.trigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        s.expansion = expansion
        if let i = state.snippets.items.firstIndex(where: { $0.id == s.id }) { state.snippets.items[i] = s }
        else { state.snippets.items.insert(s, at: 0) }
        dismiss()
    }
}

// MARK: - Style

struct StyleView: View {
    @EnvironmentObject var prefs: Preferences
    @State private var category: AppCategory = .personal

    var body: some View {
        PageScroll {
            PageHeader(title: "Style", subtitle: "Fisper adapts to where you're writing. Pick how each kind of app should sound.")
            HStack(spacing: 22) {
                ForEach(AppCategory.allCases) { c in
                    Button { category = c } label: {
                        VStack(spacing: 7) {
                            Text(c.title).font(.system(size: 13.5, weight: category == c ? .semibold : .regular))
                                .foregroundStyle(category == c ? Theme.text : Theme.text2)
                            Rectangle().fill(category == c ? Theme.text : .clear).frame(height: 2)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }

            Text("Applies in \(category.subtitle).").font(.system(size: 12.5)).foregroundStyle(Theme.text2)

            HStack(spacing: 14) {
                ForEach(WritingStyle.allCases) { s in
                    StyleCard(style: s, selected: prefs.style(for: category) == s) {
                        prefs.styles[category] = s
                    }
                }
            }
            Text("Style only changes capitalization and punctuation — your words stay yours. Code editors and terminals fall under “Other”.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
        }
    }
}

struct StyleCard: View {
    let style: WritingStyle
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(style.title).font(Theme.serif(26))
                Text(style.caption.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text3).tracking(0.6)
                Spacer(minLength: 6)
                Text(style.example)
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardAlt))
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Theme.forest : Theme.border, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.forest).font(.system(size: 16)).padding(12)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small shared pieces

struct ListContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border))
    }
}

struct ListRow<Content: View>: View {
    var onEdit: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: Content
    @State private var hover = false
    var body: some View {
        HStack {
            content.font(.system(size: 13.5))
            Spacer()
            HStack(spacing: 4) {
                Button(action: onEdit) { Image(systemName: "pencil").frame(width: 26, height: 24) }
                Button(action: onDelete) { Image(systemName: "trash").frame(width: 26, height: 24) }
            }
            .buttonStyle(.plain).foregroundStyle(Theme.text2).font(.system(size: 12))
            .opacity(hover ? 1 : 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: onEdit)
    }
}

struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.system(size: 13.5))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.text3).font(.system(size: 12))
            TextField("Search", text: $text).textFieldStyle(.plain).font(.system(size: 13))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardAlt))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
    }
}

struct EmptyState: View {
    let icon: String, title: String, detail: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.text3)
            Text(title).font(.system(size: 13.5, weight: .medium))
            Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}
