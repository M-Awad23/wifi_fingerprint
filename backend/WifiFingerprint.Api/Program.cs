using Microsoft.EntityFrameworkCore;
using WifiFingerprint.Api.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();

var connectionString = builder.Configuration.GetConnectionString("WifiFingerprint")
    ?? throw new InvalidOperationException(
        "Connection string 'WifiFingerprint' was not found.");

builder.Services.AddDbContext<WifiFingerprintDbContext>(options =>
    options.UseSqlServer(connectionString));

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.MapGet("/", () => Results.Ok(new
{
    service = "Wi-Fi Fingerprint API",
    status = "running"
}));

app.Run();
