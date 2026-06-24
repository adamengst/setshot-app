#!/usr/bin/env bash
# setshot
#
# USAGE:
#   ./setshot snapshot [--sudo] [output_file]   # capture current settings
#   ./setshot explain <before> <after>           # human-readable summary (recommended)
#   ./setshot diff <before> <after>              # filtered raw diff
#   ./setshot diff --raw <before> <after>        # unfiltered raw diff
#
# SETUP:
#   chmod +x setshot
#
# For full TCC (privacy permissions) coverage, grant Full Disk Access to SetShot:
#   System Settings > Privacy & Security > Full Disk Access > enable SetShot
#
# --sudo captures additional root-owned settings:
#   Night Shift    (/Library/Preferences/com.apple.CoreBrightness.plist)
#   Wi-Fi networks (/private/var/preferences/com.apple.wifi.known-networks.plist)
#   SMAppService login items (/var/db/com.apple.xpc.launchd/)
#
# Output is one line per setting:  DOMAIN :: key.subkey = value
#
# Binary data blobs (NSKeyedArchiver, base64-embedded plists, etc.) are decoded
# recursively so their contents appear as normal key = value lines.
#
# The default diff mode filters out known-noisy keys (timestamps, counters,
# CloudKit cache churn, window geometry, nav panel state, activity scheduling,
# app telemetry). Use --raw to see everything.

SCRIPT_NAME="$(basename "$0")"

# ── Plist flattener ───────────────────────────────────────────────────────────
# Reads a plist from stdin (binary or XML), emits one "key = value" line per
# leaf node. Implemented in the SetShot binary (--flatten-plist) to avoid any
# dependency on python3, which is a CLT stub on clean macOS installs.
#
# SETSHOT_BIN is injected by SnapshotRunner.swift when run from the app.
# It is validated here; if absent or not executable, _flatten_plist_stdin is a no-op.
if [ -z "${SETSHOT_BIN:-}" ] || [ ! -x "$SETSHOT_BIN" ]; then
  SETSHOT_BIN=""
  # When run standalone (not injected by the app), try standard install locations.
  for _candidate in \
    "/Applications/SetShot.app/Contents/MacOS/SetShot" \
    "$HOME/Applications/SetShot.app/Contents/MacOS/SetShot"; do
    if [ -x "$_candidate" ]; then SETSHOT_BIN="$_candidate"; break; fi
  done
fi

_flatten_plist_stdin() {
  if [ -n "$SETSHOT_BIN" ]; then
    "$SETSHOT_BIN" --flatten-plist 2>/dev/null
  fi
  # If SETSHOT_BIN is unavailable, silently produce no output.
  # This is intentional: running setshot.sh standalone outside the app
  # bundle is unsupported on clean macOS without CLT.
}

# ── Human-readable explainer ─────────────────────────────────────────────────
# Reads filtered diff lines from stdin, translates known keys to plain English,
# and prints a tidy summary. Unknown changes are shown in a compact raw section.


# ── Noise filter ──────────────────────────────────────────────────────────────
# Applied to diff output by default. Suppresses keys that change constantly
# regardless of user action: timestamps, counters, CloudKit cache churn,
# window geometry, nav panel state, activity scheduling, and app telemetry.
#
# Patterns are matched against the full diff line. Both sides of a changed
# pair will match the same key name, so neither orphaned + nor - lines remain.

