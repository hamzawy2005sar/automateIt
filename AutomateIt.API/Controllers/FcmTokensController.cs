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
        Console.WriteLine($"📱 [FCM] RegisterToken called for device: {request.DeviceInfo}");
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

    [HttpGet("test")]
    public async Task<IActionResult> SendTestNotification()
    {
        Console.WriteLine("🚀 [FCM] SendTestNotification called!");
        var tokens = await _context.FcmTokens.Where(t => t.IsActive).ToListAsync();
        if (!tokens.Any()) return BadRequest("No active tokens found");

        int success = 0;
        foreach (var token in tokens)
        {
            try
            {
                var message = new FirebaseAdmin.Messaging.Message
                {
                    Token = token.Token,
                    Notification = new FirebaseAdmin.Messaging.Notification
                    {
                        Title = "Test Notification",
                        Body = "If you see this, notifications are working! 🚀"
                    },
                    Android = new FirebaseAdmin.Messaging.AndroidConfig
                    {
                        Priority = FirebaseAdmin.Messaging.Priority.High,
                        Notification = new FirebaseAdmin.Messaging.AndroidNotification
                        {
                            Sound = "default",
                            ChannelId = "automations"
                        }
                    }
                };
                await FirebaseAdmin.Messaging.FirebaseMessaging.DefaultInstance.SendAsync(message);
                success++;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[TestFCM] Failed for {token.Id}: {ex.Message}");
                return BadRequest(new { message = $"Firebase Error for token {token.Id.ToString().Substring(0,8)}: {ex.Message}" });
            }
        }

        return Ok(new { message = $"Sent {success} test notifications" });
    }

    public class RegisterTokenRequest
    {
        public string Token { get; set; } = "";
        public string? DeviceInfo { get; set; }
    }
}
