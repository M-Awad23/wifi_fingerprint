namespace WifiFingerprint.Api.Data.Entities;

public class AccessPointObservation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ScanBatchId { get; set; }
    public string Bssid { get; set; } = string.Empty;
    public string? Ssid { get; set; }
    public int RssiDbm { get; set; }
    public int FrequencyMhz { get; set; }

    public ScanBatch? ScanBatch { get; set; }
}
