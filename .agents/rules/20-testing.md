# Testing Rules
- Unit Tests: xUnit
- Integration Tests: Testcontainers.PostgreSql
- External integrations: WireMock.Net
- Browser/E2E: Playwright .NET
- Architecture: ArchUnitNET
- Do not mock PostgreSQL by fake repository if testing persistence. Use Testcontainers.
