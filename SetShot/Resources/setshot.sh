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
# For full TCC (privacy permissions) coverage, grant Full Disk Access to Terminal:
#   System Settings > Privacy & Security > Full Disk Access > enable Terminal
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

# ── Python flattener ──────────────────────────────────────────────────────────
# Reads a plist from stdin (binary or XML), emits one "key = value" line per
# leaf node. bytes values are attempted as nested plists before falling back.

read -r -d '' FLATTEN_PY << 'PYEOF'
import sys, plistlib
from datetime import datetime

def flatten(obj, prefix=""):
    if isinstance(obj, bool):
        print(f"{prefix} = {obj}")
    elif isinstance(obj, int) and obj in (0, 1):
        # Normalize integer 0/1 to False/True so that plists switching between
        # <integer>1</integer> and <true/> on disk don't produce false diffs.
        # (bool is a subclass of int, so the bool check above runs first.)
        print(f"{prefix} = {bool(obj)}")
    elif isinstance(obj, plistlib.UID):
        print(f"{prefix} = <UID {obj.data}>")
    elif isinstance(obj, dict):
        for k in sorted(obj.keys(), key=str):
            flatten(obj[k], f"{prefix}.{k}" if prefix else str(k))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            flatten(v, f"{prefix}[{i}]")
    elif isinstance(obj, bytes):
        try:
            nested = plistlib.loads(obj)
            flatten(nested, prefix)
            return
        except Exception:
            pass
        print(f"{prefix} = <binary {len(obj)} bytes>")
    elif isinstance(obj, datetime):
        print(f"{prefix} = {obj.isoformat()}")
    else:
        val = str(obj)
        if len(val) > 300:
            val = val[:300] + "..."
        print(f"{prefix} = {val}")

try:
    data = plistlib.load(sys.stdin.buffer)
    flatten(data)
except Exception:
    sys.exit(1)
PYEOF

# ── Human-readable explainer ─────────────────────────────────────────────────
# Reads filtered diff lines from stdin, translates known keys to plain English,
# and prints a tidy summary. Unknown changes are shown in a compact raw section.

read -r -d '' EXPLAIN_PY << 'PYEOF'
import sys, re, json

def fmt_bool(v):
    return {"True":"ON","False":"OFF","1":"ON","0":"OFF",
            "YES":"ON","NO":"OFF","enabled":"ON","disabled":"OFF"}.get(str(v).strip(), v)

def fmt_sec(v):
    try:
        s = int(float(v))
        if s == 0: return "Never"
        if s % 3600 == 0: return f"{s//3600}h"
        if s % 60  == 0: return f"{s//60} min"
        return f"{s}s"
    except: return v

def fmt_min(v):
    try:
        m = int(float(v))
        return "Never" if m == 0 else f"{m} min"
    except: return v

def relay_status(v):
    return {"1":"ON","0":"OFF"}.get(str(v).strip(), v)

def fmt_cc_item(v):
    """Control Center item visibility: 2=in menu bar, 8=hidden, 16=always show"""
    return {"2":"in menu bar","8":"hidden","16":"always show","18":"in menu bar (always)"}.get(str(v).strip(), v)

def fmt_menubar_hide(v):
    """AutoHideMenuBarOption: 0=Always, 1=In Full Screen Only, 2=Never"""
    return {"0":"Always","1":"In Full Screen Only","2":"Never"}.get(str(int(float(v))), v)

