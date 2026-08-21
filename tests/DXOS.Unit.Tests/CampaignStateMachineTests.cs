using DXOS.Domain;
using Xunit;

namespace DXOS.Unit.Tests;

public sealed class CampaignStateMachineTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 21, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public void HappyPath_MarketerReviewThenOwnerPublish_DoesNotSkipStates()
    {
        var campaign = Campaign.CreateDraft("spring sale", "copy", "mai", Now);
        Assert.Equal(CampaignStatus.Draft, campaign.Status);

        campaign.SubmitReview(ActorRole.Marketer, Now);
        Assert.Equal(CampaignStatus.PendingReview, campaign.Status);

        campaign.SubmitReview(ActorRole.Marketer, Now);
        Assert.Equal(CampaignStatus.PendingApproval, campaign.Status);

        campaign.Approve(ActorRole.Owner, Now);
        Assert.Equal(CampaignStatus.Published, campaign.Status);
    }

    [Fact]
    public void Owner_CannotSkipMarketerReview_FromDraftOrPendingReview()
    {
        var draft = Campaign.CreateDraft("topic", "copy", "owner-1", Now);
        var draftEx = Assert.Throws<DomainRuleException>(() => draft.Approve(ActorRole.Owner, Now));
        Assert.Equal("InvalidTransition", draftEx.Code);

        draft.SubmitReview(ActorRole.Marketer, Now);
        Assert.Equal(CampaignStatus.PendingReview, draft.Status);
        var reviewEx = Assert.Throws<DomainRuleException>(() => draft.Approve(ActorRole.Owner, Now));
        Assert.Equal("InvalidTransition", reviewEx.Code);
        Assert.Contains("skip Marketer review", reviewEx.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void System_CannotApprove()
    {
        var campaign = Campaign.CreateDraft("topic", "copy", "bot", Now);
        campaign.SubmitReview(ActorRole.Marketer, Now);
        campaign.SubmitReview(ActorRole.Marketer, Now);

        var ex = Assert.Throws<DomainRuleException>(() => campaign.Approve(ActorRole.System, Now));
        Assert.Equal("ForbiddenRole", ex.Code);
        Assert.Equal(CampaignStatus.PendingApproval, campaign.Status);
    }

    [Fact]
    public void CannotJump_DraftToPublishedOrPendingApproval()
    {
        Assert.False(Campaign.IsAllowed(CampaignStatus.Draft, CampaignStatus.Published));
        Assert.False(Campaign.IsAllowed(CampaignStatus.Draft, CampaignStatus.PendingApproval));
        Assert.False(Campaign.IsAllowed(CampaignStatus.PendingReview, CampaignStatus.Published));
        Assert.True(Campaign.IsAllowed(CampaignStatus.Draft, CampaignStatus.PendingReview));
        Assert.True(Campaign.IsAllowed(CampaignStatus.PendingReview, CampaignStatus.PendingApproval));
        Assert.True(Campaign.IsAllowed(CampaignStatus.PendingApproval, CampaignStatus.Published));
    }

    [Fact]
    public void Owner_CannotSubmitReview()
    {
        var campaign = Campaign.CreateDraft("topic", "copy", "owner-1", Now);
        var ex = Assert.Throws<DomainRuleException>(() => campaign.SubmitReview(ActorRole.Owner, Now));
        Assert.Equal("ForbiddenRole", ex.Code);
        Assert.Equal(CampaignStatus.Draft, campaign.Status);
    }

    [Fact]
    public void Reject_FromReviewOrApproval_IsTerminal()
    {
        var campaign = Campaign.CreateDraft("topic", "copy", "mai", Now);
        campaign.SubmitReview(ActorRole.Marketer, Now);
        campaign.Reject(ActorRole.Marketer, Now);
        Assert.Equal(CampaignStatus.Rejected, campaign.Status);

        var ex = Assert.Throws<DomainRuleException>(() => campaign.Approve(ActorRole.Owner, Now));
        Assert.Equal("TerminalState", ex.Code);
    }
}
