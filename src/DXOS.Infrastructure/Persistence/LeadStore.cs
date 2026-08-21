using DXOS.Application;
using DXOS.Domain;
using DXOS.Infrastructure.Persistence.Entities;
using Microsoft.EntityFrameworkCore;

namespace DXOS.Infrastructure.Persistence;

public sealed class LeadStore : ILeadStore
{
    private readonly BootstrapDbContext _db;

    public LeadStore(BootstrapDbContext db)
    {
        _db = db;
    }

    public async Task AddAsync(Lead lead, CancellationToken cancellationToken)
    {
        _db.Leads.Add(ToRecord(lead));
        await _db.SaveChangesAsync(cancellationToken);
    }

    public async Task<Lead?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var record = await _db.Leads.AsNoTracking().FirstOrDefaultAsync(l => l.Id == id, cancellationToken);
        return record is null ? null : ToDomain(record);
    }

    public async Task<IReadOnlyList<Lead>> ListAsync(CancellationToken cancellationToken)
    {
        var records = await _db.Leads.AsNoTracking().OrderBy(l => l.CreatedAtUtc).ToListAsync(cancellationToken);
        return records.Select(ToDomain).ToList();
    }

    public async Task UpdateAsync(Lead lead, CancellationToken cancellationToken)
    {
        var record = await _db.Leads.FirstOrDefaultAsync(l => l.Id == lead.Id, cancellationToken)
            ?? throw new InvalidOperationException($"Lead '{lead.Id}' was not found.");
        record.Name = lead.Name;
        record.Phone = lead.Phone;
        record.Email = lead.Email;
        record.Source = lead.Source.ToString();
        record.Score = lead.Score;
        record.CampaignId = lead.CampaignId;
        record.AssignedToActor = lead.AssignedToActor;
        record.AssignedAtUtc = lead.AssignedAtUtc;
        record.ClaimedByActor = lead.ClaimedByActor;
        record.ClaimedAtUtc = lead.ClaimedAtUtc;
        record.CreatedAtUtc = lead.CreatedAtUtc;
        await _db.SaveChangesAsync(cancellationToken);
    }

    public Task<int> CountAsync(CancellationToken cancellationToken)
    {
        return _db.Leads.CountAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<string>> ListSalesActorsAsync(CancellationToken cancellationToken)
    {
        var state = await GetStateAsync(cancellationToken);
        return SplitActors(state?.SalesActors);
    }

    public async Task RememberSalesActorAsync(string actorId, CancellationToken cancellationToken)
    {
        var state = await GetOrCreateStateAsync(cancellationToken);
        var actors = SplitActors(state.SalesActors).ToList();
        if (!actors.Contains(actorId, StringComparer.Ordinal))
        {
            actors.Add(actorId);
            state.SalesActors = string.Join(',', actors);
            await _db.SaveChangesAsync(cancellationToken);
        }
    }

    public async Task<string?> GetLastAssignedSalesActorAsync(CancellationToken cancellationToken)
    {
        var state = await GetStateAsync(cancellationToken);
        return string.IsNullOrWhiteSpace(state?.LastAssignedActor) ? null : state.LastAssignedActor;
    }

    public async Task SetLastAssignedSalesActorAsync(string actorId, CancellationToken cancellationToken)
    {
        var state = await GetOrCreateStateAsync(cancellationToken);
        state.LastAssignedActor = actorId;
        await _db.SaveChangesAsync(cancellationToken);
    }

    private Task<SalesAssignmentState?> GetStateAsync(CancellationToken cancellationToken)
    {
        return _db.SalesAssignment.FirstOrDefaultAsync(s => s.Id == 1, cancellationToken);
    }

    private async Task<SalesAssignmentState> GetOrCreateStateAsync(CancellationToken cancellationToken)
    {
        var state = await _db.SalesAssignment.FirstOrDefaultAsync(s => s.Id == 1, cancellationToken);
        if (state is not null)
        {
            return state;
        }

        state = new SalesAssignmentState { Id = 1 };
        _db.SalesAssignment.Add(state);
        await _db.SaveChangesAsync(cancellationToken);
        return state;
    }

    private static IReadOnlyList<string> SplitActors(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return [];
        }

        return value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    private static LeadRecord ToRecord(Lead lead)
    {
        return new LeadRecord
        {
            Id = lead.Id,
            Name = lead.Name,
            Phone = lead.Phone,
            Email = lead.Email,
            Source = lead.Source.ToString(),
            Score = lead.Score,
            CampaignId = lead.CampaignId,
            AssignedToActor = lead.AssignedToActor,
            AssignedAtUtc = lead.AssignedAtUtc,
            ClaimedByActor = lead.ClaimedByActor,
            ClaimedAtUtc = lead.ClaimedAtUtc,
            CreatedAtUtc = lead.CreatedAtUtc
        };
    }

    private static Lead ToDomain(LeadRecord record)
    {
        return Lead.Restore(
            record.Id,
            record.Name,
            record.Phone,
            record.Email,
            Enum.Parse<LeadSource>(record.Source),
            record.Score,
            record.CampaignId,
            record.AssignedToActor,
            record.AssignedAtUtc,
            record.ClaimedByActor,
            record.ClaimedAtUtc,
            record.CreatedAtUtc);
    }
}