# Rules: (key_regex, domain_regex_or_None, label, value_fn, priority, dedup_group)
# key_regex   — matched against the key portion of "KEY = VALUE"
# domain_regex — matched against the file/domain path (None = any)
# priority    — lower wins when multiple rules match the same dedup_group
RULES = [
    # ── Scrolling & trackpad ───────────────────────────────────────────────
    (r'com\.apple\.swipescrolldirection',    None,
     "Natural scrolling",       fmt_bool, 1, "natural_scroll"),
    (r'com\.apple\.mouse\.tapBehavior',      None,
     "Tap to click",            fmt_bool, 1, "tap_click"),
    (r'^Clicking$',  r'Multitouch|BluetoothMultitouch',
     "Tap to click",            fmt_bool, 2, "tap_click"),
    (r'TrackpadThreeFingerDrag',             None,
     "Three-finger drag",       fmt_bool, 1, "three_finger_drag"),
    (r'com\.apple\.trackpad\.enableSecondaryClick', None,
     "Right-click (trackpad)",  fmt_bool, 1, "secondary_click"),

    # ── Accessibility ──────────────────────────────────────────────────────
    (r'ReduceMotionEnabled',                 None,
     "Reduce Motion",           fmt_bool, 1, "reduce_motion"),
    (r'^reduceMotion$',          r'universalaccess',
     "Reduce Motion",           fmt_bool, 2, "reduce_motion"),
    (r'reduceTransparency',                  None,
     "Reduce Transparency",     fmt_bool, 1, "reduce_transparency"),
    (r'increaseContrast',                    None,
     "Increase Contrast",       fmt_bool, 1, "increase_contrast"),
    (r'EnhancedBackgroundContrastEnabled',   None,
     "Increase Contrast",       fmt_bool, 2, "increase_contrast"),

    # ── Focus / DND prefs ─────────────────────────────────────────────────
    (r'dnd_prefs\.dndDisplaySleep',   r'ncprefs',
     "Notifications: display sleeping", fmt_bool, 1, "dnd_sleep"),
    (r'dnd_prefs\.dndDisplayLock',    r'ncprefs',
     "Notifications: lock screen",     fmt_bool, 1, "dnd_lock"),
    (r'dnd_prefs\.facetimeCanBreakDND', r'ncprefs',
     "Notifications: FaceTime breaks Focus", fmt_bool, 1, "dnd_ft"),
    (r'dnd_prefs\.repeatedFacetimeCallsBreaksDND', r'ncprefs',
     "Notifications: repeated calls break Focus", fmt_bool, 1, "dnd_repeat"),

    # ── Passwords ─────────────────────────────────────────────────────────
    (r'^DeleteVerificationCodes$',    r'onetimepasscodes',
     "Auto-delete verification codes", fmt_bool, 1, "del_otp"),

    # ── Dictation ──────────────────────────────────────────────────────────
    (r'Dictation Auto Punctuation Enabled', None,
     "Dictation: auto-punctuation",  fmt_bool, 1, "dict_autopunct"),
    (r'Dictation Enabled',          r'assistant',
     "Dictation",                    fmt_bool, 1, "dictation"),
    # AppleDictationAutoEnable: 0=Off 1=Control×2 2=Globe×2 3=Right⌘×2 4=Left⌘×2 5=Either⌘×2
    (r'^AppleDictationAutoEnable$',  r'HIToolbox',
     "Dictation shortcut",
     lambda v: {"0":"Off","1":"Control×2","2":"Globe×2",
                "3":"Right ⌘×2","4":"Left ⌘×2","5":"Either ⌘×2"}.get(str(int(float(v))), v),
     1, "dict_shortcut"),

    # ── Mouse & scrolling ──────────────────────────────────────────────────
    (r'com\.apple\.mouse\.scaling',     None,
     "Mouse tracking speed",         lambda v: v, 1, "mouse_speed"),
    (r'com\.apple\.scrollwheel\.scaling', None,
     "Scroll wheel speed",           lambda v: v, 1, "scroll_speed"),

    # ── Printing ───────────────────────────────────────────────────────────
    (r'^DefaultPaperID$',           r'PrintingPrefs',
     "Default paper size",
     lambda v: {"na-letter":"Letter","na-legal":"Legal","iso-a4":"A4",
                "iso-a3":"A3","na-tabloid":"Tabloid"}.get(v, v), 1, "paper_size"),

    # ── Notifications ─────────────────────────────────────────────────────
    # Sequoia: com.apple.ncprefs stores content_visibility directly
    (r'^content_visibility$',       r'ncprefs',
     "Notification previews",
     lambda v: {"0":"Always (default)","1":"When Unlocked","2":"Never","3":"Always"}.get(v, v),
     1, "notif_previews_global"),

    # Tahoe+: group.com.apple.usernoted.plist (1=Never 2=When Unlocked 3=Always)
    (r'^content_visibility$',       r'usernoted',
     "Notification previews (global)",
     lambda v: {"1":"Never","2":"When Unlocked","3":"Always"}.get(str(int(float(v))), v),
     2, "notif_previews_global"),

    # Global: Show notifications when display is sleeping / locked / mirroring
    # dnd=True means SUPPRESS (don't show); dnd=False means SHOW
    (r'^dnd_prefs\.dndDisplaySleep$', r'usernoted',
     "Notifications when display is sleeping",
     lambda v: "OFF (suppressed)" if str(v).lower() in ("true","1") else "ON (shown)",
     1, "notif_dnd_sleep"),
    (r'^dnd_prefs\.dndDisplayLock$',  r'usernoted',
     "Notifications when screen is locked",
     lambda v: "OFF (suppressed)" if str(v).lower() in ("true","1") else "ON (shown)",
     1, "notif_dnd_lock"),
    (r'^dnd_prefs\.dndMirrored$',     r'usernoted',
     "Notifications when mirroring/sharing display",
     lambda v: "OFF (Notifications Off)" if str(v).lower() in ("true","1") else "ON (Allow Notifications)",
     1, "notif_dnd_mirror"),

    (r'^sort_order$',                 r'usernoted',
     "Notification Center: sort order",
     lambda v: {"0":"By recency","1":"By app"}.get(str(int(float(v))), v),
     1, "notif_sort_order"),
    (r'^summarize_previews$',         r'usernoted',
     "Notification Center: summarize previews",
     fmt_bool, 1, "notif_summarize"),
    (r'^play_forwarded_notifications_sounds$', r'usernoted',
     "Notifications: sounds for forwarded notifications",
     fmt_bool, 1, "notif_forwarded_sounds"),
    (r'^dnd_prefs\.facetimeCanBreakDND$', r'usernoted',
     "Focus: FaceTime calls break through",
     fmt_bool, 1, "focus_facetime_break"),
    (r'^dnd_prefs\.playSoundsForForwardedNotifications$', r'usernoted',
     "Focus: sounds for forwarded notifications",
     fmt_bool, 1, "focus_forwarded_sounds"),
    (r'^dnd_prefs\.repeatedFacetimeCallsBreaksDND$', r'usernoted',
     "Focus: repeated FaceTime calls break through",
     fmt_bool, 1, "focus_repeated_facetime"),

    # Per-app: Show previews (content_visibility): 0=Default 1=Never 2=When Unlocked 3=Always
    (r'^app\[.+\]\.content_visibility$', r'usernoted',
     "Per-app notification previews",
     lambda v: {"0":"Default","1":"Never","2":"When Unlocked","3":"Always"}.get(str(int(float(v))), v),
     1, None),

    # Per-app: Notification grouping: 0=Automatic 1=By Application 2=Off
    (r'^app\[.+\]\.grouping$',          r'usernoted',
     "Per-app notification grouping",
     lambda v: {"0":"Automatic","1":"By Application","2":"Off"}.get(str(int(float(v))), v),
     1, None),

    # Per-app: flags bitmask — decode into human-readable feature list
    # bit 1 (0x2)=Badge  bit 2 (0x4)=Sound  bits 3+4 (0x18)=Desktop+AlertStyle
    # bits 0+8 (0x101): 0=NC on, 1=NC off  bit 12 (0x1000): 0=LockScreen on, 1=off
    # bit 25 (0x2000000)=Allow  bit 26 (0x4000000)=Critical  bit 29 (0x20000000)=TimeSensitive
    (r'^app\[.+\]\.flags$',             r'usernoted',
     "Per-app notification flags",
     lambda v: (lambda f: ", ".join(filter(None, [
         "notifications ON"  if f & 0x2000000 else "notifications OFF",
         "badge"             if f & 0x2       else None,
         "sound"             if f & 0x4       else None,
         {0b01:"desktop:temporary",0b10:"desktop:persistent"}.get((f>>3)&3, None),
         "notification-center" if not (f & 0x101) else None,
         "lock-screen"         if not (f & 0x1000) else None,
         "critical"          if f & 0x4000000 else None,
         "time-sensitive"    if f & 0x20000000 else None,
     ])))(int(float(v))),
     1, None),

    # ── Sound ─────────────────────────────────────────────────────────────
    # Alert sound: stored as file path; absent = default (Boop/Tink.aiff)
    # Tahoe UI names → file mapping (from AlertSounds.loctable):
    #   Boop=Tink  Breeze=Blow  Bubble=Pop  Crystal=Glass  Funky=Funk
    #   Heroine=Hero  Jump=Frog  Mezzo=Basso  Pebble=Bottle  Pluck=Purr
    #   Pong=Morse  Sonar=Ping  Sonumi=Sosumi  Submerge=Submarine
    (r'^com\.apple\.sound\.beep\.sound$', None,
     "Alert sound",
     lambda v: {
         "/System/Library/Sounds/Tink.aiff":      "Boop",
         "/System/Library/Sounds/Blow.aiff":      "Breeze",
         "/System/Library/Sounds/Pop.aiff":       "Bubble",
         "/System/Library/Sounds/Glass.aiff":     "Crystal",
         "/System/Library/Sounds/Funk.aiff":      "Funky",
         "/System/Library/Sounds/Hero.aiff":      "Heroine",
         "/System/Library/Sounds/Frog.aiff":      "Jump",
         "/System/Library/Sounds/Basso.aiff":     "Mezzo",
         "/System/Library/Sounds/Bottle.aiff":    "Pebble",
         "/System/Library/Sounds/Purr.aiff":      "Pluck",
         "/System/Library/Sounds/Morse.aiff":     "Pong",
         "/System/Library/Sounds/Ping.aiff":      "Sonar",
         "/System/Library/Sounds/Sosumi.aiff":    "Sonumi",
         "/System/Library/Sounds/Submarine.aiff": "Submerge",
     }.get(v, v),
     1, "alert_sound"),

    (r'^com\.apple\.sound\.beep\.volume$', None,
     "Alert volume",
     lambda v: f"{round(float(v)*100)}%", 1, "alert_volume"),

    (r'^com\.apple\.sound\.uiaudio\.enabled$', None,
     "Play UI sound effects", fmt_bool, 1, "ui_audio"),

    (r'^com\.apple\.sound\.beep\.feedback$', None,
     "Play feedback when volume changed", fmt_bool, 1, "beep_feedback"),

    (r'^AlertsUseMainDevice$', r'soundpref',
     "Play sound effects through",
     lambda v: "Selected Sound Output Device" if str(v) in ("1","True") else "Speakers",
     1, "alerts_device"),

    # StartupMute in NVRAM: %00 = sound ON (mute off), %01 = sound OFF (muted)
    (r'^StartupMute\s', r'nvram',
     "Play sound on startup",
     lambda v: "OFF" if "%01" in v else "ON",
     1, "startup_mute"),

    # ── Display & Focus ────────────────────────────────────────────────────
    (r'showListByDefault',          r'Displays-Settings',
     "Displays: show as list",     fmt_bool, 1, "displays_list"),
    (r'DisplayConfig\[0\]\.Rotation$', r'com\.apple\.windowserver\.displays',
     "Display rotation",
     lambda v: "Standard" if float(v)==0 else f"{int(float(v))}°", 1, "display_rotation"),
    (r'^TVConnectPolicy$',          r'com\.apple\.windowserver\.displays',
     "When connected to TV",
     lambda v: {"0":"Ask What to Show","1":"Mirror Entire Screen",
                "2":"Choose Window or App","3":"Use as Extended Display"}.get(str(int(float(v))), v),
     1, "tv_connect_policy"),
    (r'^Disable$',                  r'com\.apple\.universalcontrol',
     "Universal Control: allow pointer/keyboard to nearby Mac/iPad",
     lambda v: "OFF" if v=="True" else "ON", 1, "universal_control"),
    (r'disableCloudSync',           r'donotdisturbd',
     "Focus: share across devices",
     lambda v: "OFF" if str(v).lower() in ("true","1") else "ON",
     1, "focus_share_devices"),

    # Focus: GlobalConfiguration.json
    (r'^GlobalConfiguration\.modesCanImpactAvailability$', r'DoNotDisturb',
     "Focus status: share focus status",
     lambda v: {"2":"ON","1":"OFF"}.get(str(int(float(v))), v),
     1, "focus_share_status"),

    (r'^GlobalConfiguration\.preventAutoReply$', r'DoNotDisturb',
     "Focus status: prevent auto-reply",
     fmt_bool, 1, "focus_auto_reply"),

    # Focus: per-mode impactsAvailability (0=default/ON, 1=OFF, 2=ON)
    (r'^mode\[.+\]\.impactsAvailability$', r'DoNotDisturb',
     "Focus status: per-mode sharing",
     lambda v: {"0":"ON (default)","1":"OFF","2":"ON"}.get(str(int(float(v))), v),
     1, None),

    # ── Screen Time ────────────────────────────────────────────────────────
    (r'^screenTimeEnabled$',    r'screentimedx',
     "Screen Time: enabled",
     fmt_bool, 1, "st_enabled"),
    (r'^appAndWebsiteActivity$', r'screentimedx',
     "Screen Time: App & Website Activity",
     lambda v: "ON" if str(v) not in ("0","nil","none","") else "OFF",
     1, "st_app_activity"),
    (r'^cloudSyncingEnabled$',  r'screentimedx',
     "Screen Time: share across devices",
     fmt_bool, 1, "st_cloud_sync"),
    (r'^isPasscodeSet$',        r'screentimedx',
     "Screen Time: lock settings (passcode set)",
     fmt_bool, 1, "st_passcode"),
    (r'^eyeRelief$',            r'screentimedx',
     "Screen Distance: enforced",
     fmt_bool, 1, "st_eye_relief"),
    (r'^shareWebUsage$',        r'screentimedx',
     "Screen Time: share web usage",
     fmt_bool, 1, "st_share_web"),
    (r'^managed$',              r'screentimedx',
     "Screen Time: managed by MDM",
     fmt_bool, 1, "st_managed"),
    (r'^downtime_schedule_enabled$', r'screentimedx',
     "Screen Time: Downtime schedule enabled",
     fmt_bool, 1, "st_downtime"),
    (r'^content_privacy_enabled$', r'screentimedx',
     "Screen Time: Content & Privacy restrictions",
     fmt_bool, 1, "st_content_privacy"),
    (r'^always_allowed_apps_enabled$', r'screentimedx',
     "Screen Time: Always Allowed (configured)",
     fmt_bool, 1, "st_always_allowed"),
    (r'^app_limits_count$', r'screentimedx',
     "Screen Time: App Limits (total configured)",
     lambda v: f"{v} limits" if int(v) != 1 else "1 limit", 1, "st_app_limits_total"),
    (r'^app_limits_enabled_count$', r'screentimedx',
     "Screen Time: App Limits (currently active)",
     lambda v: f"{v} active", 1, "st_app_limits_active"),
    (r'^communicationPolicies\.communicationPolicy$', r'screentimedx',
     "Screen Time: Communication Limits (during screen time)",
     lambda v: {"0":"Everyone","1":"Contacts Only","2":"Contacts and groups"}.get(str(int(float(v))), v),
     1, "st_comm_policy"),
    (r'^communicationPolicies\.communicationWhileLimitedPolicy$', r'screentimedx',
     "Screen Time: Communication Limits (during downtime)",
     lambda v: {"0":"Everyone","1":"Specific contacts"}.get(str(int(float(v))), v),
     1, "st_comm_limited"),
    (r'^communicationPolicies\.communicationSafetyReceivingRestricted$', r'screentimedx',
     "Screen Time: Communication Safety (receiving)",
     fmt_bool, 1, "st_comm_safety_recv"),
    (r'^communicationPolicies\.communicationSafetySendingRestricted$', r'screentimedx',
     "Screen Time: Communication Safety (sending)",
     fmt_bool, 1, "st_comm_safety_send"),
    (r'^communicationPolicies\.communicationSafetyAnalytics$', r'screentimedx',
     "Screen Time: improve Communication Safety (analytics)",
     fmt_bool, 1, "st_comm_safety_analytics"),

    # ── Display & fonts ────────────────────────────────────────────────────
    (r'AppleFontSmoothing',                  None,
     "Font smoothing",
     lambda v: "OFF" if v=="0" else f"level {v}", 1, "font_smooth"),
    (r'AppleShowScrollBars',                 None,
     "Scroll bars",
     lambda v: {"Always":"Always visible","WhenScrolling":"When scrolling",
                "Automatic":"Automatic"}.get(v, v), 1, "scroll_bars"),
    (r'^AppleInterfaceStyle$',               None,
     "Dark Mode",
     lambda v: "Dark" if v=="Dark" else "Light" if not v else v, 1, "dark_mode"),
    (r'^AppleInterfaceStyleSwitchesAutomatically$', None,
     "Dark Mode: automatic schedule",        fmt_bool, 1, "dark_mode_auto"),
    (r'^AppleAccentColor$',                  None,
     "Accent color",
     lambda v: {"-1":"Graphite","0":"Red","1":"Orange","2":"Yellow",
                "3":"Green","4":"Blue","5":"Purple","6":"Pink"}.get(v, v),
     1, "accent_color"),
    (r'^AppleHighlightColor$',               None,
     "Highlight color",
     lambda v: v.split()[-1] if v.split() else v, 1, "highlight_color"),
    (r'^NSGlassDiffusionSetting$',            None,
     "Liquid Glass: tinted",                fmt_bool, 1, "glass_diffusion"),
    (r'^AppleIconAppearanceTheme$',          None,
     "Icon style",
     lambda v: {"TintedLight":"Tinted Light","TintedDark":"Tinted Dark",
                "Default":"Default"}.get(v, v), 1, "icon_theme"),
    (r'^AppleIconAppearanceTintColor$',      None,
     "Folder color",
     lambda v: v, 1, "folder_color"),

    (r'^AppleReduceDesktopTinting$',         None,
     "Wallpaper tinting in windows",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "desktop_tinting"),
    (r'^AppleScrollerPagingBehavior$',       None,
     "Click scroll bar",
     lambda v: "Jump to clicked spot" if v in ("True","1","YES") else "Jump to next page",
     1, "scroller_paging"),
    (r'^NSTableViewDefaultSizeMode$',        None,
     "Sidebar icon size / list view row size",
     lambda v: {"1":"Small","2":"Medium","3":"Large"}.get(v, v), 1, "tableview_size"),

    # ── Screen saver & lock ────────────────────────────────────────────────
    (r'^idleTime$',              r'screensaver',
     "Screen saver delay",      fmt_sec, 1, "ss_idle"),
    (r'^showClock$',             r'screensaver',
     "Screen saver clock",      fmt_bool, 1, "ss_clock"),
    (r'^askForPassword$',        r'screensaver',
     "Require password after sleep/screensaver", fmt_bool, 1, "ask_pw"),
    (r'askForPasswordDelay',                 None,
     "Password delay",          fmt_sec, 1, "ask_pw_delay"),

    # ── Energy & sleep ─────────────────────────────────────────────────────
    (r'Battery Power\.Display Sleep Timer',  None,
     "Display sleep (battery)", fmt_min, 1, "disp_sleep_bat"),
    (r'^Battery Power\.ReduceBrightness$',   None,
     "Dim display on battery",  fmt_bool, 1, "bat_dim"),
    (r'AC Power\.Display Sleep Timer',       None,
     "Display sleep (AC)",      fmt_min, 1, "disp_sleep_ac"),
    (r'Battery Power\.System Sleep Timer',   None,
     "System sleep (battery)",  fmt_min, 1, "sys_sleep_bat"),
    (r'AC Power\.System Sleep Timer',        None,
     "System sleep (AC)",       fmt_min, 1, "sys_sleep_ac"),
    (r'AC Power\.Disk Sleep Timer',          None,
     "Hard disk sleep (AC)",    fmt_min, 1, "disk_sleep_ac"),
    (r'AC Power\.DarkWakeBackgroundTasks',   None,
     "Wake for network access", fmt_bool, 1, "dark_wake_net"),
    (r'AC Power\.TTYSPreventSleep',          None,
     "Prevent sleep with active terminal", fmt_bool, 1, "tty_prevent_sleep"),
    (r'AC Power\.Standby Enabled',           None,
     "Standby mode",            fmt_bool, 1, "standby_enabled"),

    # ── Location Services ─────────────────────────────────────────────────
    (r'^LocationServicesEnabled$',           r'locationd',
     "Location Services",                   fmt_bool, 1, "location_services"),

    # ── Security ───────────────────────────────────────────────────────────
    (r'drop_all_level',                      None,
     "Firewall",
     lambda v: {"Last":"ON","Unknown":"OFF"}.get(v, v), 1, "firewall"),
    (r'^AutoLogOutDelay$',                   r'autologout',
     "Log out automatically after inactivity",
     lambda v: f"{int(float(v))//60}m ({v}s)" if str(v) not in ("","0") else "disabled",
     1, "autologout_delay"),
    (r'^LockdownMode$',                      r'LockdownMode',
     "Lockdown Mode",
     lambda v: "ON" if v.strip() not in ("0","","(unavailable)") else "OFF",
     1, "lockdown_mode"),
    (r'CBUser-\d+\.CBBlueReductionStatus',   None,
     "Night Shift",             relay_status, 1, "night_shift"),

    # ── iCloud & network ───────────────────────────────────────────────────
    (r'PrivacyProxyServiceStatus',  r'networkserviceproxy',
     "iCloud Private Relay",    relay_status, 1, "private_relay"),
    (r'DisablePrivateRelay',         r'SystemConfiguration/preferences',
     "Limit IP Address Tracking (per interface)",
     lambda v: "ON" if v == "1" else "OFF", 1, "disable_private_relay"),

    # ── Wi-Fi global settings ──────────────────────────────────────────────────
    (r'^PowerEnabled$',                        r'airport|wifi',
     "Wi-Fi",                                  fmt_bool, 1, "wifi_power"),
    (r'^RememberJoinedNetworks$',              r'airport|wifi',
     "Wi-Fi: remember joined networks",        fmt_bool, 1, "wifi_remember_nets"),
    (r'^AutoHotspotMode$',                     r'airport|wifi',
     "Wi-Fi: Personal Hotspot auto-join",
     lambda v: {"AskToJoin":"Ask to join","Automatic":"Automatic",
                "Off":"Off"}.get(v, v), 1, "wifi_hotspot_auto"),
    (r'^PrivateMACAddressModeSystemSetting$',  r'airport|wifi',
     "Wi-Fi: private MAC address mode",
     lambda v: {"0":"Rotating","1":"Fixed","2":"Off"}.get(v, v), 1, "wifi_mac_mode"),

    # ── Sharing services ───────────────────────────────────────────────────
    (r'com\.apple\.screensharing',  r'^sharing$',
     "Screen sharing",          fmt_bool, 1, "screen_share"),
    (r'com\.apple\.smbd',           r'^sharing$',
     "File sharing",            fmt_bool, 1, "file_share"),
    (r'com\.apple\.AppleFileServer',r'^sharing$',
     "AFP file sharing",        fmt_bool, 1, "afp_share"),
    (r'com\.apple\.RemoteDesktop',  r'^sharing$',
     "Remote management (ARD)", fmt_bool, 1, "remote_mgmt"),
    (r'com\.apple\.AirPlayXPCHelper',r'^sharing$',
     "AirPlay receiver",        fmt_bool, 1, "airplay_rx"),
    (r'com\.apple\.blued',          r'^sharing$',
     "Bluetooth sharing",       fmt_bool, 1, "bt_share"),

    # ── Accessibility: Zoom ────────────────────────────────────────────────
    (r'closeViewTrackpadGestureZoomEnabled', None,
     "Zoom: trackpad gesture",   fmt_bool, 1, "zoom_trackpad"),
    (r'closeViewScrollWheelToggle',         None,
     "Zoom: scroll wheel toggle", fmt_bool, 1, "zoom_scroll"),
    (r'closeViewSplitScreenRatio',          None,
     "Zoom: split-screen ratio",  lambda v: v, 1, "zoom_ratio"),
    (r'closeViewZoomFollowsFocus',          None,
     "Zoom: follows keyboard focus", fmt_bool, 1, "zoom_focus"),
    (r'closeViewHotkeysEnabled',            None,
     "Zoom: keyboard shortcut",  fmt_bool, 1, "zoom_hotkey"),
    (r'^closeViewScrollWheelModifiersInt$', None,
     "Zoom: scroll modifier key",
     lambda v: {"0":"None","262144":"Control","524288":"Option","786432":"Control+Option"}.get(str(round(float(v))), v),
     1, "zoom_scroll_mod"),
    (r'^HIDScrollZoomModifierMask$',        r'trackpad|Multitouch',
     "Zoom: scroll modifier key",
     lambda v: {"0":"None","262144":"Control","524288":"Option","786432":"Control+Option"}.get(str(round(float(v))), v),
     2, "zoom_scroll_mod"),
    (r'^closeViewInvertColors$',            None,
     "Zoom: invert colors",                fmt_bool, 1, "zoom_invert"),
    (r'^closeViewPanningMode$',             None,
     "Zoom: panning mode",
     lambda v: {"0":"Continuous","1":"Edge only","2":"Centered"}.get(v, v), 1, "zoom_pan_mode"),
    (r'^closeViewKeepZoomWindowStationary$',None,
     "Zoom: stationary window",            fmt_bool, 1, "zoom_stationary"),
    (r'^closeViewPressOnReleaseOff$',       None,
     "Zoom: press-and-release",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "zoom_press_release"),
    (r'^closeViewQuickSwitchHotKeysEnabled$',None,
     "Zoom: quick-switch hotkeys",         fmt_bool, 1, "zoom_quickswitch"),
    (r'^closeViewResizeHotKeysEnabled$',    None,
     "Zoom: resize hotkeys",               fmt_bool, 1, "zoom_resize_hk"),
    (r'^closeViewRestoreZoomFactorOnStartup$',None,
     "Zoom: restore zoom on login",        fmt_bool, 1, "zoom_restore"),
    (r'^closeViewTemporaryDetachEnabled$',  None,
     "Zoom: temporary detach",             fmt_bool, 1, "zoom_temp_detach"),
    (r'^closeViewTemporaryFreezePanningEnabled$',None,
     "Zoom: freeze panning hotkey",        fmt_bool, 1, "zoom_freeze_pan"),
    (r'^closeViewDisableUniversalControl$', None,
     "Zoom: disable Universal Control",    fmt_bool, 1, "zoom_disable_uc"),
    (r'^closeViewMonitorSelectionEnabled$', None,
     "Zoom: monitor selection",            fmt_bool, 1, "zoom_monitor_sel"),
    (r'^closeViewMonitorSelectionTrackpadGesture$',None,
     "Zoom: monitor selection gesture",    lambda v: v, 1, "zoom_monitor_gest"),
    (r'^closeViewFlashScreenOnNotificationEnabled$',None,
     "Flash screen for alerts",            fmt_bool, 1, "flash_screen"),
    (r'^flashScreen$',                     r'universalaccess|Accessibility',
     "Flash screen for alerts",            fmt_bool, 2, "flash_screen"),
    (r'com\.apple\.sound\.beep\.flash$',   None,
     "Flash screen for alerts",            fmt_bool, 3, "flash_screen"),
    (r'^hoverColorEnabled$',               r'universalaccess|Accessibility',
     "Hover Text: color highlight",        fmt_bool, 1, "hover_color"),

    # ── Menu Bar & Control Center ───────────────────────────────────────────
    (r'^_HIHideMenuBar$',            None,
     "Auto-hide menu bar",       fmt_bool, 1, "menubar_autohide"),
    (r'^AutoHideMenuBarOption$',     r'controlcenter',
     "Auto-hide menu bar (option)", fmt_menubar_hide, 1, "menubar_autohide_opt"),
    (r'^SLSMenuBarUseBlurredAppearance$', None,
     "Menu bar: show background", fmt_bool, 1, "menubar_bg"),
    (r'AirplayReceiverEnabled',    r'controlcenter',
     "AirPlay Receiver",          fmt_bool, 1, "cc_airplay_rx"),
    (r'^Battery$',              r'controlcenter',
     "Menu bar: Battery",        fmt_cc_item, 1, "cc_battery"),
    (r'^WiFi$',                 r'controlcenter',
     "Menu bar: Wi-Fi",          fmt_cc_item, 1, "cc_wifi"),
    (r'^Bluetooth$',            r'controlcenter',
     "Menu bar: Bluetooth",      fmt_cc_item, 1, "cc_btcc"),
    (r'^AirDrop$',              r'controlcenter',
     "Menu bar: AirDrop",        fmt_cc_item, 1, "cc_airdrop"),
    (r'^FocusModes$',           r'controlcenter',
     "Menu bar: Focus",          fmt_cc_item, 1, "cc_focus"),
    (r'^Sound$',                r'controlcenter',
     "Menu bar: Sound",          fmt_cc_item, 1, "cc_sound"),
    (r'^Display$',              r'controlcenter',
     "Menu bar: Display",        fmt_cc_item, 1, "cc_display"),
    (r'^NowPlaying$',           r'controlcenter',
     "Menu bar: Now Playing",    fmt_cc_item, 1, "cc_nowplaying"),
    (r'^VoiceControl$',         r'controlcenter',
     "Menu bar: Voice Control",  fmt_cc_item, 1, "cc_voicectl"),
    (r'^Siri$',                 r'controlcenter',
     "Menu bar: Siri",           fmt_cc_item, 1, "cc_siri"),
    (r'^Spotlight$',            r'controlcenter',
     "Menu bar: Spotlight",      fmt_cc_item, 1, "cc_spotlight"),
    (r'^ScreenMirroring$',      r'controlcenter',
     "Menu bar: Screen Mirroring", fmt_cc_item, 1, "cc_screenmirroring"),
    (r'^TimeMachine$',          r'controlcenter',
     "Menu bar: Time Machine",   fmt_cc_item, 1, "cc_timemachine"),
    (r'^Timer$',                r'controlcenter',
     "Menu bar: Timer",          fmt_cc_item, 1, "cc_timer"),
    (r'^UserSwitcher$',         r'controlcenter',
     "Menu bar: Fast User Switching", fmt_cc_item, 1, "cc_userswitcher"),
    (r'^Weather$',              r'controlcenter',
     "Menu bar: Weather",        fmt_cc_item, 1, "cc_weather"),
    (r'^visible$',              r'TextInputMenu',
     "Menu bar: Text Input / keyboard switcher", fmt_bool, 1, "cc_textinput"),

    # ── Bluetooth ──────────────────────────────────────────────────────────
    (r'ControllerPowerState',    r'Bluetooth',
     "Bluetooth",
     lambda v: {"1":"ON","0":"OFF"}.get(v, v), 1, "bluetooth"),
    (r'^enableGameControllerAutoSwitchMode$', r'Bluetooth|bluetooth',
     "Game controllers: auto-switch Bluetooth↔USB", fmt_bool, 1, "gc_auto_switch"),
    (r'^enableGameControllerUSBBluetoothPairing$', r'Bluetooth|bluetooth',
     "Game controllers: USB+Bluetooth pairing",    fmt_bool, 1, "gc_usb_bt_pair"),

    # ── Software updates ───────────────────────────────────────────────────
    (r'^AutoBackup$',            r'TimeMachine',
     "Time Machine: auto backup",        fmt_bool, 1, "tm_autobackup"),
    (r'^AutoBackupInterval$',    r'TimeMachine',
     "Time Machine: backup interval",    fmt_sec, 1, "tm_interval"),
    (r'^RequiresACPower$',       r'TimeMachine',
     "Time Machine: only on AC power",   fmt_bool, 1, "tm_acpower"),
    (r'^MobileBackups$',         r'TimeMachine',
     "Time Machine: local snapshots",    fmt_bool, 1, "tm_local_snap"),

    (r'AutomaticCheckEnabled',   r'SoftwareUpdate',
     "Auto-check for updates",  fmt_bool, 1, "sw_check"),
    (r'AutomaticallyInstallMacOSUpdates', None,
     "Auto-install macOS updates", fmt_bool, 1, "sw_install"),
    (r'AutomaticDownload',       r'SoftwareUpdate',
     "Auto-download updates",   fmt_bool, 1, "sw_download"),

    # ── macOS upgrade tracking ─────────────────────────────────────────────
    # SetupAssistant records the version you upgraded FROM
    (r'^PreviousSystemVersion$', r'SetupAssistant',
     "Upgraded from macOS",      lambda v: v, 1, "prev_macos_version"),
    (r'^PreviousBuildVersion$',  r'SetupAssistant',
     "Upgraded from build",      lambda v: v, 1, "prev_macos_build"),
    # SoftwareUpdate records when each build was installed
    (r'^InstallDateDictionary\.',r'SoftwareUpdate',
     "macOS update installed",
     lambda v: v[:10] if len(v) >= 10 else v, 1, "macos_install_date"),
    # iMessage relay migration tracks macOS version at time of migration
    (r'^systemVersionForLastRelayMICMigration$', r'sms',
     "iMessage relay: migrated to macOS", lambda v: v, 1, "imsg_relay_migration"),

    # ── Analytics ──────────────────────────────────────────────────────────
    # AutoSubmit / ThirdPartyDataSubmit: /Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist
    # (requires admin auth to change in UI; old SubmitDiagInfo domain kept for Sequoia compat)
    (r'AutoSubmit',              r'SubmitDiagInfo|CrashReporter',
     "Share Mac Analytics",      fmt_bool, 1, "analytics_mac"),
    (r'^ThirdPartyDataSubmit$',  r'CrashReporter',
     "Share with app developers", fmt_bool, 1, "analytics_3p"),

    # ── Screen saver ───────────────────────────────────────────────────────
    (r'^moduleDict\.moduleName$', r'screensaver',
     "Screen saver",            lambda v: v, 1, "ss_name"),

    # ── Sound ──────────────────────────────────────────────────────────────
    (r'com\.apple\.sound\.beep\.sound', None,
     "Alert sound",
     lambda v: v.split('/')[-1].replace('.aiff',''), 1, "alert_sound"),
    (r'com\.apple\.sound\.beep\.volume', None,
     "Alert volume",
     lambda v: f"{round(float(v)*100)}%", 1, "alert_volume"),
    (r'^ComfortSoundsSelectedSound\.\$objects\[2\]$', r'ComfortSounds',
     "Background sound",           lambda v: v, 1, "bg_sound"),
    (r'^relativeVolume$',          r'ComfortSounds',
     "Background sound volume",    lambda v: str(round(float(v), 2)), 1, "bg_sound_vol"),
    (r'^stopsOnLock$',             r'ComfortSounds',
     "Background sound stops on lock", fmt_bool, 1, "bg_sound_lock"),
    (r'^comfortSoundsEnabled$',    r'ComfortSounds',
     "Background sounds",          fmt_bool, 1, "bg_sound_enabled"),
    (r'^tinnitusFilterEnabled$',   r'ComfortSounds',
     "Background sounds: tinnitus filter", fmt_bool, 1, "bg_sound_tinnitus"),
    (r'^timerEnabled$',            r'ComfortSounds',
     "Background sounds: sleep timer",    fmt_bool, 1, "bg_sound_timer"),
    (r'^timerDurationInSeconds$',  r'ComfortSounds',
     "Background sounds: timer duration",
     lambda v: (f"{int(float(v))//60} min" if float(v) >= 60 else f"{int(float(v))}s"),
     1, "bg_sound_timer_dur"),
    (r'^timerOption$',             r'ComfortSounds',
     "Background sounds: timer type",
     lambda v: {"0":"After current track","1":"After timer duration"}.get(v, v), 1, "bg_sound_timer_opt"),
    (r'^timerOnlyOnFirstSession$', r'ComfortSounds',
     "Background sounds: timer (first session only)", fmt_bool, 1, "bg_sound_timer_first"),

    # ── Third-party app versions ────────────────────────────────────────────
    (r'^lastLaunchVersion$',          r'app-setapp',
     "Setapp version",               lambda v: v, 1, "setapp_version"),

    # ── Microsoft Office updates ────────────────────────────────────────────
    (r'^AppVersions\./Applications/Microsoft Excel\.app$',      r'autoupdate2',
     "Microsoft Excel version",     lambda v: v, 1, "msoffice_excel"),
    (r'^AppVersions\./Applications/Microsoft Word\.app$',       r'autoupdate2',
     "Microsoft Word version",      lambda v: v, 1, "msoffice_word"),
    (r'^AppVersions\./Applications/Microsoft PowerPoint\.app$', r'autoupdate2',
     "Microsoft PowerPoint version", lambda v: v, 1, "msoffice_ppt"),

    # ── Energy ─────────────────────────────────────────────────────────────
    (r'optimizeVideoStreamingOnBattery', None,
     "Optimize video streaming (battery)", fmt_bool, 1, "opt_video_bat"),

    # ── Trackpad gestures ──────────────────────────────────────────────────
    (r'fiveFingerPinchSwipeGesture', None,
     "Five-finger pinch gesture",
     lambda v: {"2":"ON","0":"OFF"}.get(v,v), 1, "gesture_5fp"),
    (r'TrackpadFiveFingerPinchGesture', None,
     "Five-finger pinch gesture",
     lambda v: {"2":"ON","0":"OFF"}.get(v,v), 2, "gesture_5fp"),
    (r'fourFingerPinchSwipeGesture', None,
     "Four-finger pinch gesture",
     lambda v: {"2":"ON","0":"OFF"}.get(v,v), 1, "gesture_4fp"),
    (r'TrackpadFourFingerPinchGesture', None,
     "Four-finger pinch gesture",
     lambda v: {"2":"ON","0":"OFF"}.get(v,v), 2, "gesture_4fp"),

    # ── Dock ───────────────────────────────────────────────────────────────
    (r'^autohide$',              r'com\.apple\.dock',
     "Dock auto-hide",          fmt_bool, 1, "dock_autohide"),
    (r'^tilesize$',              r'com\.apple\.dock',
     "Dock size",               lambda v: v, 1, "dock_size"),
    (r'^magnification$',         r'com\.apple\.dock',
     "Dock magnification",      fmt_bool, 1, "dock_mag"),
    (r'^orientation$',           r'com\.apple\.dock',
     "Dock position",
     lambda v: {"bottom":"Bottom","left":"Left","right":"Right"}.get(v,v), 1, "dock_pos"),
    (r'showDesktopGestureEnabled', r'com\.apple\.dock',
     "Show Desktop gesture",    fmt_bool, 1, "dock_desktop_gesture"),

    # ── Siri ───────────────────────────────────────────────────────────────
    (r'^Assistant Enabled$',                 r'assistant\.support',
     "Siri: enabled",                        fmt_bool, 1, "siri_enabled"),
    (r'Siri Status',                         None,
     "Siri",
     lambda v: {"1":"ON","0":"OFF"}.get(v, v), 2, "siri_enabled"),
    (r'^Use device speaker for TTS$',        r'assistant\.backedup',
     "Siri responses",
     lambda v: {"2":"Prefer Spoken Responses","1":"Automatic"}.get(str(int(float(v))), v),
     1, "siri_responses"),
    (r'^LockscreenEnabled$',                 r'Siri|assistant',
     "Siri on lock screen",                  fmt_bool, 1, "siri_lockscreen"),
    (r'^VoiceTriggerUserEnabled$',           r'Siri|assistant',
     "Hey Siri",                             fmt_bool, 1, "hey_siri"),
    (r'^VoiceTrigger Enabled$',              r'voicetrigger',
     "Hey Siri",                             fmt_bool, 2, "hey_siri"),
    (r'^Remote Darwin VoiceTrigger Enabled$',r'voicetrigger',
     "Hey Siri",                             fmt_bool, 3, "hey_siri"),
    (r'^UserPreferredVoiceTriggerPhraseType$',r'voicetrigger',
     "Siri activation phrase",
     lambda v: {"0":"Hey Siri","1":"Siri"}.get(v, v), 1, "siri_phrase_type"),
    (r'^Siri Data Sharing Opt-In Status$',   r'assistant\.support',
     "Improve Siri & Dictation (data sharing)",
     lambda v: "ON (opted-in)" if str(v) in ("1",) else "OFF (opted-out)", 1, "siri_data_sharing"),

    # ── Spotlight ──────────────────────────────────────────────────────────
    # EnabledPreferenceRules[] is an array of DISABLED category IDs.
    # Absent key means default (enabled). Identifiers:
    #   Custom.relatedContents, com.apple.iBooksX, com.apple.calculator,
    #   System.folders, System.apps, System.files, System.iPhone-apps,
    #   System.menu-items, com.apple.terminal, etc.
    (r'^EnabledPreferenceRules\[\d+\]$',        r'Spotlight',
     "Spotlight: disabled category",
     lambda v: {
         "Custom.relatedContents":  "Show Related Content",
         "com.apple.iBooksX":       "Books",
         "com.apple.calculator":    "Calculator",
         "System.folders":          "Folders",
         "System.apps":             "Apps (system)",
         "System.files":            "Files",
         "System.iPhone-apps":      "iPhone Apps",
         "System.menu-items":       "Menu Items",
     }.get(v, v), 1, None),
    (r'^PasteboardHistoryEnabled$',             r'Spotlight',
     "Spotlight: search clipboard (Results from Clipboard)",
     fmt_bool, 1, "spotlight_clipboard"),
    (r'^Search Queries Data Sharing Status$',   r'assistant\.support',
     "Spotlight: Help Apple Improve Search",
     lambda v: "OFF" if str(int(float(v))) in ("2","3") else "ON",
     1, "spotlight_analytics"),

    # ── Keyboard: repeat & delay ──────────────────────────────────────────
    (r'^KeyRepeat$',                             None,
     "Key repeat rate",
     lambda v: "Off" if int(v) >= 300000 else f"{v} (lower=faster)", 1, "key_repeat"),
    (r'^InitialKeyRepeat$',                      None,
     "Key repeat delay",
     lambda v: f"{v} (lower=shorter)", 1, "key_repeat_delay"),

    # ── Keyboard: Globe/fn key action ─────────────────────────────────────
    (r'^AppleFnUsageType$',                      r'HIToolbox',
     "Press Globe/fn key to",
     lambda v: {"0":"Do Nothing","1":"Change Input Source","2":"Show Emoji & Symbols","3":"Start Dictation"}.get(str(int(float(v))), v),
     1, "globe_key_action"),

    # ── Mouse & input extras ───────────────────────────────────────────────
    (r'com\.apple\.mouse\.doubleClickThreshold', None,
     "Double-click speed",                   lambda v: str(round(float(v), 1)), 1, "dbl_click_speed"),
    (r'^com\.apple\.mouse\.linear$',         None,
     "Mouse: pointer acceleration",
     lambda v: "OFF" if str(v) in ("1","True","true") else "ON", 1, "mouse_accel"),
    (r'^MouseButtonMode$',                   r'AppleMultitouchMouse|BluetoothMultitouch.*mouse',
     "Mouse: secondary click",
     lambda v: {"OneButton":"Off","TwoButton":"Click Right Side","RightHanded":"Click Right Side","LeftHanded":"Click Left Side"}.get(v, v),
     1, "mouse_secondary_click"),

    # ── Voice Control ──────────────────────────────────────────────────────
    (r'^CommandAndControlEnabled$',          r'Accessibility',
     "Voice Control: enabled",              fmt_bool, 1, "vc_enabled"),
    (r'^CACOverlayFadeOpacity$',             r'speech\.recognition',
     "Voice Control: overlay opacity",       lambda v: f"{round(float(v)*100)}%", 1, "vc_overlay_opacity"),
    (r'^CACOverlayFadingEnabled$',           r'speech\.recognition',
     "Voice Control: overlay fades",         fmt_bool, 1, "vc_overlay_fade"),
    (r'^DictationIMAlwaysShowOverlayKey$',   r'speech\.recognition',
     "Voice Control: always show overlay",
     lambda v: "NamedElements" if v == "NamedElements" else "None", 1, "vc_overlay_show"),

    # ── Accessibility: Switch Control & specialized ────────────────────────
    (r'^switchOnOffKey$',                    r'universalaccess|Accessibility',
     "Switch Control keyboard shortcut",     fmt_bool, 1, "switch_ctrl_shortcut"),
    (r'^keyboardAccessEnabled$',             r'universalaccess|Accessibility',
     "Switch Control: keyboard input",       fmt_bool, 1, "switch_kbd_access"),
    (r'^AssistiveTouchScannerEnabled$',      r'universalaccess|Accessibility',
     "Switch Control: scanner",              fmt_bool, 1, "switch_scanner"),
    (r'^switchHoverTextToolbarEnabled$',     r'universalaccess|Accessibility',
     "Switch Control: hover text toolbar",   fmt_bool, 1, "switch_hover_text"),
    (r'^AXSAudioDonationSiriImprovementEnabled$', r'universalaccess|Accessibility',
     "Improve Assistive Voice Features (audio donation)",
     fmt_bool, 1, "siri_donation"),
    (r'^Use Atypical Speech Model$',         r'assistant|Siri',
     "Siri: listen for atypical speech",     fmt_bool, 1, "siri_atypical"),
    (r'^Use device speaker for TTS$',        r'assistant|Siri',
     "Siri: use device speaker for speech",  fmt_bool, 1, "siri_speaker"),
    (r'^kTTSVBAllowVoiceBankingAppUsage$',   r'universalaccess|Accessibility',
     "Voice banking app access",             fmt_bool, 1, "voice_banking"),

    # ── Stage Manager ──────────────────────────────────────────────────────
    (r'^StageManager$',                      r'controlcenter',
     "Stage Manager",
     lambda v: {"0":"OFF","2":"ON","4":"ON","6":"ON","8":"ON"}.get(v, v), 1, "cc_stagemgr"),
    (r'^GloballyEnabled$',                   r'WindowManager',
     "Stage Manager",                        fmt_bool, 2, "cc_stagemgr"),
    (r'^AutoHide$',                          r'WindowManager',
     "Stage Manager: auto-hide strips",      fmt_bool, 1, "wm_sm_autohide"),
    (r'^StandardHideDesktopIcons$',          r'WindowManager',
     "Stage Manager: hide desktop icons",    fmt_bool, 1, "wm_sm_desk_icons"),
    (r'^HideDesktop$',                       r'WindowManager',
     "Stage Manager: hide desktop icons",    fmt_bool, 2, "wm_sm_desk_icons"),

    # ── Window tiling & Stage Manager ─────────────────────────────────────
    (r'^EnableTiledWindowMargins$',          r'WindowManager',
     "Window tiling: margins",               fmt_bool, 1, "wm_margins"),
    (r'^EnableTilingByEdgeDrag$',            r'WindowManager',
     "Window tiling: drag to edge",          fmt_bool, 1, "wm_edge_drag"),
    (r'^EnableTopTilingByEdgeDrag$',         r'WindowManager',
     "Window tiling: drag to top edge",      fmt_bool, 1, "wm_top_drag"),
    (r'^StageManagerHideWidgets$',           r'WindowManager',
     "Stage Manager: hide widgets",          fmt_bool, 1, "wm_sm_widgets"),
    (r'^StandardHideWidgets$',               r'WindowManager',
     "Stage Manager: hide widgets",          fmt_bool, 2, "wm_sm_widgets"),
    (r'^EnableTilingOptionAccelerator$',     r'WindowManager',
     "Window tiling: option key accelerator",fmt_bool, 1, "wm_opt_accel"),
    (r'^AppWindowGroupingBehavior$',         r'WindowManager',
     "Stage Manager: group app windows",
     lambda v: "Together" if v == "1" else "Separate", 1, "wm_sm_grouping"),
    (r'^EnableStandardClickToShowDesktop$',  r'WindowManager',
     "Click wallpaper to show desktop",      fmt_bool, 1, "wm_click_desktop"),

    # ── Dock extras ────────────────────────────────────────────────────────
    (r'^largesize$',                         r'com\.apple\.dock',
     "Dock magnification size",              lambda v: v, 1, "dock_largesize"),
    (r'^expose-group-apps$',                 r'com\.apple\.dock',
     "Mission Control: group by app",        fmt_bool, 1, "mc_group_apps"),
    (r'^enterMissionControlByTopWindowDrag$',r'com\.apple\.dock',
     "Mission Control: drag window to top",  fmt_bool, 1, "mc_top_drag"),
    (r'^show-recents$',                      r'com\.apple\.dock',
     "Dock: show recent apps",               fmt_bool, 1, "dock_recents"),
    (r'^launchanim$',                        r'com\.apple\.dock',
     "Dock: animate opening apps",           fmt_bool, 1, "dock_launchanim"),
    (r'^mineffect$',                         r'com\.apple\.dock',
     "Dock: minimize effect",
     lambda v: {"genie":"Genie","scale":"Scale","suck":"Suck"}.get(v, v), 1, "dock_mineffect"),
    (r'^minimize-to-application$',           r'com\.apple\.dock',
     "Dock: minimize to app icon",           fmt_bool, 1, "dock_min_to_app"),
    (r'^show-process-indicators$',           r'com\.apple\.dock',
     "Dock: show app indicators",            fmt_bool, 1, "dock_proc_ind"),
    (r'^mru-spaces$',                        r'com\.apple\.dock',
     "Spaces: auto-rearrange by recent use", fmt_bool, 1, "spaces_mru"),

    # ── Spaces & widgets ───────────────────────────────────────────────────
    (r'^spans-displays$',                    r'com\.apple\.spaces',
     "Displays have separate Spaces",        fmt_bool, 1, "spaces_per_display"),
    # macOS 26+: widgetAppearance controls "Dim widgets on desktop"
    # macOS 15-: widgetAppearance controlled widget color (0=Automatic,1=Monochrome,2=Full Color)
    (r'^widgetAppearance$',                  r'com\.apple\.widgets',
     "Dim widgets on desktop / Widget appearance",
     lambda v: {"0":"Always (dim) / Automatic (color)","1":"Never (dim) / Monochrome (color)","2":"Automatically (dim) / Full Color (color)"}.get(v, v), 1, "widget_appearance"),

    # ── Window behavior ────────────────────────────────────────────────────
    (r'^AppleSpacesSwitchOnActivate$',       None,
     "Spaces: switch to app's Space on activate", fmt_bool, 1, "spaces_switch_activate"),
    (r'^NSCloseAlwaysConfirmsChanges$',      None,
     "Ask to keep changes when closing documents", fmt_bool, 1, "close_confirm"),
    (r'^NSQuitAlwaysKeepsWindows$',          None,
     "Close windows when quitting an application",
     lambda v: "OFF (windows kept/restored)" if str(v) in ("1","True","true","YES") else "ON (windows close)", 1, "quit_keeps_windows"),
    (r'^AppleWindowTabbingMode$',            None,
     "Prefer tabs when opening documents",
     lambda v: {"manual":"Manual","always":"Always",
                "fullscreen":"In Full Screen Only"}.get(v, v), 1, "tab_mode"),
    (r'^AppleActionOnDoubleClick$',          None,
     "Double-click titlebar",
     lambda v: {"Maximize":"Maximize","Minimize":"Minimize",
                "None":"Do nothing"}.get(v, v), 1, "dbl_click_title"),
    (r'^AppleMiniaturizeOnDoubleClick$',     None,
     "Double-click titlebar",
     lambda v: "Minimize" if v in ("True","1","YES") else "Maximize", 2, "dbl_click_title"),
    (r'com\.apple\.springing\.enabled',      None,
     "Spring-loaded folders",               fmt_bool, 1, "springing"),
    (r'^AppleMenuBarVisibleInFullscreen$',   None,
     "Menu bar: visible in full screen",    fmt_bool, 1, "menubar_fullscreen"),
    (r'^AppleEnableSwipeNavigateWithScrolls$', None,
     "Swipe between pages",                 fmt_bool, 1, "swipe_navigate"),
    (r'^AppleScrollAnimationEnabled$',       None,
     "Scroll animation",                    fmt_bool, 1, "scroll_anim"),

    # ── Date & time ────────────────────────────────────────────────────────
    (r'^AppleICUForce24HourTime$',           None,
     "24-hour time",                         fmt_bool, 1, "time_24h"),

    # ── Login Window ───────────────────────────────────────────────────────
    (r'^LoginwindowText$',                   r'loginwindow',
     "Lock screen message",                  lambda v: v, 1, "lw_text"),
    (r'^HideUserAvatarAndName$',             r'loginwindow',
     "Lock screen: show user name and photo",
     lambda v: "OFF" if str(v) in ("1","True","true") else "ON", 1, "lw_hide_avatar"),
    (r'^SHOWFULLNAME$',                      r'loginwindow',
     "Login window: list of users vs name+password",
     lambda v: "Name and password" if str(v) in ("1","True","true") else "List of users", 1, "lw_fullname"),
    (r'^PowerOffDisabled$',                  r'loginwindow',
     "Lock screen: show sleep/restart/shutdown buttons",
     lambda v: "OFF" if str(v) in ("1","True","true") else "ON", 1, "lw_poweroff"),
    (r'^RetriesUntilHint$',                  r'loginwindow',
     "Lock screen: show password hints",
     lambda v: "OFF" if v == "0" else f"ON (after {v} tries)", 1, "lw_hint"),
    (r'^tokenRemovalAction$',                r'screensaver',
     "Lock screen on smart card removal",
     lambda v: "ON" if str(v) == "1" else "OFF", 1, "lw_token_removal"),
    (r'^UseVoiceOverAtLoginwindow$',         r'loginwindow',
     "Login window: VoiceOver",              fmt_bool, 1, "lw_vo"),
    (r'^accessibilitySettings\.mouseDriver$',r'loginwindow',
     "Login window: Mouse Keys",             fmt_bool, 1, "lw_mousekeys"),
    (r'^accessibilitySettings\.slowKey$',    r'loginwindow',
     "Login window: Slow Keys",              fmt_bool, 1, "lw_slowkey"),
    (r'^accessibilitySettings\.stickyKey$',  r'loginwindow',
     "Login window: Sticky Keys",            fmt_bool, 1, "lw_stickykey"),
    (r'^accessibilitySettings\.switchOnOffKey$', r'loginwindow',
     "Login window: Switch Control",         fmt_bool, 1, "lw_switch"),
    (r'^accessibilitySettings\.virtualKeyboardOnOff$', r'loginwindow',
     "Login window: Accessibility Keyboard", fmt_bool, 1, "lw_vkbd"),
    (r'^accessibilitySettings\.voiceOverOnOffKey$', r'loginwindow',
     "Login window: VoiceOver shortcut",     fmt_bool, 1, "lw_vokey"),

    # ── Privacy & ads ─────────────────────────────────────────────────────
    (r'^allowApplePersonalizedAdvertising$',  r'AdLib',
     "Personalized ads",                     fmt_bool, 1, "personalized_ads"),

    # ── Mail ───────────────────────────────────────────────────────────────
    (r'^AlertForNonmatchingDomains$',         r'mail',
     "Mail: warn on reply to different domain", fmt_bool, 1, "mail_domain_warn"),
    (r'^ExpandPrivateAliases$',               r'mail',
     "Mail: expand private aliases",          fmt_bool, 1, "mail_expand_alias"),
    (r'^DisableURLLoading$',                  r'mail',
     "Mail: load remote content",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "mail_remote_content"),
    (r'^AddressDisplayMode$',                 r'mail',
     "Mail: address display",
     lambda v: {"0":"Name only","1":"Name and address","2":"Address only"}.get(v, v),
     1, "mail_addr_display"),

    # ── Trackpad hardware settings ─────────────────────────────────────────
    (r'^TrackpadRightClick$',                r'trackpad|AppleMultitouch',
     "Right-click (trackpad)",               fmt_bool, 2, "secondary_click"),
    (r'^ActuateDetents$',                    r'trackpad|AppleMultitouch',
     "Trackpad: force click",
     lambda v: "ON" if v in ("1","True","YES") else "OFF", 1, "trackpad_force"),
    (r'^ForceSuppressed$',                   r'trackpad|AppleMultitouch',
     "Trackpad: force click",
     lambda v: "OFF" if v in ("1","True","YES") else "ON", 2, "trackpad_force"),
    (r'^FirstClickThreshold$',               r'trackpad|AppleMultitouch',
     "Trackpad: click pressure",
     lambda v: {"0":"Light","1":"Medium","2":"Firm"}.get(v, v), 1, "trackpad_click_pres"),
    (r'^SecondClickThreshold$',              r'trackpad|AppleMultitouch',
     "Trackpad: force click pressure",
     lambda v: {"0":"Light","1":"Medium","2":"Firm"}.get(v, v), 1, "trackpad_fclick_pres"),

    # ── Global input & text ────────────────────────────────────────────────
    (r'^NSAutomaticPeriodSubstitutionEnabled$', None,
     "Double-space to period",               fmt_bool, 1, "period_sub"),
    (r'^NSAutomaticCapitalizationEnabled$',  None,
     "Auto-capitalization",                  fmt_bool, 1, "auto_cap"),
    (r'^NSAutomaticDashSubstitutionEnabled$',None,
     "Smart dashes",                         fmt_bool, 1, "smart_dashes"),
    (r'^NSAutomaticQuoteSubstitutionEnabled$',None,
     "Smart quotes",                         fmt_bool, 1, "smart_quotes"),
    (r'^KB_DoubleQuoteOption$',              None,
     "Smart quotes: double quote style",     lambda v: v, 1, "smart_quotes_dbl"),
    (r'^KB_SingleQuoteOption$',              None,
     "Smart quotes: single quote style",     lambda v: v, 1, "smart_quotes_sgl"),
    (r'^KB_SpellingLanguage\.KB_SpellingLanguageIsAutomatic$', None,
     "Spelling: automatic language detection", fmt_bool, 1, "spelling_lang_auto"),
    (r'^NSUserQuotesArray\[0\]$',            None,
     "Smart quotes: open double",            lambda v: v, 1, "sq_open_dbl"),
    (r'^NSUserQuotesArray\[1\]$',            None,
     "Smart quotes: close double",           lambda v: v, 1, "sq_close_dbl"),
    (r'^NSUserQuotesArray\[2\]$',            None,
     "Smart quotes: open single",            lambda v: v, 1, "sq_open_sgl"),
    (r'^NSUserQuotesArray\[3\]$',            None,
     "Smart quotes: close single",           lambda v: v, 1, "sq_close_sgl"),
    (r'^NSAutomaticInlinePredictionEnabled$',None,
     "Inline text predictions",              fmt_bool, 1, "inline_pred"),
    (r'^NSAutomaticCapitalizationEnabled$',  None,
     "Auto-capitalization",                  fmt_bool, 1, "auto_cap"),
    (r'^NSPersonNameDefaultDisplayNameOrder$', None,
     "Name display order",
     lambda v: {"0":"Family name first","1":"Given name first"}.get(v, v), 1, "name_order"),
    (r'^com\.apple\.trackpad\.forceClick$',  None,
     "Trackpad: force click",
     lambda v: "ON" if v in ("1","True","YES") else "OFF", 3, "trackpad_force"),
    (r'^com\.apple\.trackpad\.scaling$',     None,
     "Trackpad speed",                       lambda v: v, 1, "trackpad_speed"),
    (r'^AppleKeyboardUIMode$',               None,
     "Full Keyboard Access",
     lambda v: "All controls" if v in ("2","3") else "Text fields only", 1, "kbd_ui_mode"),

    # ── Input Sources menu ─────────────────────────────────────────────────
    (r'^visible$',                           r'TextInputMenu',
     "Input Sources in menu bar",            fmt_bool, 1, "input_src_menu"),

    # ── Printing ───────────────────────────────────────────────────────────
    (r'^UseLastPrinter$',                    r'[Pp]rint',
     "Printing: use last printer",           fmt_bool, 1, "use_last_printer"),

    # ── Login Window ──────────────────────────────────────────── (extras) ─
    (r'^GuestEnabled$',                      r'loginwindow|LoginWindow',
     "Login window: guest account",          fmt_bool, 1, "lw_guest"),
    # AutologinUsername = macOS 26+; autoLoginUser = Sequoia and earlier
    (r'^AutologinUsername$|^autoLoginUser$',  r'loginwindow',
     "Automatically log in as",              lambda v: v, 1, "autologin_user"),

    # ── Sharing & network ──────────────────────────────────────────────────
    (r'^AllowGuestAccess$',                  r'smb',
     "SMB: allow guest access",              fmt_bool, 1, "smb_guest"),

    # ── TouchID ────────────────────────────────────────────────────────────
    (r'^DisableTouchIDFUS$',                 r'touchid',
     "TouchID: disabled at login",
     lambda v: "ON" if v in ("True","1","YES") else "OFF", 1, "touchid_fus"),

    # ── Finder ────────────────────────────────────────────────────────────
    (r'^ShowHardDrivesOnDesktop$',           r'finder',
     "Finder: hard drives on desktop",       fmt_bool, 1, "finder_hdd_desk"),
    (r'^ShowExternalHardDrivesOnDesktop$',   r'finder',
     "Finder: external drives on desktop",   fmt_bool, 1, "finder_ext_desk"),
    (r'^ShowRemovableMediaOnDesktop$',       r'finder',
     "Finder: removable media on desktop",   fmt_bool, 1, "finder_rm_desk"),
    (r'^ShowMountedServersOnDesktop$',       r'finder',
     "Finder: servers on desktop",           fmt_bool, 1, "finder_srv_desk"),
    (r'^NewWindowTarget$',                   r'finder',
     "Finder: new window shows",
     lambda v: {"PfHm":"Home","PfDe":"Desktop","PfDo":"Documents",
                "PfCm":"Computer","PfRe":"Recents","PfVo":"Volume",
                "PfLo":"Other"}.get(v, v), 1, "finder_newwin"),
    (r'^FXEnableExtensionChangeWarning$',    r'finder',
     "Finder: warn when changing extension", fmt_bool, 1, "finder_ext_warn"),
    (r'^FXRemoveOldTrashItems$',             r'finder',
     "Finder: empty Trash after 30 days",    fmt_bool, 1, "finder_trash_old"),
    (r'^WarnOnEmptyTrash$',                  r'finder',
     "Finder: warn before emptying Trash",   fmt_bool, 1, "finder_trash_warn"),
    (r'^ShowPathbar$',                       r'finder',
     "Finder: path bar",                     fmt_bool, 1, "finder_pathbar"),
    (r'^ShowStatusBar$',                     r'finder',
     "Finder: status bar",                   fmt_bool, 1, "finder_statusbar"),
    (r'^ShowTabView$',                       r'finder',
     "Finder: tab bar",                      fmt_bool, 1, "finder_tabbar"),
    (r'^NSWindowTabbingShoudShowTabBarKey-com\.apple\.finder\.',  None,
     "Finder: tab bar visible",              fmt_bool, 1, "finder_tabbar_vis"),
    (r'^FXPreferredViewStyle$',              r'finder',
     "Finder: default view",
     lambda v: {"icnv":"Icon","Nlsv":"List","clmv":"Column",
                "glyv":"Gallery"}.get(v, v), 1, "finder_view"),
    (r'^_FXSortFoldersFirst$',               r'finder',
     "Finder: folders on top when sorting",  fmt_bool, 1, "finder_folders_top"),
    (r'^_FXSortFoldersFirstOnDesktop$',      r'finder',
     "Finder: folders on top on desktop",    fmt_bool, 1, "finder_folders_top_desk"),
    (r'^FXDefaultSearchScope$',              r'finder',
     "Finder: search scope",
     lambda v: {"SCev":"This Mac","SCcf":"Current folder",
                "SCsp":"Previous scope"}.get(v, v), 1, "finder_search"),
    (r'^AppleShowAllFiles$',                 r'finder',
     "Finder: show hidden files",            fmt_bool, 1, "finder_hidden"),
    (r'^_FXEnableColumnAutoSizing$',         r'finder',
     "Finder: auto-size columns",            fmt_bool, 1, "finder_col_auto"),
    (r'^AppleShowAllExtensions$',            None,
     "Finder: show all filename extensions", fmt_bool, 1, "finder_all_ext"),
    (r'^FinderSpawnTab$',                    r'finder',
     "Finder: open folders in tabs",         fmt_bool, 1, "finder_spawn_tab"),

    # ── Region, locale & language ──────────────────────────────────────────
    (r'^AppleLocale$',                       None,
     "Region",
     lambda v: (v.split('@')[0] + " (" + v.split('@calendar=')[1].title() + " calendar)"
                if '@calendar=' in v else v.split('@')[0]), 1, "apple_locale"),
    (r'^AppleLanguages\[0\]$',              None,
     "Primary language",                     lambda v: v, 1, "lang_primary"),
    (r'^AppleLanguages\[[1-9]',             None,
     "Secondary language list",              lambda v: v, 1, "lang_secondary"),
    (r'^AppleFirstWeekday\.',               None,
     "First day of week",
     lambda v: {"1":"Sunday","2":"Monday","7":"Saturday"}.get(v, v), 1, "first_weekday"),
    (r'^AppleTemperatureUnit$',             None,
     "Temperature unit",
     lambda v: {"Celsius":"Celsius","Fahrenheit":"Fahrenheit"}.get(v, v), 1, "temp_unit"),
    (r'^AppleMetricUnits$',                 None,
     "Metric units",                         fmt_bool, 1, "metric_units"),
    (r'^AppleMeasurementUnits$',            None,
     "Measurement units",                    lambda v: v, 1, "measurement_units"),

    # ── Accessibility: display & cursor ───────────────────────────────────
    # ── Accessibility: Vision / Display ───────────────────────────────────
    (r'^InvertColorsEnabled$',               r'universalaccess|Accessibility',
     "Invert Colors",                        fmt_bool, 1, "invert_colors"),
    (r'^whiteOnBlack$',                      r'universalaccess|Accessibility',
     "Invert Colors",                        fmt_bool, 2, "invert_colors"),
    (r'^DisplayUseInvertedPolarity$',        r'CoreGraphics',
     "Invert Colors",                        fmt_bool, 3, "invert_colors"),
    (r'^__Inverted__-MADisplayFilterCategoryEnabled$', r'mediaaccessibility',
     "Invert Colors",                        fmt_bool, 4, "invert_colors"),
    (r'^AXSClassicInvertColorsPreference$',  r'universalaccess|Accessibility',
     "Classic Invert Colors",                fmt_bool, 1, "classic_invert"),
    (r'^GrayscaleDisplay$',                  r'universalaccess|Accessibility',
     "Grayscale display",                    fmt_bool, 1, "grayscale_display"),
    (r'^grayscale$',                         r'universalaccess|Accessibility',
     "Grayscale display",                    fmt_bool, 2, "grayscale_display"),
    (r'^DifferentiateWithoutColor$',         r'universalaccess|Accessibility',
     "Differentiate without color",          fmt_bool, 1, "diff_no_color"),
    (r'^differentiateWithoutColor$',         r'universalaccess|Accessibility',
     "Differentiate without color",          fmt_bool, 2, "diff_no_color"),
    (r'^DarkenSystemColors$',                None,
     "Increase Contrast",                    fmt_bool, 3, "increase_contrast"),
    (r'^contrast$',                          r'universalaccess|Accessibility',
     "Increase Contrast: level",
     lambda v: f"{round(float(v)*100)}%" if float(v) > 0 else "0% (off)", 1, "contrast_level"),
    (r'^ButtonShapesEnabled$',               r'universalaccess|Accessibility',
     "Button shapes",                        fmt_bool, 1, "btn_shapes"),
    (r'^showToolbarButtonShapes$',           r'universalaccess|Accessibility',
     "Button shapes",                        fmt_bool, 2, "btn_shapes"),
    (r'^PhotosensitiveMitigation$',          r'universalaccess|Accessibility',
     "Reduce flashing lights",               fmt_bool, 1, "photo_mitigation"),
    (r'^ReduceMotionAutoplayAnimatedImagesEnabled$', None,
     "Reduce Motion: auto-play animated images", fmt_bool, 1, "rm_anim_images"),
    (r'^PrefersNonBlinkingCursorIndicator$', r'universalaccess|Accessibility',
     "Non-blinking text cursor",             fmt_bool, 1, "nonblink_cursor"),
    (r'^UIPreferredContentSizeCategoryName$', None,
     "Text size (Dynamic Type)",
     lambda v: v.replace('UICTContentSizeCategory','').replace('Accessibility','Accessibility '), 1, "text_size"),
    (r'^closeViewSmoothImages$',             r'universalaccess|Accessibility',
     "Zoom: smooth images",                  fmt_bool, 1, "zoom_smooth_img"),
    (r'^showWindowTitlebarIcons$',           r'universalaccess|Accessibility',
     "Show window title bar icons",          fmt_bool, 1, "window_title_icons"),

    # ── Accessibility: Zoom ───── (cursor state is noise; hotkeys etc. already above)
    (r'^closeViewScrollWheelToggle$',        None,
     "Zoom: scroll wheel toggle",            fmt_bool, 2, "zoom_scroll"),

    # ── Accessibility: Hover Text & cursor ────────────────────────────────
    (r'^hoverTextEnabled$',                  r'universalaccess|Accessibility',
     "Accessibility: Hover Text",            fmt_bool, 1, "hover_text"),
    (r'^hoverTypingEnabled$',                r'universalaccess|Accessibility',
     "Accessibility: Hover Text",            fmt_bool, 2, "hover_text"),
    (r'^hoverTextIsAlwaysOn$',               r'universalaccess|Accessibility',
     "Hover Text: always on",                fmt_bool, 1, "hover_text_always"),
    (r'^hoverTypingFontSize$',               r'universalaccess|Accessibility',
     "Hover Text: font size",                lambda v: v, 1, "hover_text_size"),
    (r'^mouseDriverCursorSize$',             r'universalaccess|Accessibility',
     "Cursor size",
     lambda v: str(round(float(v), 1)), 1, "cursor_size"),
    (r'^cursorIsCustomized$',                r'universalaccess|Accessibility',
     "Custom cursor colors",                 fmt_bool, 1, "cursor_custom"),
    (r'^CGDisableCursorLocationMagnification$', None,
     "Shake pointer to locate cursor",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "cursor_shake"),

    # ── Accessibility: Keyboard ────────────────────────────────────────────
    (r'^stickyKey$',                         r'universalaccess|Accessibility',
     "Sticky Keys",                          fmt_bool, 1, "sticky_keys"),
    (r'^useStickyKeysShortcutKeys$',         r'universalaccess|Accessibility',
     "Sticky Keys: Shift×5 to toggle",       fmt_bool, 1, "sticky_keys_shortcut"),
    (r'^slowKey$',                           r'universalaccess|Accessibility',
     "Slow Keys",                            fmt_bool, 1, "slow_keys"),
    (r'^slowKeyDelay$',                      r'universalaccess|Accessibility',
     "Slow Keys delay",                      lambda v: v, 1, "slow_key_delay"),
    (r'^FullKeyboardAccessEnabled$',         r'universalaccess|Accessibility',
     "Full Keyboard Access",                 fmt_bool, 1, "full_kbd_access"),

    # ── Accessibility: Spoken Content ─────────────────────────────────────
    (r'^SpeakThisEnabled$',                  r'universalaccess|Accessibility',
     "Speak item under mouse",               fmt_bool, 2, "speak_mouse"),
    (r'^liveSpeechEnabled$',                 r'universalaccess|Accessibility',
     "Live Speech",                          fmt_bool, 1, "live_speech"),
    (r'^detectLanguagesEnabled$',            r'universalaccess|Accessibility',
     "Spoken content: detect languages",     fmt_bool, 1, "spoken_detect_lang"),
    (r'^customFonts$',                       r'universalaccess|Accessibility',
     "Accessibility: custom fonts",          fmt_bool, 1, "a11y_custom_fonts"),

    # ── Accessibility: color filters ───────────────────────────────────────
    (r'^__Color__-MADisplayFilterCategoryEnabled$', r'mediaaccessibility',
     "Color filters",
     lambda v: "ON" if v in ("1","True","YES") else "OFF", 1, "color_filters"),
    (r'^__Color__-MADisplayFilterType$',     r'mediaaccessibility',
     "Color filter type",
     lambda v: {"0":"None","1":"Protanopia","2":"Deuteranopia",
                "3":"Tritanopia","4":"Grayscale"}.get(v, v), 1, "color_filter_type"),
    (r'^MADisplayFilterGrayscaleCorrectionIntensity$', r'mediaaccessibility',
     "Grayscale intensity",                  lambda v: v, 1, "grayscale_intensity"),

    # ── Accessibility: spoken content ──────────────────────────────────────
    (r'^SpokenUIUseSpeakingHotKeyFlag$',     r'speech.synthesis',
     "Speak text-to-speech shortcut",        fmt_bool, 1, "tts_hotkey"),
    (r'^TalkingAlertsSpeakTextFlag$',        r'speech.synthesis',
     "Speak alerts",                         fmt_bool, 1, "speak_alerts"),
    (r'^speakSelectionEnabled$',             r'universalaccess|Accessibility',
     "Speak selection",                      fmt_bool, 1, "speak_selection"),
    (r'^speakItemUnderMouseEnabled$',        r'universalaccess|Accessibility',
     "Speak item under mouse",               fmt_bool, 1, "speak_mouse"),
    (r'^typingEchoEnabled$',                 r'universalaccess|Accessibility',
     "Spoken content: speak while typing",   fmt_bool, 1, "typing_echo"),
    (r'^pronunciationsEnabledKey$',          r'universalaccess|Accessibility',
     "Spoken content: custom pronunciations",fmt_bool, 1, "pronunciations"),

    # ── Accessibility: Mono audio ──────────────────────────────────────────
    (r'^System_MixStereoToMono$',            r'audio|SystemSettings',
     "Mono audio",                           fmt_bool, 1, "mono_audio"),
    (r'^stereoAsMono$',                      r'universalaccess|Accessibility',
     "Mono audio",                           fmt_bool, 2, "mono_audio"),

    # ── Accessibility: Live Captions & RTT ────────────────────────────────
    (r'^systemTranscriptionEnabled$',        r'universalaccess|Accessibility',
     "Live Captions",                        fmt_bool, 1, "live_captions"),
    (r'^systemTranscriptionTranscriptionViewFontSize$', r'universalaccess|Accessibility',
     "Live Captions: font size",             lambda v: str(round(float(v))), 1, "live_captions_font"),
    (r'^FaceTimeCaptions$',                  r'universalaccess|Accessibility',
     "FaceTime live captions",               fmt_bool, 1, "ft_captions"),
    (r'^AXSAutomaticCaptionsShowWhenLanguageMismatch$', r'universalaccess|Accessibility',
     "Captions: show when language differs", fmt_bool, 1, "caption_lang_mismatch"),
    (r'^AccessibilityReaderHotkeyEnabled$',  r'universalaccess|Accessibility',
     "Accessibility Reader: keyboard shortcut", fmt_bool, 1, "a11y_reader_hk"),
    (r'^TTYSoftwareEnabledPreference\b',     None,
     "RTT (Real-Time Text)",                 fmt_bool, 1, "rtt_enabled"),
    (r'^TTYShouldBeRealtimePreference\b',    None,
     "RTT: realtime mode",                   fmt_bool, 1, "rtt_realtime"),

    # ── Captions style & audio descriptions ───────────────────────────────
    (r'^MACaptionActiveProfile$',            r'mediaaccessibility',
     "Captions: style",
     lambda v: v.replace('MACaptionProfile-', ''), 1, "caption_profile"),
    (r'^MACaptionDisplayType$',              r'mediaaccessibility',
     "Captions: display type",
     lambda v: {"0":"Off","1":"On","2":"Automatic","3":"Always on"}.get(v, v), 1, "caption_display"),
    (r'^MACaptionPreferAccessibleCaptions$', r'mediaaccessibility',
     "Captions: prefer SDH (Subtitles for Deaf and Hard of Hearing)", fmt_bool, 1, "caption_sdh"),
    (r'^MAAudibleMediaPrefPreferDescriptiveVideo$', r'mediaaccessibility',
     "Audio descriptions for video",         fmt_bool, 1, "audio_desc"),

    # ── Camera & Vision ────────────────────────────────────────────────────
    (r'^AppleLiveTextEnabled$',              None,
     "Live Text",                            fmt_bool, 1, "live_text"),

    # ── Image Capture & device sync ───────────────────────────────────────────
    (r'^disableHotPlug$',                    r'ImageCapture',
     "Image Capture: auto-open for devices",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "imgcapture_hotplug"),
    (r'^AutomaticDeviceBackupsDisabled$',    r'AMPDevices',
     "Automatic device backups",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "device_auto_backup"),
    (r'^dontAutomaticallySyncIPods$',        r'AMPDevices',
     "Auto-sync devices (iPhone/iPod/iPad)",
     lambda v: "OFF" if v in ("True","1","YES") else "ON", 1, "device_auto_sync"),

    # ── Music / Home Sharing ───────────────────────────────────────────────
    (r'^home-sharing-enabled$',              r'mediasharingd',
     "Music: Home Sharing",
     lambda v: "ON" if v == "1" else "OFF",  1, "home_sharing"),
    (r'^photo-sharing-enabled$',             r'mediasharingd',
     "Music: Photo Sharing",
     lambda v: "ON" if v == "1" else "OFF",  1, "photo_sharing"),
    (r'^public-sharing-enabled$',            r'mediasharingd',
     "Music: Library Sharing (public)",
     lambda v: "ON" if v == "1" else "OFF",  1, "music_public_share"),

    # ── Sharing (System Settings → General → Sharing) ──────────────────────
    (r'^Activated$',                         r'AssetCache',
     "Content Caching",                      fmt_bool, 1, "content_cache"),
    (r'^CacheLimit$',                        r'AssetCache',
     "Content Caching: cache size limit",
     lambda v: "Unlimited" if v == "0" else f"{int(v)//1073741824} GB", 1, "content_cache_limit"),
    (r'^DOCAllowRemoteConnections$',         r'RemoteDesktop|Remote.Desktop',
     "Remote Desktop",                       fmt_bool, 1, "remote_desktop"),
    (r'^NAT\.Enabled$',                      r'nat',
     "Internet Sharing",
     lambda v: "ON" if v == "1" else "OFF",  1, "internet_sharing"),

    # ── Computer name & hostname ───────────────────────────────────────────
    (r'^NetBIOSName$',                       r'smb',
     "Computer name (Windows/SMB)",          lambda v: v, 1, "netbios_name"),
    (r'^ServerDescription$',                 r'smb',
     "Computer description (SMB)",           lambda v: v, 1, "smb_server_desc"),
    (r'^System\.System\.ComputerName$',      None,
     "Computer name",                        lambda v: v, 1, "computer_name"),
    (r'^ComputerName$',                      r'scutil',
     "Computer name",                        lambda v: v, 3, "computer_name"),
    (r'^LocalHostName$',                     None,
     "Local hostname",                       lambda v: v, 1, "local_hostname"),
    (r'^System\.Network\.HostNames\.LocalHostName$', None,
     "Local hostname",                       lambda v: v, 2, "local_hostname"),

    # ── Mouse ─────────────────────────────────────────────────────────────
    (r'^com\.apple\.mouse\.swapLeftRightButton$', None,
     "Mouse: swap left/right buttons",       fmt_bool, 1, "mouse_swap_buttons"),

    # ── Siri ──────────────────────────────────────────────────────────────
    (r'^Country Code$',                      r'Siri|assistant',
     "Siri: country",                        lambda v: v, 1, "siri_country"),

    # ── Game Center ───────────────────────────────────────────────────────
    (r'^GKArcadeSubscriptionState$',         r'gamecenter',
     "Game Center: Arcade subscription",
     lambda v: "Subscribed" if v == "1" else "Not subscribed", 1, "gc_arcade_sub"),

    # ── Crash reporter / diagnostics ─────────────────────────────────────
    (r'^AutoSubmit$',                        r'DiagnosticMessages|CrashReporter',
     "Crash reports: send to Apple",         fmt_bool, 1, "diag_autosubmit"),
    (r'^ThirdPartyDataSubmit$',              r'DiagnosticMessages|CrashReporter',
     "Crash reports: send to third-party developers", fmt_bool, 1, "diag_3p_submit"),

    # ── Third-party backup ────────────────────────────────────────────────
    (r'^showCustomFolders$',                 r'backblaze',
     "Backblaze: show custom folders",       fmt_bool, 1, "backblaze_custom_folders"),

    # ── Printers & Faxes (CUPS) ───────────────────────────────────────────
    # Note: individual printer[NAME].* attributes are intentionally left
    # unmatched here so they fall through to unknowns, where the collapse
    # logic below can detect all-added / all-removed and emit a single
    # "Printer added/removed: NAME (URI)" line.  Mid-life attribute changes
    # (URI moves, driver swaps) surface as readable raw lines in that section.

    # ── Default application handlers ──────────────────────────────────────
    # Matched against the summary lines emitted by the APPLICATION HANDLERS
    # snapshot section (e.g. "default-browser :: handler = com.apple.safari").
    (r'^handler$', r'default-browser',
     "Default browser",
     lambda v: {
         'com.apple.safari':         'Safari',
         'org.mozilla.firefox':      'Firefox',
         'com.google.Chrome':        'Chrome',
         'com.google.chrome':        'Chrome',
         'com.microsoft.edgemac':    'Edge',
         'com.operasoftware.Opera':  'Opera',
         'com.brave.Browser':        'Brave Browser',
         'com.vivaldi.Vivaldi':      'Vivaldi',
         'company.thebrowser.Browser': 'Arc',
     }.get(v, v), 1, "default_browser"),

    (r'^handler$', r'default-mail-client',
     "Default mail client",
     lambda v: {
         'com.apple.mail':               'Mail',
         'com.microsoft.Outlook':        'Outlook',
         'com.readdle.smartmailmac':     'Spark',
         'com.airmail.5':                'Airmail 5',
         'com.freron.MailMate':          'MailMate',
         'com.mimestream.Mimestream':    'Mimestream',
         'com.google.Gmail':             'Gmail',
         'com.tinyspeck.slackmacgap':    'Slack',
         'com.flexibits.fantastical2.mac': 'Fantastical',
     }.get(v, v), 1, "default_mail"),

    (r'^handler$', r'default-calendar-app',
     "Default calendar app",
     lambda v: {
         'com.apple.ical':               'Calendar',
         'com.apple.iCal':               'Calendar',
         'com.busymac.busycal3':         'BusyCal',
         'com.flexibits.fantastical2.mac': 'Fantastical',
         'com.readdle.smartmailmac':     'Spark',
     }.get(v, v), 1, "default_calendar"),

    (r'^handler$', r'default-rss-reader',
     "Default RSS reader",
     lambda v: {
         'com.apple.Safari':             'Safari',
         'com.apple.safari':             'Safari',
         'com.netnewswire.netnewswire':  'NetNewsWire',
         'com.reederapp.5.macOS':        'Reeder',
         'com.reeder.Reeder5':           'Reeder',
     }.get(v, v), 1, "default_rss"),
]

