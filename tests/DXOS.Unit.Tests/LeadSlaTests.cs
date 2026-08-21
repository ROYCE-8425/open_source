using DXOS.Application;
using DXOS.Domain;
using Xunit;

namespace DXOS.Unit.Tests;

public sealed class LeadSlaTests
{
    private static readonly DateTimeOffset T0 = new(2026, 8, 21, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Sla_IsFifteenMinutes()
    {
        Assert.Equal(TimeSpan.FromMinutes(15), LeadSla.Duration);
        Assert.False(LeadSla.IsExpired(T0, T0.AddMinutes(14)));
        Assert.True(LeadSla.IsExpired(T0, T0.AddMinutes(15)));
    }

    [Fact]
    public void Claim_Unclaims_WhenSlaExpires()
    {
        var lead = Lead.Intake("An", "0901", "a@x.vn", LeadSource.Form, null, "sales-a", T0);
        lead.Claim(ActorRole.Sales, "sales-a", T0);
        Assert.Equal("sales-a", lead.ClaimedByActor);

        var released = lead.ReleaseIfExpired(T0.AddMinutes(15));
        Assert.True(released);
        Assert.Null(lead.ClaimedByActor);
        Assert.Null(lead.AssignedToActor);
    }

    [Fact]
    public void Claim_StaysActive_BeforeSla()
    {
        var lead = Lead.Intake("An", "0901", null, LeadSource.Form, null, "sales-a", T0);
        lead.Claim(ActorRole.Sales, "sales-a", T0);
        Assert.False(lead.ReleaseIfExpired(T0.AddMinutes(14)));
        Assert.Equal("sales-a", lead.ClaimedByActor);
    }

    [Fact]
    public void RoundRobin_RotatesSalesActors()
    {
        var roster = new[] { "sales-a", "sales-b", "sales-c" };
        Assert.Equal("sales-a", SalesRoundRobin.Next(roster, null));
        Assert.Equal("sales-b", SalesRoundRobin.Next(roster, "sales-a"));
        Assert.Equal("sales-c", SalesRoundRobin.Next(roster, "sales-b"));
        Assert.Equal("sales-a", SalesRoundRobin.Next(roster, "sales-c"));
    }

    [Fact]
    public void NonSales_CannotClaim()
    {
        var lead = Lead.Intake("An", "0901", null, LeadSource.Form, null, null, T0);
        var ex = Assert.Throws<DomainRuleException>(() => lead.Claim(ActorRole.Owner, "owner-1", T0));
        Assert.Equal("ForbiddenRole", ex.Code);
    }

    [Fact]
    public async Task LeadService_RoundRobinAssignsThenUnclaimsAfterSla()
    {
        var clock = new MutableClock(T0);
        var store = new InMemoryLeadStore(["sales-a", "sales-b"]);
        var service = new LeadService(store, clock);

        var first = await service.IntakeFormAsync("An", "0901", "a@x.vn", null, CancellationToken.None);
        var second = await service.IntakeFormAsync("Binh", "0902", null, null, CancellationToken.None);
        Assert.Equal("sales-a", first.AssignedToActor);
        Assert.Equal("sales-b", second.AssignedToActor);
        Assert.Equal(80, first.Score);
        Assert.Equal(50, second.Score);

        var claimed = await service.ClaimAsync(new ActorContext(ActorRole.Sales, "sales-a"), first.Id, CancellationToken.None);
        Assert.Equal("sales-a", claimed.ClaimedByActor);

        clock.UtcNow = T0.AddMinutes(15);
        var listed = await service.ListAsync(CancellationToken.None);
        var expired = listed.Single(l => l.Id == first.Id);
        Assert.Null(expired.ClaimedByActor);
    }

    private sealed class MutableClock : IClock
    {
        public MutableClock(DateTimeOffset utcNow) => UtcNow = utcNow;
        public DateTimeOffset UtcNow { get; set; }
    }

    private sealed class InMemoryLeadStore : ILeadStore
    {
        private readonly Dictionary<Guid, Lead> _leads = [];
        private readonly List<string> _sales;
        private string? _lastAssigned;

        public InMemoryLeadStore(IEnumerable<string> sales) => _sales = sales.ToList();

        public Task AddAsync(Lead lead, CancellationToken cancellationToken)
        {
            _leads[lead.Id] = lead;
            return Task.CompletedTask;
        }

        public Task<Lead?> GetAsync(Guid id, CancellationToken cancellationToken)
        {
            _leads.TryGetValue(id, out var lead);
            return Task.FromResult(lead);
        }

        public Task<IReadOnlyList<Lead>> ListAsync(CancellationToken cancellationToken)
        {
            return Task.FromResult<IReadOnlyList<Lead>>(_leads.Values.ToList());
        }

        public Task UpdateAsync(Lead lead, CancellationToken cancellationToken)
        {
            _leads[lead.Id] = lead;
            return Task.CompletedTask;
        }

        public Task<int> CountAsync(CancellationToken cancellationToken)
        {
            return Task.FromResult(_leads.Count);
        }

        public Task<IReadOnlyList<string>> ListSalesActorsAsync(CancellationToken cancellationToken)
        {
            return Task.FromResult<IReadOnlyList<string>>(_sales);
        }

        public Task RememberSalesActorAsync(string actorId, CancellationToken cancellationToken)
        {
            if (!_sales.Contains(actorId, StringComparer.Ordinal))
            {
                _sales.Add(actorId);
            }

            return Task.CompletedTask;
        }

        public Task<string?> GetLastAssignedSalesActorAsync(CancellationToken cancellationToken)
        {
            return Task.FromResult(_lastAssigned);
        }

        public Task SetLastAssignedSalesActorAsync(string actorId, CancellationToken cancellationToken)
        {
            _lastAssigned = actorId;
            return Task.CompletedTask;
        }
    }
}
