using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using AutomateIt.Infrastructure.Integrations.Google;
using FirebaseAdmin.Messaging;
using Google.Apis.Calendar.v3;
using Google.Apis.Services;
using Microsoft.EntityFrameworkCore;
using System.Text;
using System.Text.Json;
using FcmNotification = FirebaseAdmin.Messaging.Notification;

namespace AutomateIt.Infrastructure.Integrations.Notification;

public class CalendarActionHandler : IActionHandler
{
    private readonly AppDbContext _db;
    private readonly GoogleAuthService _authService;

    public string ActionType => "CALENDAR_REMINDER";

    public CalendarActionHandler(AppDbContext db, GoogleAuthService authService)
    {
        _db = db;
        _authService = authService;
    }

    public async Task ExecuteAsync(Automation automation, AutomationAction action, Dictionary<string, string> context)
    {
        var eventsMessage = await GetTodayEventsAsync(automation);
        
        var activeTokens = await _db.FcmTokens
            .Where(t => t.IsActive)
            .Select(t => t.Token)
            .ToListAsync();

        if (!activeTokens.Any()) return;

        foreach (var token in activeTokens)
        {
            try
            {
                var firebaseMessage = new Message
                {
                    Token = token,
                    Notification = new FcmNotification
                    {
                        Title = "📅 مواعيدك اليوم",
                        Body = eventsMessage,
                    },
                    Data = new Dictionary<string, string>
                    {
                        { "type", "calendar_reminder" },
                        { "message", eventsMessage },
                        { "automationId", automation.Id.ToString() }
                    },
                    Android = new AndroidConfig { 
                        Priority = Priority.High,
                        Notification = new AndroidNotification
                        {
                            Sound = "default",
                            ChannelId = "automations",
                        }
                    }
                };

                await FirebaseMessaging.DefaultInstance.SendAsync(firebaseMessage);
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[Calendar] Failed to send to token: {ex.Message}");
            }
        }
    }

    private async Task<string> GetTodayEventsAsync(Automation automation)
    {
        try
        {
            var email = automation.UserEmail;
            if (string.IsNullOrEmpty(email))
            {
                throw new Exception("Automation has no UserEmail assigned.");
            }
            var credential = await _authService.GetCredentialsAsync(email);
            var service = new CalendarService(new BaseClientService.Initializer
            {
                HttpClientInitializer = credential,
                ApplicationName = "automate-it"
            });

            var request = service.Events.List("primary");
            request.TimeMin = DateTime.Today.ToUniversalTime();
            request.TimeMax = DateTime.Today.AddDays(1).ToUniversalTime();
            request.SingleEvents = true;
            request.OrderBy = EventsResource.ListRequest.OrderByEnum.StartTime;

            var events = await request.ExecuteAsync();
            if (events.Items == null || events.Items.Count == 0)
            {
                return "لا توجد مواعيد مجدولة لليوم. استمتع بيوم هادئ!";
            }

            var sb = new StringBuilder();
            sb.AppendLine("إليك مواعيدك لليوم:");
            foreach (var item in events.Items)
            {
                var start = item.Start.DateTimeDateTimeOffset?.ToString("HH:mm") ?? item.Start.Date;
                sb.AppendLine($"- {start}: {item.Summary}");
            }

            return sb.ToString();
        }
        catch (Exception ex)
        {
            return $"حدث خطأ أثناء جلب المواعيد: {ex.Message}";
        }
    }

    private static Dictionary<string, string> DeserializeActionConfig(string configStr)
    {
        if (string.IsNullOrWhiteSpace(configStr)) return new Dictionary<string, string>();
        try { return JsonSerializer.Deserialize<Dictionary<string, string>>(configStr) ?? new Dictionary<string, string>(); }
        catch { return new Dictionary<string, string>(); }
    }
}
