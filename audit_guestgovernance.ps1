<#
.SYNOPSIS
Prints the entitlement-management lifecycle status of every Entra guest user.

.DESCRIPTION
Uses Microsoft Graph v1.0 and performs only GET requests. Install the dependency:
    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

Interactive authentication requests User.Read.All and
EntitlementManagement.ReadWrite.All (the documented permission for this subject
GET endpoint). Admin consent and a supported entitlement-management or Entra
role are required. The script does not change any users or governance settings.

SubjectNotFound and LookupFailed are inconclusive, not equivalent to notGoverned.
The Graph SDK handles transient-request retries, including throttling.

.EXAMPLE
.\Audit-GuestGovernance.ps1 -TenantId 'your-tenant-id'

.EXAMPLE
.\Audit-GuestGovernance.ps1 -UseExistingConnection
Uses an existing Connect-MgGraph session, including app-only authentication.
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param (
    [Parameter(ParameterSetName = 'Interactive')]
    [string]$TenantId,

    [Parameter(Mandatory, ParameterSetName = 'Existing')]
    [switch]$UseExistingConnection,

    [string]$CsvPath = (Join-Path $PSScriptRoot 'output.csv')
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

if (-not $UseExistingConnection) {
    $connectParameters = @{
        Scopes       = @('User.Read.All', 'EntitlementManagement.ReadWrite.All')
        ContextScope = 'Process'
        NoWelcome    = $true
    }
    if ($TenantId) {
        $connectParameters.TenantId = $TenantId
    }
    Connect-MgGraph @connectParameters | Out-Null
}

$context = Get-MgContext
if (-not $context) {
    throw 'No Microsoft Graph connection. Run Connect-MgGraph first or omit -UseExistingConnection.'
}
if ($context.Environment -ne 'Global') {
    throw 'This subject endpoint is supported only in the Global Microsoft Graph cloud.'
}

Write-Host ('Auditing guest users in tenant {0}' -f $context.TenantId)
Write-Host ('{0,-20} {1}' -f 'Status', 'User (object ID)')
$organization = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName' -OutputType PSObject -ErrorAction Stop
$companyName = [string]$organization.value[0].displayName
$results = [System.Collections.Generic.List[object]]::new()

$nextLink = 'https://graph.microsoft.com/v1.0/users?$filter=userType%20eq%20%27Guest%27&$select=id,displayName,userPrincipalName&$top=999'
$guestCount = 0
$governedCount = 0
$notGovernedCount = 0
$inconclusiveCount = 0

do {
    $page = Invoke-MgGraphRequest -Method GET -Uri $nextLink -OutputType PSObject -ErrorAction Stop

    foreach ($guest in $page.value) {
        $guestCount++
        $subjectUri = "https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/subjects(objectId='$($guest.id)')?`$select=subjectLifecycle"
        $detail = $null

        try {
            $subject = Invoke-MgGraphRequest -Method GET -Uri $subjectUri -OutputType PSObject -ErrorAction Stop
            $status = [string]$subject.subjectLifecycle
            if ([string]::IsNullOrWhiteSpace($status)) {
                $status = 'Unknown'
            }
        }
        catch {
            $statusCode = $_.Exception.ResponseStatusCode
            if (-not $statusCode -and $_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
            }
            if ($statusCode -and [int]$statusCode -eq 404) {
                $status = 'SubjectNotFound'
            }
            else {
                $status = 'LookupFailed'
                $detail = $_.Exception.Message -replace '[\r\n]+', ' '
            }
        }

        switch ($status) {
            'governed'    { $governedCount++ }
            'notGoverned' { $notGovernedCount++ }
            default       { $inconclusiveCount++ }
        }

        $userLabel = '{0} <{1}> ({2})' -f $guest.displayName, $guest.userPrincipalName, $guest.id
        Write-Host ('{0,-20} {1}' -f $status, $userLabel)
        if ($detail) {
            Write-Host ('  Error: {0}' -f $detail)
        }
        $results.Add([pscustomobject]@{
            CompanyName       = $companyName
            TenantId          = $context.TenantId
            DisplayName       = $guest.displayName
            UserPrincipalName = $guest.userPrincipalName
            ObjectId          = $guest.id
            Status            = $status
            Error             = $detail
        })
    }

    $nextLink = $page.'@odata.nextLink'
} while ($nextLink)

$results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding utf8
Write-Host ('Total: {0} | Governed: {1} | Not governed: {2} | Inconclusive: {3}' -f $guestCount, $governedCount, $notGovernedCount, $inconclusiveCount)