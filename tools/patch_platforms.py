"""Runs in CI after `flutter create .` — injects permissions and the app name."""
import pathlib, re

APP_NAME = "Travel Translator"

# ---------- Android ----------
manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
xml = manifest.read_text()
perms = """    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
"""
if "RECORD_AUDIO" not in xml:
    xml = xml.replace("<application", perms + "    <application", 1)
xml = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', xml, count=1)
if "android.speech.RecognitionService" not in xml:
    xml = xml.replace("</manifest>", """    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>
</manifest>""")
manifest.write_text(xml)

# ---------- iOS ----------
plist = pathlib.Path("ios/Runner/Info.plist")
p = plist.read_text()
extra = """	<key>NSMicrophoneUsageDescription</key>
	<string>Needed to hear the conversation and translate it live.</string>
	<key>NSCameraUsageDescription</key>
	<string>Needed to translate menus and signs with the camera.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Needed for live speech translation.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
"""
if "NSMicrophoneUsageDescription" not in p:
    p = p.replace("</dict>\n</plist>", extra + "</dict>\n</plist>")
p = re.sub(r"<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>",
           f"<key>CFBundleDisplayName</key>\n\t<string>{APP_NAME}</string>", p)
plist.write_text(p)
# minSdk 24: needed by the whisper/onnx native libraries.
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = pathlib.Path(name)
    if g.exists():
        t = g.read_text()
        t = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", t)
        t = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", t)
        g.write_text(t)

# Some plugins (onnxruntime) still declare compileSdk 33; modern AndroidX libs
# require >= 34. Raise any subproject that is too low.
root_kts = pathlib.Path("android/build.gradle.kts")
root_groovy = pathlib.Path("android/build.gradle")
if root_kts.exists():
    t = root_kts.read_text()
    if "raiseCompileSdk" not in t:
        t += """

// raiseCompileSdk: bump plugins stuck on an old compileSdk
fun Project.raiseCompileSdk() {
    val android = extensions.findByName("android") ?: return
    val current = android.withGroovyBuilder { getProperty("compileSdkVersion") }?.toString() ?: ""
    val level = Regex("android-([0-9]+)").find(current)?.groupValues?.get(1)?.toIntOrNull() ?: 0
    if (level in 1..34) {
        android.withGroovyBuilder { "compileSdkVersion"(35) }
    }
}
subprojects {
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}
"""
        root_kts.write_text(t)
elif root_groovy.exists():
    t = root_groovy.read_text()
    if "raiseCompileSdk" not in t:
        t += """

// raiseCompileSdk: bump plugins stuck on an old compileSdk
def raiseCompileSdk = { project ->
    if (project.hasProperty("android")) {
        def current = project.android.compileSdkVersion?.toString() ?: ""
        def m = (current =~ /android-([0-9]+)/)
        def level = m.find() ? m.group(1).toInteger() : 0
        if (level > 0 && level < 35) {
            project.android.compileSdkVersion 35
        }
    }
}
subprojects { project ->
    if (project.state.executed) raiseCompileSdk(project) else project.afterEvaluate { raiseCompileSdk(project) }
}
"""
        root_groovy.write_text(t)

# Stable release signing so updates install over the previous version.
ks = pathlib.Path("signing/release.jks")
app_kts = pathlib.Path("android/app/build.gradle.kts")
app_groovy = pathlib.Path("android/app/build.gradle")
if ks.exists():
    if app_kts.exists():
        t = app_kts.read_text()
        if 'getByName("release")' not in t:
            t = t.replace("android {", """android {
    signingConfigs {
        create("release") {
            storeFile = file("../../signing/release.jks")
            storePassword = "traveltranslator"
            keyAlias = "travel"
            keyPassword = "traveltranslator"
        }
    }""", 1)
            t = t.replace('signingConfig = signingConfigs.getByName("debug")',
                          'signingConfig = signingConfigs.getByName("release")')
            app_kts.write_text(t)
    elif app_groovy.exists():
        t = app_groovy.read_text()
        if "signingConfigs.release" not in t:
            t = t.replace("android {", """android {
    signingConfigs {
        release {
            storeFile file("../../signing/release.jks")
            storePassword "traveltranslator"
            keyAlias "travel"
            keyPassword "traveltranslator"
        }
    }""", 1)
            t = t.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
            app_groovy.write_text(t)
    print("Release signing configured.")

# ML Kit needs iOS 15.5+.
pod = pathlib.Path("ios/Podfile")
if pod.exists():
    t = pod.read_text()
    t = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '15.5'", t, count=1, flags=re.M)
    pod.write_text(t)

# ML Kit translation, used directly from MainActivity.
for name in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    g = pathlib.Path(name)
    if g.exists():
        t = g.read_text()
        if "com.google.mlkit:translate" not in t:
            if name.endswith(".kts"):
                t += '\ndependencies {\n    implementation("com.google.mlkit:translate:17.0.3")\n}\n'
            else:
                t += "\ndependencies {\n    implementation 'com.google.mlkit:translate:17.0.3'\n}\n"
            g.write_text(t)

print("Platforms patched.")
