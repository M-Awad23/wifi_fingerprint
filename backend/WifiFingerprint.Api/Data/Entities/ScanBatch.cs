namespace WifiFingerprint.Api.Data.Entities;

public class ScanBatch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SurveySessionId { get; set; }
    public DateTime ScannedAtUtc { get; set; } = DateTime.UtcNow;

    public SurveySession? SurveySession { get; set; }
    public ICollection<AccessPointObservation> AccessPointObservations { get; set; }
        = new List<AccessPointObservation>();
}
