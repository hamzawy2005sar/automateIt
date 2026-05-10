using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using Google.Apis.Gmail.v1;
using Google.Apis.Gmail.v1.Data;
using Google.Apis.Services;
using AutomateIt.Infrastructure.Integrations.Google;

namespace AutomateIt.Infrastructure.Integrations.Gmail;

public class GmailTriggerHandler : ITriggerHandler
{
    public string TriggerType => "EMAIL_RECEIVED";

    private readonly GoogleAuthService _authService;

    public GmailTriggerHandler(GoogleAuthService authService)
    {
        _authService = authService;
    }

    private async Task<GmailService> GetGmailServiceAsync(Automation automation)
    {
        var email = automation.UserEmail ?? "user";
        var credential = await _authService.GetCredentialsAsync(email);

        return new GmailService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = "automate-it"
        });
    }

    public async Task<List<Dictionary<string, string>>> CheckAsync(Automation automation)
    {
        var results = new List<Dictionary<string, string>>();
        var service = await GetGmailServiceAsync(automation);

        // نجيب الإيميلات الغير مقروءة، الموجودة في صندوق "الأساسي" (Primary) فقط
        // ونتجاهل الإيميلات من (no-reply) أو الإعلانات ومواقع التواصل مثل لينكد إن
        var request = service.Users.Messages.List("me");
        request.Q = "is:unread category:primary -from:noreply -from:no-reply -from:donotreply";
        request.MaxResults = 5;

        var response = await request.ExecuteAsync();
        if (response.Messages == null) return results;

        foreach (var msg in response.Messages)
        {
            var fullMsg = await service.Users.Messages
                .Get("me", msg.Id).ExecuteAsync();

            var headers = fullMsg.Payload.Headers;
            var subject = headers.FirstOrDefault(h => h.Name == "Subject")?.Value ?? "";
            var from    = headers.FirstOrDefault(h => h.Name == "From")?.Value ?? "";
            var body    = GetBody(fullMsg.Payload);

            results.Add(new Dictionary<string, string>
            {
                ["messageId"] = msg.Id,
                ["from"]      = from,
                ["subject"]   = subject,
                ["body"]      = body
            });

            // Mark as read to avoid processing it again next minute!
            var mods = new ModifyMessageRequest { RemoveLabelIds = new[] { "UNREAD" } };
            await service.Users.Messages.Modify(mods, "me", msg.Id).ExecuteAsync();        }

        return results;
    }

    // دالة مساعدة لاستخراج نص الإيميل
    private string GetBody(MessagePart part)
    {
        if (part.Body?.Data != null)
        {
            var data = part.Body.Data
                .Replace('-', '+').Replace('_', '/');
            return System.Text.Encoding.UTF8.GetString(
                Convert.FromBase64String(data));
        }

        if (part.Parts != null)
            foreach (var p in part.Parts)
            {
                var result = GetBody(p);
                if (!string.IsNullOrEmpty(result)) return result;
            }

        return "";
    }
}