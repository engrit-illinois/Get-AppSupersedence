# Documentation and home: https://gitlab.engr.illinois.edu/engrit-epm/get-appsupersedence
# By mseng3

function Get-AppSupersedenceByTS {

	# TODO
	# - Find a way to check/validate that valid revision is being used?
	# - Find out if one of the app properties shows the source content revision (which I believe is different than the app revision)?
	# - Count number of unique superseded apps and output with "other info"

	param(
		# Name of Task Sequence
		[Parameter(Mandatory=$true)]
		[string]$TS,
		#[string]$TS="UIUC-ENGR-Basic Win10/7",
		#[string]$TS = "UIUC-ENGR-Basic Apps"
		#[string]$TS = "UIUC-ENGR-Basic Supersedence Script Test"
		#[string]$TS = "UIUC-ENGR-Basic Supersedence Script Test 2"
			
		# Debug output verbosity
		# 0 = Just the intended output
		# 1 = Output from intermediate steps
		# 2 = Output from various minor operations and variable value checks
		[int]$DebugLevel=0,
		
		# Log
		[string]$Log,
		
		# Site code
		[string]$SiteCode="MP0",
		
		# SMS Provider machine name
		[string]$ProviderMachineName="sccmcas.ad.uillinois.edu"
	)


	# -----------------------------------------------------------------
	# Global variables
	# -----------------------------------------------------------------

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

	# -----------------------------------------------------------------
	# Functions
	# -----------------------------------------------------------------

	# Loads the ConfigMgr power shell module, and connects to the Site.
	function Prepare {
		# Customizations
		$initParams = @{}
		#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
		#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

		# Import the ConfigurationManager.psd1 module 
		if((Get-Module ConfigurationManager) -eq $null) {
			Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
		}

		# Connect to the site's drive if it is not already present
		if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
			New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
		}

		# Set the current location to be the site code.
		Set-Location "$($SiteCode):\" @initParams
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
					" " | Out-File $log -Append
				}
			}
		}
		else {	
			if($red) { Write-Host $msg -ForegroundColor "red" }
			else { Write-Host $msg }
			if($Log) {
				"$msg" | Out-File $log -Append
			}
		}
	}
	
	# Gets all info about an app, given its ID
	# Tested with finding by `CI_ID` and `ModelName`.
	# Using other values could result in multiple matches, which would break things
	function Get-App($idType, $id) {
		# Find app using -Fast flag to speed up searching
		log -blank 1 -debug 2
		log "Getting app where `"$idType`" matches `"$id`"..." -debug 2
		$appID = Get-CMApplication -Fast | where { $_.$idType -match $id } | select CI_ID
		
		# If app was found
		if($appID.CI_ID) {
			log "Found app with `"$idType`": `"$id`"." -level 1 -debug 2
			
			# Get full app proerties now that we know which app it is
			log "Getting app properties..." -level 1 -debug 2
			$app = Get-CMApplication -Id $appID.CI_ID
			log "Done." -level 1 -debug 2
			
			log "Parsing app properties..." -level 1 -debug 2
			
			# Determine whether the box is checked for "Allow this application to be installed from the Install Application task sequence action without being deployed"
			$auto = "unknown"
			if($app.SDMPackageXML  -like '*<AutoInstall>true</AutoInstall>*') { $auto = "true" }
			else { $auto = "false" }
			
			# Determine whether the app supersedes other apps
			<#
			$isSuperseding = "unknown"
			if($app.SDMPackageXML  -like '*<Supersedes>*</Supersedes>*') { $isSupersedeing = "true" }
			else { $isSuperseding = "false" }
			#>
			
			# Grab relevant properties, and add custom properties
			$app | Add-Member -NotePropertyName "_name" -NotePropertyValue $app.LocalizedDisplayName # For convenience
			$app | Add-Member -NotePropertyName "_auto" -NotePropertyValue $auto
			#$appFull | Add-Member -NotePropertyName "_isSuperseding" -NotePropertyValue $isSuperseding
			$app | Add-Member -NotePropertyName "_supersedes" -NotePropertyValue @()
			$app | Add-Member -NotePropertyName "_hasInvalid" -NotePropertyValue $false
			$app | Add-Member -NotePropertyName "_supersedenceLength" -NotePropertyValue 0
		}
		# If app was not found
		else {
			log "Did not find app with `"$idType`": `"$id`". This app has probably been deleted but is still being referenced!" -level 1 -debug 2 -red
			
			# Make a dummy app
			log "Filling app properties with `"$INVALID`"..." -level 1 -debug 2
			
			$app = @{
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
		}
		
		log "Done." -level 1 -debug 2
		log -blank 1 -debug 2
		
		# Return app object
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
	
	# Pulls all the references from the given TS, and returns an array of app objects for each reference which refers to an app.
	# References for other types of packages are logged, but otherwise ignored.
	# In the logging, apps are counted with integers, and other packages are counted with letters, to provide an accurate count of apps.
	function Get-TSAppReferences($ts) {
		# Get references
		$tsRefs = Get-CMTaskSequence -Name $ts | Select ReferencesCount,References
		log "Found $($tsRefs.ReferencesCount) references in TS `"$ts`":"
		
		# Array for storing app objects
		$apps = @()
		
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
				$app = Get-App "CI_UniqueID" $ref.Package
				log "$($countApp + 1)) $($type.type): $($app._name) ($($app.CI_UniqueID))" -level 1
				
				# Add it to our array
				$apps += $app
				$countApp += 1
			}
			# If it's not an app
			else {
				# Just log it
				log "$([char]($countPackage))) $($type.type): $($type.name) ($($ref.Package))" -level 1
				$countPackage += 1
			}
			$progress += 1
		}
		
		# Return populated array of app objects
		$apps
	}
	
	# Populate each directly-referenced app in the array with its immediate supersedences
	function Get-SuperSedences($apps) {
		$i = 0
		foreach($app in $apps) {
			Write-Progress -Activity "Just hold on a minute, jeez..." -Status "Crawling supersedence chain of `"$($app._name)`"..." -PercentComplete (($i / $apps.count) * 100)
			log -blank 1
			log "Crawling supersedence chain of `"$($app._name)`"..."
			$app._supersedes = Get-Supersedence $app
			$i += 1
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
		
		if($app._name -ne $INVALID) {
			log -blank 1 -debug 1
			
			$app._supersedes = Get-SupersededApps $app -level $level
			
			if($app._supersedes -ne $INVALID) {
				if($app._supersedes.count -gt 0) {
					foreach($sApp in $app._supersedes) {
						$sApp._supersedes = Get-Supersedence $sApp -level ($level + 1)
					}
				}
				else {
					log "None" -level ($level + 1) -debug 1
				}
			}
			else {
				log "None because this app is invalid." -level ($level + 1) -debug 1
			}
		}
		
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
				$sApp = Get-App "ModelName" $id
				if($sApp._name -eq $INVALID) {
					log "$($count + 1)) $($sApp._name) ($($sApp.CI_UniqueID))" -level ($level + 1) -debug 1 -red
				}
				else {
					log "$($count + 1)) $($sApp._name) ($($sApp.CI_UniqueID))" -level ($level + 1) -debug 1
				}
				
				$sApps += $sApp
				$count += 1
			}
		}
		else {
			$sApps = $INVALID
		}
		
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
			$supers += $id
		}
		$supers
	}
	
	# Recursively trolls through the supersedednce chains of the app array and populates each app's _hasInvalid field
	# Just for use in the final "Other relevant info" output
	# Admittedly, this could probably be done during the rest of the processing to avoid iterating through the whole chain again, but it was an afterthought and I can't be bothered to integrate it
	function Get-Invalids($apps) {
		log -blank 1
		log "Checking for invalid supersedence references..." -debug 1
		$newApps = @()
		foreach ($app in $apps) {
			if(Has-Invalid $app) {
				$app._hasInvalid = $true
			}
			$newApps += $app
		}
		log "Done." -debug 1
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
		log -blank 1
		log "Supersedence chains:"
		log "======================================================================================================"
		log -blank 1
		
		foreach ($app in $apps) {
			log "`"$($app._name)`" ($($app.CI_UniqueID)):" -level 1
			log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -level 1
			log -blank 1
			
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
			if($app._hasInvalid) { log "Has an invalid supersedence ref: `"$($app._hasInvalid)`"" -red -level 2 }
			else { log "Has an invalid supersedence ref: `"$($app._hasInvalid)`"" -level 2 }
			log -blank 1
			
			log "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" -level 1
			log -blank 1
		}
		log "======================================================================================================"
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

	# Do the dew
	function Process {
		Prepare
	
		# Make room so the progress bar doesn't cover anything
		log -blank 5

		log "Crawling supersedence chains for TS `"$ts`"..."
		log -blank 1

		$apps = Get-TSAppReferences $TS

		$apps = Get-Supersedences $apps
		
		$apps = Get-Invalids $apps

		Print-Supersedences $apps

		#Print-OtherInfo $apps
	}

	# -----------------------------------------------------------------
	# Begin
	# -----------------------------------------------------------------

	Process
	
	log "EOF"
}