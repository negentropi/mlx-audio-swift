import Testing
@testable import MLXAudioSTT

struct QwenTranscriptionTextTests {
    @Test func detectsEnglishAndChineseWithoutChangingDictation() {
        let english = QwenTranscriptionText.parse("language English<asr_text>Hello world.")
        #expect(english.language == "English")
        #expect(english.text == "Hello world.")
        let chinese = QwenTranscriptionText.parse("language Chinese<asr_text>我們用 Swift build 這個 app。")
        #expect(chinese.language == "Chinese")
        #expect(chinese.text == "我們用 Swift build 這個 app。")
    }

    @Test func keepsLiteralLanguageAndMarkerWordsInTheBody() {
        let body = "The language Chinese<asr_text> is an example, not a command."
        #expect(QwenTranscriptionText.parse("language English<asr_text>" + body).text == body)
        #expect(QwenTranscriptionText.parse("language matters").text == "language matters")
        #expect(QwenTranscriptionText.parse("language").text == "language")
        #expect(QwenTranscriptionText.parse("Use <asr_text> literally.").text == "Use <asr_text> literally.")
    }

    @Test func explicitLanguageMeansAllGeneratedTextIsDictation() {
        let body = "language Chinese<asr_text> is a literal example."
        let parsed = QwenTranscriptionText.parse(body, forcedLanguage: "English", isFinal: false)
        #expect(parsed.language == "English")
        #expect(parsed.text == body)
        #expect(QwenTranscriptionText.parse("hello", forcedLanguage: " ").text == "hello")
    }

    @Test func partialHeadersStayHiddenAtEveryCharacterBoundary() {
        for header in ["language English<asr_text>", "language Chinese<asr_text>"] {
            for count in 0...header.count {
                let partial = String(header.prefix(count))
                #expect(QwenTranscriptionText.parse(partial, isFinal: false).text.isEmpty,
                        "Leaked partial header: \(partial)")
                #expect(QwenTranscriptionText.parse(partial, expectsHeader: true).text.isEmpty,
                        "Leaked final header: \(partial)")
            }
        }
        #expect(QwenTranscriptionText.parse("language Chinese<asr_te").text.isEmpty)
    }

    @Test func aConfirmedBoundaryInsideAHeaderCannotLeakOrDuplicateText() {
        let full = "language Chinese<asr_text>我們測試 Swift streaming。"
        let expected = "我們測試 Swift streaming。"
        for count in 0...full.count {
            let display = QwenTranscriptionText.display(
                confirmed: String(full.prefix(count)), fullWindow: full, forcedLanguage: nil)
            #expect(display.confirmed + display.provisional == expected,
                    "Incorrect display split at \(count)")
        }
    }

    @Test func incompleteHeadersAreHiddenAcrossConfirmationBoundaries() {
        let display = QwenTranscriptionText.display(
            confirmed: "language Chi", fullWindow: "language Chinese<asr_", forcedLanguage: nil)
        #expect(display.confirmed.isEmpty)
        #expect(display.provisional.isEmpty)
    }

    @Test func explicitLanguageDisplayKeepsWhitespaceAndOrdinaryLanguageWords() {
        let display = QwenTranscriptionText.display(
            confirmed: "language is ", fullWindow: "language is useful", forcedLanguage: "English")
        #expect(display.confirmed == "language is")
        #expect(display.provisional == " useful")
    }

    @Test func emptyAndWhitespaceResponsesStayEmpty() {
        #expect(QwenTranscriptionText.parse(" \n ").text.isEmpty)
        #expect(QwenTranscriptionText.parse(" language Chinese<asr_text> \n ").text.isEmpty)
    }

    @Test func eachWindowIsParsedBeforeConcatenation() {
        let windows = ["language Chinese<asr_text>我們先測試。", "language English<asr_text>Then ship it."]
        let text = windows.map { QwenTranscriptionText.parse($0).text }.joined(separator: " ")
        #expect(text == "我們先測試。 Then ship it.")
    }

    @Test func completedWindowAndProvisionalWindowUseTheRealJoiner() {
        let display = QwenTranscriptionText.display(completed: "Hello.", confirmed: "language Eng",
            fullWindow: "language English<asr_text>World", forcedLanguage: nil)
        #expect(display.confirmed == "Hello.")
        #expect(display.provisional == " World")
        #expect(display.confirmed + display.provisional == "Hello. World")
    }

    @Test func completedOverlapIsAppliedToTheWholeProvisionalWindow() {
        let full = "language English<asr_text>the world is round"
        for count in 0...full.count {
            let display = QwenTranscriptionText.display(completed: "We see the world", confirmed: String(full.prefix(count)),
                fullWindow: full, forcedLanguage: nil)
            #expect(display.confirmed + display.provisional == "We see the world is round")
        }
    }

    @Test func unicodeTokenBoundaryDisplaysOneCopy() {
        let display = QwenTranscriptionText.display(
            confirmed: "language Chinese<asr_text>�", fullWindow: "language Chinese<asr_text>語言", forcedLanguage: nil)
        #expect(display.confirmed.isEmpty)
        #expect(display.provisional == "語言")
    }
}
