# Documentation and home: https://gitlab.engr.illinois.edu/engrit-epm/get-appsupersedence
# By mseng3

function Get-AppSupersedence {

	# TODO
	# - Find a way to check/validate that valid revision is being used?
	# - Find out if one of the app properties shows the source content revision (which I believe is different than the app revision)?
	# - Count number of unique superseded apps and output with "other info"

	param(
		[Parameter(Position=0,Mandatory=$true,ParameterSetName="App1")]
		[Alias("Apps","Applications")]
		[string[]]$AppNames,
		
		[Parameter(Position=0,Mandatory=$true,ParameterSetName="Collection")]
		[string]$Collection,
		
		[Parameter(Position=0,Mandatory=$true,ParameterSetName="TS")]
		[Alias("TaskSequence")]
		[string]$TS,
		
		# Debug output verbosity
		# 0 = Just the intended output
		# 1 = Output from intermediate steps
		# 2 = Output from various minor operations and variable value checks
		[Alias("Verbosity")]
		[int]$DebugLevel=0,
		
		# Log
		[string]$Log,
		
		# Site code
		[string]$SiteCode="MP0",
		
		# SMS Provider machine name
		[string]$Provider="sccmcas.ad.uillinois.edu",
		
		# ConfigurationManager Powershell module path
		[string]$CMPSModulePath="$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1",
		
		# Caching
		[switch]$DisableCaching
	)


	# -----------------------------------------------------------------
	# Global variables
	# -----------------------------------------------------------------
	
	# Exit codes
	$APP_SEARCH_NOT_FOUND = 1
	$APP_SEARCH_ERROR = 2
	$APP_SEARCH_ERROR2 = 3
	$APP_SEARCH_MULTI = 4
	$NOT_IMPLEMENTED = 5
	$MISSING_PARAMETER = 6
	$FAILED_GETTING_TS = 7
	$NO_TS_REFS = 8
	
	$MY_PWD = $pwd.path
	
	# For counting app references
	$ASCII_0 = 0
	# For counting non-app references
	$ASCII_A = 65
	
	# Special box-drawing characters for supersedence output
	# Unfortunately the PowerShell console host can't render these
	#$BOX_CHAR = [char]0x2517 + [char]0x257A 
	# Plain "L" just doesn't look good
	#$BOX_CHAR = "L "
	$BOX_CHAR = ""
	
	# Used as a sentinal for logic flow when an invalid app reference is found
	$INVALID = "{INVALID}"
	
	# At some point warnings about using certain cmdlets without the -Fast parameter started being shown.
	# This disables those warnings.
	$CMPSSuppressFastNotUsedCheck = $true
	
	# Cache variables for apps, so we don't have to retrieve the same app multiple times
	# For when multiple apps supersede the same app
	$script:CachedAppsFast = @()
	$script:CachedApps = @()

	# -----------------------------------------------------------------
	# Functions
	# -----------------------------------------------------------------

	# Loads the ConfigMgr power shell module, and connects to the Site.
	function Prep-SCCM {
		log "Preparing connection to SCCM..."
		# Customizations
		$initParams = @{}
		#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
		#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

		# Import the ConfigurationManager.psd1 module 
		if((Get-Module ConfigurationManager) -eq $null) {
			Import-Module $CMPSModulePath @initParams -Scope Global
		}

		# Connect to the site's drive if it is not already present
		if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
			New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider @initParams
		}

		# Set the current location to be the site code.
		Set-Location "$($SiteCode):\" @initParams
		log "Done preparing connection to SCCM." -debug 2
		log -blank 1
	}

	# Custom logging, mostly for convenience and consistency
	function log {
		param(
			[string]$msg,
			[int]$level=0,
			[int]$blank=0,
			[switch]$nots,
			[int]$debug=0,
			[switch]$red
		)
		
		if($DebugLevel -lt $debug) {
			return
		}
		
		for($i = 0; $i -lt $level; $i += 1) {
			$msg = "    $msg"
		}

		if(!$nots) {
			$timestamp = Get-Date -UFormat "%Y-%m-%d %H:%M:%S"
			$msg = "[$timestamp] $msg"
		}

		if($blank -gt 0) {
			for($i = 0; $i -lt $blank; $i += 1) {
				if($red) { Write-Host " " -ForegroundColor "red" }
				else { Write-Host " " }
				if($Log) {
					" " | Out-File $Log -Append
				}
			}
		}
		else {	
			if($red) { Write-Host $msg -ForegroundColor "red" }
			else { Write-Host $msg }
			if($Log) {
				"$msg" | Out-File $Log -Append
			}
		}
	}
	
	# Necessary in case regex special characters are used in app names
	# so we can use the -match operator
	# In practice I've only seen this problem with the character "+"
	# as in "Notepad++"
	# No longer necessary, because using -eq instead of -match,
	# because searching by -match $LocalizedDisplayName was returning multiple results,
	# because apparently the -match operator assumes wildcards
	<#
	function Sanitize-ID($id) {
		log "Sanitizing ID: `"$id`"..." -debug 2
		$newID = $id.Replace("+","\+")
		log "ID `"$id`" sanitized to `"$newID`"." -debug 2
		$newID
	}
	#>
	
	# Gets all info about an app, given its ID
	# Tested with finding by `CI_ID` and `ModelName`.
	# Using other values could result in multiple matches, which would break things
	function Get-App($idType, $id, $level=0) {
		if($DebugLevel -eq 0) {
			$errorLevel = 1
		}
		else {
			$errorLevel = $level + $DebugLevel
		}
		
		# Find app using -Fast flag to speed up searching
		log "Getting app where `"$idType`" matches `"$id`"..." -debug 2 -level ($level + 1)
		
		#If caching isn't disabled
		if(-not $DisableCaching) {
			log "Looking for app in `"fast`" cache..." -debug 2 -level ($level + 2)
			
			# Get "fast" app cache variable
			$cachedAppsFast = Get-Variable -Name "CachedAppsFast" -Scope "Script" -ValueOnly
			
			# Attempt to get the "fast" app from the cache
			$app = $cachedAppsFast | Where { $_.$idType -eq $id }
			
			# If we failed, get it from MECM and cache it
			if(-not $app) {
				log "App not found in cache. Retrieving from MECM..." -debug 2 -level ($level + 3)
				$app = Get-CMApplication -Fast | Where { $_.$idType -eq $id }
				Set-Variable -Name "CachedAppsFast" -Scope "Script" -Value ($cachedAppsFast + @($app))
			}
			else {
				log "Found app in cache." -debug 2 -level ($level + 3)
			}
			
			# Grab the appID
			$appID = $app | Select CI_ID
		}		
		# If caching is disabled
		else {
			log "Caching disabled. Retrieving app from MECM..." -debug 2 -level ($level + 2)
			
			# Get "fast" app from MECM
			
			#$idSanitized = Sanitize-ID $id
			#$appID = Get-CMApplication -Fast | Where { $_.$idType -match $idSanitized } | Select CI_ID
			#$appID = Get-CMApplication -Fast | Where { $_.$idType -like $idSanitized } | Select CI_ID
			
			$appID = Get-CMApplication -Fast | Where { $_.$idType -eq $id } | Select CI_ID
		}
		log "appID: `"$appID`"." -debug 2 -level ($level + 3)
		
		# If app was found
		if($appID.CI_ID) {
			# If only one app was found
			if(@($appID).count -eq 1) {
				log "Found 1 app with `"$idType`" matching `"$id`"."  -level ($level + 2) -debug 2
				
				# Get full app proerties now that we know which app it is
				log "Getting app properties..." -level ($level + 2) -debug 2
				
				# If caching is not disabled
				if(-not $DisableCaching) {
					log "Looking for app in `"full`" cache..." -debug 2 -level ($level + 3)
					
					# Get "full" app cache variable
					$cachedApps = Get-Variable -Name "CachedApps" -Scope "Script" -ValueOnly
					
					# Attempt to get the "full" app from the cache
					$app = $cachedApps | Where { $_.CI_ID -eq $appID.CI_ID }
					
					# If we failed, get it from MECM and cache it
					if(-not $app) {
						log "App not found in cache. Retrieving from MECM..." -debug 2 -level ($level + 4)
						$app = Get-CMApplication -ID $appID.CI_ID
						Set-Variable -Name "CachedApps" -Scope "Script" -Value ($cachedApps + @($app))
					}
					else {
						log "Found app in cache." -debug 2 -level ($level + 4)
					}
				}
				# If caching is disabled
				else {
					log "Caching disabled. Retrieving app from MECM..." -debug 2 -level ($level + 2)
					
					# Get full app from MECM
					$app = Get-CMApplication -Id $appID.CI_ID
				}
				
				log "Done getting app properties." -level ($level + 2) -debug 2
				
				log "Parsing app properties..." -level ($level + 2) -debug 2
				# Determine whether the box is checked for "Allow this application to be installed from the Install Application task sequence action without being deployed"
				$auto = "unknown"
				if($app.SDMPackageXML  -like '*<AutoInstall>true</AutoInstall>*') { $auto = "true" }
				else { $auto = "false" }
				# Remove SDMPackageXML field because it's frickin huge
				#$app = $app | Select -Property * -ExcludeProperty Properties,SDMPackageXML
				
				# Determine whether the app supersedes other apps
				<#
				$isSuperseding = "unknown"
				if($app.SDMPackageXML  -like '*<Supersedes>*</Supersedes>*') { $isSupersedeing = "true" }
				else { $isSuperseding = "false" }
				#>
				
				# Grab relevant properties, and add custom properties
				$app | Add-Member -Force -NotePropertyName "_name" -NotePropertyValue $app.LocalizedDisplayName # For convenience
				$app | Add-Member -Force -NotePropertyName "_auto" -NotePropertyValue $auto
				#$appFull | Add-Member -Force -NotePropertyName "_isSuperseding" -NotePropertyValue $isSuperseding
				$app | Add-Member -Force -NotePropertyName "_supersedes" -NotePropertyValue @()
				$app | Add-Member -Force -NotePropertyName "_hasInvalid" -NotePropertyValue $false
				$app | Add-Member -Force -NotePropertyName "_supersedenceLength" -NotePropertyValue 0
				log "Done parsing app properties..." -level ($level + 2) -debug 2
			}
			elseif(@($appID).count -eq 0) {
				log "Did not find app with `"$idType`" matching `"$id`". Returned a value, but with 0 elements. Not sure how this happened!" -level $errorLevel -red
			}
			elseif(@($appID).count -gt 1) {
				log "Found more than 1 app with `"$idType`" matching `"$id`"!" -level $errorLevel -red
			}
			else {
				log "Found an unknown number of apps with `"$idType`" matching `"$id`". Not sure how this happened!" -level $errorLevel -red
			}
		}
		# If app was not found
		else {
			log "Did not find app with `"$idType`" matching `"$id`"!" -level $errorLevel -red
			log "This app might not exist, or has been deleted but is still being referenced." -level ($errorLevel + 1) -red

			if($found -ne 1) {
				# Make a dummy app
				log "Filling app properties with `"$INVALID`"..." -level ($level + 2) -debug 2
				
				$app = [PSCustomObject]@{
					"_name" = $INVALID
					"CI_UniqueID" = $INVALID
					"CIVersion" = $INVALID
					"SDMPackageXML" = $INVALID
					"_auto" = $INVALID
					#"_isSuperseding" = $INVALID
					"_supersedes" = $INVALID
					"_hasInvalid" = $INVALID
					"_supersedenceLength" = $INVALID
				}
				log "Done filling app properties with `"$INVALID`"..." -level ($level + 2) -debug 2
			}
		}
		
		log "Done getting app where `"$idType`" matches `"$id`"..." -debug 2 -level ($level + 1)
		
		# Return app object
		$app | Add-Member -Force -NotePropertyName "_givenId" -NotePropertyValue $id
		$app
	}

	# Not all references in a TS are Apps, but I couldn't find an authoritative field to check to determine which kind of package a reference ID refers to.
	# So this function uses trial and error to figure that out.
	# It's possible there are other kinds of packages not accounted for here, but this should account for the most common types
	function Get-PackageType($ref) {
		$id = $ref.Package
		
		$result = @{
			type = "Unknown Type"
			name = "Unknown Name"
		}
		
		$package = Get-CMApplication -Fast -ModelName $id
		if($package -ne $null) {
			$result.type = "App"
		}
		else {
			$package = Get-CMPackage -Fast -Id $id
			if($package -ne $null) {
				$result.type = "Package"
			}
			else {
				$package = Get-CMDriverPackage -Id $id
				if($package -ne $null) {
					$result.type = "Driver Package"
				}
				else {
					$package = Get-CMOperatingSystemImage -Id $id 
					if($package -ne $null) {
						$result.type = "OS Image"
					}
					else {
						$package = Get-CMOperatingSystemInstaller -Id $id 
						if($package -ne $null) {
							$result.type = "OS Upgrade Package"
						}
						else {
							$package = Get-CMBootImage -Id $id
							if($package -ne $null) {
								$result.type = "Boot Image"
							}
							else {
								$package = Get-CMTaskSequence -TaskSequencePackageId $id
								if($package -ne $null) {
									$result.type = "Task Sequence"
								}
							}
						}
					}
				}
			}	
		}
		$result.name = $package.Name
		
		$result
	}
	
	function Get-CollectionDeployedApps($col) {
		# Array for storing app refs
		$appNames = @()
	
		# Get deployments
		try {
			$colData = Get-CMApplicationDeployment -CollectionName $col
		}
		catch {
			log "Failed to get collection application deployments from SCCM!" -red
		}
		
		if(!$colData) {
			log "No application deployments were found for collection!" -red
		}
		else {
			log "Found $(@($colData).count) applications deployed to collection `"$col`"."
			$appNames = $colData.ApplicationName
		}
		
		$appNames
	}
	
	# Pulls all the references from the given TS, and returns an array of the references' CI_UniqueIDs.
	# References for other types of packages are ignored.
	function Get-TSReferencedApps($ts) {
		# Array for storing app refs
		$appNames = @()
	
		# Get references
		try {
			$tsData = Get-CMTaskSequence -Name $ts
		}
		catch {
			log "Failed to get task sequence from SCCM!" -red
		}
		
		if(!$tsData) {
			log "No references were found in task sequence!" -red
		}
		else {
			$tsRefs = $tsData | Select ReferencesCount,References
			log "Found $($tsRefs.ReferencesCount) references in TS `"$ts`" (there might still be references in child TSes):" -level 1
			
			# For progress bar completion
			$progress = 0
			
			# Keep separate counts for apps vs. non-apps
			# Count apps from 0
			$countApp = $ASCII_0
			# Count non-apps from A
			$countPackage = $ASCII_A
			
			# For each reference of the given TS
			foreach($ref in $tsRefs.References) {
				Write-Progress -Activity "One moment please..." -Status "Gathering information about referenced apps..." -PercentComplete (($progress / ($tsRefs.References).count) * 100)
				
				# Get the type of package
				$type = Get-PackageType $ref
				
				#If it's an app
				if($type.type -eq "App") {
					# Get an object representing the app
					#$app = Get-App "CI_UniqueID" $ref.Package
					#log "$($countApp + 1)) $($type.type): $($app._name) ($($app.CI_UniqueID))" -level 1
					
					# Add it to our array
					$appNames += @($ref.Package)
					$countApp += 1
				}
				# If it's not an app
				else {
					# Just log it
					#log "$([char]($countPackage))) $($type.type): $($type.name) ($($ref.Package))" -level 1
					$countPackage += 1
				}
				$progress += 1
			}
		}
		
		$appNames
	}
	
	# Populate each directly-referenced app in the array with its immediate supersedences
	function Get-SuperSedences($apps) {
		$i = 0
		log -blank 1
		foreach($app in $apps) {
			Write-Progress -Activity "Just hold on a minute, jeez..." -Status "Crawling supersedence chain of `"$($app._name)`"..." -PercentComplete (($i / $apps.count) * 100)
			log "Crawling supersedence chain of `"$($app._name)`"..."
			$app._supersedes = Get-Supersedence $app 1
			$i += 1
			log "Done crawling supersedence chain of `"$($app._name)`"..." -debug 1
			log -blank 1 -debug 1
		}
		$apps
	}

	# Recursively populates apps with their supersedences
	# Each app has a property called _supersedes, which is:
	# - empty, for apps which supersede 0 apps
	# - an array of app objects, representing each app which this app supersedes
	# - a single app object (because Powershell is enragingly stubborn and treats single-element arrays as if they were just that single element)
	# - A string equal to $INVALID, for app objects representing invalid references
	# Returns the top level array of supersedences, for use in the _supersedes property of the given directly-referenced app
	function Get-Supersedence($app, $level=0) {
	
		log "Getting supersedence for app: `"$($app._name)`"..." -debug 1 -level $level
		
		if($app._name -ne $INVALID) {
			$app._supersedes = Get-SupersededApps $app -level ($level + 1)
			
			if($app._supersedes -ne $INVALID) {
				if($app._supersedes.count -gt 0) {
					foreach($sApp in $app._supersedes) {
						$sApp._supersedes = Get-Supersedence $sApp -level ($level + 2)
					}
				}
				else {
					log "None" -level ($level + 2) -debug 1
				}
			}
			else {
				log "None because this app is invalid." -level ($level + 1) -debug 1
			}
		}
		log "Done getting supersedence for app: `"$($app._name)`"..." -debug 2 -level $level
		
		$app._supersedes
	}

	# Takes an app object and returns an array of app objects representing its immediately-superseded apps
	# $level is used across various functions just for visual logging indentation purposes
	function Get-SupersededApps($app, $level=0) {
		log "Apps superseded by `"$($app._name)`":" -level $level -debug 1
		
		$sApps = @()
		
		if($app._name -ne $INVALID) {
			# Outsourced getting the IDs of the superseded apps
			$supers = Get-SupersededAppsIDs($app)
			
			$count = 0
			foreach($id in $supers) {
				$sApp = Get-App "ModelName" $id $level
				if($sApp._name -eq $INVALID) {
					log "$($count + 1)) $($sApp._name) ($($sApp.CI_UniqueID))" -level ($level + 1) -debug 1 -red
				}
				else {
					log "$($count + 1)) $($sApp._name) ($($sApp.CI_UniqueID))" -level ($level + 1) -debug 1
				}
				
				$sApps += @($sApp)
				$count += 1
			}
		}
		else {
			$sApps = $INVALID
		}
		
		#log "End of apps superseded by `"$($app._name)`":" -level $level -debug 1
		$sApps
	}

	# Takes an app object, and parses its SDMPackageXML property to pull out the IDs of the apps supersded by the given app
	function Get-SupersededAppsIDs($app) {
		[xml]$xml = $app.SDMPackageXML
		$dtrs = $xml.AppMgmtDigest.DeploymentType.Supersedes.DeploymentTypeRule
		
		$supers = @()
		foreach($dtr in $dtrs) {
			$scope = $dtr.DeploymentTypeIntentExpression.DeploymentTypeApplicationReference.AuthoringScopeId
			$name = $dtr.DeploymentTypeIntentExpression.DeploymentTypeApplicationReference.LogicalName
			$id = "$scope/$name"
			$supers += @($id)
		}
		$supers
	}
	
	# Recursively trolls through the supersedednce chains of the app array and populates each app's _hasInvalid field
	# Just for use in the final "Other relevant info" output
	# Admittedly, this could probably be done during the rest of the processing to avoid iterating through the whole chain again, but it was an afterthought and I can't be bothered to integrate it
	function Get-Invalids($apps) {
		log "Checking for invalid supersedence references..." -debug 1
		$newApps = @()
		foreach ($app in $apps) {
			if(Has-Invalid $app) {
				$app._hasInvalid = $true
			}
			$newApps += @($app)
		}
		log "Done checking for invalid supersedence references." -debug 2
		$newApps
	}

	# The recursive bit of the above Get-Invalids function
	function Has-Invalid($app) {
		$hasInvalid = $false
		if($app._name -ne $INVALID) {
			foreach($sApp in $app._supersedes) {
				if(Has-Invalid $sApp) {
					$hasInvalid = $true
					break
				}
			}
		}
		else {
			$hasInvalid = $true
		}
		$hasInvalid
	}

	# Prints the whole supersedence chain for each of the TS's directly-referenced apps
	function Print-Supersedences($apps) {
		$numInvalid = 0
		
		log -blank 1
		log "Supersedence chains:"
		log "======================================================================================================"
		log -blank 1
		
		foreach ($app in $apps) {
			log "Given ID: `"$($app._givenId)`", Name: `"$($app._name)`", ModelName: ($($app.CI_UniqueID)):" -level 1
			log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -level 1
			log -blank 1
			
			if($app._name -ne $INVALID) {
				log "Supersedence chain:" -level 2
				log "----------------------------------" -level 2
				Print-Supersedence $app -level 2
				log -blank 1
				
				log "Other infos:" -level 2
				log "----------------------------------" -level 2
				log "CIVersion (Revision): `"$($app.CIVersion)`"" -level 2
				log "SDMPackageVersion (?): `"$($app.SDMPackageVersion)`"" -level 2
				log "SourceCIVersion (?): `"$($app.SourceCIVersion)`"" -level 2
				log "AutoInstall (From TS w/o being deployed): `"$($app._auto)`"" -level 2
				$invalidString = "Has an invalid supersedence ref: `"$($app._hasInvalid)`""
				if($app._hasInvalid) {
					log $invalidString -red -level 2
					$numInvalid += 1
				}
				else { log $invalidString -level 2 }
			}				
			else {
				log "This app itself is invalid." -level 2
			}
			log -blank 1
			
			log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -level 1
			log -blank 1
		}
		log "======================================================================================================"
		log -blank 1
		$numInvalidString = "Apps with invalid supersedence references: $numInvalid."
		if($numInvalid -gt 0) { log $numInvalidString -red }
		else { log $numInvalidString }
		log -blank 1
	}

	# The recursive bit of the above function
	function Print-Supersedence($app, $level=0) {
		if(($app._supersedes).count -gt 0) {
			foreach($sApp in $app._supersedes) {
				$string = $BOX_CHAR + $sApp._name
				if($sApp._name -ne $INVALID) {
					log $string -level $level
					Print-Supersedence $sApp -level ($level + 1)
				}
				else {
					log $string -level $level -red
				}
			}
		}
		else {
			$string = $BOX_CHAR + "No superseded apps"
			log $string -level $level
		}
	}
	
	function Exit-Procedure($code) {
		Set-Location $MY_PWD
		throw $code
	}
	
	function Get-AppArray {
		log "Getting list of app names or IDs..."
		$appArray = @()
		
		if($AppNames) {
			log "-AppNames was specified. App names were given as an array." -level 1 -debug 1
			$appArray = $AppNames
		}
		elseif($Collection) {
			log "-Collection was specified." -level 1 -debug 1
			$appArray = Get-CollectionDeployedApps $Collection
		}
		elseif($TS) {
			log "-TS was specified." -level 1 -debug 1
			$appArray = Get-TSReferencedApps $TS
		}
		else {
			log "-AppNames, nor -Collection, nor -TS was specified!" -red -level 1
		}
		
		if(@($appArray).count -gt 0) {
			$appArrayString = $appArray -join "`", `""
			log "`"$appArrayString`"" -level 2
		}
		
		log "Done getting list of app names or IDs." -debug 2
		
		$appArray
	}
	
	function Get-Apps($appArray) {
		log -blank 1
		log "Getting app data..."
		$apps = @()
		
		if($AppNames -or $Collection) {
			foreach($appName in $appArray) {
				log "Getting app data for app: `"$appName`"..." -level 1
				$app = Get-App "LocalizedDisplayName" $appName 1
				$apps += @($app)
				log "Done getting app data for app: `"$appName`"..." -level 1 -debug 2
			}
		}
		elseif($TS) {
			foreach($appRef in $appArray) {
				# This logic would be simpler if we just got the names of the referenced apps,
				# But doing that would require getting the applicaiton information first, which we are going to do later anyway,
				# so we may as well just use the IDs we have to save on Get-CMApplication calls.
				log "Getting app data for app with ModelName: `"$appRef`"..." -level 1
				$app = Get-App "ModelName" $appRef 1
				$apps += @($app)
				log "Done getting app data for app with ModelName: `"$appRef`"..." -level 1 -debug 2
			}
		}
		else {
			log "-AppNames, nor -Collection, nor -TS was specified!" -red
		}
		
		log "Done getting app data." -debug 2
		$apps
	}

	# Do the dew
	function Process {
		log -blank 1
		
		Prep-SCCM
		
		$appArray = Get-AppArray
		if($appArray) {
			$apps = Get-Apps $appArray
			if($apps) {
				$apps = Get-Supersedences $apps
				$apps = Get-Invalids $apps
				Print-Supersedences $apps
			}
			else {
				log "No apps were retrieved!" -red
			}
		}
		else {
			log "No app names were found/retrieved!" -red
		}
		
		Set-Location $MY_PWD
	}

	# -----------------------------------------------------------------
	# Begin
	# -----------------------------------------------------------------

	Process
	
	log "EOF"
}