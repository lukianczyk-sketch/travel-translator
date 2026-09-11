# Travel Translator

Live, two-way, offline conversation translator. Whisper large-v3-turbo (ears) → NLLB-200 1.3B (brain) → phone TTS (mouth). One Flutter codebase for Android + iPhone.

## Getting a build (free, no Mac needed)

1. **Create a repo** on GitHub named `travel-translator` (public is fine — public repos get unlimited free build minutes).
2. **Upload this folder** — easiest: GitHub → *Add file → Upload files*, drag everything in (including the `.github` folder), commit to `main`.
3. Go to the **Actions** tab. A build named *Build Android APK + iPhone IPA* starts by itself (~10–15 min).
4. When it's green, open the run and scroll to **Artifacts**:
   - `TravelTranslator-Android-APK` → unzip → `app-release.apk`
   - `TravelTranslator-iPhone-IPA` → unzip → `TravelTranslator.ipa`

## Install — Galaxy Z Fold 8
Copy `app-release.apk` to the phone, tap it, allow "install unknown apps" for your browser/Files app, install.

## Install — iPhone (Sideloadly)
1. On the laptop install **iTunes from apple.com** (not the Microsoft Store version) and **Sideloadly** from sideloadly.io.
2. Plug the iPhone in with a cable, tap *Trust* on the phone.
3. Open Sideloadly → drag `TravelTranslator.ipa` in → type the Apple ID → *Start*.
4. On the iPhone: *Settings → General → VPN & Device Management* → tap the Apple ID → *Trust*.
5. *Settings → Privacy & Security → Developer Mode* → on → restart.
6. The app lasts **7 days** on a free Apple ID; repeat step 3 to renew (or leave Sideloadly's auto-refresh on with the phone on the same wifi).

## Every future update
Upload the changed files to the repo → Actions builds new APK + IPA automatically.
