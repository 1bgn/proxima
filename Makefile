watch:
	flutter pub run build_runner watch --delete-conflicting-outputs
buildapp:
	flutter build apk --release
buildbundle:
	flutter build appbundle --release
buildios:
	 flutter clean && flutter pub get && cd ios &&pod install --repo-update && cd ..
buildweb:
	 flutter build web

