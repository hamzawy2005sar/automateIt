using AutomateIt.Core.Models;
using Microsoft.EntityFrameworkCore;

namespace AutomateIt.Infrastructure.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Automation> Automations => Set<Automation>();
    public DbSet<AutomationAction> AutomationActions => Set<AutomationAction>();
    public DbSet<UserToken> UserTokens => Set<UserToken>();
    public DbSet<ExecutionLog> ExecutionLogs => Set<ExecutionLog>();
    public DbSet<EmailApproval> EmailApprovals => Set<EmailApproval>();
    public DbSet<FcmToken> FcmTokens => Set<FcmToken>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Automation
        modelBuilder.Entity<Automation>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.TriggerConfig).HasColumnType("jsonb");
            e.HasMany(x => x.Actions)
             .WithOne(x => x.Automation)
             .HasForeignKey(x => x.AutomationId)
             .OnDelete(DeleteBehavior.Cascade);
        });

        // AutomationAction
        modelBuilder.Entity<AutomationAction>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.ActionConfig).HasColumnType("jsonb");
        });

        // EmailApproval
        modelBuilder.Entity<EmailApproval>(e =>
        {
            e.HasKey(x => x.Id);
            e.Property(x => x.Status).HasConversion<string>();
        });

        // ExecutionLog
        modelBuilder.Entity<ExecutionLog>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Automation)
             .WithMany(x => x.Logs)
             .HasForeignKey(x => x.AutomationId)
             .OnDelete(DeleteBehavior.Cascade);
        });

        // FcmToken
        modelBuilder.Entity<FcmToken>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Token).IsUnique();
        });
    }
}