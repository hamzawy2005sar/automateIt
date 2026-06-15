using Google.Apis.Auth.OAuth2;
using Google.Apis.Calendar.v3;
using Google.Apis.Gmail.v1;
using Google.Apis.Util.Store;
using Google.Apis.Auth.OAuth2.Flows;
using Google.Apis.Auth.OAuth2.Responses;

using AutomateIt.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

namespace AutomateIt.Infrastructure.Integrations.Google;

public class GoogleAuthService
{
    private readonly AppDbContext _db;
    private readonly string _clientId;
    private readonly string _clientSecret;

    public GoogleAuthService(AppDbContext db, IConfiguration config)
    {
        _db = db;
        _clientId = config["Google:ClientId"] ?? "YOUR_CLIENT_ID";
        _clientSecret = config["Google:ClientSecret"] ?? "YOUR_CLIENT_SECRET";
    }

    public async Task<UserCredential> GetCredentialsAsync(string email)
    {
        var userToken = await _db.UserTokens.FirstOrDefaultAsync(t => t.Email == email);
        if (userToken == null)
            throw new Exception($"User {email} is not authenticated.");

        var flow = new GoogleAuthorizationCodeFlow(new GoogleAuthorizationCodeFlow.Initializer
        {
            ClientSecrets = new ClientSecrets { ClientId = _clientId, ClientSecret = _clientSecret },
            Scopes = new[] { GmailService.Scope.GmailModify, CalendarService.Scope.CalendarReadonly }
        });

        var tokenResponse = new global::Google.Apis.Auth.OAuth2.Responses.TokenResponse
        {
            AccessToken = userToken.AccessToken,
            RefreshToken = userToken.RefreshToken,
            ExpiresInSeconds = (long)(userToken.ExpiryUtc - DateTime.UtcNow).TotalSeconds,
            IssuedUtc = DateTime.UtcNow.AddSeconds(-(60 * 60)) // Approximation
        };

        var credential = new UserCredential(flow, email, tokenResponse);

        // ✅ Check and Refresh token if expired
        if (credential.Token.IsExpired(global::Google.Apis.Util.SystemClock.Default))
        {
            try
            {
                if (await credential.RefreshTokenAsync(CancellationToken.None))
                {
                    userToken.AccessToken = credential.Token.AccessToken;
                    userToken.ExpiryUtc = DateTime.UtcNow.AddSeconds(credential.Token.ExpiresInSeconds ?? 3600);
                    await _db.SaveChangesAsync();
                    Console.WriteLine($"🔄 Token refreshed and saved for {email}");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ Failed to refresh token for {email}: {ex.Message}");
                // We let it continue, it will fail later with a clear Auth exception if needed
            }
        }

        return credential;
    }
}
