namespace DXOS.Domain;

public sealed class Campaign
{
    private Campaign()
    {
    }

    public Guid Id { get; private set; }
    public string Topic { get; private set; } = string.Empty;
    public string Copy { get; private set; } = string.Empty;
    public CampaignStatus Status { get; private set; }
    public string CreatedByActor { get; private set; } = string.Empty;
    public DateTimeOffset CreatedAtUtc { get; private set; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }

    public static Campaign CreateDraft(string topic, string copy, string createdByActor, DateTimeOffset nowUtc)
    {
        if (string.IsNullOrWhiteSpace(topic))
        {
            throw new DomainRuleException("InvalidTopic", "Campaign topic is required.");
        }

        if (string.IsNullOrWhiteSpace(createdByActor))
        {
            throw new DomainRuleException("InvalidActor", "Campaign actor is required.");
        }

        return new Campaign
        {
            Id = Guid.NewGuid(),
            Topic = topic.Trim(),
            Copy = copy ?? string.Empty,
            Status = CampaignStatus.Draft,
            CreatedByActor = createdByActor.Trim(),
            CreatedAtUtc = nowUtc,
            UpdatedAtUtc = nowUtc
        };
    }

    public static Campaign Restore(
        Guid id,
        string topic,
        string copy,
        CampaignStatus status,
        string createdByActor,
        DateTimeOffset createdAtUtc,
        DateTimeOffset updatedAtUtc)
    {
        return new Campaign
        {
            Id = id,
            Topic = topic,
            Copy = copy,
            Status = status,
            CreatedByActor = createdByActor,
            CreatedAtUtc = createdAtUtc,
            UpdatedAtUtc = updatedAtUtc
        };
    }

    public void SubmitReview(ActorRole role, DateTimeOffset nowUtc)
    {
        EnsureNotTerminal();
        if (role != ActorRole.Marketer)
        {
            throw new DomainRuleException("ForbiddenRole", "Only Marketer can submit a campaign for review.");
        }

        var next = Status switch
        {
            CampaignStatus.Draft => CampaignStatus.PendingReview,
            CampaignStatus.PendingReview => CampaignStatus.PendingApproval,
            _ => throw new DomainRuleException("InvalidTransition", $"Cannot submit review from {Status}.")
        };

        TransitionTo(next, nowUtc);
    }

    public void Approve(ActorRole role, DateTimeOffset nowUtc)
    {
        EnsureNotTerminal();
        if (role == ActorRole.System)
        {
            throw new DomainRuleException("ForbiddenRole", "System/AI cannot approve a campaign.");
        }

        if (role != ActorRole.Owner)
        {
            throw new DomainRuleException("ForbiddenRole", "Only Owner can approve a campaign.");
        }

        if (Status is CampaignStatus.Draft or CampaignStatus.PendingReview)
        {
            throw new DomainRuleException("InvalidTransition", "Owner cannot skip Marketer review.");
        }

        if (Status != CampaignStatus.PendingApproval)
        {
            throw new DomainRuleException("InvalidTransition", $"Cannot approve from {Status}.");
        }

        TransitionTo(CampaignStatus.Published, nowUtc);
    }

    public void Reject(ActorRole role, DateTimeOffset nowUtc)
    {
        EnsureNotTerminal();
        if (role is not (ActorRole.Owner or ActorRole.Marketer))
        {
            throw new DomainRuleException("ForbiddenRole", "Only Owner or Marketer can reject a campaign.");
        }

        if (Status is not (CampaignStatus.PendingReview or CampaignStatus.PendingApproval))
        {
            throw new DomainRuleException("InvalidTransition", $"Cannot reject from {Status}.");
        }

        TransitionTo(CampaignStatus.Rejected, nowUtc);
    }

    private void EnsureNotTerminal()
    {
        if (Status is CampaignStatus.Published or CampaignStatus.Rejected)
        {
            throw new DomainRuleException("TerminalState", $"Campaign is already {Status}.");
        }
    }

    private void TransitionTo(CampaignStatus next, DateTimeOffset nowUtc)
    {
        if (!IsAllowed(Status, next))
        {
            throw new DomainRuleException("InvalidTransition", $"Cannot transition from {Status} to {next}.");
        }

        Status = next;
        UpdatedAtUtc = nowUtc;
    }

    public static bool IsAllowed(CampaignStatus from, CampaignStatus to)
    {
        return (from, to) switch
        {
            (CampaignStatus.Draft, CampaignStatus.PendingReview) => true,
            (CampaignStatus.PendingReview, CampaignStatus.PendingApproval) => true,
            (CampaignStatus.PendingReview, CampaignStatus.Rejected) => true,
            (CampaignStatus.PendingApproval, CampaignStatus.Published) => true,
            (CampaignStatus.PendingApproval, CampaignStatus.Rejected) => true,
            _ => false
        };
    }
}