LINE_RE   = re.compile(r'^([+-])\s*(.*?)\s*::\s*(.+)$')
KV_RE     = re.compile(r'^(.*?)\s*=\s*(.*)$')
SYSST_RE  = re.compile(r'^([+-])\s*((?:FileVault|SIP|Gatekeeper|Firewall|AdminPassword)\s+::)\s*(.+)$')

def apply_rules(domain, key, val):
    best_pri, best = 999, None
    for key_re, dom_re, label, val_fn, pri, group in RULES:
        if not re.search(key_re, key):
            continue
        if dom_re and not re.search(dom_re, domain, re.IGNORECASE):
            continue
        if pri < best_pri:
            best_pri, best = pri, (label, val_fn, group)
    if best:
        label, val_fn, group = best
        try:    hval = val_fn(val)
        except: hval = val
        return label, hval, group
    return None

known    = {}   # group -> {label, before, after}
unknowns = {}   # "domain :: key" -> {before, after}

# Accumulator for NSUserDictionaryReplacementItems — diffed by content, not index
TREPL_RE = re.compile(r'^NSUserDictionaryReplacementItems\[(\d+)\]\.(replace|with|on)$')
text_rep = {'-': {}, '+': {}}

for raw_line in sys.stdin:
    line = raw_line.rstrip('\n')
    if not line or line.startswith(('---','+++','@@')):
        continue
    if line[0] not in ('+','-'):
        continue
    sign = line[0]

    # System-state lines (FileVault/SIP/Gatekeeper) — no KEY=VALUE structure
    m = SYSST_RE.match(line)
    if m:
        sign, tag, rest = m.group(1), m.group(2).strip(), m.group(3).strip()
        label_map = {
            "FileVault ::": ("FileVault",  lambda v: "ON" if "On"  in v else "OFF" if "Off" in v else v, "filevault"),
            "SIP ::":       ("SIP",        lambda v: "enabled" if "enabled" in v else "disabled" if "disabled" in v else v, "sip"),
            "Gatekeeper ::":("Gatekeeper", lambda v: "enabled" if "enabled" in v else "disabled" if "disabled" in v else v, "gatekeeper"),
            "Firewall ::":  ("Firewall",   lambda v: "OFF" if "State = 0" in v else "Block all" if "State = 2" in v else "ON", "firewall"),
            "AdminPassword ::": ("Require admin password for system settings",
                                 lambda v: "ON" if "timeout=0" in v else "OFF" if "2147483647" in v else v,
                                 "admin_password_settings"),
        }
        for prefix, (label, fn, group) in label_map.items():
            if tag.startswith(prefix.split()[0]):
                if group not in known:
                    known[group] = {'label': label, 'before': None, 'after': None}
                try:    hval = fn(rest)
                except: hval = rest
                known[group]['before' if sign=='-' else 'after'] = hval
        continue

    m = LINE_RE.match(line)
    if not m:
        continue
    sign, domain, rest = m.group(1), m.group(2), m.group(3)

    kv = KV_RE.match(rest)
    if not kv:
        continue
    key, val = kv.group(1).strip(), kv.group(2).strip()

    # Text replacements: accumulate by index, diff by content later
    tm = TREPL_RE.match(key)
    if tm:
        idx, field = tm.group(1), tm.group(2)
        text_rep[sign].setdefault(idx, {})[field] = val
        continue

    result = apply_rules(domain, key, val)
    if result:
        label, hval, group = result
        # When dedup_group is None, each (domain,key) gets its own slot
        gkey = (domain, key) if group is None else group
        if gkey not in known:
            known[gkey] = {'label': label, 'before': None, 'after': None}
        known[gkey]['before' if sign=='-' else 'after'] = hval
    else:
        dk = f"{domain} :: {key}"
        if dk not in unknowns:
            unknowns[dk] = {'before': None, 'after': None}
        unknowns[dk]['before' if sign=='-' else 'after'] = val

