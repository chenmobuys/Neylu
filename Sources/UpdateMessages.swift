import Foundation

extension UpdateFailure {
    static func describe(_ error: Error, language: AppLanguage) -> String {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return L10n.text("update.status.cancelled", language: language)
        }
        if let failure = error as? UpdateFailure { return failure.message(language: language) }
        if error is DecodingError { return metadata.message(language: language) }
        if (error as NSError).domain == NSURLErrorDomain { return L10n.text("update.error.connection", language: language) }
        return operation.message(language: language)
    }

    var displayMessage: String { message(language: AppLanguage.load()) }
    func message(language: AppLanguage) -> String { L10n.text(rawValue, language: language) }

}

extension AvailableUpdate {
    func releaseNotes(language: AppLanguage) -> String {
        let marker = language.resolved() == .simplifiedChinese ? "<!-- neylu:zh-Hans -->" : "<!-- neylu:en -->"
        guard let start = notes.range(of: marker) else { return notes }
        let remainder = notes[start.upperBound...]
        let end = remainder.range(of: "<!-- neylu:")?.lowerBound ?? remainder.endIndex
        return String(remainder[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
