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
        
        if (!config.TryGetValue("hour", out var hourStr) || !config.TryGetValue("minute", out var minuteStr))
        {
            Console.WriteLine($"   [TimeTrigger] ⚠️ No 'hour' or 'minute' key found in config. Keys present: {string.Join(", ", config.Keys)}");
            return new List<Dictionary<string, string>>();
        }

        if (!int.TryParse(hourStr?.ToString(), out var targetHour) || !int.TryParse(minuteStr?.ToString(), out var targetMinute))
        {
            Console.WriteLine($"   [TimeTrigger] ❌ Failed to parse target time: {hourStr}:{minuteStr}");
            return new List<Dictionary<string, string>>();
        }

        // Get current server time
        var now = DateTime.Now;
        var currentTime = now.TimeOfDay;
        
        Console.WriteLine($"   [TimeTrigger] Checking... Server Time: {currentTime.Hours}:{currentTime.Minutes:D2} | Target: {targetHour}:{targetMinute:D2}");

        // Check if the current time matches the target time (within the current minute)
        if (currentTime.Hours == targetHour && currentTime.Minutes == targetMinute)
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
                Console.WriteLine($"   [TimeTrigger] ✅ Time matched! Firing action.");
                return new List<Dictionary<string, string>>
                {
                    new Dictionary<string, string>
                    {
                        { "triggerTime", $"{targetHour}:{targetMinute:D2}" },
                        { "message", $"Time matched: {targetHour}:{targetMinute:D2}" }
                    }
                };
            }
            else
            {
                Console.WriteLine($"   [TimeTrigger] ⏳ Time matched, but already ran today for this automation.");
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
            var dict = JsonSerializer.Deserialize<Dictionary<string, object>>(configStr);
            if (dict == null) return new Dictionary<string, string>();

            var result = new Dictionary<string, string>();
            foreach (var kvp in dict)
            {
                result[kvp.Key] = kvp.Value?.ToString() ?? "";
            }
            return result;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"   [TimeTrigger] Error parsing TriggerConfig: {ex.Message}");
            return new Dictionary<string, string>();
        }
    }
}
