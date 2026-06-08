using System.Formats.Asn1;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace PkiRa;

/// <summary>
/// Allow-list validation for inbound CSRs. Permanent rejections (returned
/// via <see cref="CsrValidationResult.IsValid"/> == false) cause the
/// Function to write a rejection record and return success so the blob
/// trigger does not retry/poison.
/// </summary>
public sealed class CsrValidator
{
    private readonly string _allowedDnsSuffix;

    public CsrValidator(string allowedDnsSuffix)
    {
        _allowedDnsSuffix = allowedDnsSuffix.TrimStart('.').ToLowerInvariant();
    }

    public CsrValidationResult Validate(string csrPem)
    {
        CertificateRequest req;
        try
        {
            // LoadSigningRequestPem requires a hash algorithm; CSR self-signature
            // is verified via SkipSignatureValidation = false.
            req = CertificateRequest.LoadSigningRequestPem(
                csrPem,
                HashAlgorithmName.SHA256,
                CertificateRequestLoadOptions.Default);
        }
        catch (Exception ex)
        {
            return Reject($"CSR parse failed: {ex.Message}");
        }

        // 🔑 Key sanity
        var pub = req.PublicKey;
        var algOid = pub.Oid?.Value;
        switch (algOid)
        {
            case "1.2.840.113549.1.1.1": // RSA
                using (var rsa = pub.GetRSAPublicKey())
                {
                    if (rsa is null || rsa.KeySize < 2048)
                    {
                        return Reject($"RSA key too small: {rsa?.KeySize ?? 0}");
                    }
                }
                break;
            case "1.2.840.10045.2.1": // EC
                using (var ec = pub.GetECDsaPublicKey())
                {
                    if (ec is null)
                    {
                        return Reject("EC public key could not be parsed");
                    }
                    var size = ec.KeySize;
                    if (size != 256 && size != 384)
                    {
                        return Reject($"Unsupported EC curve size: {size}");
                    }
                }
                break;
            default:
                return Reject($"Unsupported public key algorithm OID: {algOid}");
        }

        // 📛 Subject CN
        string? cn = null;
        foreach (var rdn in req.SubjectName.EnumerateRelativeDistinguishedNames())
        {
            if (!rdn.HasMultipleElements && rdn.GetSingleElementType().Value == "2.5.4.3")
            {
                cn = rdn.GetSingleElementValue();
            }
        }

        if (cn is not null && !MatchesSuffix(cn))
        {
            return Reject($"CN '{cn}' not under allowed suffix '.{_allowedDnsSuffix}'");
        }

        // 🌐 SAN extension
        var dnsSans = new List<string>();
        var hasUriSan = false;
        var hasEmailSan = false;
        var hasIpSan = false;

        foreach (var ext in req.CertificateExtensions)
        {
            switch (ext.Oid?.Value)
            {
                case "2.5.29.17": // SubjectAltName
                    ParseSans(ext.RawData, dnsSans, out hasUriSan, out hasEmailSan, out hasIpSan);
                    break;
                case "2.5.29.19": // BasicConstraints
                    var bc = ext as X509BasicConstraintsExtension
                             ?? new X509BasicConstraintsExtension(new AsnEncodedData(ext.RawData), ext.Critical);
                    if (bc.CertificateAuthority)
                    {
                        return Reject("CSR requests CA bit (BasicConstraints CA=true)");
                    }
                    break;
                case "2.5.29.15": // KeyUsage
                    var ku = ext as X509KeyUsageExtension
                             ?? new X509KeyUsageExtension(new AsnEncodedData(ext.RawData), ext.Critical);
                    if ((ku.KeyUsages & X509KeyUsageFlags.KeyCertSign) != 0 ||
                        (ku.KeyUsages & X509KeyUsageFlags.CrlSign) != 0)
                    {
                        return Reject("KeyUsage requests keyCertSign or cRLSign");
                    }
                    break;
                case "2.5.29.37": // ExtendedKeyUsage
                    var eku = ext as X509EnhancedKeyUsageExtension
                              ?? new X509EnhancedKeyUsageExtension(new AsnEncodedData(ext.RawData), ext.Critical);
                    foreach (var oid in eku.EnhancedKeyUsages)
                    {
                        if (oid.Value is not ("1.3.6.1.5.5.7.3.1" or "1.3.6.1.5.5.7.3.2"))
                        {
                            return Reject($"EKU not in {{serverAuth, clientAuth}}: {oid.Value}");
                        }
                    }
                    break;
                default:
                    if (ext.Critical &&
                        ext.Oid?.Value is not ("2.5.29.17" or "2.5.29.19" or "2.5.29.15" or "2.5.29.37"))
                    {
                        return Reject($"Unknown critical extension: {ext.Oid?.Value}");
                    }
                    break;
            }
        }

        if (hasUriSan) return Reject("URI SANs are not permitted");
        if (hasEmailSan) return Reject("Email SANs are not permitted");
        if (hasIpSan) return Reject("IP SANs are not permitted in this lab");

        foreach (var dns in dnsSans)
        {
            if (dns.StartsWith('*'))
            {
                return Reject($"Wildcard DNS SAN not permitted: {dns}");
            }
            if (!MatchesSuffix(dns))
            {
                return Reject($"DNS SAN '{dns}' not under allowed suffix '.{_allowedDnsSuffix}'");
            }
        }

        if (cn is null && dnsSans.Count == 0)
        {
            return Reject("CSR has neither CN nor any DNS SAN");
        }

        var sub = cn ?? dnsSans[0];
        return CsrValidationResult.Accept(sub, dnsSans);
    }

    private bool MatchesSuffix(string name)
    {
        var n = name.ToLowerInvariant();
        return n == _allowedDnsSuffix || n.EndsWith("." + _allowedDnsSuffix);
    }

    private static void ParseSans(
        byte[] raw,
        List<string> dnsOut,
        out bool hasUri,
        out bool hasEmail,
        out bool hasIp)
    {
        hasUri = hasEmail = hasIp = false;
        var reader = new AsnReader(raw, AsnEncodingRules.DER);
        var seq = reader.ReadSequence();
        while (seq.HasData)
        {
            var tag = seq.PeekTag();
            // GeneralName CHOICE — context-specific tags
            switch (tag.TagValue)
            {
                case 1: // rfc822Name (email)
                    hasEmail = true;
                    seq.ReadCharacterString(UniversalTagNumber.IA5String, tag);
                    break;
                case 2: // dNSName
                    var dns = seq.ReadCharacterString(UniversalTagNumber.IA5String, tag);
                    dnsOut.Add(dns);
                    break;
                case 6: // uniformResourceIdentifier
                    hasUri = true;
                    seq.ReadCharacterString(UniversalTagNumber.IA5String, tag);
                    break;
                case 7: // iPAddress
                    hasIp = true;
                    seq.ReadOctetString(tag);
                    break;
                default:
                    seq.ReadEncodedValue();
                    break;
            }
        }
    }

    private static CsrValidationResult Reject(string reason) =>
        new(false, reason, "", Array.Empty<string>());
}

public sealed record CsrValidationResult(
    bool IsValid,
    string Reason,
    string Subject,
    IReadOnlyList<string> DnsSans)
{
    public static CsrValidationResult Accept(string subject, IReadOnlyList<string> dnsSans) =>
        new(true, "", subject, dnsSans);
}