# ── iCloud re-hydration filter ───────────────────────────────────────────────
# These plists are managed by iCloud and are absent from early-morning snapshots
# (taken before iCloud sync).  A pre-sync → post-sync diff shows them all as
# "absent → value" even though the user made no changes.  Suppress pure additions
# (before=None) for known iCloud-managed keys; value→value changes are never
# suppressed, so a real setting change is always visible.
_ICLOUD_GROUPS = {
    'focus_share_status', 'focus_auto_reply',           # DoNotDisturb GlobalConfiguration
    'focus_facetime_break', 'focus_forwarded_sounds', 'focus_repeated_facetime',
    'wifi_power', 'wifi_remember_nets',                 # Wi-Fi
    'wifi_hotspot_auto', 'wifi_mac_mode',
    'tm_autobackup', 'tm_interval',                     # Time Machine
    'tm_acpower', 'tm_local_snap',
    'analytics_mac', 'analytics_3p',                    # Crash Reporter / Analytics
    'mail_domain_warn', 'mail_expand_alias',             # Mail
    'mail_remote_content', 'mail_addr_display',
    'notif_previews_global',                             # Notifications global
    'notif_dnd_sleep', 'notif_dnd_lock', 'notif_dnd_mirror',
    'notif_sort_order', 'notif_summarize', 'notif_forwarded_sounds',
    'firewall', 'admin_password_settings',
    'lockdown_mode',                                     # Lockdown Mode (default=OFF)
    'st_enabled', 'st_app_activity', 'st_cloud_sync',   # Screen Time (iCloud-synced)
    'st_passcode', 'st_eye_relief', 'st_share_web',
    'st_managed', 'st_downtime', 'st_content_privacy',
    'st_always_allowed', 'st_app_limits_total', 'st_app_limits_active',
    'st_comm_policy', 'st_comm_limited',
    'st_comm_safety_recv', 'st_comm_safety_send', 'st_comm_safety_analytics',
}
_ICLOUD_DOMAIN_RE = re.compile(r'DoNotDisturb', re.IGNORECASE)
_ICLOUD_UNKNOWN_RE = re.compile(
    r'(usernoted.*::|DoNotDisturb.*::|mail-shared.*::|TimeMachine.*::|airport\.preferences.*::)',
    re.IGNORECASE)

