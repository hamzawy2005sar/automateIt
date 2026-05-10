using AutomateIt.Core.Interfaces;
using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AutomationsController : ControllerBase
{
    private readonly AppDbContext _context;

    private readonly IEnumerable<IActionHandler> _actions;
    public AutomationsController(AppDbContext context, IEnumerable<IActionHandler> actions)
    {
        _context = context;
        _actions = actions;
    }

    // GET: api/automations
    [HttpGet]
    public async Task<ActionResult<IEnumerable<Automation>>> GetAutomations(string? email = null)
    {
        var query = _context.Automations.AsQueryable();
        
        if (!string.IsNullOrEmpty(email))
        {
            query = query.Where(a => a.UserEmail == email);
        }

        return await query
            .Include(a => a.Actions.OrderBy(x => x.Order))
            .Include(a => a.Logs.OrderByDescending(l => l.ExecutedAt).Take(5))
            .ToListAsync();
    }

    // GET: api/automations/{id}
    [HttpGet("{id}")]
    public async Task<ActionResult<Automation>> GetAutomation(Guid id)
    {
        var automation = await _context.Automations
            .Include(a => a.Actions.OrderBy(x => x.Order))
            .Include(a => a.Logs)
            .FirstOrDefaultAsync(a => a.Id == id);

        if (automation == null)
            return NotFound();

        return automation;
    }

    // POST: api/automations
    [HttpPost]
    public async Task<ActionResult<Automation>> CreateAutomation([FromBody] Automation automation)
    {
        Console.WriteLine($"[POST] Received automation: {automation?.Name}");
        if (automation?.Actions != null) {
            Console.WriteLine($"[POST] Actions count: {automation.Actions.Count}");
        }
        automation.CreatedAt = DateTime.UtcNow;
        // إذا لم يكن هناك ID نتركه ليأخذ قيمة افتراضية
        if (automation.Id == Guid.Empty)
            automation.Id = Guid.NewGuid();

        _context.Automations.Add(automation);
        await _context.SaveChangesAsync();

        return CreatedAtAction(nameof(GetAutomation), new { id = automation.Id }, automation);
    }

    // PUT: api/automations/{id}
    [HttpPut("{id}")]
    public async Task<IActionResult> UpdateAutomation(Guid id, Automation automation)
    {
        if (id != automation.Id)
            return BadRequest("ID mismatch");

        _context.Entry(automation).State = EntityState.Modified;

        try
        {
            await _context.SaveChangesAsync();
        }
        catch (DbUpdateConcurrencyException)
        {
            if (!await _context.Automations.AnyAsync(e => e.Id == id))
                return NotFound();
            else
                throw;
        }

        return NoContent();
    }

    // DELETE: api/automations/{id}
    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteAutomation(Guid id)
    {
        var automation = await _context.Automations.FindAsync(id);
        if (automation == null)
            return NotFound();

        _context.Automations.Remove(automation);
        await _context.SaveChangesAsync();

        return NoContent();
    }
    // POST: api/automations/trigger/{triggerType}
    [HttpPost("trigger/{triggerType}")]
    public async Task<IActionResult> TriggerExternal(string triggerType)
    {
        var automations = await _context.Automations
            .Include(a => a.Actions.OrderBy(x => x.Order))
            .Where(a => a.IsActive && a.TriggerType == triggerType)
            .ToListAsync();

        if (!automations.Any())
            return NotFound($"No active automations found for trigger: {triggerType}");

        foreach (var automation in automations)
        {
            foreach (var actionConfig in automation.Actions)
            {
                var handler = _actions.FirstOrDefault(h => h.ActionType == actionConfig.ActionType);
                if (handler != null)
                {
                    await handler.ExecuteAsync(automation, actionConfig, new Dictionary<string, string> { ["source"] = "ExternalTrigger" });
                }
            }
            
            _context.ExecutionLogs.Add(new ExecutionLog
            {
                AutomationId = automation.Id,
                Status = "SUCCESS",
                Message = $"تم تنفيذ Workflow بواسطة محفز خارجي: {triggerType} (عدد الأكشنز: {automation.Actions.Count})"
            });
        }

        await _context.SaveChangesAsync();
        return Ok(new { message = $"Triggered {automations.Count} automation(s)" });
    }
}
