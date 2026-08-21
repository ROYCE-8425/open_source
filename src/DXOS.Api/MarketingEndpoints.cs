using DXOS.Application;
using DXOS.Domain;

namespace DXOS.Api;

internal static class MarketingEndpoints
{
    public static void MapMarketingSlice(this WebApplication app)
    {
        app.MapPost("/campaigns", async (CreateCampaignRequest request, CampaignService campaigns, HttpContext http, CancellationToken cancellationToken) =>
        {
            return await ExecuteAsync(http, actor => campaigns.CreateDraftAsync(actor, request.Topic ?? string.Empty, cancellationToken));
        });

        app.MapPost("/campaigns/{id:guid}/submit-review", async (Guid id, CampaignService campaigns, HttpContext http, CancellationToken cancellationToken) =>
        {
            return await ExecuteAsync(http, actor => campaigns.SubmitReviewAsync(actor, id, cancellationToken));
        });

        app.MapPost("/campaigns/{id:guid}/approve", async (Guid id, CampaignService campaigns, HttpContext http, CancellationToken cancellationToken) =>
        {
            return await ExecuteAsync(http, actor => campaigns.ApproveAsync(actor, id, cancellationToken));
        });

        app.MapPost("/campaigns/{id:guid}/reject", async (Guid id, CampaignService campaigns, HttpContext http, CancellationToken cancellationToken) =>
        {
            return await ExecuteAsync(http, actor => campaigns.RejectAsync(actor, id, cancellationToken));
        });

        app.MapGet("/campaigns/{id:guid}", async (Guid id, CampaignService campaigns, HttpContext http, CancellationToken cancellationToken) =>
        {
            try
            {
                ReadActor(http);
                var campaign = await campaigns.GetAsync(id, cancellationToken);
                return campaign is null
                    ? Results.NotFound(new { error = $"Campaign '{id}' was not found." })
                    : Results.Ok(ToCampaignResponse(campaign));
            }
            catch (DomainRuleException ex)
            {
                return MapDomainException(ex);
            }
        });

        app.MapPost("/leads/webhook", async (FormLeadRequest request, LeadService leads, HttpContext http, CancellationToken cancellationToken) =>
        {
            try
            {
                ReadActor(http);
                var lead = await leads.IntakeFormAsync(request.Name ?? string.Empty, request.Phone, request.Email, request.CampaignId, cancellationToken);
                return Results.Ok(ToLeadResponse(lead));
            }
            catch (DomainRuleException ex)
            {
                return MapDomainException(ex);
            }
        });

        app.MapGet("/leads", async (LeadService leads, HttpContext http, CancellationToken cancellationToken) =>
        {
            try
            {
                ReadActor(http);
                var items = await leads.ListAsync(cancellationToken);
                return Results.Ok(items.Select(ToLeadResponse).ToList());
            }
            catch (DomainRuleException ex)
            {
                return MapDomainException(ex);
            }
        });

        app.MapPost("/leads/{id:guid}/claim", async (Guid id, LeadService leads, HttpContext http, CancellationToken cancellationToken) =>
        {
            return await ExecuteAsync(http, actor => leads.ClaimAsync(actor, id, cancellationToken), ToLeadResponse);
        });

        app.MapGet("/dashboard/cpl", async (decimal? spend, LeadService leads, HttpContext http, CancellationToken cancellationToken) =>
        {
            try
            {
                ReadActor(http);
                var dashboard = await leads.GetCplAsync(spend ?? 0, cancellationToken);
                return Results.Ok(new
                {
                    spend = dashboard.Spend,
                    leadCount = dashboard.LeadCount,
                    cpl = dashboard.Cpl,
                    adsLive = false,
                    status = "NOT_READY"
                });
            }
            catch (DomainRuleException ex)
            {
                return MapDomainException(ex);
            }
        });
    }

    private static async Task<IResult> ExecuteAsync<T>(
        HttpContext http,
        Func<ActorContext, Task<T>> action,
        Func<T, object>? projector = null)
    {
        try
        {
            var actor = ReadActor(http);
            var result = await action(actor);
            if (result is Campaign campaign)
            {
                return Results.Ok(ToCampaignResponse(campaign));
            }

            if (result is Lead lead)
            {
                return Results.Ok(ToLeadResponse(lead));
            }

            return Results.Ok(projector is null ? result : projector(result));
        }
        catch (DomainRuleException ex)
        {
            return MapDomainException(ex);
        }
    }

    private static ActorContext ReadActor(HttpContext http)
    {
        var roleRaw = http.Request.Headers["X-DXOS-Role"].ToString();
        var actorRaw = http.Request.Headers["X-DXOS-Actor"].ToString();
        if (!Enum.TryParse<ActorRole>(roleRaw, ignoreCase: true, out var role))
        {
            throw new DomainRuleException("InvalidActor", "Header X-DXOS-Role must be Owner, Marketer, Content, Sales, or System.");
        }

        if (string.IsNullOrWhiteSpace(actorRaw))
        {
            throw new DomainRuleException("InvalidActor", "Header X-DXOS-Actor is required.");
        }

        return new ActorContext(role, actorRaw.Trim());
    }

    private static IResult MapDomainException(DomainRuleException ex)
    {
        return ex.Code switch
        {
            "NotFound" => Results.NotFound(new { error = ex.Message, code = ex.Code }),
            "ForbiddenRole" => Results.Json(new { error = ex.Message, code = ex.Code }, statusCode: StatusCodes.Status403Forbidden),
            "AlreadyClaimed" or "InvalidTransition" or "TerminalState" => Results.Conflict(new { error = ex.Message, code = ex.Code }),
            _ => Results.BadRequest(new { error = ex.Message, code = ex.Code })
        };
    }

    private static object ToCampaignResponse(Campaign campaign)
    {
        return new
        {
            id = campaign.Id,
            topic = campaign.Topic,
            copy = campaign.Copy,
            status = campaign.Status.ToString(),
            createdByActor = campaign.CreatedByActor,
            createdAtUtc = campaign.CreatedAtUtc,
            updatedAtUtc = campaign.UpdatedAtUtc,
            adsPushed = false
        };
    }

    private static object ToLeadResponse(Lead lead)
    {
        return new
        {
            id = lead.Id,
            name = lead.Name,
            phone = lead.Phone,
            email = lead.Email,
            source = lead.Source.ToString(),
            score = lead.Score,
            campaignId = lead.CampaignId,
            assignedToActor = lead.AssignedToActor,
            assignedAtUtc = lead.AssignedAtUtc,
            claimedByActor = lead.ClaimedByActor,
            claimedAtUtc = lead.ClaimedAtUtc,
            createdAtUtc = lead.CreatedAtUtc
        };
    }
}

internal sealed record CreateCampaignRequest(string? Topic);

internal sealed record FormLeadRequest(string? Name, string? Phone, string? Email, Guid? CampaignId);
