namespace DXOS.Domain;

public sealed class Lead
{
    private Lead()
    {
    }

    public Guid Id { get; private set; }
    public string Name { get; private set; } = string.Empty;
    public string? Phone { get; private set; }
    public string? Email { get; private set; }
    public LeadSource Source { get; private set; }
    public int Score { get; private set; }
    public Guid? CampaignId { get; private set; }
    public string? AssignedToActor { get; private set; }
    public DateTimeOffset? AssignedAtUtc { get; private set; }
    public string? ClaimedByActor { get; private set; }
    public DateTimeOffset? ClaimedAtUtc { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; private set; }

    public static Lead Intake(
        string name,
        string? phone,
        string? email,
        LeadSource source,
        Guid? campaignId,
        string? assignedToActor,
        DateTimeOffset nowUtc)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new DomainRuleException("InvalidName", "Lead name is required.");
        }

        var assigned = string.IsNullOrWhiteSpace(assignedToActor) ? null : assignedToActor.Trim();
        return new Lead
        {
            Id = Guid.NewGuid(),
            Name = name.Trim(),
            Phone = string.IsNullOrWhiteSpace(phone) ? null : phone.Trim(),
            Email = string.IsNullOrWhiteSpace(email) ? null : email.Trim(),
            Source = source,
            Score = LeadScoring.Score(phone, email),
            CampaignId = campaignId,
            AssignedToActor = assigned,
            AssignedAtUtc = assigned is null ? null : nowUtc,
            CreatedAtUtc = nowUtc
        };
    }

    public static Lead Restore(
        Guid id,
        string name,
        string? phone,
        string? email,
        LeadSource source,
        int score,
        Guid? campaignId,
        string? assignedToActor,
        DateTimeOffset? assignedAtUtc,
        string? claimedByActor,
        DateTimeOffset? claimedAtUtc,
        DateTimeOffset createdAtUtc)
    {
        return new Lead
        {
            Id = id,
            Name = name,
            Phone = phone,
            Email = email,
            Source = source,
            Score = score,
            CampaignId = campaignId,
            AssignedToActor = assignedToActor,
            AssignedAtUtc = assignedAtUtc,
            ClaimedByActor = claimedByActor,
            ClaimedAtUtc = claimedAtUtc,
            CreatedAtUtc = createdAtUtc
        };
    }

    public void Claim(ActorRole role, string salesActor, DateTimeOffset nowUtc)
    {
        if (role != ActorRole.Sales)
        {
            throw new DomainRuleException("ForbiddenRole", "Only Sales can claim a lead.");
        }

        if (string.IsNullOrWhiteSpace(salesActor))
        {
            throw new DomainRuleException("InvalidActor", "Sales actor is required to claim a lead.");
        }

        ReleaseIfExpired(nowUtc);

        if (!string.IsNullOrWhiteSpace(ClaimedByActor))
        {
            throw new DomainRuleException("AlreadyClaimed", $"Lead is already claimed by {ClaimedByActor}.");
        }

        var actor = salesActor.Trim();
        ClaimedByActor = actor;
        ClaimedAtUtc = nowUtc;
        AssignedToActor = actor;
        AssignedAtUtc = nowUtc;
    }

    public bool ReleaseIfExpired(DateTimeOffset nowUtc)
    {
        var startedAt = ClaimedAtUtc ?? AssignedAtUtc;
        if (startedAt is null)
        {
            return false;
        }

        if (!LeadSla.IsExpired(startedAt.Value, nowUtc))
        {
            return false;
        }

        ClaimedByActor = null;
        ClaimedAtUtc = null;
        AssignedToActor = null;
        AssignedAtUtc = null;
        return true;
    }
}
