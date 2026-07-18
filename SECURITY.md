# Security Policy

## Supported Versions

We actively support and monitor security vulnerabilities for the following versions of the RAM Cleaner & Flusher:

| Version | Supported |
| --- | --- |
| v1.0.x |  Yes |

---

## Privileges & Low-Level API Disclosures

This utility is a high-performance memory manager. To achieve real-time memory cleanup (similar to Microsoft Sysinternals RAMMap), the script performs the following operations:
1. **Administrative Access**: Requires running as Administrator to interact with Windows kernel APIs.
2. **P/Invoke Call Wrappers**: Compiles inline C# code to interface with `ntdll.dll`, `kernel32.dll`, `psapi.dll`, and `advapi32.dll`.
3. **Privilege Adjustments**: Accesses token settings to enable `SeProfileSingleProcessPrivilege` and `SeIncreaseQuotaPrivilege` which are standard OS-level diagnostic rights.

### 🛡️ Secure Execution Promise
* **100% Telemetry Free**: The script has **no network dependencies** or internet-facing requests. It performs all calculations offline.
* **Fully Auditable**: The script is open-source. We encourage developers to audit [RAM_Flusher.ps1](RAM_Flusher.ps1) and verify the safety of the P/Invoke declarations.

---

## Reporting a Vulnerability

If you identify a security issue or unexpected behavior:
1. **Do not open a public GitHub issue**.
2. Please send a direct email to the developer or contact via GitHub/Facebook profile:
   * **AliSakkaf**: [GitHub Profile](https://github.com/alisakkaf) / [Facebook](https://www.facebook.com/AliSakkaf.Dev/)
3. We will review your findings immediately and work on releasing a patch within 24 to 48 hours.

Thank you for helping keep this optimizer secure!
