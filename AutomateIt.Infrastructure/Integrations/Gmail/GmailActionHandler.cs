using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.AI;
using AutomateIt.Infrastructure.Data;
using Google.Apis.Gmail.v1;
using Google.Apis.Gmail.v1.Data;
using Google.Apis.Services;
using System.Text;
using System.Text.Json;
using AutomateIt.Infrastructure.Integrations.Google;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.Infrastructure.Integrations.Gmail;

public class GmailActionHandler : IActionHandler
{
    public string ActionType => "SEND_EMAIL";
    private const string DefaultReply =
        "Hello, I received your email. Thank you for reaching out. I will get back to you as soon as possible.";

    private readonly GroqService _groq;
    private readonly AppDbContext _db;
    private readonly GoogleAuthService _authService;

    public GmailActionHandler(GroqService groq, AppDbContext db, GoogleAuthService authService)
    {
        _groq = groq;
        _db = db;
        _authService = authService;
    }

    public async Task ExecuteAsync(Automation automation, AutomationAction action, Dictionary<string, string> context)
    {
        var config = DeserializeActionConfig(action.ActionConfig);
        var replyBody = await BuildReplyBodyAsync(config, context);

        // ✅ Save as pending approval instead of sending immediately
        var approval = new EmailApproval
        {
            AutomationId  = automation.Id,
            MessageId     = context["messageId"],
            SenderEmail   = context["from"],
            Subject       = context["subject"],
            ProposedReply = replyBody,
            Status        = ApprovalStatus.Pending,
            UserEmail     = automation.UserEmail
        };

        _db.EmailApprovals.Add(approval);
        await _db.SaveChangesAsync();

        // إرسال إشعار للمستخدم بأن هناك رد مقترح ينتظر موافقته
        var activeTokens = await _db.FcmTokens
            .Where(t => t.IsActive)
            .Select(t => t.Token)
            .ToListAsync();

        foreach (var token in activeTokens)
        {
            try
            {
                var firebaseMessage = new FirebaseAdmin.Messaging.Message
                {
                    Token = token,
                    Notification = new FirebaseAdmin.Messaging.Notification
                    {
                        Title = "New Email Draft",
                        Body = $"AI drafted a reply for: {context["subject"]}",
                    },
                    Android = new FirebaseAdmin.Messaging.AndroidConfig
                    {
                        Priority = FirebaseAdmin.Messaging.Priority.High,
                        Notification = new FirebaseAdmin.Messaging.AndroidNotification
                        {
                            Sound = "default",
                            ChannelId = "automations",
                        },
                    },
                };
                await FirebaseAdmin.Messaging.FirebaseMessaging.DefaultInstance.SendAsync(firebaseMessage);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[FCM] Failed to send approval notification: {ex.Message}");
            }
        }

        Console.WriteLine($"✅ Approval saved (Id={approval.Id}) and notification sent.");
    }

    /// <summary>Called from ApprovalsController when user approves the reply.</summary>
    public async Task SendApprovedEmailAsync(EmailApproval approval)
    {
        var email = approval.UserEmail;
        if (string.IsNullOrEmpty(email))
        {
            throw new Exception("Approval has no UserEmail assigned.");
        }

        var service = await GetGmailServiceAsync(email);
        var subject  = $"Re: {approval.Subject}";
        var rawEmail = $"To: {approval.SenderEmail}\r\nSubject: {subject}\r\n\r\n{approval.ProposedReply}";
        var encoded  = Convert.ToBase64String(Encoding.UTF8.GetBytes(rawEmail))
                              .Replace('+', '-').Replace('/', '_');

        await service.Users.Messages.Send(
            new Message { Raw = encoded }, "me"
        ).ExecuteAsync();

        Console.WriteLine($"📧 Email sent to {approval.SenderEmail}");
    }

    private async Task<string> BuildReplyBodyAsync(
        Dictionary<string, string> config,
        Dictionary<string, string> context)
    {
        try
        {
            config.TryGetValue("aiRules", out var aiRules);
            return await _groq.GenerateReplyAsync(
                $"من: {context["from"]}\nالموضوع: {context["subject"]}\n\n{context["body"]}",
                aiRules
            );
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Groq failed, falling back to template reply. {ex.Message}");

            if (config.TryGetValue("replyTemplate", out var replyTemplate) &&
                !string.IsNullOrWhiteSpace(replyTemplate))
                return $"{replyTemplate} (Error: {ex.Message})";

            return $"{DefaultReply} (Error: {ex.Message})";
        }
    }

    private static Dictionary<string, string> DeserializeActionConfig(string actionConfig)
    {
        if (string.IsNullOrWhiteSpace(actionConfig))
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string>>(actionConfig)
                ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }
        catch (JsonException)
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }
    }

    private async Task<GmailService> GetGmailServiceAsync(Automation automation)
    {
        if (string.IsNullOrEmpty(automation.UserEmail))
        {
            throw new Exception("Automation has no UserEmail assigned.");
        }
        return await GetGmailServiceAsync(automation.UserEmail);
    }

    private async Task<GmailService> GetGmailServiceAsync(string email)
    {
        var credential = await _authService.GetCredentialsAsync(email);

        return new GmailService(new BaseClientService.Initializer
        {
            HttpClientInitializer = credential,
            ApplicationName = "automate-it"
        });
    }
}
