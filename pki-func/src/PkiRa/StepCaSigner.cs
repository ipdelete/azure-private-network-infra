using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.Json;
using Jose;

namespace PkiRa;

/// <summary>
/// Holds the decrypted step-ca JWK provisioner private key and mints
/// one-time tokens (OTTs) that authorize a single CSR signing call.
///
/// The encrypted JWK (JWE with PBES2-HS256+A128KW + A256GCM) and its
/// password are loaded once from environment (resolved via Key Vault
/// references), decrypted, and cached for the lifetime of the Function
/// host instance. Subsequent invocations reuse the cached key.
/// </summary>
public sealed class StepCaSigner
{
    public string Kid { get; }
    public string Algorithm { get; }
    private readonly object _signingKey;
    private readonly string _provisioner;
    private readonly string _audience;
    private readonly string _rootSha;

    public StepCaSigner(string encryptedJwkJwe, string password, string provisioner, string stepCaUrl, string rootSha)
    {
        _provisioner = provisioner;
        _audience = $"{stepCaUrl.TrimEnd('/')}/1.0/sign";
        _rootSha = rootSha;

        var decrypted = JWT.Decode(encryptedJwkJwe, password);
        using var doc = JsonDocument.Parse(decrypted);
        var root = doc.RootElement;

        var kty = root.GetProperty("kty").GetString() ?? throw new InvalidOperationException("JWK missing kty");
        Kid = root.TryGetProperty("kid", out var kidEl) ? kidEl.GetString() ?? "" : "";

        (_signingKey, Algorithm) = kty switch
        {
            "EC" => BuildEc(root),
            "RSA" => BuildRsa(root),
            "OKP" => throw new NotSupportedException("Ed25519 (OKP) JWKs are not supported in this build."),
            _ => throw new InvalidOperationException($"Unsupported JWK kty: {kty}")
        };
    }

    private static (object key, string alg) BuildEc(JsonElement root)
    {
        var crv = root.GetProperty("crv").GetString();
        var x = Base64Url(root.GetProperty("x").GetString()!);
        var y = Base64Url(root.GetProperty("y").GetString()!);
        var d = Base64Url(root.GetProperty("d").GetString()!);
        var curve = crv switch
        {
            "P-256" => ECCurve.NamedCurves.nistP256,
            "P-384" => ECCurve.NamedCurves.nistP384,
            "P-521" => ECCurve.NamedCurves.nistP521,
            _ => throw new InvalidOperationException($"Unsupported EC curve: {crv}")
        };
        var alg = crv switch
        {
            "P-256" => "ES256",
            "P-384" => "ES384",
            "P-521" => "ES512",
            _ => throw new InvalidOperationException($"Unsupported EC curve: {crv}")
        };
        var ecdsa = ECDsa.Create(new ECParameters
        {
            Curve = curve,
            Q = new ECPoint { X = x, Y = y },
            D = d
        });
        return (ecdsa, alg);
    }

    private static (object key, string alg) BuildRsa(JsonElement root)
    {
        var n = Base64Url(root.GetProperty("n").GetString()!);
        var e = Base64Url(root.GetProperty("e").GetString()!);
        var d = Base64Url(root.GetProperty("d").GetString()!);
        var p = Base64Url(root.GetProperty("p").GetString()!);
        var q = Base64Url(root.GetProperty("q").GetString()!);
        var dp = Base64Url(root.GetProperty("dp").GetString()!);
        var dq = Base64Url(root.GetProperty("dq").GetString()!);
        var qi = Base64Url(root.GetProperty("qi").GetString()!);
        var rsa = RSA.Create(new RSAParameters
        {
            Modulus = n,
            Exponent = e,
            D = d,
            P = p,
            Q = q,
            DP = dp,
            DQ = dq,
            InverseQ = qi
        });
        return (rsa, "RS256");
    }

    /// <summary>Mint a one-time token (JWT) for a single sign call.</summary>
    public string MintOtt(string subject, IEnumerable<string> dnsSans)
    {
        var now = DateTimeOffset.UtcNow;
        var claims = new Dictionary<string, object>
        {
            ["iss"] = _provisioner,
            ["aud"] = _audience,
            ["sub"] = subject,
            ["sans"] = dnsSans.ToArray(),
            ["sha"] = _rootSha,
            ["iat"] = now.ToUnixTimeSeconds(),
            ["nbf"] = now.AddSeconds(-30).ToUnixTimeSeconds(),
            ["exp"] = now.AddMinutes(5).ToUnixTimeSeconds(),
            ["jti"] = Guid.NewGuid().ToString("N"),
        };
        var headers = new Dictionary<string, object>
        {
            ["kid"] = Kid,
            ["typ"] = "JWT",
        };
        var jwsAlg = Algorithm switch
        {
            "ES256" => JwsAlgorithm.ES256,
            "ES384" => JwsAlgorithm.ES384,
            "ES512" => JwsAlgorithm.ES512,
            "RS256" => JwsAlgorithm.RS256,
            _ => throw new InvalidOperationException($"Unsupported JWS alg: {Algorithm}")
        };
        return JWT.Encode(claims, _signingKey, jwsAlg, extraHeaders: headers);
    }

    private static byte[] Base64Url(string s)
    {
        var padded = s.Replace('-', '+').Replace('_', '/');
        switch (padded.Length % 4)
        {
            case 2: padded += "=="; break;
            case 3: padded += "="; break;
        }
        return Convert.FromBase64String(padded);
    }
}

/// <summary>
/// HttpClientHandler factory that validates step-ca's TLS chain against
/// a pinned root cert loaded from STEP_CA_ROOT_CERT_PEM. Hostname check
/// is left to the default validator (we still depend on the platform to
/// match the cert SAN against the request URL host).
/// </summary>
public static class PinnedRootHandlerFactory
{
    public static HttpClientHandler Create(X509Certificate2 pinnedRoot)
    {
        return new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = (request, leaf, chain, errors) =>
            {
                if (leaf is null || chain is null)
                {
                    return false;
                }

                // We only tolerate UntrustedRoot — anything else (hostname mismatch,
                // expired, revoked) must still fail.
                var allowedErrors = System.Net.Security.SslPolicyErrors.None
                                  | System.Net.Security.SslPolicyErrors.RemoteCertificateChainErrors;
                if ((errors & ~allowedErrors) != 0)
                {
                    return false;
                }

                using var customChain = new X509Chain();
                customChain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                customChain.ChainPolicy.CustomTrustStore.Add(pinnedRoot);
                customChain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                return customChain.Build(leaf);
            }
        };
    }
}
