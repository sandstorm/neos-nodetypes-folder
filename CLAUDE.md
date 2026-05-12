- THIS is a NEOS/FLOW Package!!!
- Run all behavioral tests: `mise run test:behavior`
- Run a specific behavioral test file: `mise run test:behavior Features/Smoke/Smoke.feature`
- **Always lint before and after editing PHP files.**
- TRY TO NOT RUN RAW COMMANDS — use mise tasks instead. ASK before changing mise task definitions.

Neos/Flow:
- If you need pointers about current Neos/Flow best practices, ASK. The user is a Neos/Flow expert.
- Prefer Flow annotations (`#[Flow\Scope("singleton")]`, `#[Flow\Inject]`) over Objects.yaml.
- DO NOT use `#[Flow\Proxy(false)]` — classes must work with Flow's proxy mechanism.
- On errors, after changing class annotations, run `flow:cache:flush` in the container to clear stale proxies.

Testing:
- Behavioral tests use the standard `neos/contentrepository-testsuite` traits (`CRTestSuiteTrait`, `CRBehavioralTestsSubjectProvider`, `MigrationsTrait`) — never duplicate production wiring code into test code.
- Assert observable behavior (URI paths, projection state, routing results) — not internal strings.
- Use the real SUT: test through the actual CR + projection stack, not mocks of production internals.

Coding practices:
- Either add a short "why" comment at the doc comment of a class, or add a "@see [classname-with-why-comment] for context" comment accordingly.
- in PHPdocs, if referencing other classes, use {@see [classname]} so that it is auto-clickable in IDEs.
- Mark each class with either @internal [ 1 sentence explanation why] or @api [ 1 sentence explanation why] (ask if unsure).
- Use modern PHP 8.4 syntax.
- Interfaces should end with "Interface".
- SMALL, WELL REVIEWABLE, SELF DESCRIBING COMMITS. You STOP BEFORE CREATING COMMITS (I REVIEW BEFORE).
