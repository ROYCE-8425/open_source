using DXOS.Domain;
using Xunit;

namespace DXOS.Unit.Tests;

public sealed class LeadScoringTests
{
    [Fact]
    public void Score_PhoneAndEmail_Is80()
    {
        Assert.Equal(80, LeadScoring.Score("+84901234567", "a@example.com"));
    }

    [Theory]
    [InlineData("+84901234567", null)]
    [InlineData("+84901234567", "")]
    [InlineData(null, "a@example.com")]
    [InlineData("  ", "a@example.com")]
    public void Score_OnlyPhoneOrOnlyEmail_Is50(string? phone, string? email)
    {
        Assert.Equal(50, LeadScoring.Score(phone, email));
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData("", "")]
    [InlineData("  ", "  ")]
    public void Score_NeitherPhoneNorEmail_Is20(string? phone, string? email)
    {
        Assert.Equal(20, LeadScoring.Score(phone, email));
    }

    [Fact]
    public void FormIntake_UsesScoringRule()
    {
        var now = new DateTimeOffset(2026, 8, 21, 10, 0, 0, TimeSpan.Zero);
        var both = Lead.Intake("An", "0901", "a@x.vn", LeadSource.Form, null, null, now);
        var phoneOnly = Lead.Intake("An", "0901", null, LeadSource.Message, null, null, now);
        var none = Lead.Intake("An", null, null, LeadSource.Call, null, null, now);

        Assert.Equal(80, both.Score);
        Assert.Equal(50, phoneOnly.Score);
        Assert.Equal(20, none.Score);
        Assert.Equal(LeadSource.Message, phoneOnly.Source);
        Assert.Equal(LeadSource.Call, none.Source);
    }
}
