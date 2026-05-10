using System.Text.Json.Serialization;

namespace AutomateIt.Core.Models;

public class Automation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public bool IsActive { get; set; } = true;
    public string? UserEmail { get; set; }

    // Trigger
    public string TriggerType { get; set; } = ""; // "EMAIL_RECEIVED"
    public string TriggerConfig { get; set; } = "{}"; // JSON

    // Actions (Workflow)
    public ICollection<AutomationAction> Actions { get; set; } = new List<AutomationAction>();

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    [JsonIgnore]
    public ICollection<ExecutionLog> Logs { get; set; } = new List<ExecutionLog>();
}