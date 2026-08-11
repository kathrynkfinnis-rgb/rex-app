import SwiftUI

/// Recipe text parsing, mirroring src/lib/recipe.ts so a recipe written on
/// the phone and one written on the web round-trip identically.
enum RexRecipe {
    private static let stepVerbs: Set<String> = [
        "preheat", "heat", "mix", "add", "combine", "stir", "whisk", "pour",
        "bake", "cook", "simmer", "boil", "fry", "roast", "chop", "slice",
        "dice", "mince", "season", "serve", "let", "cover", "remove", "place",
        "transfer", "reduce", "drain", "rest", "cool", "garnish", "repeat",
        "set", "line", "grease", "sprinkle", "spread", "layer", "roll",
        "knead", "whip", "beat", "melt", "toss", "fold", "arrange", "top",
        "drizzle", "spoon", "divide", "return", "bring", "turn", "flip", "rub",
        "marinate", "chill", "freeze", "warm", "blend", "process", "strain",
        "peel", "trim", "crush", "squeeze", "zest", "coat", "dust", "brush",
        "put", "leave", "meanwhile",
    ]

    static func isIngredientsHeading(_ line: String) -> Bool {
        let l = line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " #:*-"))
        return l == "ingredient" || l == "ingredients"
    }

    static func isMethodHeading(_ line: String) -> Bool {
        let l = line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " #:*-"))
        return ["method", "instruction", "instructions", "step", "steps",
                "direction", "directions", "preparation", "how to make",
                "how to cook", "what to do"].contains(l)
    }

    /// Reads like an instruction: numbered, long, or opening with a cooking verb.
    static func looksLikeStep(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.range(of: "^\\d+[.)]\\s+", options: .regularExpression) != nil { return true }
        if t.count > 80 { return true }
        let first = t.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? ""
        return stepVerbs.contains(first)
    }

    static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(
            of: "^\\s*(?:[-*•·]|\\d+[.)])\\s+", with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Splits free text into ingredients and method, coping with documents
    /// that have no headings at all.
    static func parse(_ text: String) -> (ingredients: [String], method: [String]) {
        let src = text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty else { return ([], []) }

        var section: String? = nil
        var ingredients: [String] = []
        var method: [String] = []

        for raw in src.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isIngredientsHeading(line) { section = "ing"; continue }
            if isMethodHeading(line) { section = "method"; continue }

            if section != "method" && looksLikeStep(line) { section = "method" }
            if section == nil { section = "ing" }

            let clean = stripBullet(line)
            if clean.isEmpty { continue }
            if section == "ing" { ingredients.append(clean) } else { method.append(clean) }
        }
        return (ingredients, method)
    }

    static func serialize(ingredients: [String], method: [String]) -> String {
        let ing = ingredients.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let met = method.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var parts: [String] = []
        if !ing.isEmpty {
            parts.append("## Ingredients")
            parts.append(contentsOf: ing.map { "- \($0)" })
        }
        if !met.isEmpty {
            if !parts.isEmpty { parts.append("") }
            parts.append("## Method")
            parts.append(contentsOf: met.enumerated().map { "\($0.offset + 1). \($0.element)" })
        }
        return parts.joined(separator: "\n")
    }
}

/// Paste a whole recipe and have it split into ingredients and method, or
/// build it line by line. Restores the web behaviour testers missed.
struct RecipeEditorView: View {
    @Binding var recipeText: String

    @State private var ingredients: [String] = [""]
    @State private var method: [String] = [""]
    @State private var showPaste = false
    @State private var pasteBuffer = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: RexSpacing.lg) {
            HStack {
                Text("Recipe")
                    .font(RexFont.text(14, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Spacer()
                Button {
                    showPaste.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 11))
                        Text("Paste whole recipe").font(RexFont.text(12, weight: .medium))
                    }
                    .foregroundStyle(RexColor.primary)
                    .padding(.horizontal, RexSpacing.md)
                    .padding(.vertical, 6)
                    .background(RexColor.badgeBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if showPaste {
                VStack(alignment: .leading, spacing: RexSpacing.sm) {
                    Text("Paste from anywhere — we'll split the ingredients and steps.")
                        .font(RexFont.text(12))
                        .foregroundStyle(RexColor.mutedForeground)
                    TextEditor(text: $pasteBuffer)
                        .font(RexFont.text(13))
                        .frame(height: 150)
                        .padding(RexSpacing.sm)
                        .background(RexColor.card)
                        .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                                .stroke(RexColor.border, lineWidth: 1)
                        )
                    HStack {
                        Button("Cancel") { showPaste = false; pasteBuffer = "" }
                            .font(RexFont.text(13))
                            .foregroundStyle(RexColor.mutedForeground)
                        Spacer()
                        Button("Split it up") { applyPaste() }
                            .font(RexFont.text(13, weight: .semibold))
                            .foregroundStyle(RexColor.primary)
                    }
                }
                .padding(RexSpacing.md)
                .background(RexColor.muted)
                .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
            }

            section(title: "Ingredients", items: $ingredients, placeholder: "e.g. 200g plain flour")
            section(title: "Method", items: $method, placeholder: "Describe the step…")
        }
        .onAppear {
            guard !loaded else { return }
            let parsed = RexRecipe.parse(recipeText)
            if !parsed.ingredients.isEmpty { ingredients = parsed.ingredients }
            if !parsed.method.isEmpty { method = parsed.method }
            loaded = true
        }
        .onChange(of: ingredients) { _, _ in push() }
        .onChange(of: method) { _, _ in push() }
    }

    private func section(title: String, items: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: RexSpacing.sm) {
            HStack {
                Text(title)
                    .font(RexFont.display(18, weight: .semibold))
                    .foregroundStyle(RexColor.foreground)
                Spacer()
                Text("\(items.wrappedValue.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)")
                    .font(RexFont.text(12))
                    .foregroundStyle(RexColor.mutedForeground)
            }

            ForEach(items.wrappedValue.indices, id: \.self) { i in
                HStack(spacing: RexSpacing.sm) {
                    TextField(placeholder, text: Binding(
                        get: { i < items.wrappedValue.count ? items.wrappedValue[i] : "" },
                        set: { if i < items.wrappedValue.count { items.wrappedValue[i] = $0 } }
                    ))
                    .font(RexFont.text(15))
                    .padding(RexSpacing.md)
                    .background(RexColor.card)
                    .clipShape(RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: RexRadius.input, style: .continuous)
                            .stroke(RexColor.border, lineWidth: 1)
                    )

                    if items.wrappedValue.count > 1 {
                        Button {
                            items.wrappedValue.remove(at: i)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                                .foregroundStyle(RexColor.mutedForeground)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                items.wrappedValue.append("")
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11))
                    Text("Add").font(RexFont.text(13))
                }
                .foregroundStyle(RexColor.mutedForeground)
            }
            .buttonStyle(.plain)
        }
    }

    private func applyPaste() {
        guard !pasteBuffer.trimmingCharacters(in: .whitespaces).isEmpty else {
            showPaste = false
            return
        }
        let parsed = RexRecipe.parse(pasteBuffer)
        if parsed.ingredients.isEmpty && parsed.method.isEmpty {
            // Nothing recognisable — keep it as a single step rather than lose it.
            method = [pasteBuffer.trimmingCharacters(in: .whitespaces)]
        } else {
            if !parsed.ingredients.isEmpty { ingredients = parsed.ingredients }
            if !parsed.method.isEmpty { method = parsed.method }
        }
        pasteBuffer = ""
        showPaste = false
        push()
    }

    private func push() {
        recipeText = RexRecipe.serialize(ingredients: ingredients, method: method)
    }
}
