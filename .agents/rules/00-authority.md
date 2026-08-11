# SOURCE OF TRUTH ORDER

1. Accepted OpenSpec specification
2. Architecture Decision Records
3. Business Rules
4. Beads task acceptance criteria
5. Workspace Rules
6. Project Skills
7. Existing code patterns
8. Model assumptions

If two sources conflict:
STOP and report the conflict.
Do not silently choose.

## Roles
**Codex OWNS:**
- OpenSpec
- Architecture
- ADR
- Beads decomposition
- Acceptance Criteria
- Security design
- Review
- Final verdict

**Gemini OWNS:**
- Implementation
- Tests
- Migration
- Local verification
- Bug fixes
- Implementation evidence

**Gemini KHÔNG du?c (MUST NOT):**
- approve own implementation
- silently change spec
- silently install NuGet/npm package
- remove failing test
- weaken architecture rule
- disable security scanner
- merge main

**Codex KHÔNG review l?i k? c?a Gemini:**
Codex review:
- git diff
- test result
- build result
- security output
- runtime traces
Không review: 'Gemini nói là dã hoàn thành.'
