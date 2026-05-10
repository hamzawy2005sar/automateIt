using System.Text.Json.Serialization;

namespace AutomateIt.Core.Models;

public class AutomationAction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid AutomationId { get; set; }
    
    [JsonIgnore]
    public Automation? Automation { get; set; }

    public string ActionType { get; set; } = "";
    public string ActionConfig { get; set; } = "{}"; // JSON
    public int Order { get; set; }
}
