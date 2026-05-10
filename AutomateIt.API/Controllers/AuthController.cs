using Microsoft.AspNetCore.Mvc;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Auth.OAuth2.Flows;
using Google.Apis.Gmail.v1;
using Google.Apis.Calendar.v3;
using AutomateIt.Infrastructure.Data;
using AutomateIt.Core.Models;
using Microsoft.EntityFrameworkCore;

using Microsoft.Extensions.Configuration;

namespace AutomateIt.API.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly string _clientId;
    private readonly string _clientSecret;
    private readonly string _redirectUri;

    public AuthController(AppDbContext db, IConfiguration config)
    {
        _db = db;
        _clientId = config["Google:ClientId"] ?? "YOUR_CLIENT_ID";
        _clientSecret = config["Google:ClientSecret"] ?? "YOUR_CLIENT_SECRET";
        _redirectUri = config["Google:RedirectUri"] ?? "http://localhost:5161/api/auth/google/callback";
    }

    [HttpGet("google/login")]
    public IActionResult Login()
    {
        var scopes = new[] { GmailService.Scope.GmailModify, CalendarService.Scope.CalendarReadonly };
        var authUrl = $"https://accounts.google.com/o/oauth2/v2/auth?" +
                      $"client_id={_clientId}&" +
                      $"redirect_uri={_redirectUri}&" +
                      $"response_type=code&" +
                      $"scope={string.Join(" ", scopes)}&" +
                      $"access_type=offline&" +
                      $"prompt=consent";
        
        return Ok(new { url = authUrl });
    }

    [HttpGet("google/callback")]
    public async Task<IActionResult> Callback(string code)
    {
        var flow = new GoogleAuthorizationCodeFlow(new GoogleAuthorizationCodeFlow.Initializer
        {
            ClientSecrets = new ClientSecrets { ClientId = _clientId, ClientSecret = _clientSecret }
        });

        var token = await flow.ExchangeCodeForTokenAsync("user", code, _redirectUri, CancellationToken.None);
        
        // We need the email to save the token. Google's token response doesn't have it by default.
        // We'd usually use an IdToken or call the UserInfo API.
        // For now, let's just assume we'll get the email from the UserInfo API.
        var email = await GetUserEmailAsync(token.AccessToken);

        var userToken = await _db.UserTokens.FirstOrDefaultAsync(t => t.Email == email);
        if (userToken == null)
        {
            userToken = new UserToken { Email = email };
            _db.UserTokens.Add(userToken);
        }

        userToken.AccessToken = token.AccessToken;
        userToken.RefreshToken = token.RefreshToken ?? userToken.RefreshToken;
        userToken.ExpiryUtc = DateTime.UtcNow.AddSeconds(token.ExpiresInSeconds ?? 3600);

        await _db.SaveChangesAsync();

        return Content("<html><body><h1>Authenticated Successfully!</h1><p>You can close this window now.</p></body></html>", "text/html");
    }

    [HttpGet("status/{email}")]
    public async Task<IActionResult> GetStatus(string email)
    {
        var token = await _db.UserTokens.FirstOrDefaultAsync(t => t.Email == email);
        return Ok(new { isAuthenticated = token != null });
    }

    private async Task<string> GetUserEmailAsync(string accessToken)
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", accessToken);
        var response = await client.GetAsync("https://www.googleapis.com/oauth2/v2/userinfo");
        var json = await response.Content.ReadAsStringAsync();
        var data = System.Text.Json.JsonDocument.Parse(json);
        return data.RootElement.GetProperty("email").GetString() ?? throw new Exception("Could not get email");
    }
}
