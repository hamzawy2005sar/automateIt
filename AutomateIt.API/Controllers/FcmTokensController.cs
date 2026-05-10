using AutomateIt.Core.Models;
using AutomateIt.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.API.Controllers;

[ApiController]
[Route("api/[controller]")]
public class FcmTokensController : ControllerBase
{
    private readonly AppDbContext _context;

    public FcmTokensController(AppDbContext context)
    {
        _context = context;
    }

    [HttpPost]
    public async Task<IActionResult> RegisterToken([FromBody] RegisterTokenRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Token))
            return BadRequest("Token is required");

        var existing = await _context.FcmTokens
            .FirstOrDefaultAsync(t => t.Token == request.Token);

        if (existing != null)
        {
            existing.IsActive = true;
            existing.LastUsedAt = DateTime.UtcNow;
            existing.DeviceInfo = request.DeviceInfo;
        }
        else
        {
            _context.FcmTokens.Add(new FcmToken
            {
                Token = request.Token,
                DeviceInfo = request.DeviceInfo,
            });
        }

        await _context.SaveChangesAsync();
        return Ok(new { message = "Token registered successfully" });
    }

    [HttpDelete("{token}")]
    public async Task<IActionResult> UnregisterToken(string token)
    {
        var existing = await _context.FcmTokens
            .FirstOrDefaultAsync(t => t.Token == token);

        if (existing == null)
            return NotFound("Token not found");

        existing.IsActive = false;
        await _context.SaveChangesAsync();
        return Ok(new { message = "Token unregistered" });
    }

    [HttpGet]
    public async Task<IActionResult> GetActiveTokens()
    {
        var tokens = await _context.FcmTokens
            .Where(t => t.IsActive)
            .Select(t => new { t.Id, t.Token, t.DeviceInfo, t.CreatedAt, t.LastUsedAt })
            .ToListAsync();

        return Ok(tokens);
    }

    public class RegisterTokenRequest
    {
        public string Token { get; set; } = "";
        public string? DeviceInfo { get; set; }
    }
}
