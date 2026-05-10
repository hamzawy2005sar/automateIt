using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace AutomateIt.Infrastructure.AI;

public class GroqService
{
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private const string FallbackReply = "تعذّر إنشاء الرد.";

    public GroqService(HttpClient http, IConfiguration config)
    {
        _http = http;
        _apiKey = config["Groq:ApiKey"]!;
        
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
    }

    public async Task<string> GenerateReplyAsync(string emailContent)
    {
        var url = "https://api.groq.com/openai/v1/chat/completions";
        
        var body = new
        {
            model = "llama-3.1-8b-instant",
            messages = new[]
            {
                new 
                {
                    role = "system",
                    content = "أنت مساعد ذكي. اقرأ هذا الإيميل واكتب رداً مناسباً ومهنياً باللغة المطلوبة (يفضل العربية إذا كان النص عربياً). اكتب الرد فقط بدون أي شرح إضافي. يجب عليك دائماً أن تنهي رسالتك وتوقع باسم (حمزة)."
                },
                new
                {
                    role = "user",
                    content = emailContent
                }
            }
        };

        var contentString = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

        int maxRetries = 3;
        for (int i = 0; i < maxRetries; i++)
        {
            var response = await _http.PostAsync(url, contentString);
            var json = await response.Content.ReadAsStringAsync();

            Console.WriteLine($"====== GROQ API RESPONSE (Attempt {i + 1}) ======");
            Console.WriteLine(json);
            Console.WriteLine("=================================");

            using var doc = JsonDocument.Parse(json);

            if (response.IsSuccessStatusCode)
            {
                if (TryGetReplyText(doc.RootElement, out var replyText))
                    return replyText;

                var unexpectedError = TryGetApiError(doc.RootElement);
                throw new InvalidOperationException(
                    $"Groq response did not contain a reply candidate. {unexpectedError}");
            }

            if (response.StatusCode == System.Net.HttpStatusCode.TooManyRequests && i < maxRetries - 1)
            {
                int delayMs = (int)Math.Pow(2, i + 1) * 1000;
                Console.WriteLine($"Rate limit hit (429). Retrying in {delayMs}ms...");
                await Task.Delay(delayMs);
                continue;
            }

            var apiError = TryGetApiError(doc.RootElement);
            Console.WriteLine($"!!! GROQ API ERROR: {apiError} (Status: {response.StatusCode})");
            throw new InvalidOperationException(
                $"Groq API error ({(int)response.StatusCode}): {apiError}");
        }

        throw new InvalidOperationException("Failed to generate reply from Groq after multiple attempts.");
    }

    private static bool TryGetReplyText(JsonElement root, out string replyText)
    {
        replyText = FallbackReply;

        if (!root.TryGetProperty("choices", out var choices) ||
            choices.ValueKind != JsonValueKind.Array ||
            choices.GetArrayLength() == 0)
            return false;

        var firstChoice = choices[0];
        if (!firstChoice.TryGetProperty("message", out var message) ||
            !message.TryGetProperty("content", out var contentElement))
            return false;

        var text = contentElement.GetString();
        if (string.IsNullOrWhiteSpace(text))
            return false;

        replyText = text.Trim();
        return true;
    }

    private static string TryGetApiError(JsonElement root)
    {
        if (root.TryGetProperty("error", out var error) &&
            error.TryGetProperty("message", out var message))
            return message.GetString() ?? FallbackReply;

        return "Unknown Groq API error.";
    }
}
