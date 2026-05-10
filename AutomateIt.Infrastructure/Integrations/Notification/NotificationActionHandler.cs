using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using FirebaseAdmin.Messaging;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using FcmNotification = FirebaseAdmin.Messaging.Notification;

namespace AutomateIt.Infrastructure.Integrations.Notification;

public class NotificationActionHandler : IActionHandler
{
    private readonly AppDbContext _db;

    public string ActionType => "SEND_NOTIFICATION";

    public NotificationActionHandler(AppDbContext db)
    {
        _db = db;
    }

    public async Task ExecuteAsync(Automation automation, AutomationAction action, Dictionary<string, string> context)
    {
        var config = DeserializeActionConfig(action.ActionConfig);
        var title = config.TryGetValue("title", out var t) ? t : "AutomateIt";
        var message = config.TryGetValue("message", out var msg) ? msg : "حان وقت تنفيذ الأتمتة الخاصة بك!";

        var activeTokens = await _db.FcmTokens
            .Where(t => t.IsActive)
            .Select(t => t.Token)
            .ToListAsync();

        if (!activeTokens.Any())
        {
            Console.WriteLine("[FCM] No active device tokens registered.");
            return;
        }

        var sentCount = 0;
        var failedCount = 0;

        foreach (var token in activeTokens)
        {
            try
            {
                var firebaseMessage = new Message
                {
                    Token = token,
                    Notification = new FcmNotification
                    {
                        Title = title,
                        Body = message,
                    },
                    Data = new Dictionary<string, string>
                    {
                        { "automationId", automation.Id.ToString() },
                        { "automationName", automation.Name },
                        { "type", "automation_trigger" },
                    },
                    Android = new AndroidConfig
                    {
                        Priority = Priority.High,
                        Notification = new AndroidNotification
                        {
                            Sound = "default",
                            ChannelId = "automations",
                        },
                    },
                };

                await FirebaseMessaging.DefaultInstance.SendAsync(firebaseMessage);
                sentCount++;
            }
            catch (FirebaseMessagingException ex)
            {
                failedCount++;
                Console.WriteLine($"[FCM] Failed to send to token: {ex.Message}");

                if (ex.MessagingErrorCode == MessagingErrorCode.Unregistered ||
                    ex.MessagingErrorCode == MessagingErrorCode.SenderIdMismatch)
                {
                    var badToken = await _db.FcmTokens.FirstOrDefaultAsync(t => t.Token == token);
                    if (badToken != null)
                    {
                        badToken.IsActive = false;
                    }
                }
            }
        }

        Console.WriteLine($"[FCM] Sent: {sentCount}, Failed: {failedCount} for automation: {automation.Name}");
    }

    private static Dictionary<string, string> DeserializeActionConfig(string configStr)
    {
        if (string.IsNullOrWhiteSpace(configStr))
            return new Dictionary<string, string>();

        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string>>(configStr)
                ?? new Dictionary<string, string>();
        }
        catch
        {
            return new Dictionary<string, string>();
        }
    }
}
