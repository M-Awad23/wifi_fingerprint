namespace WifiFingerprint.Api.Data.Entities;

public class SurveySession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string BuildingName { get; set; } = string.Empty;
    public string LocationLabel { get; set; } = string.Empty;
    public DateTime StartedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? EndedAtUtc { get; set; }

    public ICollection<ScanBatch> ScanBatches { get; set; } = new List<ScanBatch>();
}