NOISE_PATTERN='(
  ^[-+]Date:\s|
  ^[-+]Snapshot complete:|
  ^[-+]Mode:\s|
  ^[-+]#{5}|

  xpc\.activity2\.plist ::|

  :: .*CloudKitAccountInfoCache\.|
  :: .*AccountInfoValidationCounter\s*=|
  :: .*ActivityBaseDates\.|
  :: .*\.NS\.time\s*=|
  :: .*SULastCheckTime\s*=|
  :: .*update\.check\.timestamp\s*=|
  :: .*AVTSyncImportDate\s*=|
  :: .*OwnedDeviceLastPublish|
  :: .*websocketServer_last|
  :: .*checkedHLSKeysTime\s*=|
  :: .*refreshedHLSKeysTime\s*=|
  :: .*LicenseExec[A-Za-z]*\s*=|
  :: .*segment\.events\s*=|
  :: .*last-usage-report|
  :: .*SDXInstallerLast|
  :: .*\.LastUpdateTime\s*=|
  :: .*_DKThrottledActivityLast|
  :: .*update-state-indexing|
  \.appPID\s*=|
  :: .*lastAccountSettingsResponse|
  :: .*lastOAuth[0-9]*Token|
  :: .*lastSuccessfulAuthorization|
  :: .*lastDialectCheckDate\s*=|
  :: .*treatments\.lastUpdateDate\s*=|
  :: .*DiagnosticCache\.|
  :: .*diagnosticData\s*=|

  :: .*NSWindow Frame |
  :: .*NSWindow.*Size\s*=|
  NSTableView Columns|
  NSServices\.CF|
  browser\.column\.|
  :: .*NSNavLastRootDirectory\s*=|
  :: .*NSNavPanelExpandedState|
  :: .*NSNavRecentPlace|
  :: .*NSNavPanel.*Size|
  :: .*NSRecentDocumentRecords\s*=|
  :: .*recentSearchStrings\s*=|

  :: .*SULastVersion\s*=|
  :: .*SUHasLaunchedBefore\s*=|
  :: .*lastWhatsNewVersion\s*=|
  :: .*LastWhatsNew[A-Za-z]*\s*=|

  :: .*ABBookLastSyncedDeviceToken\s*=|
  :: .*AppBadgeCount\s*=|
  :: .*BadgeCount\s*=|
  :: .*DateLastCheckedIn\s*=|
  :: .*lastCloudSyncTimestamp|
  :: .*lastPublishTime\s*=|
  :: .*lastRunTimeStamp\s*=|
  :: .*serviceStartCount\s*=|
  :: .*AMSDeviceBiometricsState\s*=|
  SpotlightKnowledgeV2\.stats\[|
  com\.apple\.biometrickitd\.plist ::|
  com\.apple\.mmcs\.plist ::|
  com\.apple\.sociallayerd\.|
  AOSKit\.RegInfo\.|
  \.gamed\.plist ::|
  Game-Center-Settings|
  identityservicesd\.plist ::|
  :: Suggestions[\._#]|
  -lastAppUpdateCheckDate\s*=|
  -lastUpdateCheckDate\s*=|
  \.imessage\.bag\.plist ::|
  :: PHS Asset Manifest.*modificationDate\s*=|
  :: apps\[[0-9]+\]\.src\[|
  :: [0-9]+-Last[A-Za-z]*Date\s*=|
  :: [0-9]+-Last[A-Za-z]*Time\s*=|
  \.itunescloudd\.plist ::|
  NSPServiceStatusManagerInfo\.\$top\.|
  NSPServiceStatusManagerInfo\.\$objects\[|
  :: CheckUpdateTimestamp\s*=|
  :: LastFullSuccessfulDate\s*=|
  :: LastSuccessfulDate\s*=|
  :: DDMPersistedErrorKey\.|
  AccessibilityHearingNearby|
  \.amsengagementd\.plist ::|
  \.AdPlatforms\.plist ::|
  :: TTSSynthesisProviderCachedComponentsKey\.\$objects\[|
  :: donate\.reminder\.|
  ch\.sudo\.cyberduck :: uses\s*=|
  :: UserInfo\.com\.apple\.MobileAsset\.|
  systemsettings\.extensions[^:]*:: LastIndexed\.|
  systemsettings\.extensions[^:]*:: current_state\.|
  DevSupportSizer\.|
  :: NSOSPRecentPlaces\[|
  :: AMSFPCertExpiration\s*=|
  :: .*Validation Expiration\s*=|
  :: WebsiteNameProviderLastUpdateTime\s*=|
  :: CKStartupTime\s*=|
  :: CKPerBootTasks\[|
  CloudSubscriptionFeatures\.[a-zA-Z]*[Cc]ache\.plist ::|
  \.facetime\.bag\.plist ::|
  \.FamilyCircle\.plist ::|
  windowserver\.displays.*:: .*\.(CurrentInfo|UnmirrorInfo)\.|
  windowserver\.displays.*:: .*DefaultConfigVersion\s*=|
  dt\.Xcode\.plist :: IDEAnalytics|
  dt\.Xcode\.plist :: IDEAppStatistics|
  dt\.Xcode\.plist :: IDERecentEditorDocuments\[|
  dt\.Xcode\.plist :: IDESwiftPackage|
  :: closeViewZoomedIn\s*=|
  :: userAccessCode\s*=|
  :: RecentMoveAndCopyDestinations\[|
  inputAnalytics\.|
  GenerativeFunctions\.|
  searchpartyuseragent\.plist ::|
  AutoWake\.plist ::|
  org\.cups\.printers\.plist ::|
  Maps\.mapssyncd\.plist ::|
  \.mediaanalysisd\.plist ::|
  \.mlhost\.plist ::|
  \.mobiletimerd\.plist :: MTAlarm|
  \.passd[^/]*\.plist ::|
  \.people\.plist :: widgetSuggestion|
  :: lastHighlightTitlesUpdateDate\s*=|
  :: lastRecentHighlightUpdateDate\s*=|
  \.privatecloudcomputed\.plist ::|
  PersonalizationPortrait\.plist ::|
  wifi\.message-tracer\.plist ::|
  :: NSPLastGeohash\s*=|
  NSPSignatureInfo\.\$objects\[|
  :: MeCard.*Version\s*=|
  :: NicknameActiveListVersion\s*=|
  :: sidebarItemInfo\.|
  :: volumeWSG\s*=|
  autoupdate.*:: .*Volumes|
  \.itunescloud[^/d]*\.plist ::|
  quicklook\.ThumbnailsAgent\.plist ::|
  \.rapport\.plist ::|
  Safari\.PasswordBreachAgent\.plist ::|
  Safari\.SafeBrowsing\.plist ::|
  screencapture.*\.plist :: last-analytics|
  :: HashManager-Last|
  siri\.DialogEngine\.plist ::|
  PropertyStore-1\.1\.plist ::|
  cloud\.quota\.plist ::|
  \.biomesyncd\.plist ::|
  CallHistorySyncHelper\.plist ::|
  \.chronod\.plist :: NetworkEnabledAfterBootNotification\.|
  \.chronod\.plist :: extensionsPendingDescriptorRefetch\[|
  \.chronod\.plist :: hasMigratedRemoteWidgetsEnabledState\s*=|
  \.chronod\.plist :: hasRemoteWidgets\s*=|
  \.chronod\.plist :: lastEffectiveSignificantTimeChange\s*=|
  \.chronod\.plist :: lastKnownTimes\.|
  \.chronod\.plist :: migrationState\s*=|
  \.chronod\.plist :: effectiveRemoteWidgetsEnabled\s*=|
  \.cseventlistener\.plist ::|
  AssetMetricsWorker\.plist ::|
  \.tipsd\.plist ::|
  DataDeliveryServices\.plist ::|
  coreservices\.useractivityd[^/]*:: kLocalPasteboardBlobName\s*=|
  coreservices\.useractivityd[^/]*:: kRemotePasteboardBlobName\s*=|
  captive\.plist :: WISPrAccounts\.|
  :: SpotlightKnowledgeV2\.|
  :: IDE_CA_Daily_|
  :: RegisteredBooks\.|
  :: RegistrationOrder\[|
  :: UserDismissedLimitedNetworkFirstJoins\.|
  :: personalMediaEnabledByRouteUID\.|
  :: activeHearingProtectionEnabled\.|
  audio\.SystemSettings\.plist :: device\.|
  :: HostMetadata\.|
  \.storage\.oai\.plist ::|
  app-setapp\.plist :: mediaHistory\s*=|
  Microsoft AutoUpdate.*:: .*[/\\]Volumes[/\\]|
  :: .*accessToken\s*=|
  :: usage-report-upload-failure|
  :: LastHeartbeatDateString\.|
  :: NSStatusItem Visible|
  :: recent-apps\[|
  \.cyberduck\.plist :: uses\s*=|
  \.cyberduck\.plist :: donate\.|
  DevCachesSizer\.|
  public-sharing-settings\.|
  :: LastIMDNotification|
  :: VCLSDataSequenceKey\s*=|
  :: batchNumber\s*=|
  \.domainscache\.plist ::|
  :: mod-count\s*=|
  CalContactsProviderHistoryToken\.|
  kCDIntentDeletionContactStoreChangeHistoryToken\.|
  HashManager-LastConsumedHistoryTokenKey\.|
  ContactsChangeHistoryToken\.|
  :: UserInfo\.com\.apple\.MobileAsset\.TTSAX|
  :: FXRecentFolders\[|
  com\.apple\.screensaver[^:]*:: moduleDict\.path\s*=|

  com\.apple\.DuetExpertCenter\.|
  :: Workaround_[0-9]+\s*=|
  :: .*assertionCookie\s*=|
  :: .*recentPanes|
  :: CurrentExtensionURL\s*=|
  com\.apple\.networkextension\.uuidcache\.|
  com\.apple\.networkextension\.plist :: \$objects\[|
  com\.apple\.networkextension\.plist :: \$top\.Generation\s*=|
  drop_all_feature_content_filter\s*=|
  _errorGenerationCount\s*=|
  CloudKitLastSyncSinceInternetReachable\s*=|
  launchDarkly\.|
  NSLinguisticDataAssetsRequestTime\s*=|
  CommCenterStartsThisBoot\s*=|
  LastCheckForExpiringProfiles\s*=|
  TALAppsToRelaunchAtLogin|
  NSPProxyAgentManagerPreferences\.\$objects\[|
  UpdateInfo\.[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]|
  com\.apple\.madrid\.|
  com\.apple\.appstored\.|
  LocalDBStats\.|
  lastUsedSettingsPref\.|
  com\.apple\.commcenter\.|
  com\.apple\.print\.custompresets\.|
  RefreshEvents\.com\.apple\.MobileAsset\.|
  SpacesDisplayConfiguration\.|
  AllCachedAvailableResourcesKey\.|
  accountsListCategorizedCountsCache\.|
  PrivacyProxyAppStatus\s*=|
  PrivacyProxyNetworkStatus|
  PrivacyProxyServiceStatus(Start|End)Date\s*=|
  com\.apple\.remindd\.plist ::|
  corespotlightui\.plist :: lastVisible|
  corespotlightui\.plist :: lastWindow|
  StatusKitAgent\.plist ::|
  StorageManagement\.Service\.plist ::|
  textInput\.keyboardServices\.textReplacement\.plist ::|
  translationd\.plist ::|
  :: NSSplitView Subview Frames|
  :: NSOSPLastRootDirectory\s*=|
  :: AirplayReceiverAdvertising\s*=|
  :: last-analytics-stamp|
  :: closeViewZoomFactor\s*=|
  :: closeViewZoomFactorBeforeTermination\s*=|
  :: UMfailureCount\s*=|
  :: DejalStats|
  grammarly\.|
  autoupdate\.fba\.plist ::|
  autoupdate.*:: LastUpdate\s*=|
  autoupdate.*:: Applications\.|
  autoupdate.*:: ApplicationsSystem\.|

  :: ODDI.*\.\$objects\[|
  :: .*deviceexperimentmetrics\.\$objects\[|
  :: .*digestmetrics\.\$objects\[|
  :: .*cohortmetrics\.\$objects\[|

  :: lastVisibleScreenRect\s*=|
  :: lastWindowPosition\s*=|

  :: .*Statsig\.|
  :: .*_analytics_last_sent\s*=|
  :: lastNotificationSettingsResponse|
  :: lastSelectedConversation\s*=|
  :: sentryTracingConfiguration\s*=|
  :: amplitudePulse|
  :: SuppressUpdatesAvailableUserNotification|
  :: superCopyUpsellLastSeen\s*=|
  :: unwrite_access_token\s*=|
  :: unwrite_refresh_token|
  :: unwrite_token_expiry\s*=|
  thebrowser\.[^:]*:: ModalWindowController_rect|
  thebrowser\.[^:]*:: SidebarAnalytics\.|
  keyboardmaestro\.[^:]*:: SIVC|
  keyboardmaestro.*:: MacroHistorySavedHistory\[|
  keyboardmaestro.*editor.*:: MacrosWindowControllerSettings\[|
  keyboardmaestro.*:: .*\.MacroHistory\.|
  keyboardmaestro.*:: .*\.Selection\.Selected|
  keyboardmaestro.*:: .*\.Selection\.MacrosViewList|
  keyboardmaestro.*:: .*WindowPositionAndSize\s*=|
  diagnostics.agent[^:]*::|
  familycircled[^:]*::|
  powerlogd[^:]*::|
  searchpartyd.*:: SPBeacon|
  \.gms\.availability|
  speakerrecognition[^:]*::|
  :: Accounts\.[A-Za-z0-9-]+\.|
  :: MultiUser Shared Data|
  commcenter.runtime.storage[^:]*::|
  FontRegistry.*:: LastUpdated|
  :: apps\[[0-9]+\]\.flags\s*=|
  usernotificationskit[^:]*:: OnboardingLastShown|
  :: FirstOfferDateDictionary\.|
  :: RecommendedUpdates\[|
  CloudSubscriptionFeatures\.optIn|
  :: AppleSymbolicHotKeys\.[0-9]+\.value\.type|
  :: NSStatusItem Preferred Position|
  :: LastBackgroundSuccessfulDate\s*=|
  :: LastSuccessfulBackground[A-Za-z]*Date\s*=|
  :: PrivateMACAddressRotationKeyTimestamp\s*=|
  :: Accounts\[[0-9]+\]\.Services\[[0-9]+\]\.|
  :: orderedItems\[[0-9]+\]\.enabled\s*=|
  app-setapp.*:: IKEvents|
  :: ComputerPrefsLastRemovedDate|
  :: SoundTab\s*=|
  weather\.sensitive[^:]*::|
  hourly_forecasts[^/]*\.plist ::|
  daily_forecasts[^/]*\.plist ::|
  historical_data[^/]*\.plist ::|
  almanac_data[^/]*\.plist ::|
  wug_locations[^/]*\.plist ::|
  current_conditions[^/]*\.plist ::|
  group\.com\.apple\.tv[^:]*::|
  \.com\.apple\.containermanagerd\.metadata[^:]*::|
  com\.apple\.homed[^:]*::|
  homed\.notbackedup[^:]*::|
  swtransparency[^:]*::|
  com\.apple\.transparency[^:]*::|
  tipsnext[^:]*::|
  ScreenCaptureApprovals[^:]*::|
  messages\.pinning[^:]*::|
  TCC-user ::|
  TCC-system ::|
  com\.apple\.MobileSMS[^:]*::|
  TimeMachine.*:: Destinations\[|
  TimeMachine.*:: BackupAlias|
  TimeMachine.*:: LastConfigurationTraceDate|
  TimeMachine.*:: NetBootClientInfo|
  TimeMachine.*:: SkipPaths\[|
  TimeMachine.*:: ExcludeByPath\[|
  TimeMachine.*:: HealthCheck|
  TimeMachine.*:: Snapshot|
  TimeMachine.*:: Result\s*=|
  TimeMachine.*:: ExcludedVolumeUUIDs\[|
  TimeMachine.*:: HostUUIDs\[|
  TimeMachine.*:: LastBackupActivity|
  TimeMachine.*:: LastDestinationID|
  TimeMachine.*:: PreferencesVersion|
  PegasusConfiguration[^:]*::|
  group\.com\.apple\.calendar[^:]*::|
  AppleIntelligenceReport[^:]*::|
  :: adprivacyd|
  :: Sig_AppleLocale\s*=|
  :: Sig_AppleLanguages\s*=|
  iCal.*:: BirthdayEvents|
  iCal.*:: NotificationsLastLocale|
  com\.apple\.dock.*:: region\s*=|
  mediasharingd.*:: home-sharing-computer-id|
  mediasharingd.*:: home-sharing-group-id|
  mediasharingd.*:: home-sharing-settings\.home-sharing-user-id|
  mediasharingd.*:: home-sharing-settings\.home-sharing-user-name|
  mediasharingd.*:: photo-sharing-settings\.|
  ncprefs.*:: apps\[|
  GlobalPreferences.*:: com\.apple\.finder\.SyncExtensions\.dirMap\.|
  NewDeviceOutreach[^:]*::|
  :: ForceClickSavedState\s*=|
  softwareupdate.*:: ProductKeysLastSeenByUser\[|
  ReportCrash.*:: TrialCache\.|
  settings\.Storage[^:]*::|
  sharingd.*:: AutoUnlockLastSeenVersion\s*=|
  sharingd.*:: AutoUnlockLastSeenWatchDate\s*=|
  sharingd.*:: AutoUnlockWatchCurrentlyInList\s*=|
  TextUnderstandingObserver.*:: deletionStreamBookmark\s*=|
  sharingd.*:: AppleIDAgentMetaInfo\.\$objects\[|
  sharingd.*:: SDAirDrop.*Date\s*=|
  icloudmailagent.*::|
  AMPLibraryAgent[^:]*::|
  ARDAgent.*:: ARDAdmin_AppStoreURL\s*=|
  ARDAgent.*:: Version\s*=|
  AssetCache.*:: LastConfig|
  AssetCache.*:: LastPort\s*=|
  AssetCache.*:: LastRegOrFlush\s*=|
  AssetCache.*:: Region\s*=|
  AssetCache.*:: SavedCacheSize\s*=|
  AssetCache.*:: SavedCacheDetails\.|
  AssetCache.*:: ListenWithPeersAndParents\s*=|
  AssetCache.*:: LocalSubnetsOnly\s*=|
  AssetCache.*:: PeerLocalSubnetsOnly\s*=|
  AssetCache.*:: Port\s*=|
  AssetCache.*:: ReservedVolumeSpace\s*=|
  AssetCache.*:: ServerGUID\s*=|
  AssetCache.*:: Version\s*=|
  bluetooth.*:: BluetoothAutoSeek|
  RemoteDesktop.*:: RSAKeySize\s*=|
  RemoteManagement.*:: allowInsecureDH\s*=|
  nat.*:: NAT\.AirPort\.|
  nat.*:: NAT\.PrimaryInterface\.Device\s*=|
  nat.*:: NAT\.PrimaryInterface\.Enabled\s*=|
  nat.*:: NAT\.PrimaryInterface\.HardwareKey\s*=|
  nat.*:: NAT\.SharingNetwork|
  nat.*:: NAT\.NatPortMapDisabled\s*=|
  nat.*:: NAT\.PrimaryService\s*=|
  pbs[^:]*:: FinderActive\.|
  bird[^:]*::|
  finder.*:: TagsCloudSerialNumber\s*=|
  finder.*:: NewWindowTargetPath\s*=|
  finder.*:: [A-Za-z]+ViewSettings\.|
  finder.*:: FXRecentFolders\[|
  finder.*:: FXInfoPanesExpanded\.|
  finder.*:: FXPreferencesWindow\.|
  finder.*:: PreferencesWindow\.LastSelection\s*=|
  finder.*:: WindowBounds\s*=|
  finder.*:: Bulk[A-Za-z]+\s*=|
  finder.*:: DataSeparatedDisplayNameCache\s*=|
  finder.*:: CopyProgressWindowLocation\s*=|
  universalaccess.*:: cursorFill\.|
  universalaccess.*:: cursorOutline\.|
  :: NSColorPanel|
  :: NSToolbar Configuration|
  :: SpokenContentDefaultVoiceSelections|
  universalaccess.*:: grayscaleMigrated\s*=|
  universalaccess.*:: hoverTextIsHoveringAndVisible\s*=|
  universalaccess.*:: hoverTextTypingWindowPosition\s*=|
  universalaccess.*:: hoverTypingFontStyle\s*=|
  universalaccess.*:: History\.MouseKeys\[|
  :: VoiceOverTouchLanguageRotor\[|
  universalaccess.*:: closeViewZoom|
  universalaccess.*:: FontSizeCategory\.|
  universalaccess.*:: sessionChange\s*=|
  universalaccess.*:: login\s*=|
  universalaccess.*:: hudNotified|
  :: BrailleInputDeviceConnected\s*=|
  :: PrefersHorizontalText\s*=|
  :: GenericAccessibilityClientEnabled\s*=|
  :: AutomationEnabled\s*=|
  :: ApplicationAccessibilityEnabled\s*=|
  :: AccessibilityEnabled\s*=|
  :: com\.apple\.accessibility\.AirPods|
  universalaccess.*:: com\.apple\.custommenu\.|
  AMSSamplingSession|
  Passwords.*:: WBS[A-Za-z]+\s*=|
  Passwords.*:: dateOfLast|
  Spotlight.*:: startTime\s*=|
  sirisuggestions.*:: indexVersionLastBuiltTime\.|
  fileproviderd.*:: iCDPackageExtensions\[|
  speech\.recognition.*:: VisibleNetworkSRLocaleIdentifiers|
  :: PKOrderManagementDisabled\s*=|
  :: TISRomanSwitchState\s*=|
  Wallet.*:: PKSafariCredentialProvisioningConsented\s*=|
  :: AppleGlobalTextInputProperties\.|
  :: AppleEnabledInputSources\[[0-9]+\]\.InputSourceKind\s*=|
  :: AppleEnabledInputSources\[[0-9]+\]\.KeyboardLayout ID\s*=|
  :: AppleSymbolicHotKeys\.[0-9]+\.enabled\s*=|
  :: AppleSymbolicHotKeys\.[0-9]+\.value\.parameters\[|
  :: NSLinguisticDataAssetsRequested\[[0-9]+\]\s*=|
  :: NSLinguisticDataAssetsRequestTime\s*=|
  :: com\.apple\.trackpad\.trackpadCornerClickBehavior\s*=|
  :: ContextMenuGesture\s*=|
  Keyboard-Settings.*:: WebKitUseSystemAppearance\s*=|
  wpc\.energyservices.*::|
  noticeboard.*:: LastNoticeboardCatalogCheck\s*=|
  Accessibility\.Assets.*:: RefreshEvents\.|
  Accessibility\.Assets.*:: UserInfo\..*\.Date\s*=|
  configurationprofiles.*:: Workaround_|
  PersonalAudio.*::|
  ComfortSounds.*:: ComfortSoundsSelectedSound\.\$objects\[0|
  ComfortSounds.*:: ComfortSoundsSelectedSound\.\$objects\[1|
  ComfortSounds.*:: ComfortSoundsSelectedSound\.\$objects\[[3-9]|
  ComfortSounds.*:: ComfortSoundsSelectedSound\.\$objects\[2[0-9]|
  ComfortSounds.*:: ComfortSoundsSelectedSound\.\$objects\[3[0-9]|
  ComfortSounds.*:: ComfortSoundsSelectedSound\.\$objects\[2\]\.|

  EmojiPreferences.*:: EMFDefaultsKey\.|
  CharacterPaletteIM.*:: CVPerProcessWindowState\.|
  finder.*:: FXLastSearchScope\s*=|
  finder.*:: SGTRecentFileSearches\[|
  HIToolbox.*:: AppleSelectedInputSources\[|
  HIToolbox.*:: AppleSavedCurrentInputSource\.|
  HIToolbox.*:: AppleInputSourceHistory\[|
  :: AppleEnabledInputSources\[[0-9]+\]\.KeyboardLayout Name\s*=|
  donotdisturbd.*:: DNDSModeConfigurationsContactHistoryToken\.|
  [Aa]pp[Ss]tore.*:: lastBootstrapDate\s*=|
  [Aa]pp[Ss]tore.*:: mostRecentTabIdentifier\s*=|
  app\.eyesoff.*:: SULast|
  speech\.recognition.*:: DictationIMCommandCounts\.|
  speech\.recognition.*:: DictationIMLast|
  speech\.recognition.*:: DictationIMMessage|
  speech\.recognition.*:: DictationIMUseOnlyOfflineDictation\s*=|
  stickersd.*::|
  studentd.*:: LastDateProviderSessionToken\s*=|
  talagent.*:: LastKeyChange\s*=|
  Wallet.*:: PKLastProductCacheUpdateTimestampKey\s*=|
  thebrowser.*:: mostRecentUpdateDownloadTime\s*=|
  thebrowser.*:: LittleBrowserWindow|
  us\.zoom.*:: ZMDisplayNav|
  us\.zoom.*:: ZMJoinMeetingFlowAnchor\s*=|
  us\.zoom.*:: .*Date\s*=|
  573518.*:: RecentlySearchedItems\[|
  :: SKDUserDefaultsRoot\.SKDUserDefaultsMap\.|
  TokenBucketRateLimiter[^:]*::|
  wallpaper\.aerial.*:: remoteResourceExpiration|
  :: AirDropID\s*=|
  corespotlightui.*:: CSReceiverBundleIdentifierState\.|
  AddressBook.*:: ABMetaDataChangeCount\s*=|
  jetpackassetd[^:]*::|
  unilog\.[^:]*::|
  :: AttentionPrefBundleIDs\.|
  wifi.*:: wifi\.network\.ssid\..*\.CaptiveProfile\.|
  wifi.*:: wifi\.network\.ssid\..*\.SSID\s*=|
  wifi.*:: wifi\.network\.ssid\..*\.SupportedSecurityTypes\s*=|
  wifi.*:: wifi\.network\.ssid\..*\.RemovedAt\s*=|
  findmy.*:: DataManager::|
  com\.tidbits\.setshot|
  :: displaysLastCursorLocation\.|
  :: closeViewCustomHotkeyKey\.|
  IMCoreSpotlight.*:: .*\.\$objects\[|
  :: NSNavPanelFileLastListMode|
  :: NSNavPanelFileListMode|
  :: NavPanelFileListMode|
  :: NSLinguisticDataAssetsRequestedByChecker\[|

  :: restoreTrueToneEnabled\s*=|
  :: HearingFeatureUsagePreference\s*=|
  ComfortSounds.*:: timerEndInterval\s*=|
  ComfortSounds.*:: activeTimerEndTimeStamp\s*=|
  ComfortSounds.*:: lastEnablementTimestamp\s*=|
  Accessibility.*:: NameRecognitionUserNeedsDefaultEnglishLocale|
  :: AXSAirPodsNoiseCancellationWithOneUnit\.|
  :: AirPodsHoldDurationPreference\.|
  :: AirPodsTapSpeedPreference\.|
  :: com\.apple\.accessibility\.AirPods|
  :: AccessibilityReaderHotkey\.[A-Z_]+\.(charCode|keyCode|modifiers)\s*=|
  DictionaryServices.*:: DCSActiveDictionaries\[|
  iCal.*:: CalUICanvasOccurrenceFontSize\s*=|
  speech\.recognition.*:: CACLabelFontSize\s*=|
  info\.eurocomp\.Timing|
  speech\.recognition.*:: DictationIMTargetApplications\[|
  SpeechRecognitionCore.*:: CACVocabularyEntries\[|
  speech\.recognition.*:: CACVocabularyEntries\[|
  speech\.recognition.*CustomCommands[^:]*::|
  :: PersistentHistoryProcessingDates\.|
  :: axShortcutExposedFeatures\.|
  :: SCLaunchedAsSlave\s*=|
  :: scrollBarOverrideIdentifiers\[|
  :: scrollBarOverrideOriginalValue\s*=|
  :: AppleEnabledInputSources\[[0-9]+\]\.Bundle ID\s*=|
  :: CACPersistentSleepState\s*=|
  :: CACUserHintsFeatures\s*=|
  :: PreferencesLastLoadedOn\.|
  :: AssistiveControlType\s*=|
  :: switchInputs\.|
  :: keyboardAccessPassthroughMode\s*=|
  :: switchHoldBeforeRepeatDuration\s*=|
  :: systemTranscriptionTranscriptionViewFont\.|
  :: closeViewWindowPosition\.|
  :: closeViewWindowSize\.|
  :: lastNightShiftDate\s*=|
  :: lastNightShiftMode\s*=|
  cloudphotod.*:: CPLResetReasons\[|
  :: FFStorage\.|
  setapp.*:: known_environments\[|
  app-setapp.*:: known_environments\[|
  setapp.*:: known_customers\[|
  :: AvatarCacheIndex\[|
  AvatarCacheIndex[^:]*::|
  :: _TestCanary\s*=|
  :: ACDMonthlyAnalyticsLastPosted\s*=|
  :: AKDeviceUnlockState\s*=|
  :: AppleLanguagesDidMigrate\s*=|
  :: com\.apple\.finder\.SyncExtensions\.collaborationMap\.|
  :: com\.maintain\.cocktail|
  :: BugsnagUserUserId\s*=|
  :: SUEnableAutomaticChecks\s*=|
  :: SUSendProfileInfo\s*=|
  :: SUUpdateGroupIdentifier\s*=|
  :: hasAppManagementPermission\s*=|
  :: hasCompletedWelcomeTour\s*=|
  :: termsAcceptedVersion\s*=|
  :: termsAndPrivacyAccepted\s*=|
  :: welcomeTourCompletedVersion\s*=|
  app\.updatest\.[^:]*::|
  ChatGPTHelper[^:]*::|
  AtlasUpdateHelper[^:]*::|
  Accessibility\.Assets[^:]*:: InstalledAssets\.|
  :: [0-9A-Fa-f]{8}_[0-9A-Fa-f]{8}_|
  accounts\.suggestions[^:]*:: LocalDeviceID\s*=|
  accountsd[^:]*:: LastSystemVersion\s*=|
  ActivityMonitor[^:]*:: Column Width\.|
  ActivityMonitor[^:]*:: UserColumnSortPerTab\.|
  APFSUserAgent[^:]*:: LastBootUUID\s*=|
  :: AMSFraudReportLastStateCleanupDate\s*=|
  :: AMSJSVersionMap\.|
  mediasharingd.*:: home-sharing-sequence-id\s*=|
  mediasharingd.*:: shared-library-id\s*=|
  mediasharingd.*:: shared-library-machine-id\s*=|
  AOSPushRelay[^:]*::|
  :: IRServiceToken\.|
  identityservicesd[^:]*:: CheckedDuplicatedUniqueID\s*=|
  imservice\.[^:]*:: ActiveAccounts\[|
  imservice\.[^:]*:: OnlineAccounts\[|
  ManagedClient[^:]*:: MigratedShareKitPayloads\s*=|
  :: airplay :: cloudLibraryIsOn\s*=|
  Control\ Center.*:: Siri\s*=|
  ai\.perplexity\.[^:]*:: LastRunAppBundlePath\s*=|

  \.\$class\s*=|
  \.\$classes\[|
  \.\$classname\s*=|
  \.\$top\.[A-Za-z]+ = <UID|
  \.NS\.objects\[[0-9]+\] = <UID|
  = <UID [0-9]+>$|
  :: NSPConfiguration\.\$objects\[|

  settings\.storage.*:: AppsSizer\.|
  settings\.storage.*:: TrashSizer\.|
  AuthKit.*:: time(Config|Cfg)\.\$|
  businessservicesd.*:: BCS|
  controlcenter.*:: LastPeriodicAnalyticsPostDate\s*=|
  Messages.*:: lastCoolOffDate\s*=|
  wallpaper\.aerial.*:: scheduledUpdateDate\s*=|
  ExternalObjects.*:: databases\.|
  WidgetConfigurations.*:: entries\[[0-9]+\]\.date\s*=|
  AddressBook.*::|
  TimeMachine.*:: AlwaysShowDeletedBackupsWarning\s*=|
  TimeMachine.*:: IncludeByPath\[|
  TimeMachine.*:: LastCompactTime\s*=|
  TimeMachine.*:: LocalizedDiskImageVolumeName\s*=|
  TimeMachine.*:: SkipSystemFiles\s*=|
  airport.*:: Counter\s*=|
  airport.*:: DeviceUUID\s*=|
  airport.*:: JoinModeFallback\[|
  airport.*:: PrivateMACAddressDeviceKey\s*=|
  airport.*:: PrivateMACAddressRotationKey\s*=|
  airport.*:: Version\s*=|
  RPIdentitySyncCache.*::|
  BDSICloudIdentityToken.*::|
  timemachine.*:: LastNotificationDates\.|
  ExternalObjects.*:: account:\[|
  appleintelligencereporting.*::|
  personalizationportrait.*::|
  suggestions.*TextUnderstanding.*::|
  textunderstanding\.runtime.*::|
  networkd\.networknomicon.*::|
  networkd.*:: pqtls_probe_enabled\s*=|
  ExternalObjects.*:: contact:|
  imagent.*:: SpotlightPersistentTask|
  seserviced.*::|
  thebrowser.*:: KronosStableTime\.|
  gridDataServices.*::|
  Spotlight.*:: engagementCount|
  siri.*:: WFSync.*Date\s*=|
  siri.*:: numAppInstalls|
  Terminal.*:: LastTerminalStartTime\s*=|
  powerlogHelperd.*:: BootSessionUUID\s*=|
  preferences\.sharing.*:: LocalChanged\s*=|
  :: LastResultCode\s*=|
  flexibits.*::|
  backgroundassets.*:: .*LastWeekly|
  appleaccount.*:: .*[Bb]oot[Ss]ession|
  IMCoreSpotlight.*:: IMCSLast|
  LaunchServices.*:: LSHandlers\[|
  itunesstored.*:: AuthenticationStarted\s*=|
  Retrobatch.*:: SULast|
  keyboardmaestro.*:: MBPreferences|
  thebrowser.*:: TopBarColorCache\.|
  NetworkInterfaces.*:: Interfaces\[|
  iMazing.*::|
  mirage\.app\.Dune.*::|
  SuperDuper.*:: UMinfoURL\s*=|
  :: PNUserDefaultPhotosAppLastLaunchDateKey\s*=|
  sharingd.*:: AfterFirstUseExpirationDate\s*=|
  app-setapp.*:: annotateLastBackgroundColor\.|
  app-setapp.*:: s[0-9]+\s*=|

  screentimedx :: settingsModificationDate\s*=|
  screentimedx :: needsToSetPasscode\s*=|
  screentimedx :: communicationPolicies\.communicationSafetyNotification\s*=|

  wallpaper.*Index.*::|
  CacheDelete.*::|
  facetime.*:: lastFetchedContactHistoryToken\.|
  thebrowser.*:: .*[Uu]pdate.*[Ss]ince\s*=|
  thebrowser.*:: automaticUpdateWillRelaunchApp\s*=|
  thebrowser.*:: softwareUpdater[Ww]ill[Rr]elaunch|
  nvram.*:: StartupMute\s*=|
  VirtualBuddy.*:: window-|
  VirtualBuddy.*:: defaultDirectory|
  VirtualBuddy.*:: config\..*\.collapsed\s*=|
  PrintingPrefs.*:: LastUsedPrinters\[|
  DiagnosticMessagesHistory.*:: Canary\s*=|
  DiagnosticMessagesHistory.*:: AutoSubmitVersion\s*=|
  DiagnosticMessagesHistory.*:: LastCleanupCalled\s*=|
  DiagnosticMessagesHistory.*:: LastFullSubmissionCalled\s*=|
  DiagnosticMessagesHistory.*:: LastFullSubmissionSuccess\s*=|
  DiagnosticMessagesHistory.*:: .*InvestigationID\s*=|
  DiagnosticMessagesHistory.*:: PreviousSetPreferences|
  DiagnosticMessagesHistory.*:: Seed|
  DiagnosticMessagesHistory.*:: StoreDataCreation|
  DiagnosticMessagesHistory.*:: .*DataSubmitVersion\s*=|
  DiagnosticMessagesHistory.*:: lastQuantized|
  DiagnosticMessagesHistory.*:: lastSubmission|
  controlcenter\.bentoboxes.*:: boxes\s*=|
  systemsettings\.extensions.*:: sessionUUID\s*=|
  Accessibility\.Assets.*:: StoreCurrentBootTime\s*=|
  CloudSubscriptionFeatures\.config.*:: subscriptionStatus\.sessionId\s*=|
  CloudSubscriptionFeatures\.diagnostic.*::|
  CrashReporter.*:: .*\.bootUUID\s*=|
  assistant.*:: Last.*experiment.*check.*date\s*=|
  contextsync.*:: lastBootUUID\s*=|
  findmy.*:: Daemon::LastLaunch.*UUID\s*=|
  iCloudNotification.*:: .*sessionUUID\s*=|
  knowledge-agent.*:: ScreenTimeSyncDisabled\s*=|
  liveactivitiesd.*:: KnownClients\[|
  liveactivitiesd.*:: LastAuthorizationStatusEventDate\s*=|
  cloudkeychainproxy.*:: KeyAccountUUID\s*=|
  audio.*SystemSettings.*:: seed\s*=|
  SoftwareUpdate.*:: DidSkipBackgroundDownload|
  SoftwareUpdate.*:: LastCollected.*Date\s*=|
  SoftwareUpdate.*:: LastLogin.*HarvestDate\s*=|
  AppleMediaServices.*:: AMSD.*Homes\[|
  AppleMediaServices.*:: ITFE|
  CoreDuet.*:: DKSync2Policy|
  DiagnosticExtensions.*:: .*XPCActivity|
  gamecenter.*:: GKForcePrivacyNotice\s*=|
  print\.add.*:: defaultTableView\s*=|
  Siri.*:: SiriPrefStashedStatusMenuVisible\s*=|
  assistant\.backedup.*:: SiriAvailability\.|
  assistant.*:: Flush\ Session\ Tickets\ Cache\s*=|
  assistant.*:: PHS\ Asset\ Manifest|
  windowserver\.displays.*:: DisplaySets\.|
  windowserver\.displays.*:: account\s*=|
  ActivityMonitor.*:: OpenMainWindow\s*=|
  Music.*:: Home\ Sharing\ Settings\.|
  dhcp6d.*::|
  dock.*:: .*tile-data\.(file|parent)-mod-date|
  :: .*lastLaunchBootSessionUUID\s*=|
  :: lastAppInstallDate\s*=|
  :: engagementDate-|
  finder.*:: EmptyTrashProgressWindowLocation\s*=|
  remindd.*babysitter.*:: RefreshingWaiters\.|
  Mixpanel.*::|

  # Cache / internal-state domains (high entry counts, no user settings)
  EmojiCache.*::|
  sociallayerd.*::|
  newscore.*::|
  commerce\.knownclients.*::|
  identityservices.*idstatuscache.*::|
  facetime\.bag.*::|
  SpeakSelection.*::|
  flexibits\.cardhop.*::|
  preferences.pre.upgrade.source.*::|

  # ByHost UUID plists — per-machine hardware topology (UUID starts with digit or uppercase hex)
  windowserver\.[0-9A-F].*::|

  # Universal Control: suppress internal topology blob; preserves the Disable key
  universalcontrol.*:: Configuration|

  # Music / TV: store column layouts (600+ entries each) and per-view library state
  (Music|TV).*plist :: store[A-Z]|
  (Music|TV).*plist :: PPr4:|

  # Notification center per-app table (iCloud syncs ~200 apps at once; values are
  # opaque bitmasks and implicit defaults being made explicit — no real information)
  usernoted.*:: app\[|

  # CUPS transient printer state (idle/processing/stopped — not a setting)
  CUPS :: printer\[.*\]\.state =|

  # 1Password App Store purchase-intent timestamp (auto-updated, not a setting)
  1password.*:: SKPurchaseIntentUpdatesLastChecked|

  # ImageKit last-used image picker state (binary blob, changes on every panel open)
  :: IKPreferencesLast|

  # DoNotDisturb/DB: system Focus mode display names — Apple-defined strings
  # (Do Not Disturb, Driving, Fitness, Gaming, Mindfulness, Personal, Reading,
  #  Reduce Interruptions, Work, Sleep) — not user settings, never vary
  DoNotDisturb.*DB :: mode\[.*\]\.name =|

  # Snapshot section headers (########## SECTION NAME ##########)
  #{10}|

  # Blank diff lines — empty lines used as section separators in the snapshot format
  ^[-+]$|

  # Sleep prevention summary line without process list (e.g. "sleep   0")
  # The verbose form with process names is caught by \(sleep prevented by below
  [-+] sleep +[0-9]+$|
  \(sleep prevented by|
  :: \(not readable|
  :: \(not found|

  # macOS upgrade: per-app OS version stamps (reset on first launch after each upgrade)
  LastOSLaunchVersion\s*=|
  \.babysitter.*:: LastSystemVersion\s*=|
  :: kDAMigrationBuildVersionKey\s*=|
  :: CNLastCheckedBuildVersion\s*=|
  :: AMSLastMigratedBuildVersion\s*=|
  loginwindow.*:: (Build|System)VersionStamp(AsNumber|AsString)\s*=|
  loginwindow.*:: MiniBuddyLaunchCount\s*=|
  :: OptimizerPreviousBuild\s*=|
  :: UpdateSettingsRunStamp\.|
  FontRegistry.*:: Version\s*=|
  SoftwareUpdate.*:: LastAttempt(Build|System)Version\s*=|

  # macOS upgrade: System Settings search index rebuild status
  systemsettings.*:: (force-state-indexing|IndexSettings-indexing|osVersion)|

  # macOS upgrade: cloudphotod upgrade history (timestamps + library version strings)
  cloudphotod.*:: _CPLUpgradeHistory|

  # macOS upgrade: security smartcard token class UUIDs (rotated on each upgrade)
  security\.ctkd-db.*:: classes\.|

  # macOS upgrade: AvatarUI avatar cache rebuild flag (transient, cleared after flush)
  AvatarUI.*:: AVTAvatarUI(LastCacheVersion|FlushThumbnailCache)\s*=|

  # macOS upgrade: aerial wallpaper new-video download timestamp (not a user setting)
  wallpaper\.aerial.*:: LastAerialDownloadDate\s*=|

  # macOS upgrade: Messages contact nickname hash migration counter
  messages\.nicknames.*:: IMDNicknameHashCalculationVersion\s*=|

  # macOS upgrade: Siri installation date log (informational, redundant with SetupAssistant)
  sirisuggestions.*:: osInstalledDates\.|

  # macOS upgrade: Accessibility Assets TTS engine component metadata
  # (new speech synthesis plugins registered by the OS; not user-configurable)
  Accessibility\.Assets.*:: StoreLoaders\.|

  # macOS upgrade: pre-upgrade network config snapshot (entirely UUID-reshuffled each
  # upgrade; generates 70+ lines of churn with no user-visible setting information)
  preferences-pre-upgrade-new-target|

  # powerd.charging: boot-scoped UUIDs and PIDs (change every boot, not settings)
  powerd\.charging.*:: bootSessionUUID\s*=|
  powerd\.charging.*:: policies\.\$objects\[|

  # Energy/pmset: BatteryWarn per-device timestamp counters
  PowerManagement.*:: BatteryWarn\.|

  # App Store: onboarding acknowledgment list (array reordering, not new content)
  appstore.*:: ASAcknowledgedOnboardingItems\[|

  # GamePolicyAgent: installed games list (array reordering on update/upgrade)
  GamePolicyAgent.*:: installedGames\.\$objects\[|

  # dataaccess babysitter: transient calendar/data refresh state
  \.babysitter.*:: RefreshingWaiters\.|

  # CloudSubscriptionFeatures: transient subscription status refresh flag
  CloudSubscriptionFeatures\.config.*:: subscriptionStatus.*\.value\s*=|

  # Accessibility Assets: StoreTasks download-task configuration churn
  Accessibility\.Assets.*:: StoreTasks\.|

  # AudioAccessory: AirPods/headphone battery telemetry (transient, not a setting)
  AudioAccessory.*:: lastSeenBatteryInfosV2\.\$objects\[|

  # diagnosticextensionsd: bug session array element reordering (internal, not a setting)
  diagnosticextensionsd.*:: bugsession:|

  # Safari: internal bookmarks sync agent version stamp
  Safari.*:: NewestLaunchedSafariBookmarksSyncAgentVersion\s*=|

  # Siri: post-upgrade index version rebuild (informational, redundant with upgrade markers)
  sirisuggestions.*:: currentIndexVersion\s*=|

  # FileVault: transient analytics event
  filevault.*:: lastAnalyticsEvent\.|

  # Affinity Designer/Photo/Publisher: window restore blob (NSKeyedArchiver, changes on every open)
  affinity.*:: .*\.restore\.windows|

  # Affinity: crash-watcher flag (True while app is running, reverts on clean exit)
  affinity.*:: .*\.watchForCrash\s*=|

  # Affinity: floating tool panel position (drifts with every open)
  affinity.*:: .*\.tools\.[^:]*\.frame\s*=|

  # macOS Diagnostics / Instruments: entire log filter plist (Xcode-managed, changes whenever
  # Xcode or Instruments configures debug logging; the whole file is noise)
  Logging/.*diagnosticd\.filter|
  diagnosticd\.filter.*:: logicalExp\.[^:]*\.pid\.
)'

# Collapse to single-line regex.
# Strip leading whitespace, drop comment lines (#), then join and clean up trailing |).
# Do NOT strip all spaces — that would break patterns containing literal spaces.
NOISE_RE="$(echo "$NOISE_PATTERN" | sed 's/^[[:space:]]*//' | grep -v '^#' | tr -d '\n' | sed 's/|)/)/g')"

# ── Device identity ───────────────────────────────────────────────────────────

SETSHOT_PREF_DOMAIN="com.tidbits.setshot"
SETSHOT_PREF_KEY="DeviceName"

sanitize_name() {
  # Spaces and apostrophes → hyphens; strip anything not alphanumeric/hyphen/underscore
  echo "$1" | tr "' " '--' | tr -cd '[:alnum:]-_'
}

get_device_name() {
  local stored
  stored=$(defaults read "$SETSHOT_PREF_DOMAIN" "$SETSHOT_PREF_KEY" 2>/dev/null)
  if [ -z "$stored" ]; then
    local computer_name
    computer_name=$(scutil --get ComputerName 2>/dev/null || hostname)
    stored=$(sanitize_name "$computer_name")
    defaults write "$SETSHOT_PREF_DOMAIN" "$SETSHOT_PREF_KEY" "$stored"
    echo "SetShot: registered this device as \"$stored\"" >&2
    echo "  Run '$SCRIPT_NAME device <name>' to change it." >&2
  fi
  echo "$stored"
}

do_device() {
  local snap_dir
  snap_dir="$(cd "$(dirname "$0")" && pwd)/setshots"

  if [ -z "${1:-}" ]; then
    local name
    name=$(get_device_name)
    echo "Device name:     $name"
    echo "Setshots folder: $snap_dir/$name/"
    return
  fi

  local new_name
  new_name=$(sanitize_name "$1")
  if [ -z "$new_name" ]; then
    echo "Error: invalid device name '$1'"
    exit 1
  fi

  local old_name
  old_name=$(defaults read "$SETSHOT_PREF_DOMAIN" "$SETSHOT_PREF_KEY" 2>/dev/null)
  defaults write "$SETSHOT_PREF_DOMAIN" "$SETSHOT_PREF_KEY" "$new_name"
  echo "Device name: ${old_name:-<unset>} → $new_name"

  if [ -n "$old_name" ] && [ -d "$snap_dir/$old_name" ] && [ ! -d "$snap_dir/$new_name" ]; then
    mv "$snap_dir/$old_name" "$snap_dir/$new_name"
    echo "Renamed: setshots/$old_name/ → setshots/$new_name/"
  fi
}

# ── Helpers ───────────────────────────────────────────────────────────────────

usage() {
  echo "Usage:"
  echo "  $SCRIPT_NAME snapshot [--sudo] [output_file]"
  echo "  $SCRIPT_NAME compare [--diff [--raw]]             # interactive snapshot picker"
  echo "  $SCRIPT_NAME explain <before_file> <after_file>   # human-readable summary"
  echo "  $SCRIPT_NAME diff [--raw] <before_file> <after_file>"
  echo "  $SCRIPT_NAME device [name]                        # show or set device identity"
  exit 1
}

# Read a setshot file, transparently decompressing .gz files
cat_snapshot() {
  local f="$1"
  if [[ "$f" == *.gz ]]; then
    gunzip -c "$f"
  else
    cat "$f"
  fi
}

# Compress setshots older than 7 days in a device directory
compress_old_setshots() {
  local device_dir="$1"
  local cutoff
  cutoff=$(date -v-7d +%s 2>/dev/null) || return  # macOS only; skip if unavailable
  local compressed=0
  while IFS= read -r f; do
    local mtime
    mtime=$(stat -f %m "$f" 2>/dev/null)
    if [ -n "$mtime" ] && [ "$mtime" -lt "$cutoff" ]; then
      gzip -9 "$f" 2>/dev/null && compressed=$((compressed + 1))
    fi
  done < <(find "$device_dir" -maxdepth 1 -name "setshot_*.txt" 2>/dev/null)
  [ "$compressed" -gt 0 ] && echo "  Compressed $compressed old setshot(s)."
}

section() {
  echo ""
  echo "########## $* ##########"
  echo ""
}

# Domains whose reads can wake a media daemon and trigger the
# Media & Apple Music (kTCCServiceMediaLibrary) TCC prompt on macOS 15+.
# Suppressed on every read surface unless the user has explicitly opted in.
# Matches (case-insensitively): anything with "media" in the domain name,
# plus Apple Music/iTunes/AMP-specific domains, TV app, Podcasts, and
# AppleMediaServices. TV triggers kTCCServiceMediaLibrary just like Music.
_MUSIC_RE='com\.apple\.(Music|iTunes|iTunesX|iCloud\.Music|amp|AMP[A-Za-z]+|itunes[a-z]*|media[A-Za-z]*|HomeSharing|CloudMusic|AppleMediaServices|PersonalAudio|TV|Podcasts)'

_is_music_path() {
  [ "${SETSHOT_CHECK_MUSIC:-0}" = "1" ] && return 1
  echo "$1" | grep -qiE "/${_MUSIC_RE}"
}

flatten_domain() {
  local domain="$1"
  _is_music_path "$domain" && return
  defaults export "$domain" - 2>/dev/null \
    | _flatten_plist_stdin \
    | sed "s|^|${domain} :: |"
}

flatten_plist() {
  local f="$1"
  _is_music_path "$f" && return
  _flatten_plist_stdin < "$f" \
    | sed "s|^|${f} :: |"
}

# Reads a root-owned plist via sudo cat, flattens as current user.
flatten_plist_sudo() {
  local f="$1"
  _is_music_path "$f" && return
  sudo cat "$f" 2>/dev/null \
    | _flatten_plist_stdin \
    | sed "s|^|${f} :: |"
}

# ── Snapshot ──────────────────────────────────────────────────────────────────

do_snapshot() {
  local use_sudo=false
  if [ "${1:-}" = "--sudo" ]; then
    use_sudo=true
    shift
  fi

  local device_name device_dir snap_dir
  device_name=$(get_device_name)
  snap_dir="$(cd "$(dirname "$0")" && pwd)/setshots"
  device_dir="$snap_dir/$device_name"
  mkdir -p "$device_dir"

  local outfile="${1:-$device_dir/setshot_$(date +%Y-%m-%d_%H%M).txt.gz}"

  echo "Capturing settings snapshot..."
  echo "Device: $device_name"
  if [ "$use_sudo" = true ]; then
    echo "Mode:   elevated (--sudo)"
  fi
  echo "Output: $outfile"
  echo ""

  {
    echo "=========================================="
    echo "macOS Settings Snapshot"
    echo "Date:  $(date)"
    echo "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "Host:  $(scutil --get ComputerName 2>/dev/null || echo 'unknown')"
    echo "User:  $(whoami)"
    if [ "$use_sudo" = true ]; then
      echo "Mode:  elevated (--sudo)"
    fi
    echo "=========================================="

    section "NSGlobalDomain"
    flatten_domain "NSGlobalDomain"

    section "PLIST FILES: ~/Library/Preferences"
    # Only Apple-owned domains: com.apple.* plus a small whitelist of
    # Apple system plists that don't carry the com.apple prefix.
    while IFS= read -r f; do
      flatten_plist "$f"
    done < <(find "$HOME/Library/Preferences" \( \
        -name "com.apple.*.plist" \
        -o -name "CoreGraphics.plist" \
        -o -name "LockdownMode.plist" \
        -o -name "screentimedx.plist" \
        -o -name "sharing.plist" \
      \) -maxdepth 2 2>/dev/null \
      | if [ "${SETSHOT_CHECK_MUSIC:-0}" != "1" ]; then grep -viE "/${_MUSIC_RE}"; else cat; fi \
      | sort)

    section "PLIST FILES: /Library/Preferences"
    while IFS= read -r f; do
      flatten_plist "$f"
    done < <(find "/Library/Preferences" -name "com.apple.*.plist" -maxdepth 2 2>/dev/null | sort)

    # Analytics opt-in lives outside /Library/Preferences — capture it explicitly
    DIAG_HIST="/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"
    [ -f "$DIAG_HIST" ] && flatten_plist "$DIAG_HIST"

    section "FOCUS (~/Library/DoNotDisturb/DB)"
    # Focus config is stored in JSON files, not plists
    DND_DB="$HOME/Library/DoNotDisturb/DB"
    if [ -f "$DND_DB/GlobalConfiguration.json" ]; then
      # Extract Focus/DND config from JSON files using JXA (no python3/CLT required).
      # DND_DB_JXA is passed via environment to avoid shell quoting issues in the heredoc.
      export DND_DB_JXA="$DND_DB"
      osascript -l JavaScript << 'JSEOF' 2>/dev/null
ObjC.import('Foundation')
var db = $.NSProcessInfo.processInfo.environment.objectForKey('DND_DB_JXA').js

function readJSON(path) {
  var data = $.NSData.dataWithContentsOfFile(path)
  if (!data || data.length === 0) return null
  var str = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding)
  if (!str || str.isNil()) return null
  return JSON.parse(str.js)
}

function emit(key, val) {
  var line = db + ' :: ' + key + ' = ' + val + '\n'
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(
    $.NSString.alloc.initWithString(line).dataUsingEncoding($.NSUTF8StringEncoding)
  )
}

try {
  var gc = readJSON(db + '/GlobalConfiguration.json')
  if (gc) {
    var d = gc.data[0]
    emit('GlobalConfiguration.modesCanImpactAvailability', d.modesCanImpactAvailability)
    emit('GlobalConfiguration.preventAutoReply', d.preventAutoReply)
  }
} catch(e) {}

try {
  var mc = readJSON(db + '/ModeConfigurations.json')
  if (mc) {
    var modes = mc.data[0].modeConfigurations
    var ids = Object.keys(modes).sort()
    for (var i = 0; i < ids.length; i++) {
      var mode_id = ids[i]
      var cfg = modes[mode_id]
      var name = (cfg.mode && cfg.mode.name) ? cfg.mode.name : mode_id
      emit('mode[' + mode_id + '].name', name)
      emit('mode[' + mode_id + '].impactsAvailability', cfg.impactsAvailability)
    }
  }
} catch(e) {}
JSEOF
      unset DND_DB_JXA
    else
      echo "$DND_DB :: (not found)"
    fi

    section "SCREEN TIME (screentimediagnose)"
    # Screen Time stores settings in a sandboxed SQLite database; readable only
    # via the screentimediagnose tool in ScreenTimeCore.framework.
    STDIAG="/System/Library/PrivateFrameworks/ScreenTimeCore.framework/screentimediagnose"
    if [ -x "$STDIAG" ]; then
      "$STDIAG" inspect 2>/dev/null | awk '
      # Parse the ObjC-style description output from screentimediagnose inspect.
      # Tracks brace depth to distinguish top-level keys from nested content.
      # Uses only POSIX awk (no 3-argument match, no gawk extensions).
      BEGIN {
        depth = 0; pre = 0; section = ""; sdepth = 0; comm = 0; cdepth = 0
        bp_id = ""; bp_en = ""; alt = 0; aen = 0
        BPMAP["bedtime_activation_personal"]      = "downtime_schedule_enabled"
        BPMAP["digital_health_restrictions"]       = "content_privacy_enabled"
        BPMAP["always_allow_activation_personal"]  = "always_allowed_apps_enabled"
      }
      {
        pre = depth
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          else if (c == "}") depth--
        }
        post = depth
      }

      # Detect top-level section opens
      pre == 0 && /^settings = \{/   { section = "settings";   sdepth = post; next }
      pre == 0 && /^blueprints = \{/ { section = "blueprints"; sdepth = post; next }
      # Leave section when depth falls back below the section level
      section != "" && post < sdepth { section = ""; comm = 0; next }

      # Settings: top-level key=value (no brace change, not a dict opener)
      section == "settings" && pre == sdepth && post == sdepth && !/\{/ {
        s = $0; gsub(/^[[:space:]]+/, "", s)
        if (s ~ /^[a-zA-Z][a-zA-Z0-9_]*[[:space:]]*=/) {
          key = s; sub(/[[:space:]]*=.*/, "", key)
          val = s; sub(/^[^=]*=[[:space:]]*/, "", val); sub(/;[[:space:]]*$/, "", val)
          print "screentimedx :: " key " = " val
        }
      }
      # Settings: entering communicationPolicies nested dict
      section == "settings" && /communicationPolicies/ && pre == sdepth && post > sdepth {
        comm = 1; cdepth = post; next
      }
      # communicationPolicies content
      section == "settings" && comm && pre == cdepth && post == cdepth && !/\{/ {
        s = $0; gsub(/^[[:space:]]+/, "", s)
        if (s ~ /^[a-zA-Z][a-zA-Z0-9_]*[[:space:]]*=/) {
          key = s; sub(/[[:space:]]*=.*/, "", key)
          val = s; sub(/^[^=]*=[[:space:]]*/, "", val); sub(/;[[:space:]]*$/, "", val)
          print "screentimedx :: communicationPolicies." key " = " val
        }
      }
      # Closing communicationPolicies
      section == "settings" && comm && post < cdepth { comm = 0 }

      # Blueprints: detect new blueprint entry
      section == "blueprints" && pre == sdepth && /"[^"]+" = \{/ {
        if (bp_id != "") {
          if (bp_id in BPMAP) print "screentimedx :: " BPMAP[bp_id] " = " bp_en
          if (bp_id ~ /^budget_activation_/) { alt++; if (bp_en == "1") aen++ }
        }
        s = $0; sub(/^[[:space:]]*"/, "", s); sub(/".*/, "", s); bp_id = s; bp_en = ""
        next
      }
      # Blueprint content: look for enabled key
      section == "blueprints" && bp_id != "" && pre > sdepth && post > sdepth {
        if (/enabled[[:space:]]*=/) {
          s = $0
          sub(/.*enabled[[:space:]]*=[[:space:]]*/, "", s); sub(/;.*/, "", s)
          gsub(/[[:space:]]/, "", s); bp_en = s
        }
      }
      # Closing a blueprint dict
      section == "blueprints" && bp_id != "" && pre > sdepth && post == sdepth {
        if (bp_id in BPMAP) print "screentimedx :: " BPMAP[bp_id] " = " bp_en
        if (bp_id ~ /^budget_activation_/) { alt++; if (bp_en == "1") aen++ }
        bp_id = ""
      }

      END {
        if (bp_id != "") {
          if (bp_id in BPMAP) print "screentimedx :: " BPMAP[bp_id] " = " bp_en
          if (bp_id ~ /^budget_activation_/) { alt++; if (bp_en == "1") aen++ }
        }
        print "screentimedx :: app_limits_count = " alt
        print "screentimedx :: app_limits_enabled_count = " aen
      }
      '
    else
      echo "screentimedx :: (screentimediagnose not found)"
    fi

    section "SOUND (NVRAM)"
    # Play sound on startup is stored in NVRAM, not a plist
    nvram StartupMute 2>/dev/null || echo "nvram :: StartupMute = (not set)"

    section "WALLPAPER (~/Library/Application Support/com.apple.wallpaper)"
    # Wallpaper selection stored here — not in ~/Library/Preferences
    WP_INDEX="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
    if [ -f "$WP_INDEX" ]; then
      flatten_plist "$WP_INDEX"
    else
      echo "${WP_INDEX} :: (not found)"
    fi

    section "APPLICATION HANDLERS (default browser / mail client)"
    LS_PLIST="$HOME/Library/Application Support/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
    if [ -f "$LS_PLIST" ]; then
      flatten_plist "$LS_PLIST"
      # Emit explicit summary lines for the most important URL-scheme handlers.
      # These produce stable "default-browser :: handler = ..." lines that the
      # explain engine can translate to friendly names even when the LSHandlers
      # array index shifts (which raw flatten output cannot do reliably).
      # Uses plutil to convert the binary plist to XML, then awk to parse it.
      plutil -convert xml1 -o - "$LS_PLIST" 2>/dev/null | awk '
      BEGIN {
        SCHEMES["http"]    = "default-browser"
        SCHEMES["https"]   = "default-browser-https"
        SCHEMES["mailto"]  = "default-mail-client"
        SCHEMES["webcal"]  = "default-calendar-app"
        SCHEMES["feed"]    = "default-rss-reader"
        in_h = 0; scheme = ""; role = ""; next_is = ""
      }
      /^[[:space:]]*<dict>[[:space:]]*$/ { in_h = 1; scheme = ""; role = ""; next_is = ""; next }
      /^[[:space:]]*<\/dict>[[:space:]]*$/ {
        if (in_h && scheme != "" && role != "") handlers[scheme] = role
        in_h = 0; next
      }
      in_h && /LSHandlerURLScheme/ { next_is = "scheme"; next }
      in_h && /LSHandlerRoleAll/   { next_is = "role";   next }
      in_h && /LSHandlerRoleViewer/ && role == "" { next_is = "role"; next }
      next_is != "" && /<string>/ {
        s = $0; sub(/.*<string>/, "", s); sub(/<\/string>.*/, "", s)
        if (next_is == "scheme") scheme = s
        else if (next_is == "role")   role   = s
        next_is = ""
      }
      END {
        for (s in SCHEMES)
          if (s in handlers) print SCHEMES[s] " :: handler = " handlers[s]
      }
      '
    else
      echo "${LS_PLIST} :: (not found)"
    fi

    section "SYSTEM CONFIGURATION"
    echo "scutil :: ComputerName  = $(scutil --get ComputerName  2>/dev/null || echo '(not set)')"
    echo "scutil :: LocalHostName = $(scutil --get LocalHostName 2>/dev/null || echo '(not set)')"
    echo "scutil :: HostName      = $(scutil --get HostName      2>/dev/null || echo '(not set)')"
    echo ""
    echo "--- scutil: DNS ---"
    scutil --dns   2>/dev/null || echo "(unavailable)"
    echo ""
    echo "--- scutil: proxy ---"
    scutil --proxy 2>/dev/null || echo "(unavailable)"
    echo ""
    echo "--- networksetup: services ---"
    networksetup -listallnetworkservices 2>/dev/null || echo "(unavailable)"

    section "CONFIGURATION PROFILES"
    profiles list -all 2>/dev/null || echo "(none, or permission denied)"

    section "LAUNCH AGENTS & DAEMONS"
    for dir in \
        "$HOME/Library/LaunchAgents" \
        "/Library/LaunchAgents" \
        "/Library/LaunchDaemons"; do
      ls "$dir" 2>/dev/null | while IFS= read -r f; do
        echo "${dir} :: ${f}"
      done
    done

    if [ "${SETSHOT_CHECK_TCC:-0}" = "1" ]; then
    section "TCC PRIVACY DATABASE"
    echo "# Format: service | client | client_type | auth_value | auth_reason | modified"
    echo "# auth_value: 0=denied  2=allowed"
    echo ""

    USER_TCC="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -r "$USER_TCC" ]; then
      sqlite3 "$USER_TCC" \
        "SELECT 'TCC-user :: ' || service || ' | ' || client || ' | ' || client_type
              || ' | ' || auth_value || ' | ' || COALESCE(auth_reason,'') || ' | '
              || datetime(last_modified,'unixepoch','localtime')
         FROM access ORDER BY service, client;" 2>/dev/null \
        || echo "TCC-user :: (query failed)"
    else
      echo "TCC-user :: (not readable — grant Full Disk Access to SetShot)"
    fi

    SYS_TCC="/Library/Application Support/com.apple.TCC/TCC.db"
    if [ -r "$SYS_TCC" ]; then
      sqlite3 "$SYS_TCC" \
        "SELECT 'TCC-system :: ' || service || ' | ' || client || ' | ' || client_type
              || ' | ' || auth_value || ' | ' || COALESCE(auth_reason,'') || ' | '
              || datetime(last_modified,'unixepoch','localtime')
         FROM access ORDER BY service, client;" 2>/dev/null \
        || echo "TCC-system :: (query failed)"
    else
      echo "TCC-system :: (not readable — grant Full Disk Access to SetShot)"
    fi
    fi  # SETSHOT_CHECK_TCC

    section "SYSTEM STATE"
    echo "SIP         :: $(csrutil status       2>/dev/null || echo '(unavailable)')"
    echo "Gatekeeper  :: $(spctl --status        2>/dev/null || echo '(unavailable)')"
    echo "FileVault   :: $(fdesetup status       2>/dev/null || echo '(unavailable)')"
    echo "Firewall    :: $(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo '(unavailable)')"
    _adm_timeout=$(security authorizationdb read system.preferences 2>/dev/null \
      | plutil -extract timeout raw -o - - 2>/dev/null)
    echo "AdminPassword :: timeout=${_adm_timeout:-(unavailable)}"
    LDM_VAL=$(launchctl bootenv 2>/dev/null | awk '/LockdownMode/{print $2}')
    echo "LockdownMode :: LockdownMode = ${LDM_VAL:-0}"
    echo ""
    # NOTE: Keyboard backlight brightness and idle dim time cannot be captured
    # on Apple Silicon Macs (macOS 13+). They are managed by corebrightnessd
    # (Mach service com.apple.backlightd) and stored in GUID-namespaced NVRAM
    # partitions requiring com.apple.private.iokit.system-nvram-allow. On Intel
    # Macs, these were in com.apple.BezelServices (kDim, kDimTime), but that
    # mechanism is gone on Apple Silicon. Would require a compiled Swift helper
    # with private entitlements to query the KeyboardBrightnessClient SPI.

    echo "--- pmset ---"
    # Reformat pmset -g output into "pmset :: [section.]key = value" lines so
    # DiffEngine can parse and diff individual energy settings. Section prefixes
    # ("Battery Power.", "AC Power.") are added for named sections; "Currently
    # in use" resets to no prefix. The trailing "(sleep prevented by ...)"
    # parenthetical is stripped so the sleep timer value diffs cleanly.
    pmset -g 2>/dev/null | awk '
      BEGIN { prefix="" }
      /^Battery Power:/    { prefix="Battery Power."; next }
      /^AC Power:/         { prefix="AC Power."; next }
      /^Currently in use:/ { prefix=""; next }
      /^[^ ]/              { prefix=""; next }
      /^ / {
        line=$0; sub(/^ +/,"",line)
        sub(/ \([^)]*\)?$/,"",line)
        n=split(line,p); if(n<2) next
        v=p[n]; k=line; sub(/ +[^ ]+$/,"",k)
        print "pmset :: " prefix k " = " v
      }
    '
    echo ""
    echo "--- systemsetup ---"
    systemsetup -getnetworktimeserver 2>/dev/null || echo "(unavailable)"
    systemsetup -getusingnetworktime  2>/dev/null || echo "(unavailable)"
    systemsetup -gettimezone          2>/dev/null || echo "(unavailable)"
    systemsetup -getremotelogin       2>/dev/null || echo "(unavailable)"
    systemsetup -getremoteappleevents 2>/dev/null || echo "(unavailable)"

    section "SHARING SERVICES"
    # Reports enabled/disabled for each service by reading the system-domain
    # disabled-overrides table. launchctl list (user session) cannot see system
    # daemons on macOS 13+, so it always returned "disabled" regardless of state.
    # print-disabled system shows the explicit override for each daemon:
    #   "com.apple.foo" => enabled   → service was enabled via System Settings
    #   "com.apple.foo" => disabled  → service was explicitly disabled
    #   (absent)                     → using plist default, which for sharing
    #                                  daemons is Disabled=true → disabled
    _lctl_disabled=$(launchctl print-disabled system 2>/dev/null)
    for svc in \
        com.apple.screensharing \
        com.apple.smbd \
        com.apple.netbiosd \
        com.apple.AppleFileServer \
        com.apple.AirPlayXPCHelper \
        com.openssh.sshd \
        com.apple.AEServer; do
      if echo "$_lctl_disabled" | grep -qF "\"${svc}\" => enabled"; then
        echo "sharing :: ${svc} = enabled"
      else
        echo "sharing :: ${svc} = disabled"
      fi
    done
    # Printer Sharing is controlled by the CUPS scheduler (not a launchd override).
    _cups_share=$(cupsctl 2>/dev/null | grep '^_share_printers=' | cut -d= -f2)
    if [ "${_cups_share}" = "1" ]; then
      echo "sharing :: org.cups.PrintingPrefs.PrinterSharing = enabled"
    else
      echo "sharing :: org.cups.PrintingPrefs.PrinterSharing = disabled"
    fi
    # Remote Management is a LaunchAgent controlled by KeepAlive.PathState on a
    # sentinel file, not a LaunchDaemon with a disabled override — so it never
    # appears in print-disabled system. Check the sentinel file directly instead.
    _rdm_sentinel="/Library/Application Support/Apple/Remote Desktop/RemoteManagement.launchd"
    if [ -f "$_rdm_sentinel" ]; then
      echo "sharing :: com.apple.RemoteDesktop.agent = enabled"
    else
      echo "sharing :: com.apple.RemoteDesktop.agent = disabled"
    fi

    section "TIME MACHINE"
    tmutil destinationinfo 2>/dev/null || echo "(no destinations configured)"
    echo ""
    tmutil status 2>/dev/null || echo "(unavailable)"

    section "PRINTERS & FAXES"
    # CUPS printer/fax queues — stable attributes only (state-change timestamps excluded).
    # lpstat requires no root; lpoptions gives per-printer details.
    _printer_names=$(lpstat -p 2>/dev/null | awk '/^printer / { print $2 }' | sort)
    if [ -z "$_printer_names" ]; then
      echo "CUPS :: (no printers configured)"
    else
      while IFS= read -r _pname; do
        _state=$(lpstat -p "$_pname" 2>/dev/null \
          | awk '/^printer / { s=$4; gsub(/\.$/, "", s); print s; exit }')
        echo "CUPS :: printer[${_pname}].state = ${_state:-unknown}"
        _raw=$(lpoptions -p "$_pname" 2>/dev/null)
        for _kl in \
            "printer-info:info" \
            "printer-make-and-model:driver" \
            "printer-uri-supported:uri" \
            "printer-location:location" \
            "printer-is-accepting-jobs:accepting" \
            "printer-is-shared:shared" \
            "print-color-mode:default-color" \
            "sides:default-sides"; do
          _src="${_kl%%:*}"; _lbl="${_kl##*:}"
          # Extract value: handles key='quoted value' and key=unquoted
          _val=$(printf '%s\n' "$_raw" \
            | grep -oE "${_src}='[^']*'|${_src}=[^ ]+" \
            | head -1 \
            | sed "s/^${_src}=//; s/^'//; s/'$//")
          [ -n "$_val" ] && [ "$_val" != "''" ] \
            && echo "CUPS :: printer[${_pname}].${_lbl} = ${_val}"
        done
      done <<< "$_printer_names"
    fi

    section "SYSTEM EXTENSIONS"
    systemextensionsctl list 2>/dev/null || echo "(unavailable)"

    section "BACKGROUND TASK MANAGEMENT (Login Items & Background)"
    # sfltool dumpbackgroundtaskmanagement lists all BTM-registered items:
    # login items (Open at Login) and background helpers (Allow in Background).
    # Output is normalized to "BTM :: <identifier> :: <key> = <value>" lines.
    if command -v sfltool >/dev/null 2>&1; then
      sfltool dumpbackgroundtaskmanagement 2>/dev/null \
      | awk '
        # App or Helper line with inline Bundle ID
        /App:|Helper/ && /Bundle ID:/ {
          idx = index($0, "Bundle ID:")
          if (idx > 0) {
            rest = substr($0, idx + 10)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
            identifier = rest
          }
          next
        }
        # Explicit Identifier line (overrides bundle-id from above for sub-items)
        /^[[:space:]]+Identifier:/ {
          sub(/^[[:space:]]+Identifier:[[:space:]]+/, "")
          identifier = $0
          next
        }
        # Disposition — the field that changes when user toggles allow/deny
        identifier != "" && /^[[:space:]]+Disposition:/ {
          sub(/^[[:space:]]+Disposition:[[:space:]]+/, "")
          print "BTM :: " identifier " :: disposition = " $0
          identifier = ""
        }
      ' \
      | sort \
      || echo "BTM :: (sfltool query failed)"
    else
      echo "BTM :: (sfltool not available)"
    fi

    # ── Sudo-elevated captures ────────────────────────────────────────────────
    if [ "$use_sudo" = true ]; then

      section "LOCATION SERVICES (sudo)"
      LS_BYHOST=$(sudo find /var/db/locationd/Library/Preferences/ByHost \
                    -name "com.apple.locationd.*.plist" 2>/dev/null | head -1)
      if [ -n "$LS_BYHOST" ]; then
        flatten_plist_sudo "$LS_BYHOST"
      else
        echo "locationd :: (not found or not readable)"
      fi

      section "NIGHT SHIFT (sudo)"
      NS_PLIST="/Library/Preferences/com.apple.CoreBrightness.plist"
      if sudo test -r "$NS_PLIST" 2>/dev/null; then
        flatten_plist_sudo "$NS_PLIST"
      else
        echo "${NS_PLIST} :: (not readable even with sudo)"
      fi

      section "WI-FI KNOWN NETWORKS (sudo)"
      WIFI_PLIST="/private/var/preferences/com.apple.wifi.known-networks.plist"
      if sudo test -r "$WIFI_PLIST" 2>/dev/null; then
        flatten_plist_sudo "$WIFI_PLIST"
      else
        echo "${WIFI_PLIST} :: (not found or not readable)"
      fi

      section "SMAPPSERVICE LOGIN ITEMS (sudo)"
      # macOS 13+ login items registered via SMAppService live under
      # /var/db/com.apple.xpc.launchd/ — typically in per-UID subdirectories.
      LAUNCHD_DB="/var/db/com.apple.xpc.launchd"
      if sudo test -d "$LAUNCHD_DB" 2>/dev/null; then
        while IFS= read -r f; do
          flatten_plist_sudo "$f"
        done < <(sudo find "$LAUNCHD_DB" -name "*.plist" 2>/dev/null | sort)
      else
        echo "${LAUNCHD_DB} :: (not found)"
      fi

    fi
    # ── End sudo-elevated captures ────────────────────────────────────────────

    echo ""
    echo "=========================================="
    echo "Snapshot complete: $(date)"
    echo "=========================================="

  } | if [[ "$outfile" == *.gz ]]; then gzip -9; else cat; fi > "$outfile"

  local size
  size="$(du -sh "$outfile" 2>/dev/null | cut -f1)"
  echo "Done. Size: $size"

  compress_old_setshots "$device_dir"

  # ── Relay files ───────────────────────────────────────────────────────────────
  # Relay files are pre-created by the Claude VM so it can read Mac-written content
  # in the same session (virtiofs only allows reading files whose inodes existed at
  # mount time, or were created by the VM itself).
  # Rotation: overwrite in-place with cat (preserves inode, avoids EDEADLK).
  local relay_latest="$device_dir/.relay_latest.txt"
  local relay_prev="$device_dir/.relay_prev.txt"
  if [ -f "$relay_latest" ] && [ -f "$relay_prev" ]; then
    # Rotate prev ← latest (in-place overwrite to preserve VM-created inode)
    cat "$relay_latest" > "$relay_prev" 2>/dev/null || true
    # Write new snapshot into latest relay (decompress if needed)
    if [[ "$outfile" == *.gz ]]; then
      gunzip -c "$outfile" > "$relay_latest" 2>/dev/null || true
    else
      cat "$outfile" > "$relay_latest" 2>/dev/null || true
    fi
    echo "  (relay files updated)"
  fi

  echo ""
  echo "To compare any two setshots interactively:"
  echo "  $SCRIPT_NAME compare"
}

# ── Compare (interactive picker) ─────────────────────────────────────────────

do_compare() {
  local mode="${1:-explain}"   # explain | diff
  local raw_flag="${2:-}"

  local snap_dir
  snap_dir="$(cd "$(dirname "$0")" && pwd)/setshots"

  if [ ! -d "$snap_dir" ]; then
    echo "No setshots directory at: $snap_dir"
    echo "Run:  $SCRIPT_NAME snapshot  to create one."
    exit 1
  fi

  # ── Device selection ────────────────────────────────────────────────────────
  local devices=()
  while IFS= read -r d; do
    devices+=("$(basename "$d")")
  done < <(find "$snap_dir" -mindepth 1 -maxdepth 1 -type d | sort)

  if [ "${#devices[@]}" -eq 0 ]; then
    echo "No device folders found in $snap_dir."
    echo "Run:  $SCRIPT_NAME snapshot  to create one."
    exit 1
  fi

  local device_dir
  if [ "${#devices[@]}" -eq 1 ]; then
    device_dir="$snap_dir/${devices[0]}"
  else
    echo "Select device:"
    PS3="  Enter number: "
    local chosen_device
    select chosen_device in "${devices[@]}"; do
      [ -n "$chosen_device" ] && { device_dir="$snap_dir/$chosen_device"; break; }
      echo "  Invalid — try again."
    done
    echo
  fi

  # ── File selection ───────────────────────────────────────────────────────────
  # Collect both .txt and .txt.gz, sorted by filename (date-stamped)
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$device_dir" -maxdepth 1 \( -name "setshot_*.txt" -o -name "setshot_*.txt.gz" \) 2>/dev/null | sort)

  # Append relay files if they have content (non-empty means Mac has written to them)
  local relay_prev="$device_dir/.relay_prev.txt"
  local relay_latest="$device_dir/.relay_latest.txt"
  [ -s "$relay_prev"   ] && files+=("$relay_prev")
  [ -s "$relay_latest" ] && files+=("$relay_latest")

  local count="${#files[@]}"
  if [ "$count" -lt 2 ]; then
    echo "Need at least 2 setshots in $device_dir (found $count)."
    exit 1
  fi

  # Labels: strip path, .gz, and setshot_ prefix; relay files get descriptive names
  local labels=()
  for f in "${files[@]}"; do
    local base
    base="$(basename "$f")"
    case "$base" in
      .relay_prev.txt)   labels+=("[relay: previous snapshot]") ;;
      .relay_latest.txt) labels+=("[relay: latest snapshot]")   ;;
      *)
        base="${base%.gz}"
        base="${base%.txt}"
        labels+=("${base#setshot_}")
        ;;
    esac
  done

  local before_file after_file chosen_label

  echo "Select BEFORE setshot (older):"
  PS3="  Enter number: "
  select chosen_label in "${labels[@]}"; do
    if [ -n "$chosen_label" ]; then
      # Find the matching file (may be .txt or .txt.gz)
      local idx=$(( REPLY - 1 ))
      before_file="${files[$idx]}"
      break
    fi
    echo "  Invalid — try again."
  done

  echo
  echo "Select AFTER setshot (newer):"
  PS3="  Enter number: "
  select chosen_label in "${labels[@]}"; do
    if [ -n "$chosen_label" ]; then
      local idx=$(( REPLY - 1 ))
      after_file="${files[$idx]}"
      break
    fi
    echo "  Invalid — try again."
  done
  echo

  if [ "$mode" = "diff" ]; then
    do_diff $raw_flag "$before_file" "$after_file"
  else
    do_explain "$before_file" "$after_file"
  fi
}

# ── Explain ───────────────────────────────────────────────────────────────────

do_explain() {
  local before="$1"
  local after="$2"

  for f in "$before" "$after"; do
    if [ ! -f "$f" ]; then
      echo "Error: file not found: $f"
      exit 1
    fi
  done

  if [ -z "$SETSHOT_BIN" ]; then
    echo "Error: SetShot binary not found."
    echo "Install SetShot.app or set SETSHOT_BIN to the binary path."
    exit 1
  fi

  "$SETSHOT_BIN" --explain-diff "$before" "$after"
}

# ── Diff ──────────────────────────────────────────────────────────────────────

do_diff() {
  local raw=false
  if [ "${1:-}" = "--raw" ]; then
    raw=true
    shift
  fi

  local before="$1"
  local after="$2"

  for f in "$before" "$after"; do
    if [ ! -f "$f" ]; then
      echo "Error: file not found: $f"
      exit 1
    fi
  done

  echo "Before: $before"
  echo "After:  $after"
  if [ "$raw" = false ]; then
    echo "Mode:   filtered  (use --raw for full output)"
  else
    echo "Mode:   raw"
  fi
  echo ""
  echo "Lines starting with '-' were removed or changed."
  echo "Lines starting with '+' were added or changed."
  echo "=========================================="
  echo ""

  if [ "$raw" = true ]; then
    diff --unified=0 <(cat_snapshot "$before") <(cat_snapshot "$after") || true
  else
    diff --unified=0 <(cat_snapshot "$before") <(cat_snapshot "$after") \
      | grep -vE '^@@' \
      | grep -vE "$NOISE_RE" \
      || true
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

[ $# -lt 1 ] && usage

case "$1" in
  snapshot)
    shift
    # Pass through optional --sudo and optional output filename
    sudo_flag=""
    if [ "${1:-}" = "--sudo" ]; then
      sudo_flag="--sudo"
      shift
    fi
    do_snapshot $sudo_flag "${1:-}"
    ;;
  compare)
    shift
    cmp_mode="explain"
    cmp_raw=""
    if [ "${1:-}" = "--diff" ]; then cmp_mode="diff"; shift; fi
    if [ "${1:-}" = "--raw"  ]; then cmp_raw="--raw"; shift; fi
    do_compare "$cmp_mode" "$cmp_raw"
    ;;
  explain)
    shift
    [ $# -lt 2 ] && { echo "Error: explain requires two filenames."; usage; }
    do_explain "$1" "$2"
    ;;
  diff)
    shift
    raw_flag=""
    if [ "${1:-}" = "--raw" ]; then
      raw_flag="--raw"
      shift
    fi
    [ $# -lt 2 ] && { echo "Error: diff requires two filenames."; usage; }
    do_diff $raw_flag "$1" "$2"
    ;;
  device)
    shift
    do_device "${1:-}"
    ;;
  *)
    usage
    ;;
esac
