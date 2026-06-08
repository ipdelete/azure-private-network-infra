using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Azure;
using Azure.Identity;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace PkiRa;

/// <summary>
/// Blob-triggered RA flow:
///   1. Pick up CSR PEM from csr/&lt;request-id&gt;.csr.
///   2. Validate against the allow-list (see <see cref="CsrValidator"/>).
///   3. Mint a JWK provisioner OTT and POST {csr, ott} to step-ca /1.0/sign.
///   4. Write the resulting cert chain to certs/&lt;sha256(csr-bytes)&gt;.crt
///      with If-None-Match: * so at-least-once retries are idempotent.
///   5. Permanent failures (validation, malformed CSR) → write
///      rejected/&lt;name&gt;.json and return success (do not retry).
///      Transient failures (5xx, network) → throw so BlobTrigger retries.
/// </summary>
public class SignCsrFunction
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly StepCaSigner _signer;
    private readonly CsrValidator _validator;
    private readonly ILogger<SignCsrFunction> _logger;

    public SignCsrFunction(
        IHttpClientFactory httpClientFactory,
        StepCaSigner signer,
        CsrValidator validator,
        ILogger<SignCsrFunction> logger)
    {
        _httpClientFactory = httpClientFactory;
        _signer = signer;
        _validator = validator;
        _logger = logger;
    }

    [Function("SignCsr")]
    public async Task Run(
        [BlobTrigger("csr/{name}", Connection = "PkiStorageConnection")] ReadOnlyMemory<byte> csrBytes,
        string name)
    {
        var csrHash = Convert.ToHexString(SHA256.HashData(csrBytes.Span)).ToLowerInvariant();
        _logger.LogInformation(
            "CSR received: blob={Name} bytes={Size} sha256={Hash}",
            name, csrBytes.Length, csrHash);

        var csrPem = Encoding.UTF8.GetString(csrBytes.Span);

        // ✅ Allow-list validation
        var validation = _validator.Validate(csrPem);
        if (!validation.IsValid)
        {
            _logger.LogWarning(
                "CSR rejected: blob={Name} reason={Reason}", name, validation.Reason);
            await WriteRejectionAsync(name, csrHash, validation.Reason);
            return; // permanent — do not retry
        }

        // 🔐 Mint OTT and call step-ca
        string chainPem;
        try
        {
            var ott = _signer.MintOtt(validation.Subject, validation.DnsSans);
            chainPem = await CallStepCaAsync(csrPem, ott);
        }
        catch (StepCaPermanentException ex)
        {
            _logger.LogWarning(ex, "step-ca permanent failure for blob={Name}", name);
            await WriteRejectionAsync(name, csrHash, $"step-ca rejected: {ex.Message}");
            return;
        }

        // 💾 Idempotent cert write
        var certName = $"{csrHash}.crt";
        var written = await WriteCertIfAbsentAsync(certName, chainPem);
        if (written)
        {
            _logger.LogInformation(
                "Certificate written: blob=certs/{CertName} subject={Subject} sans={Sans}",
                certName, validation.Subject, string.Join(",", validation.DnsSans));
        }
        else
        {
            _logger.LogInformation(
                "Certificate already present (idempotent skip): blob=certs/{CertName}", certName);
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // step-ca call
    // ─────────────────────────────────────────────────────────────────

    private async Task<string> CallStepCaAsync(string csrPem, string ott)
    {
        var client = _httpClientFactory.CreateClient("StepCA");
        var payload = new { csr = csrPem, ott };
        var response = await client.PostAsJsonAsync("/1.0/sign", payload);

        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync();
            // 4xx = permanent (policy/validation rejection on the CA side).
            // 5xx and network errors are surfaced as exceptions for retry.
            if ((int)response.StatusCode is >= 400 and < 500)
            {
                throw new StepCaPermanentException(
                    $"step-ca {(int)response.StatusCode}: {body}");
            }
            throw new HttpRequestException(
                $"step-ca {(int)response.StatusCode}: {body}",
                inner: null,
                statusCode: response.StatusCode);
        }

        var json = await response.Content.ReadAsStringAsync();
        return ExtractChain(json);
    }

    /// <summary>Prefer certChain[] when present; fall back to crt + ca concat.</summary>
    private static string ExtractChain(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;

        if (root.TryGetProperty("certChain", out var chainEl) &&
            chainEl.ValueKind == JsonValueKind.Array && chainEl.GetArrayLength() > 0)
        {
            var sb = new StringBuilder();
            foreach (var p in chainEl.EnumerateArray())
            {
                sb.Append(p.GetString()?.TrimEnd()).Append('\n');
            }
            return sb.ToString();
        }

        var crt = root.TryGetProperty("crt", out var crtEl) ? crtEl.GetString() : null;
        var ca = root.TryGetProperty("ca", out var caEl) ? caEl.GetString() : null;
        if (string.IsNullOrEmpty(crt))
        {
            throw new StepCaPermanentException("step-ca response missing both certChain and crt");
        }
        return string.IsNullOrEmpty(ca) ? crt! : crt!.TrimEnd() + "\n" + ca.TrimEnd() + "\n";
    }

    // ─────────────────────────────────────────────────────────────────
    // Storage helpers
    // ─────────────────────────────────────────────────────────────────

    private static BlobContainerClient GetContainerClient(string containerName)
    {
        var accountName = Environment.GetEnvironmentVariable("PKI_STORAGE_ACCOUNT_NAME")
            ?? throw new InvalidOperationException("PKI_STORAGE_ACCOUNT_NAME not configured");
        var svc = new BlobServiceClient(
            new Uri($"https://{accountName}.blob.core.windows.net"),
            new DefaultAzureCredential());
        return svc.GetBlobContainerClient(containerName);
    }

    private async Task<bool> WriteCertIfAbsentAsync(string blobName, string certPem)
    {
        var blob = GetContainerClient("certs").GetBlobClient(blobName);
        var content = Encoding.UTF8.GetBytes(certPem);
        try
        {
            await blob.UploadAsync(
                new BinaryData(content),
                new BlobUploadOptions
                {
                    Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                    HttpHeaders = new BlobHttpHeaders { ContentType = "application/x-pem-file" }
                });
            return true;
        }
        catch (RequestFailedException ex) when (ex.Status == (int)HttpStatusCode.PreconditionFailed
                                             || ex.Status == (int)HttpStatusCode.Conflict)
        {
            return false; // idempotent skip
        }
    }

    private async Task WriteRejectionAsync(string sourceName, string csrHash, string reason)
    {
        var blob = GetContainerClient("rejected").GetBlobClient($"{sourceName}.json");
        var payload = JsonSerializer.SerializeToUtf8Bytes(new RejectionRecord(
            SourceBlob: sourceName,
            CsrSha256: csrHash,
            Reason: reason,
            RejectedAtUtc: DateTimeOffset.UtcNow));
        try
        {
            await blob.UploadAsync(
                new BinaryData(payload),
                new BlobUploadOptions
                {
                    Conditions = new BlobRequestConditions { IfNoneMatch = ETag.All },
                    HttpHeaders = new BlobHttpHeaders { ContentType = "application/json" }
                });
        }
        catch (RequestFailedException ex) when (ex.Status == (int)HttpStatusCode.PreconditionFailed
                                             || ex.Status == (int)HttpStatusCode.Conflict)
        {
            // Already recorded — fine.
        }
    }

    private sealed record RejectionRecord(
        [property: JsonPropertyName("source_blob")] string SourceBlob,
        [property: JsonPropertyName("csr_sha256")] string CsrSha256,
        [property: JsonPropertyName("reason")] string Reason,
        [property: JsonPropertyName("rejected_at_utc")] DateTimeOffset RejectedAtUtc);
}

public sealed class StepCaPermanentException : Exception
{
    public StepCaPermanentException(string message) : base(message) { }
}
