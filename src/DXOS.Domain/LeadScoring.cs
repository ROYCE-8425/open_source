namespace DXOS.Domain;

public static class LeadScoring
{
    public const int PhoneAndEmailScore = 80;
    public const int PhoneOrEmailScore = 50;
    public const int FallbackScore = 20;

    public static int Score(string? phone, string? email)
    {
        var hasPhone = !string.IsNullOrWhiteSpace(phone);
        var hasEmail = !string.IsNullOrWhiteSpace(email);
        if (hasPhone && hasEmail)
        {
            return PhoneAndEmailScore;
        }

        if (hasPhone || hasEmail)
        {
            return PhoneOrEmailScore;
        }

        return FallbackScore;
    }
}
