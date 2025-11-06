Place Arabic font files here, e.g.:
- Cairo-Regular.ttf
- Cairo-Bold.ttf
OR use NotoSansArabic-Regular.ttf / NotoSansArabic-Bold.ttf

After copying, ensure pubspec.yaml contains:
  fonts:
    - family: Cairo
      fonts:
        - asset: assets/fonts/Cairo-Regular.ttf
        - asset: assets/fonts/Cairo-Bold.ttf

Then run:
flutter pub get
Restart the app (full restart).
