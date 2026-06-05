using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace PkiRa;

public class SignCsrFunction
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<SignCsrFunction> _logger;

    public SignCsrFunction(IHttpClientFactory httpClientFactory, ILogger<SignCsrFunction> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    [Function("SignCsr")]
    public async Task Run(
        [BlobTrigger("csr/{name}", Connection = "PkiStorageConnection")] ReadOnlyMemory<byte> csrBytes,
        string name)
    {
        _logger.LogInformation("CSR received: {Name} ({Size} bytes)", name, csrBytes.Length);

        var csrPem = Encoding.UTF8.GetString(csrBytes.Span);

        // Request a signed certificate from step-ca
        var certPem = await SignCsr(csrPem);

        // Write the signed cert to the certs container
        var certBlobName = Path.ChangeExtension(name, ".crt");
        await WriteCert(certBlobName, certPem);

        _logger.LogInformation("Certificate written: certs/{CertName}", certBlobName);
    }

    private async Task<string> SignCsr(string csrPem)
    {
        var provisioner = Environment.GetEnvironmentVariable("STEP_CA_PROVISIONER")
            ?? throw new InvalidOperationException("STEP_CA_PROVISIONER not configured");
        var password = Environment.GetEnvironmentVariable("STEP_CA_PASSWORD")
            ?? throw new InvalidOperationException("STEP_CA_PASSWORD not configured");

        // Generate a one-time token from step-ca for signing
        var client = _httpClientFactory.CreateClient("StepCA");

        // Step 1: Get a signing token using the provisioner password
        var tokenRequest = new
        {
            ott = await GetProvisionerToken(client, provisioner, password, csrPem)
        };

        // Step 2: Sign the CSR
        var signRequest = new
        {
            csr = csrPem,
            ott = tokenRequest.ott
        };

        var response = await client.PostAsJsonAsync("/1.0/sign", signRequest);
        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<SignResponse>();
        return result?.Crt
            ?? throw new InvalidOperationException("step-ca returned empty certificate");
    }

    private static async Task<string> GetProvisionerToken(
        HttpClient client, string provisioner, string password, string csrPem)
    {
        // Extract the common name from the CSR for the token request
        // For the lab, we pass the CSR and let step-ca handle subject extraction
        var payload = new
        {
            provisioner,
            password,
            csr = csrPem
        };

        var response = await client.PostAsJsonAsync("/1.0/sign", payload);

        // If step-ca accepts direct CSR signing with provisioner credentials,
        // the response contains the certificate directly
        if (response.IsSuccessStatusCode)
        {
            var result = await response.Content.ReadFromJsonAsync<SignResponse>();
            // Return the OTT if available, otherwise this was a direct sign
            return result?.Crt ?? string.Empty;
        }

        throw new InvalidOperationException(
            $"Failed to get provisioner token: {response.StatusCode} - {await response.Content.ReadAsStringAsync()}");
    }

    private async Task WriteCert(string blobName, string certPem)
    {
        var accountName = Environment.GetEnvironmentVariable("PKI_STORAGE_ACCOUNT_NAME")
            ?? throw new InvalidOperationException("PKI_STORAGE_ACCOUNT_NAME not configured");

        var blobServiceClient = new BlobServiceClient(
            new Uri($"https://{accountName}.blob.core.windows.net"),
            new DefaultAzureCredential());

        var containerClient = blobServiceClient.GetBlobContainerClient("certs");
        var blobClient = containerClient.GetBlobClient(blobName);

        var content = Encoding.UTF8.GetBytes(certPem);
        await blobClient.UploadAsync(new BinaryData(content), overwrite: true);
    }

    private record SignResponse(string Crt, string Ca);
}
