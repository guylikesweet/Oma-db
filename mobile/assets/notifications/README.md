# OmaSales notification sounds

Put the custom team-chat sound here:

- `mobile/assets/notifications/chat_message.wav`

The GitHub Actions Android build copies that file into the Android notification resources and uses it for the `Oma team chat` notification channel.

If the file is not present, the build generates a short fallback sound so the APK still builds.

The existing business notification sounds remain:
- `scanner_beep.wav`
- `ship_horn.wav`
- `airport_arrival.wav`
