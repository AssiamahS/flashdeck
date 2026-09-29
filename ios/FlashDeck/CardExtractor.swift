import Foundation

/// Runs inside the imported page and pulls term/definition pairs out of the rendered DOM.
/// Quizlet first (two TermText spans per term), then common card layouts, definition
/// lists and two-column tables. Returns JSON: { title, count, cards: [{front, back}], blocked }.
/// Same script the Mac probe was tested with (99/99 on a Quizlet set, 2026-09-28).
enum CardExtractor {
    struct Result: Decodable {
        var title: String
        var count: Int
        var cards: [Card]
        var blocked: Bool
    }

    static let script = #"""
    (() => {
      const clean = s => (s || '').replace(/\s+/g, ' ').trim();
      const pairs = [];
      const push = (f, b) => { f = clean(f); b = clean(b); if (f && b && f !== b) pairs.push({ front: f, back: b }); };
      const tt = Array.from(document.querySelectorAll('.TermText, [class*="TermText"]')).map(e => e.innerText);
      if (tt.length >= 2) for (let i = 0; i + 1 < tt.length; i += 2) push(tt[i], tt[i + 1]);
      if (!pairs.length) document.querySelectorAll('.card, .flashcard, [class*="flashcard"]').forEach(c => {
        const q = c.querySelector('[class*="question"], [class*="front"], [class*="term"]');
        const a = c.querySelector('[class*="answer"], [class*="back"], [class*="definition"]');
        if (q && a) push(q.innerText, a.innerText);
      });
      if (!pairs.length) document.querySelectorAll('dl').forEach(dl => {
        dl.querySelectorAll('dt').forEach(dt => { const dd = dt.nextElementSibling; if (dd && dd.tagName === 'DD') push(dt.innerText, dd.innerText); });
      });
      if (!pairs.length) document.querySelectorAll('table').forEach(t => {
        t.querySelectorAll('tr').forEach(tr => { const c = tr.querySelectorAll('td'); if (c.length === 2) push(c[0].innerText, c[1].innerText); });
      });
      const title = clean(document.title).replace(/\s*(Flashcards\s*\|\s*Quizlet|\|\s*Quizlet|- Brainscape|\|\s*Cram\.com)\s*$/i, '');
      const head = document.title + ' ' + (document.body ? document.body.innerText.slice(0, 400) : '');
      return JSON.stringify({ title, count: pairs.length, cards: pairs, blocked: /captcha|press\s*&\s*hold|access denied/i.test(head) });
    })()
    """#
}

extension Deck {
    /// "Duolingo flash cards" → "duolingo-flash-cards"; matches what the editor has always done.
    static func slug(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }
}
