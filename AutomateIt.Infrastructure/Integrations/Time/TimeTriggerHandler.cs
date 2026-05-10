using System.Text.Json;
using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.Infrastructure.Integrations.Time;

public class TimeTriggerHandler : ITriggerHandler
{
    private readonly AppDbContext _db;

    public string TriggerType => "TIME";

    public TimeTriggerHandler(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<Dictionary<string, string>>> CheckAsync(Automation automation)
    {
        var config = DeserializeTriggerConfig(automation.TriggerConfig);
        if (!config.TryGetValue("time", out var targetTimeStr))
        {
            return new List<Dictionary<string, string>>();
        }

        if (!TimeSpan.TryParse(targetTimeStr, out var targetTime))
        {
            return new List<Dictionary<string, string>>();
        }

        // Get current server time
        var now = DateTime.Now;
        var currentTime = now.TimeOfDay;

        // Check if the current time matches the target time (within the current minute)
        if (currentTime.Hours == targetTime.Hours && currentTime.Minutes == targetTime.Minutes)
        {
            // Check if it already ran today
            var startOfDay = now.Date.ToUniversalTime();
            var endOfDay = startOfDay.AddDays(1);

            var alreadyRanToday = await _db.ExecutionLogs
                .AnyAsync(log => log.AutomationId == automation.Id 
                              && log.ExecutedAt >= startOfDay 
                              && log.ExecutedAt < endOfDay);

            if (!alreadyRanToday)
            {
                return new List<Dictionary<string, string>>
                {
                    new Dictionary<string, string>
                    {
                        { "triggerTime", targetTimeStr },
                        { "message", $"Time matched: {targetTimeStr}" }
                    }
                };
            }
        }

        return new List<Dictionary<string, string>>();
    }

    private static Dictionary<string, string> DeserializeTriggerConfig(string configStr)
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
