#!/system/bin/sh
# MiSans system font - Magisk installer customization for Android 11

SKIPUNZIP=0

ui_print " "
ui_print "*******************************"
ui_print "  MiSans System Font (A11)"
ui_print "*******************************"
ui_print " "

API="$(getprop ro.build.version.sdk)"
ui_print "- Android SDK version: $API"
if [ "$API" != "30" ]; then
  ui_print "! This module is built for Android 11 (SDK 30)."
  ui_print "! Other releases may use a different font list layout."
  ui_print "! Continuing - disable the module and reboot if text breaks."
fi

if [ ! -f /system/etc/fonts.xml ]; then
  abort "! /system/etc/fonts.xml not found - unsupported ROM."
fi

# Check every font the shipped fonts.xml actually references, so the two
# weight variants (stock / bold) stay self-contained.
FONTS="$(grep -o 'MiSans-[A-Za-z]*\.ttf' "$MODPATH/system/etc/fonts.xml" | sort -u)"
for font in $FONTS; do
  if [ ! -f "$MODPATH/system/fonts/$font" ]; then
    abort "! system/fonts/$font is missing from the module zip."
  fi
done

DEFAULT_FONT="$(grep 'weight="400"' "$MODPATH/system/etc/fonts.xml" | head -n 1 | sed 's/.*>\(MiSans-[A-Za-z]*\.ttf\)<.*/\1/')"
ui_print "- Fonts: $(echo $FONTS | tr '\n' ' ')"
ui_print "- Default (400) weight: $DEFAULT_FONT"

if ! grep -q "NotoSansCJK-Regular.ttc" /system/etc/fonts.xml; then
  ui_print "! This ROM has no Noto Sans CJK fallback entry."
  ui_print "! Characters outside MiSans may render as tofu."
fi

ui_print "- Applying permissions"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/etc/fonts.xml" 0 0 0644
set_perm_recursive "$MODPATH/system/fonts" 0 0 0755 0644

ui_print "- Installed. Reboot to apply the new font."
ui_print " "
