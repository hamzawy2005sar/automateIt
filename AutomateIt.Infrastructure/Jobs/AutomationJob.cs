using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.Infrastructure.Jobs;

public class AutomationJob
{
    private readonly AppDbContext _db;
    private readonly IEnumerable<ITriggerHandler> _triggers;
    private readonly IEnumerable<IActionHandler> _actions;

    public AutomationJob(
        AppDbContext db,
        IEnumerable<ITriggerHandler> triggers,
        IEnumerable<IActionHandler> actions)
    {
        _db       = db;
        _triggers = triggers;
        _actions  = actions;
    }

    public async Task RunAsync()
    {
        // جيب كل الأتمتة الفعّالة مع الأكشنز المرتبطة بها مرتبة
        var automations = await _db.Automations
            .Where(a => a.IsActive)
            .Include(a => a.Actions.OrderBy(x => x.Order))
            .ToListAsync();

        foreach (var automation in automations)
        {
            try
            {
                // لاقي الـ Trigger الصح
                var trigger = _triggers
                    .FirstOrDefault(t => t.TriggerType == automation.TriggerType);
                if (trigger == null) continue;

                // شيك إذا في إيميلات جديدة
                var events = await trigger.CheckAsync(automation);
                if (!events.Any()) continue;

                // نفّذ كل الأكشنز بالتسلسل على كل حدث
                foreach (var context in events)
                {
                    foreach (var actionConfig in automation.Actions)
                    {
                        var handler = _actions
                            .FirstOrDefault(h => h.ActionType == actionConfig.ActionType);
                        
                        if (handler == null) continue;

                        await handler.ExecuteAsync(automation, actionConfig, context);
                    }

                    var successMsg = context.TryGetValue("from", out var fromEmail) 
                        ? $"تم الرد على: {fromEmail}" 
                        : $"تم تنفيذ Workflow بنجاح لـ {automation.Name} (عدد الأكشنز: {automation.Actions.Count})";

                    // سجّل النجاح
                    _db.ExecutionLogs.Add(new ExecutionLog
                    {
                        AutomationId = automation.Id,
                        Status       = "SUCCESS",
                        Message      = successMsg
                    });
                }
            }
            catch (Exception ex)
            {
                // سجّل الخطأ
                _db.ExecutionLogs.Add(new ExecutionLog
                {
                    AutomationId = automation.Id,
                    Status       = "FAILED",
                    Message      = ex.Message
                });
            }
        }

        await _db.SaveChangesAsync();
    }
}