for _gkey in list(known.keys()):
    _e = known[_gkey]
    if _e['before'] is not None:
        continue  # real change — never suppress
    if isinstance(_gkey, str) and _gkey in _ICLOUD_GROUPS:
        del known[_gkey]
    elif isinstance(_gkey, tuple) and _ICLOUD_DOMAIN_RE.search(_gkey[0]):
        del known[_gkey]  # mode[...].impactsAvailability (group=None keys)

for _dk in list(unknowns.keys()):
    _e = unknowns[_dk]
    if _e['before'] is None and _ICLOUD_UNKNOWN_RE.search(_dk):
        del unknowns[_dk]

# Build recognized list (filter out noise where before==after)
recognized = [
    (g['label'], g['before'] or '(default)', g['after'] or '(default)')
    for g in known.values()
    if g['before'] != g['after']
]
recognized.sort(key=lambda x: x[0])

# ── Text replacement content-diff ────────────────────────────────────────
def _repl_map(side):
    """Build {replace_string: expansion} from accumulated index dict."""
    result = {}
    for fields in side.values():
        r = fields.get('replace')
        if r is not None:
            result[r] = fields.get('with', '')
    return result

before_repls = _repl_map(text_rep['-'])
after_repls  = _repl_map(text_rep['+'])
if before_repls or after_repls:
    for r in sorted(after_repls):
        w_after = after_repls[r]
        if r not in before_repls:
            if w_after:   # empty = index-shift artifact, not a real addition
                recognized.append(('Text replacement added', '(none)', f'{r} → {w_after}'))
        else:
            w_before = before_repls[r]
            if w_before and w_after and w_before != w_after:
                recognized.append((f'Text replacement: {r}', w_before, w_after))
            # if either side is empty it's an index-shift artifact — skip
    for r in sorted(before_repls):
        if r not in after_repls:
            w_before = before_repls[r]
            if w_before:  # empty = index-shift artifact
                recognized.append(('Text replacement removed', f'{r} → {w_before}', '(none)'))
    recognized.sort(key=lambda x: x[0])

