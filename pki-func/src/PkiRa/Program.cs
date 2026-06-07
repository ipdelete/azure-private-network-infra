using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.ApplicationInsights;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        services.AddHttpClient("StepCA", client =>
        {
            var caUrl = Environment.GetEnvironmentVariable("STEP_CA_URL")
                ?? throw new InvalidOperationException("STEP_CA_URL not configured");
            client.BaseAddress = new Uri(caUrl);
        }).ConfigurePrimaryHttpMessageHandler(() =>
        {
            // step-ca uses a self-signed cert — accept it in the lab
            return new HttpClientHandler
            {
                ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true
            };
        });
    })
    .Build();

host.Run();
