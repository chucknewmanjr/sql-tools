process{
    $scriptfolder = "$env:Build_SourcesDirectory\$env:vcs_approot\Scripts"
    $scriptfiles = Get-ChildItem $scriptfolder
    CleanFilesForAzure $scriptfolder
    AddPrePostSQLScript $scriptfiles
    }
        
    begin {
        
        function AddPrePostSQLScript($scriptfiles) {
            foreach ($scriptfile in $scriptfiles) {
                $scriptfilepath = $scriptfile.FullName
                $Filename = $scriptfile.Name
                $ScriptChangeNumber = $Filename.split('_')[0].trimstart('0')
        
                $presql = "
                    IF NOT EXISTS (SELECT * FROM [dbo].[ChangeLog] WHERE change_number = $ScriptChangeNumber)
                    BEGIN
                        INSERT INTO [dbo].[ChangeLog] (change_number, delta_set, start_dt, applied_by, description) VALUES ($($ScriptChangeNumber), 'Main', getdate(), user_name(), '$($Filename)')
                    END
                    ELSE
                    BEGIN
                        UPDATE 
                            [dbo].[ChangeLog] 
                        SET 
                            start_dt = getdate(),
                            applied_by = user_name(),
                            description = '$($Filename)'
                        WHERE 
                            change_number = $($ScriptChangeNumber) 
                            AND delta_set = 'Main'
                    END
        
                    PRINT 'Executing File: $($Filename)'
                        SET xact_abort on
                    BEGIN TRANSACTION
                    GO
                    "
        
                $postsql = "
                             GO -- This GO is absolutely necessary!
                    if XACT_STATE() = 1 
                       BEGIN
                         COMMIT TRANSACTION                     
                       END  
        
                    UPDATE [dbo].[ChangeLog] SET complete_dt = getdate() WHERE change_number = $($ScriptChangeNumber) AND delta_set = 'Main'"
        
                Write-Output $scriptfilepath  
                $sqlfile = Get-Content -Path $scriptfilepath -Raw 
                $newsqlfile = "$($presql)$($sqlfile)$($postsql)"
                Clear-Content $scriptfilepath
                Add-Content -Path $scriptfilepath -Value $newsqlfile
            }
        }

        function CleanFilesForAzure($scriptfolder) {
            $pattern = "(?:(?i)(ON([\s]+))(\[)?([A-Za-z_#@][A-Za-z0-9#$@_]*_FG)(\s*)(\])?)|((?i)(TEXTIMAGE_ON([\s]+))(\[)?([A-Za-z_#@][A-Za-z0-9#$@_]*_FG)(\s*)(\])?)"
            $pattern2 = "(?:(?i)(\[)?WPCore(\s*)(\])?\.)(?=((\[)?[A-Za-z_#@][A-Za-z0-9#$@_]*(\s*)(\])?\.))|(?:(?i)(\[)?BPM(\s*)(\])?\.)(?=((\[)?[A-Za-z_#@][A-Za-z0-9#$@_]*(\s*)(\])?\.))|(?:(?i)(\[)?ImportFramework(\s*)(\])?\.)(?=((\[)?[A-Za-z_#@][A-Za-z0-9#$@_]*(\s*)(\])?\.))|(?:(?i)(\[)?IDEA(\s*)(\])?\.)(?=((\[)?[A-Za-z_#@][A-Za-z0-9#$@_]*(\s*)(\])?\.))"
        
            $Files = get-childitem $scriptfolder *.sql -Exclude *.dll, *.exe -rec
            foreach ($file in $Files) {
                #replace file content
                if (!$file.PSIsContainer) {
                    # reset readonly bit
                    if ($file.IsReadOnly) {
                        $file.IsReadOnly = $false
                    }
                    
                    Write-Output $scriptfilepath   
                    $fileContent = [System.Io.File]::ReadAllText($file.fullname,[System.Text.Encoding]::UTF8)
        
                    if ([regex]::Match($fileContent, $pattern).Success) {
                        $fileContent = $fileContent -replace $pattern, ' '
                        Set-Content $fileContent -LiteralPath $file.fullname
                    }
                    
                    $scriptfolder = ($file.fullname | split-path)
        
                    if (([regex]::Match($fileContent, $pattern2).Success) -and ($scriptfolder -like '*StoredProcedures*')) {
                        $fileContent = $fileContent -replace $pattern2, ''
                        Set-Content $fileContent -LiteralPath $file.fullname 
                    }
                    
                }
            }
        }
    }
