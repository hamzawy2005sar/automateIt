using AutomateIt.Core.Interfaces;
using AutomateIt.Infrastructure.AI;
using AutomateIt.Infrastructure.Data;
using AutomateIt.Infrastructure.Integrations.Gmail;
using AutomateIt.Infrastructure.Integrations.Time;
using AutomateIt.Infrastructure.Integrations.Notification;
using AutomateIt.Infrastructure.Jobs;
using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
using Hangfire;
using Hangfire.PostgreSql;
using AutomateIt.Infrastructure.Integrations.Google;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// ── Firebase Admin SDK ──────────────────────────────
var firebaseCredPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "firebase_service_account.json");
if (File.Exists(firebaseCredPath))
{
    FirebaseApp.Create(new AppOptions
    {
        Credential = GoogleCredential.FromFile(firebaseCredPath),
    });
    Console.WriteLine("✅ Firebase Admin SDK initialized");
}
else
{
    Console.WriteLine("⚠️ firebase_service_account.json not found — FCM notifications will not work");
}

// ── Database ──────────────────────────────────────
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));

// ── Hangfire ──────────────────────────────────────
builder.Services.AddHangfire(config =>
    config.UsePostgreSqlStorage(options =>
        options.UseNpgsqlConnection(builder.Configuration.GetConnectionString("Default"))));
builder.Services.AddHangfireServer();

// ── Groq AI ───────────────────────────────────────
builder.Services.AddHttpClient<GroqService>();
builder.Services.AddScoped<GoogleAuthService>();
builder.Services.AddScoped<GmailActionHandler>();

// ── Plugin System (هون بتضيف أي Handler جديد بسطر واحد) ──
builder.Services.AddScoped<ITriggerHandler, GmailTriggerHandler>();
builder.Services.AddScoped<ITriggerHandler, TimeTriggerHandler>();

builder.Services.AddScoped<IActionHandler, GmailActionHandler>();
builder.Services.AddScoped<IActionHandler, NotificationActionHandler>();
builder.Services.AddScoped<IActionHandler, CalendarActionHandler>();

// ── Jobs ──────────────────────────────────────────
builder.Services.AddScoped<AutomationJob>();

builder.Services.AddControllers().AddJsonOptions(options =>
{
    options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
});
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// ── CORS ──────────────────────────────────────────
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll",
        policy =>
        {
            policy.AllowAnyOrigin()
                  .AllowAnyMethod()
                  .AllowAnyHeader();
        });
});

var app = builder.Build();

// ── Migrations تلقائي عند التشغيل ─────────────────
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

// ── Swagger ───────────────────────────────────────
app.UseSwagger();
app.UseSwaggerUI();

// ── Hangfire Dashboard ────────────────────────────
app.UseHangfireDashboard("/jobs");

// ── جدولة الـ Job كل دقيقة ────────────────────────
RecurringJob.AddOrUpdate<AutomationJob>(
    "check-emails",
    job => job.RunAsync(),
    "* * * * *" // كل دقيقة
);

// ── CORS ──────────────────────────────────────────
app.UseCors("AllowAll");

app.MapControllers();
app.Run();
