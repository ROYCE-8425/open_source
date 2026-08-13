# Open Source Components

Status: BOOTSTRAP_INCOMPLETE

DX-OS source is intended to be released under Apache-2.0 as recorded by ADR-0001. Dependencies and reused source retain their own licenses. External services are documented separately in `docs/THIRD_PARTY_SERVICES.md`.

Every direct OSS component must record component, version, source/project, license, purpose, whether modified, and whether redistributed. BR001-R7 must reconcile this document against resolved packages, tools, containers, `THIRD_PARTY_NOTICES.md`, and `artifacts/sbom.cdx.json` before READY.

| Component | Version | Source/project | License | Purpose | Modified | Redistributed |
|---|---|---|---|---|---|---|
| Microsoft.NET.Test.Sdk | 17.13.0 | https://github.com/microsoft/vstest | MIT | .NET test infrastructure | No | As resolved package/build output |
| xunit.v3 | 3.2.2 | https://github.com/xunit/xunit | Apache-2.0 | Unit, integration, and architecture test foundation | No | As resolved package/build output |

This is the verified R2 direct-package baseline, not the final runtime inventory. Entries added by later workstreams must be reviewed in the same change that consumes them.
