# Third-Party Services

Status: BOOTSTRAP_INCOMPLETE

External services are disclosed separately from open-source dependencies. Use of proprietary development tooling does not change the Apache-2.0 license decision for DX-OS source.

| Service/tool | Category | Purpose | Runtime required | Data boundary | Cost/access assumption | Fallback/replacement |
|---|---|---|---|---|---|---|
| Gemini | Development AI tooling | Bootstrap implementation assistance | No | Repository content supplied during authorized development sessions | Provider account/access may be required for development only | Human implementation or another approved coding assistant |
| OpenAI/Codex | Development AI tooling | Architecture review, verification, and repository assistance | No | Repository content supplied during authorized development sessions | Provider account/access may be required for development only | Human review or another approved coding assistant |

No email/SMS, advertising, cloud, SaaS, proprietary demo API, or paid runtime service is approved at the current bootstrap stage. Any future service must be added here in the same reviewed change that introduces it.

The runtime architecture must not make a proprietary paid service an undocumented mandatory dependency. AI integrations must follow [ADR-0002](adr/0002-third-party-services-and-ai-provider-independence.md).
