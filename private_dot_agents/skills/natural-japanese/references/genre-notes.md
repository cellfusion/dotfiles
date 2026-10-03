# Genre and audience adjustments

Start with the user's purpose and the source's genre. The same phrase, length, or structure can help one audience and impede another. The practical guidance below is editorial heuristic unless explicitly identified as source guidance. [sources.md](sources.md) links the primary sources and explains their scope.

## Technical documents (`tech`)

Prioritize unambiguous actors, conditions, operations, units, limits, and expected results. Keep UI labels, command syntax, API names, error messages, and defined terms exact. Avoid rotating synonyms for the same concept.

Use numbered steps when order matters, lists for independent requirements, and tables for comparable parameters. Put warnings before the action they constrain. A repeated step template may reduce reader effort; do not break it to create artificial variation.

Explain unfamiliar terms for beginners, but do not inflate an expert reference with definitions readers already know. Preserve distinctions such as permitted versus possible, required versus recommended, and tested versus expected behavior. A useful rewrite cannot invent a test result or guarantee.

In debugging records, chronology may be evidence. An executive summary can state the supported result early while retaining the discovery sequence later. Do not insert suspense or remove chronology indiscriminately.

## Business documents (`business`)

Readers often need a decision, status, action, or deadline. Put the supported main answer or request early, then explain reasons and detail. Conclusion-first or PREP-style arrangements are options, not compulsory templates.

Separate decisions, proposals, forecasts, and open issues. A memo requesting discussion need not take a stance the author has not supplied. Minutes must not turn support for an idea into a final agreement. Use the relevant document-type reference rather than assuming that all business prose needs a recommendation at the end.

### Emails and requests

Preserve the sender–recipient relationship, courtesy, urgency, and commitments. Make the request, requested response, and supplied deadline easy to find. Do not invent a deadline, attachment, previous agreement, apology, or promise.

- Before: 「可能であれば、金曜日までにご確認いただけますでしょうか。」
- Possible after: 「可能でしたら、金曜日までにご確認いただけますか。」

Invariant: a conditional courteous request, not a mandatory instruction. 「金曜日までに確認してください」 changes the force and may not be a faithful edit.

Greetings and closing courtesies can serve a relationship. They are not empty merely because they contain no new factual information. Reduce excessive honorific layering only when the intended degree of respect remains.

## Essays, blogs, and personal prose (`essay`)

Narrative order, ambiguity, long sentences, repetition, fragments, colloquial endings, and deferred conclusions can be intentional. Review whether they serve the author's voice and reader experience. Do not impose a business summary, universal lesson, next action, or forced emotional arc.

Retain experiences, feelings, metaphors, and uncertainty actually present in the material. Never add a personal memory, sensory scene, frustration, or first-person conviction to simulate authenticity. If asked to write a fictional piece, follow that explicit fictional framing; do not present it as the user's lived experience.

## Public writing

**Source guidance:** The 2022 Council for Cultural Affairs recommendation distinguishes notices, records, and explanations for the general public, and balances accuracy, clarity, and consideration for readers. It supports early conclusions, helpful headings, explanations of unfamiliar terms, and short enough sentences to keep relations clear. It does not impose a single strictness profile on every document.

Use established forms where they serve legal or administrative function. Explain necessary specialized vocabulary rather than replacing it with a near-synonym that loses legal meaning. The commentary's 50–60-character cue is a prompt to inspect readability, not a bound. Passive voice and omitted subjects can remain when appropriate and unambiguous.

## Accessible Japanese (やさしい日本語)

**Source guidance:** The [2020 ISA/Bunka guideline](https://www.moj.go.jp/isa/content/930006072.pdf), Chapter 2, recommends organizing information, adapting words and notation, then checking comprehension with Japanese-language teachers or intended readers. It explicitly avoids strict criteria because readers' language backgrounds and abilities differ.

For the intended audience, consider:

- Familiar words, clear clause relations, manageable sentences, and explicit necessary actors.
- Explanations of essential terms and abbreviations rather than unexplained jargon.
- Furigana and clear dates/times when useful; account for the delivery medium and multilingual needs.
- Direct instructions that distinguish what is required, optional, and unnecessary.
- Checks with actual readers when possible; do not claim such checks occurred if they did not.

Do not introduce a universal 24-character limit, JLPT-only vocabulary requirement, kanji percentage, or blanket katakana ban. The NINJAL [loanword proposal resource](https://www2.ninjal.ac.jp/gairaigo/) can help find alternatives, but check the intended technical sense and note that the resource is historical rather than continuously updated.

Accessibility does not authorize changing uncertainty into certainty. The guideline itself permits 「～かもしれません」 or 「たぶん～です」 when a categorical assertion would be problematic. It also uses 「することができます」 for ability. Those are important counterexamples to universal word bans.

## Tool profiles

`lint.py --genre essay|tech|business` selects the existing tool's profile. It is not a claim that the genre is objectively classified or that the resulting findings are calibrated probabilities. There are no separate `public` or `easy` profile names in this invocation. For mixed documents, use judgment and review sections for their actual purpose rather than forcing a profile to fit.

Common tool conventions and absolute-path commands are in `revision-guide.md`. Preserve meaning and genre even when a legitimate feature triggers a finding.
