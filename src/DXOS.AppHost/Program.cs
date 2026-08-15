var builder = DistributedApplication.CreateBuilder(args);

var runId = Environment.GetEnvironmentVariable("DXOS_RUN_ID");
if (!string.IsNullOrWhiteSpace(runId) && !System.Text.RegularExpressions.Regex.IsMatch(runId, "^[a-zA-Z0-9_-]{8,64}$"))
{
    throw new InvalidOperationException($"Invalid DXOS_RUN_ID format: '{runId}'. Expected alphanumeric string of 8-64 characters.");
}

var postgres = builder.AddPostgres("postgres")
    .WithImage("postgres")
    .WithImageTag("18.4-alpine@sha256:9a8afca54e7861fd90fab5fdf4c42477a6b1cb7d293595148e674e0a3181de15");

if (!string.IsNullOrWhiteSpace(runId))
{
    postgres.WithContainerRuntimeArgs("--label", $"dxos.run.id={runId}");
}

var db = postgres.AddDatabase("dxos");

var apiPortStr = Environment.GetEnvironmentVariable("API_PORT");
int? apiPort = int.TryParse(apiPortStr, out var p) && p > 0 ? p : null;

var api = builder.AddProject<Projects.DXOS_Api>("api")
    .WithReference(db)
    .WaitFor(db)
    .WithEnvironment("Database__AutoMigrate", "true")
    .WithEnvironment("EngineeringSmoke__Enabled", "true");

if (!string.IsNullOrWhiteSpace(runId))
{
    api.WithEnvironment("DXOS_RUN_ID", runId);
}

if (apiPort.HasValue)
{
    var portStr = apiPort.Value.ToString();
    api.WithHttpEndpoint(port: apiPort.Value, targetPort: apiPort.Value, name: "http", isProxied: false);
    api.WithEnvironment("ASPNETCORE_URLS", "http://localhost:" + portStr);
}

builder.Build().Run();
