using System.Security.Cryptography.X509Certificates;
using System.Text;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.ApplicationInsights;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using PkiRa;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        // 🔑 Load step-ca root cert from env (KV-backed) and build the pinned-chain handler
        var rootPem = Environment.GetEnvironmentVariable("STEP_CA_ROOT_CERT_PEM")
            ?? throw new InvalidOperationException("STEP_CA_ROOT_CERT_PEM not configured");
        var pinnedRoot = X509Certificate2.CreateFromPem(rootPem);

        // Sanity: warn if STEP_CA_FINGERPRINT does not match the loaded root SHA-256
        var expectedFp = Environment.GetEnvironmentVariable("STEP_CA_FINGERPRINT")?.ToLowerInvariant();
        var actualFp = Convert.ToHexString(
            System.Security.Cryptography.SHA256.HashData(pinnedRoot.RawData)).ToLowerInvariant();
        if (!string.IsNullOrEmpty(expectedFp) && expectedFp != actualFp)
        {
            Console.Error.WriteLine(
                $"[WARN] STEP_CA_FINGERPRINT ({expectedFp}) does not match SHA-256 of loaded root ({actualFp})");
        }

        // 🔐 Build the step-ca signer once (decrypts encrypted JWK with the provisioner password)
        var encJwk = Environment.GetEnvironmentVariable("STEP_CA_PROVISIONER_JWK")
            ?? throw new InvalidOperationException("STEP_CA_PROVISIONER_JWK not configured");
        var password = Environment.GetEnvironmentVariable("STEP_CA_PROVISIONER_PASSWORD")
            ?? throw new InvalidOperationException("STEP_CA_PROVISIONER_PASSWORD not configured");
        var provisioner = Environment.GetEnvironmentVariable("STEP_CA_PROVISIONER") ?? "ra-provisioner";
        var stepCaUrl = Environment.GetEnvironmentVariable("STEP_CA_URL")
            ?? throw new InvalidOperationException("STEP_CA_URL not configured");

        services.AddSingleton(new StepCaSigner(encJwk, password, provisioner, stepCaUrl, actualFp));

        // ✅ Validator
        var allowedSuffix = Environment.GetEnvironmentVariable("CSR_ALLOWED_DNS_SUFFIX") ?? "pki-lab.local";
        services.AddSingleton(new CsrValidator(allowedSuffix));

        // 🌐 HTTP client → step-ca, validates server cert against pinned root
        services.AddHttpClient("StepCA", client =>
        {
            client.BaseAddress = new Uri(stepCaUrl);
        }).ConfigurePrimaryHttpMessageHandler(() => PinnedRootHandlerFactory.Create(pinnedRoot));
    })
    .Build();

host.Run();
