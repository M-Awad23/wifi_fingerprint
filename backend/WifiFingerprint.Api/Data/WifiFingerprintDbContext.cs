using Microsoft.EntityFrameworkCore;
using WifiFingerprint.Api.Data.Entities;

namespace WifiFingerprint.Api.Data;

public class WifiFingerprintDbContext : DbContext
{
    public WifiFingerprintDbContext(DbContextOptions<WifiFingerprintDbContext> options)
        : base(options)
    {
    }

    public DbSet<SurveySession> SurveySessions => Set<SurveySession>();
    public DbSet<ScanBatch> ScanBatches => Set<ScanBatch>();
    public DbSet<AccessPointObservation> AccessPointObservations
        => Set<AccessPointObservation>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<SurveySession>(entity =>
        {
            entity.HasKey(x => x.Id);
            entity.Property(x => x.BuildingName).HasMaxLength(200).IsRequired();
            entity.Property(x => x.LocationLabel).HasMaxLength(200).IsRequired();
            entity.HasMany(x => x.ScanBatches)
                .WithOne(x => x.SurveySession)
                .HasForeignKey(x => x.SurveySessionId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ScanBatch>(entity =>
        {
            entity.HasKey(x => x.Id);
            entity.HasIndex(x => new { x.SurveySessionId, x.ScannedAtUtc });
            entity.HasMany(x => x.AccessPointObservations)
                .WithOne(x => x.ScanBatch)
                .HasForeignKey(x => x.ScanBatchId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<AccessPointObservation>(entity =>
        {
            entity.HasKey(x => x.Id);
            entity.Property(x => x.Bssid).HasMaxLength(17).IsRequired();
            entity.Property(x => x.Ssid).HasMaxLength(32);
            entity.HasIndex(x => new { x.ScanBatchId, x.Bssid });
        });
    }
}
