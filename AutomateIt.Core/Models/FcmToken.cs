namespace AutomateIt.Core.Models;

public class FcmToken
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Token { get; set; } = "";
    public string? DeviceInfo { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;
    public bool IsActive { get; set; } = true;
}
