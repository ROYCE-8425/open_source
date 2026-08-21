namespace DXOS.Infrastructure.Persistence.Entities;

public sealed class CampaignRecord
{
    public Guid Id { get; set; }
    public string Topic { get; set; } = string.Empty;
    public string Copy { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string CreatedByActor { get; set; } = string.Empty;
    public DateTimeOffset CreatedAtUtc { get; set; }
    public DateTimeOffset UpdatedAtUtc { get; set; }
}
