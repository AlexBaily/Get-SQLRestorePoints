##
# Function Get-SQLRestorePoints
# Author: Alex Baily
# Date: 30/01/2016
# v0.5
#
#
# This is the beginning of a script that will be able to read backups from a directory and generate a list of restore 
# points for different databases. For example, from one full backup on 2017-01-02 it will then go through all Tlog / diff backups.
# If it finds a break in the LSN chain for the t-log backups, it will cease at this point and that will be where you can restore to from 
# that specific full, this will give another restore point for the full to the diff etc.
#
##

function Get-SQLRestorePoints {

    [CmdletBinding()]
    param(
        [Parameter (
            ValueFromPipeline = $true,
            Position = 0
        )]
        [object]$sqlServer,
        [System.Management.Automation.PSCredential]$credential,
        [Parameter (
            ValueFromPipeline = $true,
            Position = 1
        )]
        [string[]]$Path

    )

    BEGIN {
        
        ##Need to add these variables so that they are not hard coded, they need to be loaded per SQL version.
        Add-Type -Path "C:\Program Files\Microsoft SQL Server\130\SDK\Assemblies\Microsoft.SqlServer.Smo.dll"
        Add-Type -Path "C:\Program Files\Microsoft SQL Server\130\SDK\Assemblies\Microsoft.SqlServer.SmoExtended.dll"

        Write-Verbose "Attempting to connect to $sqlServer..."

        try {
            $server = new-object Microsoft.SqlServer.Management.Smo.Server("$sqlServer")
            $server.ConnectionContext.ApplicationName = "Test App"
            $server.ConnectionContext.LoginSecure = $true
            $server.ConnectionContext.ConnectAsUser = $true
            $server.connectioncontext.ConnectAsUserName = $credential.UserName
            $server.ConnectionContext.ConnectAsUserPassword = $credential.GetNetworkCredential().Password
            $server.ConnectionContext.ConnectTimeout = 5
            $server.ConnectionContext.connect()

        }
        catch {
               ##To do
        }


    }
    Process {

        $files = Get-ChildItem -Path $Path
        $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
        $backupArray = @()
        $databases = New-Object System.Collections.ArrayList
        
        #Finding the backup files within the path/s specified and getting their attributes.
        #These are then added to the backupArray
        foreach($file in $files) {

            $fileName = $file.FullName
            $restore.Devices.AddDevice("$fileName"
                ,[Microsoft.SqlServer.Management.Smo.DeviceType]::File)
            $backupHeader = $restore.ReadBackupHeader($server)
            $databaseName = $backupHeader.DatabaseName[0]

            #Adding the databases to the DB name so that the DB names can be later referenced.
            if(!($databases.Contains("$databaseName"))) {
                $databases.Add("$databaseName")
            }
            
            $count = $backupHeader.Rows.Count
            

            #Need to find the best way to get the latest full from the backup set. Currently this is being done via index.
            if($count -gt 1){
                $backupFile = New-Object -TypeName PSObject
                $backupFile | Add-Member -Name 'DatabaseName' -MemberType NoteProperty -Value $backupHeader.DatabaseName[$count - 1]
                $backupFile | Add-Member -Name 'BackupName' -MemberType NoteProperty -Value $backupHeader.BackupName[$count - 1]
                $backupFile | Add-Member -Name 'FirstLSN' -MemberType NoteProperty -Value $backupHeader.FirstLSN[$count - 1]
                $backupFile | Add-Member -Name 'LastLSN' -MemberType NoteProperty -Value $backupHeader.LastLSN[$count - 1]
                $backupFile | Add-Member -Name 'Backup Start' -MemberType NoteProperty -Value $backupHeader.BackupStartDate[$count - 1]
                $backupFile | Add-Member -Name 'Backup Type' -MemberType NoteProperty -Value $backupHeader.BackupType[$count - 1]
            }
            else {
                #If this is the first backup in a backup set
                $backupFile = New-Object -TypeName PSObject
                $backupFile | Add-Member -Name 'DatabaseName' -MemberType NoteProperty -Value $backupHeader.DatabaseName
                $backupFile | Add-Member -Name 'BackupName' -MemberType NoteProperty -Value $backupHeader.BackupName
                $backupFile | Add-Member -Name 'FirstLSN' -MemberType NoteProperty -Value $backupHeader.FirstLSN
                $backupFile | Add-Member -Name 'LastLSN' -MemberType NoteProperty -Value $backupHeader.LastLSN
                $backupFile | Add-Member -Name 'Backup Start' -MemberType NoteProperty -Value $backupHeader.BackupStartDate
                $backupFile | Add-Member -Name 'Backup Type' -MemberType NoteProperty -Value $backupHeader.BackupType
            }

            #Adding the current backupFile to the backup array
            $backupArray += $backupFile
            #Removing the device from the restore object.
            $restore.Devices.RemoveAt(0)
        }

        return $backupArray
 
    }

    END {

        $server.ConnectionContext.Disconnect()      

    }

}
