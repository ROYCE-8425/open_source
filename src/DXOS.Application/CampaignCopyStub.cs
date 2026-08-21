namespace DXOS.Application;

public sealed class CampaignCopyStub
{
    public string DraftFromTopic(string topic)
    {
        var normalized = string.IsNullOrWhiteSpace(topic) ? "untitled" : topic.Trim();
        return $"DX-OS draft copy for '{normalized}'. Form-lead CTA only. NOT_READY: no live ads, no LLM.";
    }
}
