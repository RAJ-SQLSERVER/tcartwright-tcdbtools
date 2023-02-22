﻿Function Invoke-Telnet {
    <#
    .SYNOPSIS
        A powershell telnet client alternative.

    .DESCRIPTION
        A powershell telnet client alternative. Commands can also be sent in batch, or in interactive mode.

    .PARAMETER ComputerName
        This is a required parameter where you need to specify a computer name which can be localhost or a remote computer

    .PARAMETER Port
        This is a required parameter where you need to specify a TCP port you want to test connection on.

    .PARAMETER Timeout
        This is an optional parameter where you can specify the timeout in milli-seconds. Default timeout is 10000ms (10 seconds)

    .PARAMETER Commands
        This is an optional parameter where you can send in a string array of the commands to issue to the remote host when connected. If this parameter is omitted, you will be prompted for commands to send.

    .EXAMPLE
        Telnet -ComputerName DC1 -Port 3389
        This command reports if DC1 can be connected on port 3389 which is default port for Remote Desktop Protocol (RDP). By simply running this command, you can check if Remote Desktop is enabled on computer DC1.

    .EXAMPLE
        Telnet WebServer 80
        This command tells you if WebServer is reachable on Port 80 which is default port for HTTP.

    .EXAMPLE
        Get-Content C:\Computers.txt | Telnet -Port 80
        This command will take all the computernames from a text file and pipe each computername to Telnet Cmdlet to report if all the computers are accessible on Port 80.

    .NOTES
        Original sources:
            - https://www.techtutsonline.com/powershell-alternative-telnet-command/
            - https://www.leeholmes.com/blog/2009/10/28/scripting-network-tcp-connections-in-powershell/

        Tim Cartwright: Updated to be interactive, also can optionally take a command list to be like a full featured telnet client
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true)]
        [Alias ('HostName','cn','Host','Computer')]
        [String]$ComputerName,
        [Parameter(Mandatory=$true,
            ValueFromPipeline=$true,
            ValueFromPipelineByPropertyName=$true)]
        [int32]$Port,
        [int32] $Timeout = 10000,
        [string[]] $Commands
    )

    begin {
        $commandPosition = 0
        $commandCount = $Commands.Count

        ## Create a buffer to receive the response
        $buffer = new-object System.Byte[] 1024
        $encoding = new-object System.Text.AsciiEncoding

        $outputBuffer = ""
        $foundMore = $false
    }

    Process {
        foreach($Computer in $ComputerName) {
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connection = $tcp.BeginConnect($Computer, $Port, $null, $null)
                $connection.AsyncWaitHandle.WaitOne($timeout,$false)  | Out-Null


                if ($tcp.Connected) {
                    Write-InformationColorized "Successfully connected to Host: `"$Computer`" on Port: `"$Port`"" -ForegroundColor Green

                    $tcpStream = $tcp.GetStream()
                    $tcpStream.ReadTimeout = 1000
                    $writer = New-Object System.IO.StreamWriter($tcpStream)
                    $writer.AutoFlush = $true

                    while ($command -ine "exit") {
                        $outputBuffer = ""
                        # Read all the data available from the stream, writing it to the outputbuffer when done.
                        do {
                            # Read what data is available
                            $foundmore = $false

                            do {
                                try {
                                    $read = $tcpStream.Read($buffer, 0, 1024)

                                    if ($read -gt 0) {
                                        $foundmore = $true
                                        $outputBuffer += ($encoding.GetString($buffer, 0, $read))
                                    }
                                } catch {
                                    $foundMore = $false;
                                    $read = 0
                                }
                            } while ($read -gt 0)
                        } while ($foundmore)

                        # write the recieved data out to the host
                        if (!([string]::IsNullOrWhiteSpace($outputBuffer))) {
                            # remove the last LF char, and write the output out to the host
                            Write-Information $outputBuffer.TrimEnd("`n")
                        }

                        $command = ""
                        if ($Commands.Count -eq 0) {
                            # prompt the user for the command to send
                            $command = Read-Host -Prompt "Command"
                        } else {
                            # we got a command array, lets select the command out, and get ready to pick the next one
                            if ($commandPosition -ge $commandCount) { break; }
                            $command = $commands[$commandPosition];
                            $commandPosition++;
                            # clean up the command so we can write it out
                            $cmd = $command -replace "`r|`n", " "
                            if ($cmd.Length -ge 80) { $cmd = $cmd.SubString(0, 80) + "..." }
                            Write-InformationColorized "Sending: $cmd" -ForegroundColor Yellow
                        }

                        # write the command back to the remote host
                        if (!([string]::IsNullOrWhiteSpace($command))) {
                            $writer.WriteLine($command);
                        }
                    }
                    Write-InformationColorized "`r`nDone." -ForegroundColor Yellow
                } else {
                    Write-InformationColorized "Could not connect to Host: `"$Computer `" on Port: `"$Port`"" -ForegroundColor Red
                }
            } catch {
                Write-InformationColorized "Unknown Error: $($_)" -ForegroundColor Red
            } finally {
                if ($null -ne $writer) { $writer.Dispose(); }
                if ($null -ne $tcp) { $tcp.Dispose(); }
            }
        }

    }
    End {}
}



