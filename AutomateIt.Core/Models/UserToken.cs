using System.ComponentModel.DataAnnotations;

namespace AutomateIt.Core.Models;

public class UserToken
{
    [Key]
    public string Email { get; set; } = null!;
    public string AccessToken { get; set; } = null!;
    public string RefreshToken { get; set; } = null!;
    public DateTime ExpiryUtc { get; set; }
}
