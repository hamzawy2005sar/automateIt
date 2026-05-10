namespace AutomateIt.Core.Models;

public enum ApprovalStatus { Pending, Approved, Rejected }

public class EmailApproval
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid AutomationId { get; set; }
    public string MessageId { get; set; } = "";
    public string SenderEmail { get; set; } = "";
    public string Subject { get; set; } = "";
    public string ProposedReply { get; set; } = "";
    public ApprovalStatus Status { get; set; } = ApprovalStatus.Pending;
    public string? UserEmail { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
