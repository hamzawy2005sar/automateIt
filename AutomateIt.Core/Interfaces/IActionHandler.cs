using AutomateIt.Core.Models;

namespace AutomateIt.Core.Interfaces;

public interface IActionHandler
{
    string ActionType { get; }
    Task ExecuteAsync(Automation automation, AutomationAction action, Dictionary<string, string> context);
    // context فيه بيانات الإيميل الواصل + الرد من Gemini
}