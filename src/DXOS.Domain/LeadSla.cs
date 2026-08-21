namespace DXOS.Domain;

public static class LeadSla
{
    public static readonly TimeSpan Duration = TimeSpan.FromMinutes(15);

    public static bool IsExpired(DateTimeOffset startedAtUtc, DateTimeOffset nowUtc)
    {
        return nowUtc - startedAtUtc >= Duration;
    }
}
