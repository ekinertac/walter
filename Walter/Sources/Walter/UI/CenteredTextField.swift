// CenteredTextField.swift — Vertically-centering NSTextField for the launcher input
//
// NSTextField's default cell baselines text to the top of the field, which
// looks fine when the font height roughly matches the field height. The
// launcher's search input enforces a fixed scaled height (~36 × scale)
// but the font auto-shrinks as the user types a long query — so a shrunk
// 14pt font in a 108pt-tall field ends up hugging the top, with a big
// empty band below. This subclass overrides every entry point AppKit uses
// to position the drawn text and the field editor so the cursor, glyphs,
// and selection rectangles all sit centered on the field's vertical axis.
//
// Used by LauncherPanelController as the searchField. The custom cell is
// installed via `NSTextField.cellClass` so a plain `CenteredTextField()`
// already gets the right behavior.

import AppKit

final class CenteredTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { CenteredTextFieldCell.self }
        set {}
    }
}

final class CenteredTextFieldCell: NSTextFieldCell {

    /// Returns a frame whose origin and height have been adjusted so the
    /// text's line box sits on the field's vertical center. Used by every
    /// AppKit hook that draws or edits the text (titleRect, drawingRect,
    /// edit:withFrame:, select:withFrame:) — leaving any of them on the
    /// default leaves the cursor / selection out of sync with the text.
    private func centered(_ frame: NSRect) -> NSRect {
        let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        // ascender + |descender| approximates the visible line height.
        let lineHeight = font.ascender - font.descender
        guard frame.height > lineHeight else { return frame }
        let yInset = (frame.height - lineHeight) / 2.0
        var adjusted = frame
        adjusted.origin.y += yInset
        adjusted.size.height -= yInset * 2
        return adjusted
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: centered(rect))
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: centered(rect))
    }

    override func edit(withFrame rect: NSRect,
                       in controlView: NSView,
                       editor textObj: NSText,
                       delegate: Any?,
                       event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView,
                   editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect,
                         in controlView: NSView,
                         editor textObj: NSText,
                         delegate: Any?,
                         start selStart: Int,
                         length selLength: Int) {
        super.select(withFrame: centered(rect), in: controlView,
                     editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }
}
