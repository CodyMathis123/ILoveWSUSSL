function Set-ILWCertificateBinding {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IssuingCA,
        [Parameter(Mandatory = $false)]
        [string]$WebSite = 'WSUS Administration',
        [Parameter(Mandatory = $false)]
        [string]$HostName = $env:COMPUTERNAME
    )
    try {
        $WSUS_Server = Get-WsusServer -ErrorAction Stop
    }
    catch {
        # This is not a WSUS server, or it is in an error state. Return non-compliant.
        return 'Not a WSUS Server'
    }

    $WSUSPorts = Get-ILWSUSPortNumbers -WSUSServer $WSUS_Server
    $PortNumber = switch ($WSUSPorts.WSUSIsSSL) {
        $true {
            $WSUSPorts.WSUSPort1
        }
        $false {
            switch ($WSUSPorts.WSUSPort1) {
                80 {
                    443
                }
                default {
                    $WSUSPorts.WSUSPort1 + 1
                }
            }
        }
    }

    $ServerAuth = Get-ChildItem -Path Cert:\LocalMachine\My\  | Where-Object { $_.issuer -match $IssuingCA -and ($_.Subject -match $HostName -or $_.DnsNameList -match $HostName) -and $_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication' } | Sort-Object -Property NotAfter | Select-Object -Last 1
    if ($ServerAuth.NotAfter -le (Get-Date)) {
        $Message = "Unable to find a non-expired Server Authentication Certificate which matches [HostName: $Hostname] [Issuer: $IssuingCA]"
        Write-Error $Message
        return $Message
    }
    elseif ($null -eq $ServerAuth) {
        $Message = "Unable to find a Server Authentication Certificate which matches [HostName: $Hostname] [Issuer: $IssuingCA]"
        Write-Error $Message
        return $Message
    }

    $Binding = Get-WebBinding -Name $Website -Protocol https

    if ($null -eq $Binding) {
        $null = New-WebBinding -Name $Website -Protocol https -Port $PortNumber
        $Binding = Get-WebBinding -Name $Website -Protocol https
    }

    switch ($Binding.CertificateHash -eq $ServerAuth.Thumbprint) {
        $true {
            return 'Compliant'
        }
        $false {
            try {
                $Binding.AddSslCertificate($ServerAuth.Thumbprint, 'MY')
                return 'Compliant'
            }
            catch {
                $Message = "An error occurred while performing AddSslCertificate against [IIS: $($Binding.ItemXPath)] [Error: $($_.Exception.Message)]"
                Write-Error $Message

                return $Message
            }
        }
    }
}