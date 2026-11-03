namespace WifiFingerprint.Api.Data.Entities;

public class ScanBatch
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid SurveySessionId { get; set; }
    public DateTime ScannedAtUtc { get; set; } = DateTime.UtcNow;
    public long? DeviceScanTimestampUs { get; set; }
    public string LocationLabel { get; set; } = string.Empty;
    public string? FloorId { get; set; }
    public string? MapVersion { get; set; }
    public double? X { get; set; }
    public double? Y { get; set; }
    public string? DeviceModel { get; set; }
    public double? HeadingDegrees { get; set; }
    public double? OrientationX { get; set; }
    public double? OrientationY { get; set; }
    public double? OrientationZ { get; set; }

    public SurveySession? SurveySession { get; set; }
    public ICollection<AccessPointObservation> AccessPointObservations { get; set; } = new List<AccessPointObservation>();
}
