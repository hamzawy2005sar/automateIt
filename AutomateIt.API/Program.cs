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

// Dynamic port binding for hosting services (like Railway, Render, Heroku)
var port = Environment.GetEnvironmentVariable("PORT") ?? "5161";
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

// ── Firebase Admin SDK ──────────────────────────────
var firebaseCredPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "firebase_service_account.json");
var firebaseEnvJson = Environment.GetEnvironmentVariable("FIREBASE_SERVICE_ACCOUNT_JSON");

if (!string.IsNullOrEmpty(firebaseEnvJson))
{
    FirebaseApp.Create(new AppOptions
    {
        Credential = GoogleCredential.FromJson(firebaseEnvJson),
    });
    Console.WriteLine("✅ Firebase Admin SDK initialized from environment variable");
}
else if (File.Exists(firebaseCredPath))
{
    FirebaseApp.Create(new AppOptions
    {
        Credential = GoogleCredential.FromFile(firebaseCredPath),
    });
    Console.WriteLine("✅ Firebase Admin SDK initialized from file");
}
else
{
    Console.WriteLine("⚠️ Firebase credentials not found (neither environment variable nor file exist) — FCM notifications will not work");
}

// ── Database & Connection String ─────────────────────
var connectionString = builder.Configuration.GetConnectionString("Default");
var databaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL");

if (!string.IsNullOrEmpty(databaseUrl))
{
    try
    {
        // Convert postgres://username:password@hostname:port/database to Npgsql format
        var uri = new Uri(databaseUrl);
        var userInfo = uri.UserInfo.Split(':');
        var username = userInfo[0];
        var password = userInfo.Length > 1 ? userInfo[1] : "";
        var host = uri.Host;
        var portNum = uri.Port;
        var database = uri.AbsolutePath.TrimStart('/');
        
        connectionString = $"Host={host};Port={portNum};Database={database};Username={username};Password={password};SslMode=Require;TrustServerCertificate=true";
        Console.WriteLine("✅ Database connection string parsed from DATABASE_URL environment variable.");
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ Failed to parse DATABASE_URL: {ex.Message}. Falling back to default connection string.");
    }
}

builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(connectionString));

// ── Hangfire ──────────────────────────────────────
builder.Services.AddHangfire(config =>
    config.UsePostgreSqlStorage(options =>
        options.UseNpgsqlConnection(connectionString)));
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

// Debug middleware
app.Use(async (context, next) => {
    Console.WriteLine($"Incoming Request: {context.Request.Method} {context.Request.Path}");
    await next();
});

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
    "*/1 * * * *" // كل دقيقة (الحد الأدنى لـ Hangfire)
);

// ── تشغيل يدوي إضافي كل 5 ثوانٍ من أجل الديمو ──
Task.Run(async () => {
    var serviceProvider = app.Services;
    var stoppingToken = new CancellationToken();
    while (!stoppingToken.IsCancellationRequested) {
        try {
            using (var scope = serviceProvider.CreateScope()) {
                var job = scope.ServiceProvider.GetRequiredService<AutomationJob>();
                await job.RunAsync();
            }
        }
        catch (Exception ex) {
            Console.WriteLine($"❌ Background Loop Error: {ex.Message}");
        }
        await Task.Delay(5000, stoppingToken);
    }
});

// ── CORS ──────────────────────────────────────────
app.UseCors("AllowAll");

app.MapControllers();
app.Run();
