# Entra Guest Governance Audit

A PowerShell script that reports the entitlement-management lifecycle status of guest users in a Microsoft Entra tenant. It uses Microsoft Graph v1.0 and makes only `GET` requests; it does not modify users, access packages, or governance settings.

## What It Reports

For each guest account, the CSV includes:

- `CompanyName`: the tenant organization's display name
- `TenantId`: the Microsoft Graph tenant ID
- `DisplayName`, `UserPrincipalName`, and `ObjectId`: guest identity details
- `Status`: the entitlement-management subject lifecycle result
- `Error`: lookup error detail when a lookup fails

`governed` and `notGoverned` are returned lifecycle statuses. `SubjectNotFound`, `LookupFailed`, and `Unknown` are inconclusive; they should not be interpreted as `notGoverned`. A `LookupFailed` error may include diagnostic details, so treat the CSV as tenant data and store or share it accordingly.

## Requirements

- Windows PowerShell or PowerShell 7
- Microsoft Graph PowerShell authentication module:

  ```powershell
  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
  ```

- Microsoft Graph access to list users and query entitlement-management subjects
- A supported entitlement-management or Microsoft Entra role, and admin consent where required
- The Global Microsoft Graph cloud; the script exits for other Graph environments

For interactive sign-in, the script requests `User.Read.All` and `EntitlementManagement.ReadWrite.All`. The audit itself remains read-only; the latter is the documented permission required for this subject `GET` endpoint. If using an existing Graph connection, connect first with an identity that has the required access and consent.

## Run

Interactive sign-in, optionally specifying the tenant:

```powershell
.\Audit-GuestGovernance.ps1 -TenantId 'your-tenant-id'
```

Sign in using an existing Microsoft Graph connection:

```powershell
Connect-MgGraph -Scopes 'User.Read.All', 'EntitlementManagement.ReadWrite.All'
.\Audit-GuestGovernance.ps1 -UseExistingConnection
```

By default, the report is written to `output.csv` in the script's directory. Choose another path with `-CsvPath`:

```powershell
.\Audit-GuestGovernance.ps1 -TenantId 'your-tenant-id' -CsvPath '.\reports\guest-governance.csv'
```

The target directory must already exist. Run the script directly; do not redirect its console output to the CSV path. The script writes its structured report with `Export-Csv` and prints progress and totals to the console.

## Notes

- The script follows Graph pagination when listing guests.
- Microsoft Graph SDK retry handling applies to transient requests, including throttling.
- The output can contain personal and tenant-identifying information. Protect it according to your organization's data-handling requirements.
