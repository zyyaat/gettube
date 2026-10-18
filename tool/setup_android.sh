#!/usr/bin/env bash
# GetTube — one-time Android scaffolding.
# Generates the android/ folder with YOUR Flutter version (guaranteed
# compatibility), then applies GetTube's manifest + platform channel code.
set -e
cd "$(dirname "$0")/.."

echo "==> flutter create (android)"
flutter create . --org com.gettubeapp --project-name gettube --platforms android

echo "==> applying AndroidManifest permissions"
cp android_patch/AndroidManifest.xml android/app/src/main/AndroidManifest.xml

echo "==> applying MainActivity (MediaStore platform channel)"
mkdir -p android/app/src/main/kotlin/com/gettubeapp/gettube
cp android_patch/MainActivity.kt android/app/src/main/kotlin/com/gettubeapp/gettube/MainActivity.kt

echo "==> setting minSdk to 24 (required by ffmpeg_kit)"
if [ -f android/app/build.gradle.kts ]; then
  sed -i.bak 's/minSdk = flutter.minSdkVersion/minSdk = 24/' android/app/build.gradle.kts
  rm -f android/app/build.gradle.kts.bak
elif [ -f android/app/build.gradle ]; then
  sed -i.bak 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' android/app/build.gradle
  rm -f android/app/build.gradle.bak
fi

echo ""
echo "✅ Android is ready. Next steps:"
echo "   flutter pub get"
echo "   flutter run          # debug"
echo "   flutter build apk --release   # release APK"
