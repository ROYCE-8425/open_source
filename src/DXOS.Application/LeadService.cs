using DXOS.Domain;

namespace DXOS.Application;

public sealed class LeadService
{
    private readonly ILeadStore _store;
    private readonly IClock _clock;

    public LeadService(ILeadStore store, IClock clock)
    {
        _store = store;
        _clock = clock;
    }

    public async Task<Lead> IntakeFormAsync(
        string name,
        string? phone,
        string? email,
        Guid? campaignId,
        CancellationToken cancellationToken)
    {
        var now = _clock.UtcNow;
        var salesActors = await _store.ListSalesActorsAsync(cancellationToken);
        var lastAssigned = await _store.GetLastAssignedSalesActorAsync(cancellationToken);
        var assigned = SalesRoundRobin.Next(salesActors, lastAssigned);
        var lead = Lead.Intake(name, phone, email, LeadSource.Form, campaignId, assigned, now);
        await _store.AddAsync(lead, cancellationToken);
        if (!string.IsNullOrWhiteSpace(assigned))
        {
            await _store.SetLastAssignedSalesActorAsync(assigned, cancellationToken);
        }

        return lead;
    }

    public async Task<Lead> RecordMessageOrCallAsync(
        string name,
        string? phone,
        string? email,
        LeadSource source,
        Guid? campaignId,
        CancellationToken cancellationToken)
    {
        if (source is not (LeadSource.Message or LeadSource.Call))
        {
            throw new DomainRuleException("InvalidSource", "Only Message or Call records can be stored without inbox integration.");
        }

        var lead = Lead.Intake(name, phone, email, source, campaignId, assignedToActor: null, _clock.UtcNow);
        await _store.AddAsync(lead, cancellationToken);
        return lead;
    }

    public async Task<IReadOnlyList<Lead>> ListAsync(CancellationToken cancellationToken)
    {
        var leads = await _store.ListAsync(cancellationToken);
        var now = _clock.UtcNow;
        foreach (var lead in leads)
        {
            if (lead.ReleaseIfExpired(now))
            {
                await _store.UpdateAsync(lead, cancellationToken);
            }
        }

        return leads;
    }

    public async Task<Lead> ClaimAsync(ActorContext actor, Guid leadId, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(actor.ActorId))
        {
            throw new DomainRuleException("InvalidActor", "X-DXOS-Actor is required.");
        }

        var lead = await _store.GetAsync(leadId, cancellationToken);
        if (lead is null)
        {
            throw new DomainRuleException("NotFound", $"Lead '{leadId}' was not found.");
        }

        lead.Claim(actor.Role, actor.ActorId, _clock.UtcNow);
        await _store.UpdateAsync(lead, cancellationToken);
        await _store.RememberSalesActorAsync(actor.ActorId, cancellationToken);
        return lead;
    }

    public async Task<CplDashboard> GetCplAsync(decimal spend, CancellationToken cancellationToken)
    {
        var leads = await ListAsync(cancellationToken);
        var leadCount = leads.Count;
        var safeSpend = spend < 0 ? 0 : spend;
        var cpl = leadCount == 0 ? 0 : decimal.Round(safeSpend / leadCount, 2, MidpointRounding.AwayFromZero);
        return new CplDashboard(safeSpend, leadCount, cpl);
    }
}

public sealed record CplDashboard(decimal Spend, int LeadCount, decimal Cpl);