def json_equal(a, b):
    """Return True if a and b are semantically identical JSON (ignoring key order)."""
    try:
        return json.loads(a) == json.loads(b)
    except Exception:
        return False

# Build unknown lists
# ── CUPS printer add/remove collapse ─────────────────────────────────────────
# When all attributes of a printer are uniformly added or removed, fold them
# into a single "Printer added/removed: NAME (URI)" recognized entry.
_CUPS_ATTR_RE = re.compile(r'^CUPS :: printer\[([^\]]+)\]\.(.+)$')
_cups_groups = {}
for _dk, _entry in list(unknowns.items()):
    _m = _CUPS_ATTR_RE.match(_dk)
    if not _m:
        continue
    _cups_groups.setdefault(_m.group(1), []).append((_dk, _m.group(2), _entry))

for _pname, _attrs in _cups_groups.items():
    _all_added   = all(e['before'] is None and e['after']  is not None for _, _, e in _attrs)
    _all_removed = all(e['after']  is None and e['before'] is not None for _, _, e in _attrs)
    if not (_all_added or _all_removed):
        continue
    _vals    = {a: (e['after'] or e['before']) for _, a, e in _attrs}
    _display = _vals.get('info') or _pname
    _uri     = _vals.get('uri', '')
    _label   = ("Printer added: " if _all_added else "Printer removed: ") + _display
    if _uri:
        _label += f" ({_uri})"
    recognized.append((_label, '', ''))
    for _dk, _, _ in _attrs:
        del unknowns[_dk]

