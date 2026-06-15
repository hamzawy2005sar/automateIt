using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace AutomateIt.Infrastructure.Jobs;

public class AutomationJob
{
    private readonly IServiceScopeFactory _scopeFactory;

    public AutomationJob(IServiceScopeFactory scopeFactory)
    {
        _scopeFactory = scopeFactory;
    }

    public async Task RunAsync()
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Get all active automations
        var automations = await db.Automations
            .Where(a => a.IsActive)
            .Include(a => a.Actions.OrderBy(x => x.Order))
            .ToListAsync();

        // Get available tokens
        var tokens = await db.UserTokens.ToListAsync();
        if (!tokens.Any())
        {
            Console.WriteLine("⚠️ No authenticated users found in UserTokens table. Skipping automation run.");
            return;
        }

        Console.WriteLine($"🔍 Found {tokens.Count} tokens in database: {string.Join(", ", tokens.Select(t => t.Email))}");

        var tasks = automations.Select(async automation =>
        {
            using var localScope = _scopeFactory.CreateScope();
            var localDb = localScope.ServiceProvider.GetRequiredService<AppDbContext>();
            var localTriggers = localScope.ServiceProvider.GetServices<ITriggerHandler>();
            var localActions = localScope.ServiceProvider.GetServices<IActionHandler>();

            Console.WriteLine($"⚙️ Checking automation concurrently: {automation.Name} (Type: {automation.TriggerType})");
            try
            {
                // If UserEmail is missing, try to fix it using the first available VALID token
                if (string.IsNullOrEmpty(automation.UserEmail) || automation.UserEmail == "user")
                {
                    var validToken = tokens.FirstOrDefault(t => t.Email != "user" && t.Email.Contains("@"));
                    if (validToken != null)
                    {
                        var localAutomation = await localDb.Automations.FindAsync(automation.Id);
                        if (localAutomation != null)
                        {
                            localAutomation.UserEmail = validToken.Email;
                            await localDb.SaveChangesAsync();
                            automation.UserEmail = validToken.Email; // Keep local copy updated
                            Console.WriteLine($"   ✅ Auto-assigned valid email {automation.UserEmail} to automation: {automation.Name}");
                        }
                    }
                    else
                    {
                        Console.WriteLine($"   ⚠️ Skipping: No valid UserEmail and no real tokens available.");
                        return;
                    }
                }

                // Find the correct Trigger Handler
                var trigger = localTriggers.FirstOrDefault(t => t.TriggerType == automation.TriggerType);
                if (trigger == null) 
                {
                    Console.WriteLine($"   ⚠️ Skipping: No trigger handler found for type: {automation.TriggerType}");
                    return;
                }

                // Check for new events
                var events = await trigger.CheckAsync(automation);
                if (!events.Any())
                {
                    return;
                }

                Console.WriteLine($"   🔥 Found {events.Count} new events for {automation.Name}! Processing concurrently...");

                // Execute all actions sequentially for this automation
                foreach (var context in events)
                {
                    foreach (var actionConfig in automation.Actions)
                    {
                        var handler = localActions.FirstOrDefault(h => h.ActionType == actionConfig.ActionType);
                        if (handler == null)
                        {
                            Console.WriteLine($"      ⚠️ No action handler for {actionConfig.ActionType}");
                            continue;
                        }

                        await handler.ExecuteAsync(automation, actionConfig, context);
                    }

                    var successMsg = context.TryGetValue("from", out var fromEmail) 
                        ? $"Processed email from: {fromEmail}" 
                        : $"Workflow executed successfully for: {automation.Name}";

                    // Log success
                    localDb.ExecutionLogs.Add(new ExecutionLog
                    {
                        AutomationId = automation.Id,
                        Status       = "SUCCESS",
                        Message      = successMsg,
                        ExecutedAt   = DateTime.UtcNow
                    });
                }
                
                await localDb.SaveChangesAsync();
            }
            catch (Exception ex)
            {
                // Log failure
                Console.WriteLine($"   ❌ Error processing {automation.Name}: {ex.Message}");
                try
                {
                    localDb.ExecutionLogs.Add(new ExecutionLog
                    {
                        AutomationId = automation.Id,
                        Status       = "FAILED",
                        Message      = ex.Message,
                        ExecutedAt   = DateTime.UtcNow
                    });
                    await localDb.SaveChangesAsync();
                }
                catch (Exception logEx)
                {
                    Console.WriteLine($"   ❌ Error logging failure for {automation.Name}: {logEx.Message}");
                }
            }
        });

        await Task.WhenAll(tasks);
    }
}