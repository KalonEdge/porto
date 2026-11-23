import Testing
@testable import Porto

struct TerminalTests {
    @Test func parsesKeysMouseAndText() {
        let bytes = Array("\u{1B}[A\u{1B}[B\u{1B}OD\u{1B}[C\r\t\u{1B}[Z\u{1B}[6~\u{1B}[H\u{1B}[<0;7;4M\u{1B}[<0;7;4m\u{1B}[<64;1;1Mjß語\u{7F}\u{0C}".utf8)
        #expect(TerminalScreen.parse(bytes) == [
            .up, .down, .left, .right, .enter, .tab, .backTab, .pageDown, .home, .click(x: 6, y: 3), .scrollUp,
            .character("j"), .character("ß"), .character("語"), .backspace, .control("l"),
        ])
        #expect(TerminalScreen.parse([0x1B]) == [.escape])
        #expect(TerminalScreen.parse([0x03]) == [.control("c")])
        // A colour reply that arrives late is dropped, not read as keys.
        #expect(TerminalScreen.parse(Array("\u{1B}]10;rgb:ffff/ffff/ffff\u{1B}\\q".utf8)) == [.character("q")])
        #expect(TerminalScreen.parse(Array("\u{1B}]11;rgb:1e1e/1e1e/2121\u{07}k".utf8)) == [.character("k")])
    }

    @Test func keepsMultibyteTextWhole() {
        for name in ["Größe", "développement", "中文服务", "שָׁלוֹם", "日本語", "Українська"] {
            #expect(TerminalScreen.parse(Array(name.utf8)) == name.map(InputEvent.character))
            for width in 0...12 {
                #expect([Span(name)].fitted(to: width).width == width)
                #expect(TextWidth.of(TextWidth.middle(name, width: width)) <= width)
            }
        }
    }

    @Test func measuresColumns() {
        #expect(TextWidth.of("porto") == 5)
        #expect(TextWidth.of("端口") == 4)
        #expect(TextWidth.of("é") == 1)
        #expect(TextWidth.of("שָׁלוֹם") == 4)
        #expect(TextWidth.middle("~/code/project/apps/web", width: 11) == "~/cod…s/web")

        let line: Line = [Span("feature"), Span("/porthole")]
        #expect(line.truncated(to: 10).map(\.text).joined() == "feature/p…")
        #expect(line.fitted(to: 24).width == 24)
        let split = Line.split([Span("porthole menu bar icon")], [Span("1.24 GB")], width: 20)
        #expect(split.map(\.text).joined() == "porthole me… 1.24 GB")
        #expect(split.width == 20)
    }

    @Test func mapsColours() {
        #expect(TerminalScreen.ansi256(RGB(0x000000)) == 16)
        #expect(TerminalScreen.ansi256(RGB(0xFFFFFF)) == 231)
        #expect(TerminalScreen.ansi256(RGB(0x808080)) == 244)
        #expect(ColorDepth.detect(environment: ["NO_COLOR": "1", "COLORTERM": "truecolor"]) == .none)
        // An empty NO_COLOR doesn't count (no-color.org).
        #expect(ColorDepth.detect(environment: ["NO_COLOR": "", "COLORTERM": "truecolor"]) == .truecolor)
        #expect(ColorDepth.detect(environment: ["COLORTERM": "24bit"]) == .truecolor)
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-256color"]) == .ansi256)
        #expect(ColorDepth.detect(environment: ["TERM": "dumb"]) == .none)
    }

    @Test func brailleLinesAreContinuous() {
        var canvas = BrailleCanvas(columns: 2, rows: 1)
        canvas.plot([(x: 0, y: 3), (x: 3, y: 0)])
        #expect(canvas.text(row: 0) == "⡠⠊")
        var empty = BrailleCanvas(columns: 3, rows: 2)
        #expect(empty.isEmpty(row: 1, column: 2))
        empty.set(-1, 0)
        empty.set(6, 0)
        #expect(empty.text(row: 0) == "⠀⠀⠀")
    }
}
