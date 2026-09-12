# Travel Translator

Live, two-way, offline conversation translator. Whisper large-v3-turbo (ears) → Silero VAD (reflexes) → NLLB-200 (brain) → phone TTS (mouth). One Flutter codebase for Android + iPhone. Everything runs on the phone; nothing leaves it.

## Getting a build (free, no Mac needed)

1. Repo: `https://github.com/lukianczyk-sketch/travel-translator` (public → unlimited free build minutes).
2. Upload this folder's contents (including the hidden `.github` folder) to the repo's `main` branch.
3. **Actions** tab → *Build Android APK + iPhone IPA* runs by itself (~15–25 min; the first iPhone build compiles whisper.cpp).
4. When green, open the run → **Artifacts**:
   - `TravelTranslator-Android-APK` → `app-arm64-v8a-release.apk`
   - `TravelTranslator-iPhone-IPA` → `TravelTranslator.ipa`

## Install — Galaxy S24 Ultra
Copy the APK to the phone, open it from My Files, allow "install unknown apps", install.

## Install — iPhone (Sideloadly)
1. Laptop: install **iTunes from apple.com** (not the Microsoft Store one) and **Sideloadly** (sideloadly.io).
2. Plug the iPhone in, tap *Trust* on the phone.
3. Sideloadly → drag `TravelTranslator.ipa` in → Apple ID → *Start*.
4. iPhone: *Settings → General → VPN & Device Management* → tap the Apple ID → *Trust*.
5. *Settings → Privacy & Security → Developer Mode* → on → restart.
6. Free Apple ID = app works **7 days**; repeat step 3 to renew.

## First run
Languages tab → download the three engine packs on wifi (≈1.8 GB total, one time) → tap your languages → Talk.

## In a conversation
- Big red **stop** ends it. **Replay** re-speaks the last translation. **Aa** enlarges text.
- **Speed gauge** button shows real timing per sentence: *hear · translate · total*.
- Their words are spoken in English; your English is spoken in their language. Audio goes wherever the phone is routed (earbuds if connected, otherwise the speaker).

## Every update
Upload the changed files to the repo → Actions rebuilds both automatically.