unk_changed = [(k, v['before'], v['after']) for k,v in unknowns.items()
               if v['before'] is not None and v['after'] is not None
               and v['before'] != v['after']
               and not json_equal(v['before'], v['after'])]
unk_added   = [(k, v['after'])  for k,v in unknowns.items() if v['before'] is None and v['after'] is not None]
unk_removed = [(k, v['before']) for k,v in unknowns.items() if v['after']  is None and v['before'] is not None]

total = len(recognized) + len(unk_changed) + len(unk_added) + len(unk_removed)

if total == 0:
    print("No changes detected.")
    sys.exit(0)

UUID_RE = re.compile(r'\.[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}', re.IGNORECASE)

# Maps bundle IDs (after stripping path and .plist) to human-readable names.
# Matched case-insensitively; longest match wins when one ID is a prefix of another.
DOMAIN_NAMES = {
    # System
    "NSGlobalDomain":                                       "System",
    ".GlobalPreferences":                                   "System",
    "com.apple.loginwindow":                                "Login Window",
    "com.apple.systempreferences":                          "System Settings",
    "com.apple.systemuiserver":                             "Menu Bar",
    "com.apple.dock":                                       "Dock",
    "com.apple.finder":                                     "Finder",
    "com.apple.desktopservices":                            "Desktop Services",
    "com.apple.LaunchServices":                             "Launch Services",
    "com.apple.security":                                   "Security",
    "com.apple.keychainaccess":                             "Keychain",
    # Display & Energy
    "com.apple.Displays-Settings.extension":                "Displays",
    "com.apple.energysaver":                                "Energy Saver",
    "com.apple.PowerManagement":                            "Energy / Power",
    "com.apple.Battery":                                    "Battery",
    # Input
    "com.apple.AppleMultitouchTrackpad":                    "Trackpad",
    "com.apple.driver.AppleBluetoothMultitouch.trackpad":   "Trackpad (Bluetooth)",
    "com.apple.driver.AppleBluetoothMultitouch.mouse":      "Mouse (Bluetooth)",
    "com.apple.preference.mouse":                           "Mouse",
    "com.apple.HIToolbox":                                  "Keyboard",
    "com.apple.keyboard":                                   "Keyboard",
    # Accessibility
    "com.apple.universalaccess":                            "Accessibility",
    "com.apple.Accessibility":                              "Accessibility",
    "com.apple.Accessibility.Assets":                       "Accessibility Assets",
    # Notifications & Focus
    "com.apple.ncprefs":                                    "Notification Center",
    "com.apple.donotdisturbd":                              "Focus / Do Not Disturb",
    # Network & Connectivity
    "com.apple.wifi":                                       "Wi-Fi",
    "com.apple.airport":                                    "Wi-Fi",
    "com.apple.bluetoothd":                                 "Bluetooth",
    "com.apple.bluetooth":                                  "Bluetooth",
    "com.apple.firewall":                                   "Firewall",
    "com.apple.NetworkExtension":                           "Network Extension",
    "com.apple.networkextension":                           "Network Extension",
    "com.apple.vpn":                                        "VPN",
    "com.apple.sharing":                                    "Sharing",
    # iCloud & Accounts
    "MobileMeAccounts":                                     "iCloud",
    "com.apple.icloud":                                     "iCloud",
    "com.apple.appleaccountd":                              "Apple Account",
    # Privacy & Updates
    "com.apple.SoftwareUpdate":                             "Software Update",
    "com.apple.TimeMachine":                                "Time Machine",
    "com.apple.spotlight":                                  "Spotlight",
    "com.apple.Siri":                                       "Siri",
    "com.apple.screensaver":                                "Screen Saver",
    "com.apple.controlcenter":                              "Control Center",
    # Sound
    "com.apple.sounds":                                     "Sound",
    "com.apple.sound":                                      "Sound",
    "com.apple.ComfortSounds":                              "Comfort Sounds",
    # Sharing services
    "com.apple.screensharing":                              "Screen Sharing",
    "com.apple.smbd":                                       "File Sharing (SMB)",
    "com.apple.RemoteDesktop":                              "Remote Desktop",
    # Apps
    "com.apple.Safari":                                     "Safari",
    "com.apple.mail":                                       "Mail",
    "com.apple.iChat":                                      "Messages",
    "com.apple.Messages":                                   "Messages",
    "com.apple.facetime":                                   "FaceTime",
    "com.apple.Photos":                                     "Photos",
    "com.apple.Preview":                                    "Preview",
    "com.apple.TextEdit":                                   "TextEdit",
    "com.apple.Terminal":                                   "Terminal",
    "com.apple.amp.mediasharingd":                          "Music Sharing",
    "com.apple.knowledge-agent":                            "Siri Knowledge",
    "com.apple.sharingd":                                   "AirDrop / Sharing",
    "com.apple.assistant":                                  "Siri",
    "com.apple.assistant.support":                          "Dictation / Siri",
    "com.apple.assistant.backedup":                         "Siri (synced)",
    "com.apple.imessage.bag":                               "iMessage",
    "org.cups.PrintingPrefs":                               "Printing",
    "com.apple.onetimepasscodes":                           "Verification Codes",
    "com.apple.itunescloudd":                               "iCloud Music",
    "com.apple.networkserviceproxy":                        "Network Service Proxy",
    "com.apple.AccessibilityHearingNearby":                 "Hearing Nearby",
    "com.apple.amsengagementd":                             "App Store Engagement",
    "com.apple.AdPlatforms":                                "Ad Platforms",
    "com.apple.SpeakSelection":                             "Speak Selection",
    "com.apple.systemsettings.extensions":                  "System Settings",
    # System services
    "BTM":                                                  "Login Items / Background",
    "com.apple.mediaaccessibility":                         "Display Filters",
    "com.apple.speech.synthesis.general.prefs":             "Spoken Content",
    # Third-party
    "com.setapp.DesktopClient":                             "Setapp",
    "com.raycast.macos":                                    "Raycast",
    "com.google.Chrome":                                    "Chrome",
    "com.microsoft.Word":                                   "Word",
    "com.microsoft.Excel":                                  "Excel",
    "com.microsoft.Outlook":                                "Outlook",
    "com.microsoft.autoupdate2":                            "Microsoft AutoUpdate",
    "us.zoom.xos":                                          "Zoom",
    "us.zoom.updater":                                      "Zoom Updater",
    "com.1password.1password":                              "1Password",
    "com.agilebits.onepassword7":                           "1Password 7",
    "com.dropbox.client2":                                  "Dropbox",
    "com.spotify.client":                                   "Spotify",
    "com.obsproject.obs-studio":                            "OBS",
    "com.adobe.Acrobat.Pro":                                "Acrobat Pro",
    "com.slack.Slack":                                      "Slack",
    "com.tinyspeck.slackmacgap":                            "Slack",
    "com.figma.Desktop":                                    "Figma",
    "com.docker.docker":                                    "Docker",
}

# Reverse-DNS prefix stripper for unlisted domains
_RDNS_RE = re.compile(r'^(com|net|org|io|co|us|uk|de|fr|jp)\.[^.]+\.', re.IGNORECASE)

def friendly_domain(raw):
    """Convert a bundle-ID-style filename to a human-readable app/service name."""
    # Try exact match first, then case-insensitive
    if raw in DOMAIN_NAMES:
        return DOMAIN_NAMES[raw]
    low = raw.lower()
    for k, v in DOMAIN_NAMES.items():
        if k.lower() == low:
            return v
    # Longest prefix match (e.g. com.apple.screensaver.ByHost → Screen Saver)
    best_len, best_val = 0, None
    for k, v in DOMAIN_NAMES.items():
        if low.startswith(k.lower()) and len(k) > best_len:
            best_len, best_val = len(k), v
    if best_val:
        return best_val
    # Strip com.apple. for unlisted Apple domains
    if raw.lower().startswith("com.apple."):
        return raw[len("com.apple."):]
    # Strip reverse-DNS prefix for third-party (e.g. us.zoom.updater → updater)
    stripped = _RDNS_RE.sub('', raw)
    return stripped if stripped != raw else raw

def clean_domain(dk):
    """Produce a human-readable 'App :: key' string from a raw 'path :: key' diff token."""
    parts = dk.split(' :: ', 1)
    fname = parts[0].split('/')[-1] if '/' in parts[0] else parts[0]
    fname = UUID_RE.sub('', fname)
    fname = fname.removesuffix('.plist')
    fname = friendly_domain(fname)
    return f"{fname} :: {parts[1]}" if len(parts)==2 else fname

