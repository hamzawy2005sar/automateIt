using System.Text.Json.Serialization;

namespace AutomateIt.Core.Models;

public class ExecutionLog
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid AutomationId { get; set; }
    [JsonIgnore]
    public Automation? Automation { get; set; }
    public string Status { get; set; } = ""; // "SUCCESS" | "FAILED"
    public string Message { get; set; } = "";
    public DateTime ExecutedAt { get; set; } = DateTime.UtcNow;
}