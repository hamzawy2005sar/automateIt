using AutomateIt.Core.Models;

namespace AutomateIt.Core.Interfaces;

public interface ITriggerHandler
{
    string TriggerType { get; }
    Task<List<Dictionary<string, string>>> CheckAsync(Automation automation);
    // يرجع list من الإيميلات الجديدة — كل إيميل = Dictionary فيه بياناته
}