noun = "change" if total == 1 else "changes"
print(f"{total} {noun} detected:\n")

# Recognized section uses its own column width.
# Label-only entries (bv=='' and av=='') are exempt from alignment.
rw = max((len(x[0]) for x in recognized if x[1] != '' or x[2] != ''), default=0)

# Unrecognized sections share their own column width
unk_labels = ([clean_domain(k) for k, *_ in unk_changed] +
              [clean_domain(k) for k, *_ in unk_added] +
              [clean_domain(k) for k, *_ in unk_removed])
w = max((len(x) for x in unk_labels), default=0)

if recognized:
    for label, bv, av in recognized:
        if bv == '' and av == '':
            print(f"  {label}")
        else:
            print(f"  {label:<{rw}}  {bv} → {av}")
    print()

INLINE_MAX = 80   # if before+after fits on one line, keep it there

def fmt_inline(bv, av, sign):
    bvs, avs = str(bv)[:100], str(av)[:100]
    if sign == 'changed':
        if len(bvs) + len(avs) <= INLINE_MAX:
            return f"{bvs} → {avs}"
        else:
            return f"\n      before: {bvs}\n      after:  {avs}"
    else:
        return avs if sign == 'added' else bvs

def show_raw(items, sign):
    LIMIT = 30
    for k, *vals in items[:LIMIT]:
        ck = clean_domain(k)
        if sign == 'changed':
            bv, av = vals
            suffix = fmt_inline(bv, av, 'changed')
            if '\n' in suffix:
                print(f"  {ck:<{w}}{suffix}")
            else:
                print(f"  {ck:<{w}}  {suffix}")
        elif sign == 'added':
            print(f"  {ck:<{w}}  (added) {str(vals[0])[:100]}")
        else:
            print(f"  {ck:<{w}}  (removed) {str(vals[0])[:100]}")
    if len(items) > LIMIT:
        print(f"  … and {len(items)-LIMIT} more")

if unk_changed:
    show_raw(unk_changed, 'changed')
    print()
if unk_added:
    show_raw(unk_added, 'added')
    print()
if unk_removed:
    show_raw(unk_removed, 'removed')
    print()
PYEOF

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
  \.chronod\.plist ::|
  \.cseventlistener\.plist ::|
  AssetMetricsWorker\.plist ::|
  \.tipsd\.plist ::|
  DataDeliveryServices\.plist ::|
  coreservices\.useractivityd[^/]*::|
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
  Bluetooth.*:: PrefKeyServicesEnabled\s*=|
  mediasharingd.*:: home-sharing-computer-id|
  mediasharingd.*:: home-sharing-group-id|
  mediasharingd.*:: home-sharing-settings\.|
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
  AssetCache.*:: AllowTetheredCaching\s*=|
  AssetCache.*:: SavedCacheDetails\.|
  bluetooth.*:: BluetoothAutoSeek|
  RemoteDesktop.*:: RSAKeySize\s*=|
  RemoteManagement.*:: allowInsecureDH\s*=|
  nat.*:: NAT\.AirPort\.|
  nat.*:: NAT\.PrimaryInterface\.|
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

flatten_domain() {
  local domain="$1"
  defaults export "$domain" - 2>/dev/null \
    | { python3 -c "$FLATTEN_PY" 2>/dev/null; } 2>/dev/null \
    | sed "s|^|${domain} :: |"
}

flatten_plist() {
  local f="$1"
  { python3 -c "$FLATTEN_PY" < "$f" 2>/dev/null; } 2>/dev/null \
    | sed "s|^|${f} :: |"
}

# Reads a root-owned plist via sudo cat, flattens as current user.
flatten_plist_sudo() {
  local f="$1"
  sudo cat "$f" 2>/dev/null \
    | { python3 -c "$FLATTEN_PY" 2>/dev/null; } 2>/dev/null \
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
      \) -maxdepth 2 2>/dev/null | sort)

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
      python3 - "$DND_DB" << 'PYEOF'
import json, sys, os
db = sys.argv[1]

def emit(key, val):
    print(f"{db} :: {key} = {val}")

# GlobalConfiguration: modesCanImpactAvailability controls "Share Focus status" globally
gc = json.load(open(f"{db}/GlobalConfiguration.json"))
data = gc["data"][0]
emit("GlobalConfiguration.modesCanImpactAvailability", data.get("modesCanImpactAvailability", ""))
emit("GlobalConfiguration.preventAutoReply", data.get("preventAutoReply", ""))

# ModeConfigurations: per-mode settings
mc = json.load(open(f"{db}/ModeConfigurations.json"))
modes = mc["data"][0]["modeConfigurations"]
for mode_id, cfg in sorted(modes.items()):
    name = cfg.get("mode", {}).get("name", mode_id)
    emit(f"mode[{mode_id}].name", name)
    emit(f"mode[{mode_id}].impactsAvailability", cfg.get("impactsAvailability", ""))
PYEOF
    else
      echo "$DND_DB :: (not found)"
    fi

    section "SCREEN TIME (screentimediagnose)"
    # Screen Time stores settings in a sandboxed SQLite database; readable only
    # via the screentimediagnose tool in ScreenTimeCore.framework.
    python3 << 'PYEOF'
import subprocess, sys, re

STDIAG = "/System/Library/PrivateFrameworks/ScreenTimeCore.framework/screentimediagnose"
r = subprocess.run([STDIAG, "inspect"], capture_output=True, text=True)
if r.returncode != 0:
    print("screentimedx :: (screentimediagnose failed)")
    sys.exit(0)

text = r.stdout

def extract_block(text, label):
    """Return the content between the outermost braces after 'label ='."""
    idx = text.find(label + ' =')
    if idx == -1: return None
    try:
        brace_start = text.index('{', idx)
    except ValueError:
        return None
    depth = 0
    for i in range(brace_start, len(text)):
        if text[i] == '{': depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                return text[brace_start+1:i]
    return None

def flat_keys(block):
    """Extract top-level key=value pairs from a brace block (skip nested dicts)."""
    out = {}
    inner_depth = 0
    for line in block.splitlines():
        s = line.strip()
        inner_depth += s.count('{') - s.count('}')
        if inner_depth > 0 or '=' not in s:
            continue
        k, v = s.split('=', 1)
        out[k.strip()] = v.strip().rstrip(';')
    return out

# ── Top-level settings ────────────────────────────────────────────────────────
settings_block = extract_block(text, 'settings')
if settings_block:
    for k, v in sorted(flat_keys(settings_block).items()):
        print(f"screentimedx :: {k} = {v}")

    # communicationPolicies nested dict
    comm_block = extract_block(settings_block, 'communicationPolicies')
    if comm_block:
        for k, v in sorted(flat_keys(comm_block).items()):
            print(f"screentimedx :: communicationPolicies.{k} = {v}")

# ── Blueprint enabled states ──────────────────────────────────────────────────
# stable blueprint IDs and their UI meaning
BLUEPRINTS = {
    "bedtime_activation_personal":       "downtime_schedule_enabled",
    "digital_health_restrictions":       "content_privacy_enabled",
    "always_allow_activation_personal":  "always_allowed_apps_enabled",
}
blueprints_block = extract_block(text, 'blueprints')
if blueprints_block:
    for bp_id, key in BLUEPRINTS.items():
        m = re.search(rf'"{re.escape(bp_id)}" =\s*\{{', blueprints_block)
        if not m:
            continue
        sub = extract_block(blueprints_block[m.start():], f'"{bp_id}"')
        if sub is None:
            continue
        kv = flat_keys(sub)
        if 'enabled' in kv:
            print(f"screentimedx :: {key} = {kv['enabled']}")

    # ── App Limits: count usage-limit blueprints (UUID-keyed, not stable) ─────
    app_limit_total   = len(re.findall(r'"budget_activation_[^"]+" =\s*\{', blueprints_block))
    app_limit_enabled = 0
    for m in re.finditer(r'"(budget_activation_[^"]+)" =\s*\{', blueprints_block):
        sub = extract_block(blueprints_block[m.start():], f'"{m.group(1)}"')
        if sub and flat_keys(sub).get('enabled') == '1':
            app_limit_enabled += 1
    print(f"screentimedx :: app_limits_count = {app_limit_total}")
    print(f"screentimedx :: app_limits_enabled_count = {app_limit_enabled}")
PYEOF

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
      python3 - "$LS_PLIST" << 'PYEOF'
import sys, plistlib
try:
    with open(sys.argv[1], 'rb') as _f:
        _data = plistlib.load(_f)
except Exception:
    sys.exit(0)
_by_scheme = {}
for _h in _data.get('LSHandlers', []):
    _s = _h.get('LSHandlerURLScheme')
    _r = _h.get('LSHandlerRoleAll') or _h.get('LSHandlerRoleViewer') or ''
    if _s and _r:
        _by_scheme[_s] = _r
_want = [
    ('http',    'default-browser'),
    ('https',   'default-browser-https'),
    ('mailto',  'default-mail-client'),
    ('webcal',  'default-calendar-app'),
    ('feed',    'default-rss-reader'),
]
for _scheme, _label in _want:
    if _scheme in _by_scheme:
        print(f"{_label} :: handler = {_by_scheme[_scheme]}")
PYEOF
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
      echo "TCC-user :: (not readable — grant Full Disk Access to Terminal)"
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
      echo "TCC-system :: (not readable — grant Full Disk Access to Terminal)"
    fi

    section "SYSTEM STATE"
    echo "SIP         :: $(csrutil status       2>/dev/null || echo '(unavailable)')"
    echo "Gatekeeper  :: $(spctl --status        2>/dev/null || echo '(unavailable)')"
    echo "FileVault   :: $(fdesetup status       2>/dev/null || echo '(unavailable)')"
    echo "Firewall    :: $(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || echo '(unavailable)')"
    echo "AdminPassword :: $(security authorizationdb read system.preferences 2>/dev/null | python3 -c 'import sys,plistlib; d=plistlib.loads(sys.stdin.buffer.read()); print("timeout="+str(d.get("timeout","?")))' 2>/dev/null || echo '(unavailable)')"
    LDM_VAL=$(launchctl bootenv 2>/dev/null | awk '/LockdownMode/{print $2}')
    echo "LockdownMode :: LockdownMode = ${LDM_VAL:-0}"
    echo ""
    echo "--- pmset ---"
    pmset -g 2>/dev/null || echo "(unavailable)"
    echo ""
    echo "--- systemsetup ---"
    systemsetup -getnetworktimeserver 2>/dev/null || echo "(unavailable)"
    systemsetup -getusingnetworktime  2>/dev/null || echo "(unavailable)"
    systemsetup -gettimezone          2>/dev/null || echo "(unavailable)"
    systemsetup -getremotelogin       2>/dev/null || echo "(unavailable)"
    systemsetup -getremoteappleevents 2>/dev/null || echo "(unavailable)"

    section "SHARING SERVICES"
    # Reports enabled/disabled for each service based on launchctl load state.
    for svc in \
        com.apple.screensharing \
        com.apple.smbd \
        com.apple.netbiosd \
        com.apple.AppleFileServer \
        com.apple.RemoteDesktop.agent \
        com.apple.blued \
        com.apple.AirPlayXPCHelper; do
      if launchctl list "$svc" &>/dev/null; then
        echo "sharing :: ${svc} = enabled"
      else
        echo "sharing :: ${svc} = disabled"
      fi
    done

    section "TIME MACHINE"
    tmutil destinationinfo 2>/dev/null || echo "(no destinations configured)"
    echo ""
    tmutil status 2>/dev/null || echo "(unavailable)"

    section "PRINTERS & FAXES"
    # CUPS printer/fax queues — stable attributes only (state-change timestamps excluded).
    # lpstat requires no root; lpoptions gives per-printer details.
    python3 << 'PYEOF'
import subprocess, re, sys

def run(*cmd):
    try:
        r = subprocess.run(list(cmd), capture_output=True, text=True, timeout=10)
        return r.stdout
    except Exception:
        return ""

# Gather state: "printer NAME is idle/stopped/processing"
state_re = re.compile(r'^printer\s+(\S+)\s+is\s+(\S+)', re.MULTILINE)
states = {m.group(1): m.group(2).rstrip('.') for m in state_re.finditer(run("lpstat", "-p"))}

if not states:
    print("CUPS :: (no printers configured)")
else:
    # Stable keys to extract from lpoptions (exclude timestamps, internal bitmasks)
    WANT = {
        "printer-info":            "info",
        "printer-make-and-model":  "driver",
        "printer-uri-supported":   "uri",
        "printer-location":        "location",
        "printer-is-accepting-jobs": "accepting",
        "printer-is-shared":       "shared",
        "print-color-mode":        "default-color",
        "sides":                   "default-sides",
    }
    kv_re = re.compile(r"(\S+)='([^']*)'|(\S+)=(\S+)")

    for name in sorted(states):
        prefix = f"CUPS :: printer[{name}]"
        print(f"{prefix}.state = {states[name]}")

        raw = run("lpoptions", "-p", name)
        opts = {}
        for m in kv_re.finditer(raw):
            k = m.group(1) or m.group(3)
            v = m.group(2) if m.group(2) is not None else m.group(4)
            opts[k] = v

        for src_key, label in WANT.items():
            if src_key in opts:
                v = opts[src_key].strip()
                if v not in ('', "''"):
                    print(f"{prefix}.{label} = {v}")
PYEOF

    section "SYSTEM EXTENSIONS"
    systemextensionsctl list 2>/dev/null || echo "(unavailable)"

    section "BACKGROUND TASK MANAGEMENT (Login Items & Background)"
    # sfltool dumpbackgroundtaskmanagement lists all BTM-registered items:
    # login items (Open at Login) and background helpers (Allow in Background).
    # Output is normalized to "BTM :: <identifier> :: <key> = <value>" lines.
    if command -v sfltool >/dev/null 2>&1; then
      sfltool dumpbackgroundtaskmanagement 2>/dev/null \
      | python3 -c "
import sys, re
identifier = None
app_label = None
for raw in sys.stdin:
    line = raw.rstrip()
    # New top-level item (App or Helper)
    m = re.search(r'(?:App|Helper[^:]*): (.+?)\s+Bundle ID: (.+)', line)
    if m:
        app_label  = m.group(1).strip()
        identifier = m.group(2).strip()
        continue
    # Identifier line (overrides bundle-id extraction above for sub-items)
    m = re.search(r'^\s+Identifier: (.+)', line)
    if m:
        identifier = m.group(1).strip()
        continue
    # Disposition — the field that changes when user toggles allow/deny
    m = re.search(r'^\s+Disposition: (.+)', line)
    if m and identifier:
        print(f'BTM :: {identifier} :: disposition = {m.group(1).strip()}')
        identifier = None   # reset; next Identifier line starts a new item
" 2>/dev/null \
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

  diff --unified=0 <(cat_snapshot "$before") <(cat_snapshot "$after") \
    | grep -vE '^@@' \
    | grep -vE "$NOISE_RE" \
    | python3 -c "$EXPLAIN_PY"
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
