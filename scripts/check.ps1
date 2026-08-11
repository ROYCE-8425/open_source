dotnet restore
dotnet format --verify-no-changes
dotnet build --configuration Release -warnaserror
dotnet test tests/DXOS.Architecture.Tests
dotnet test tests/DXOS.Unit.Tests
dotnet test tests/DXOS.Integration.Tests
docker compose build
gitleaks git .
trivy fs .
syft . -o cyclonedx-json=artifacts/sbom.cdx.json
