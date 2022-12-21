﻿function Invoke-DBCompareServerSettings {
    <#
        .SYNOPSIS
            Compares all server settings for each instance passed in to generate a report showing differences. The user options are also compared
            individually. Any user option will have its name suffixed with (options).

        .DESCRIPTION
            Compares all server settings for each instance passed in to generate a report showing differences.

        .PARAMETER ServerInstances
            The sql server instances to connect to and compare. At least two servers must be passed in.

        .PARAMETER Credentials
            Specifies credentials to connect to the database with. If not supplied then a trusted connection will be used.

        .PARAMETER IgnoreVersionDifferences
            If a SQL Server does not support a particular setting because it is an older version then the value will be a dash: "-". If this switch is
            present, then any setting value with a dash will not be considered a difference.

        .INPUTS
            None. You cannot pipe objects to this script.

        .OUTPUTS
            A list of the servers and a comparison report.

        .EXAMPLE
            PS> .\Invoke-DBCompareServerSettings -ServerInstance "servername" -Databases "AdventureWorks2008","AdventureWorks2012" -SourceFileGroupName SHRINK_DATA_TEMP -TargetFileGroupName PRIMARY

        .EXAMPLE
            PS> .\Invoke-DBCompareServerSettings -ServerInstance "servername" -Databases "AdventureWorks2008","AdventureWorks2012" -UserName "user.name" -Password "ilovelamp" -SourceFileGroupName PRIMARY -TargetFileGroupName SHRINK_DATA_TEMP

        .LINK
            https://github.com/tcartwright/tcdbtools

        .NOTES
            Author: Tim Cartwright

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateCount(2,999)]
        [string[]]$ServerInstances,
        [pscredential]$Credentials,
        [switch]$IgnoreVersionDifferences
    )

    begin {
        $groups = ($ServerInstances | Group-Object)
        if ($groups | Where-Object { $_.Count -gt 1 }) {
            throw "You cannot pass in duplicate ServerInstances"
            return
        }

        $sqlCon = InitSqlObjects -ServerInstance $ServerInstances[0] -Credentials $Credentials
        $SqlCmdArguments = $sqlCon.SqlCmdArguments
        $list = [System.Collections.ArrayList]::new()

        $compareServers =  $ServerInstances | ForEach-Object { ($_).ToUpper() }
        $query = "
    DECLARE @options TABLE ([name] nvarchar(35), [minimum] int, [maximum] int, [config_value] int, [run_value] int)
    DECLARE @optionsCheck TABLE([id] int NOT NULL IDENTITY, [setting_name] varchar(128))
    DECLARE @current_value INT;

    INSERT INTO @options ([name], [minimum], [maximum], [config_value], [run_value])
    EXEC sp_configure 'user_options';

    SELECT @current_value = [config_value] FROM @options;

    INSERT INTO @optionsCheck
        ([setting_name])
    VALUES
        ('DISABLE_DEF_CNST_CHK'),
        ('IMPLICIT_TRANSACTIONS'),
        ('CURSOR_CLOSE_ON_COMMIT'),
        ('ANSI_WARNINGS'),
        ('ANSI_PADDING'),
        ('ANSI_NULLS'),
        ('ARITHABORT'),
        ('ARITHIGNORE'),
        ('QUOTED_IDENTIFIER'),
        ('NOCOUNT'),
        ('ANSI_NULL_DFLT_ON'),
        ('ANSI_NULL_DFLT_OFF'),
        ('CONCAT_NULL_YIELDS_NULL'),
        ('NUMERIC_ROUNDABORT'),
        ('XACT_ABORT')

    SELECT [name], [value]
    FROM sys.configurations c
        UNION ALL
    SELECT CONCAT(oc.[setting_name], ' (options)'),
        [server_option] = CASE WHEN (@current_value & fn.[value]) = fn.[value] THEN 1 ELSE 0 END
    FROM @optionsCheck oc
    CROSS APPLY (
        SELECT [value] = CASE WHEN oc.id > 1 THEN POWER(2, oc.id - 1) ELSE 1 END
    ) fn
        "
    }

    process {
        try {
            for ($i = 0; $i -le ($compareServers.Count - 1); $i++) {
                $srvrName = $compareServers[$i]
                $SqlCmdArguments.ServerInstance = $srvrName
                $results =  Invoke-SqlCmd @SqlCmdArguments -As DataRows -Query $query -ErrorAction Stop

                foreach ($r in $results) {
                    $setting = $list | Where-Object { $_.Name -ieq $r.Name }
                    if (-not $setting) {
                        # the original list does not have this setting yet, so add it
                        $setting = [PSCustomObject] @{
                            NAME = $r.Name
                            DIFFS = ""
                        }
                        $list.Add($setting) | Out-Null
                    }
                    $setting | Add-Member -MemberType NoteProperty -Name $srvrName -Value $r.Value
                }
            }
        } catch {
            throw
            return
        }

        # lets sort the list now that we have all the properties added
        $list = $list | Sort-Object Name

        # add the missing settings for older servers that do not support some settings
        foreach ($item in $list) {
            foreach ( $srvr in $compareServers ) {
                if (-not (Get-Member -inputobject $item -name $srvr -Membertype Properties)) {
                    $item | Add-Member -MemberType NoteProperty -Name $srvr -Value "-"
                }
            }
        }

        # now that all the servers have values for each of the fields, lets compare all the values
        foreach ($result in $list) {
            $isDiff = CompareSettings -setting $result -propertyNames $compareServers -IgnoreVersionDifferences:$IgnoreVersionDifferences.IsPresent
            $result.DIFFS = $isDiff
        }
    }

    end {
        return $list
    }
}
