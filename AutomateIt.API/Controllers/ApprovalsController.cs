using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using AutomateIt.Infrastructure.Integrations.Gmail;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.API.Controllers;

[ApiController]
[Route("api/approvals")]
public class ApprovalsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly GmailActionHandler _gmailHandler;

    public ApprovalsController(AppDbContext db, GmailActionHandler gmailHandler)
    {
        _db = db;
        _gmailHandler = gmailHandler;
    }

    // GET /api/approvals/pending
    [HttpGet("pending")]
    public async Task<IActionResult> GetPending()
    {
        var pending = await _db.EmailApprovals
            .Where(a => a.Status == ApprovalStatus.Pending)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync();

        return Ok(pending);
    }

    // POST /api/approvals/{id}/approve
    [HttpPost("{id}/approve")]
    public async Task<IActionResult> Approve(Guid id)
    {
        var approval = await _db.EmailApprovals.FindAsync(id);
        if (approval == null) return NotFound();
        if (approval.Status != ApprovalStatus.Pending)
            return BadRequest("Already processed.");

        try
        {
            await _gmailHandler.SendApprovedEmailAsync(approval);
            approval.Status = ApprovalStatus.Approved;
            await _db.SaveChangesAsync();
            return Ok(new { message = "Email sent successfully!" });
        }
        catch (Exception ex)
        {
            Console.WriteLine($"❌ Error sending approved email: {ex}");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    // POST /api/approvals/{id}/reject
    [HttpPost("{id}/reject")]
    public async Task<IActionResult> Reject(Guid id)
    {
        var approval = await _db.EmailApprovals.FindAsync(id);
        if (approval == null) return NotFound();
        if (approval.Status != ApprovalStatus.Pending)
            return BadRequest("Already processed.");

        approval.Status = ApprovalStatus.Rejected;
        await _db.SaveChangesAsync();
        return Ok(new { message = "Reply rejected." });
    }

    // POST /api/approvals/approve-all
    [HttpPost("approve-all")]
    public async Task<IActionResult> ApproveAll()
    {
        var pending = await _db.EmailApprovals
            .Where(a => a.Status == ApprovalStatus.Pending)
            .ToListAsync();

        int sent = 0, failed = 0;
        foreach (var approval in pending)
        {
            try
            {
                await _gmailHandler.SendApprovedEmailAsync(approval);
                approval.Status = ApprovalStatus.Approved;
                sent++;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Error in ApproveAll for item {approval.Id}: {ex.Message}");
                failed++;
            }
        }

        await _db.SaveChangesAsync();
        return Ok(new { sent, failed });
    }

    // POST /api/approvals/reject-all
    [HttpPost("reject-all")]
    public async Task<IActionResult> RejectAll()
    {
        var pending = await _db.EmailApprovals
            .Where(a => a.Status == ApprovalStatus.Pending)
            .ToListAsync();

        foreach (var approval in pending)
            approval.Status = ApprovalStatus.Rejected;

        await _db.SaveChangesAsync();
        return Ok(new { rejected = pending.Count });
    }
}
